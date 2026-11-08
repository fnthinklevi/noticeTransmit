package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 重试队列纯逻辑测试（RetryQueueLogic，无 Android 依赖）。
 *
 * 消费方：`RetryQueue`（N4 失败推送自动重试队列）。约束来自 roadmap N4：
 * 上限 50 条（保留最新）/ 过期 24h / 每条最多重放 3 次 / 重放冷却 15 分钟。
 */
class RetryQueueTest {

    private val now = 1_700_000_000_000L

    private fun item(
        id: String = "r1",
        attempts: Int = 0,
        queueReplays: Int = 3,
        nextAttemptAt: Long = now,
        createdAt: Long = now,
    ) = RetryItem(
        id = id,
        url = "https://example.com/hook",
        payload = """{"title":"t"}""",
        webhookType = "GENERIC",
        secret = "",
        contentType = "application/json; charset=utf-8",
        recordId = "rec_$id",
        attempts = attempts,
        queueReplays = queueReplays,
        nextAttemptAt = nextAttemptAt,
        createdAt = createdAt,
        headers = mapOf("X-Api-Key" to "k-1"),
    )

    // ===== isReplayable =====

    @Test
    fun replayable_whenFreshAndWithinCooldownAndBelowAttempts() {
        assertTrue(RetryQueueLogic.isReplayable(item(), now))
    }

    @Test
    fun notReplayable_whenAttemptsExhausted() {
        assertFalse(RetryQueueLogic.isReplayable(item(attempts = 3), now))
        assertFalse(RetryQueueLogic.isReplayable(item(attempts = 5), now))
    }

    @Test
    fun notReplayable_duringCooldown() {
        assertFalse(RetryQueueLogic.isReplayable(item(nextAttemptAt = now + 1), now))
        // 冷却刚好到期（now == nextAttemptAt）即可重放
        assertTrue(RetryQueueLogic.isReplayable(item(nextAttemptAt = now), now))
    }

    @Test
    fun notReplayable_after24hExpiry() {
        val expired = item(createdAt = now - RetryQueueLogic.MAX_AGE_MS - 1)
        assertFalse(RetryQueueLogic.isReplayable(expired, now))
        // 边界内侧：恰好 24h 仍未过期
        val boundary = item(createdAt = now - RetryQueueLogic.MAX_AGE_MS)
        assertTrue(RetryQueueLogic.isReplayable(boundary, now))
    }

    // ===== T251 重试预算（queueReplays 按通道盖戳）=====

    @Test
    fun budgetLimitedItem_notReplayableAfterItsOwnBudget() {
        // Server酱/PushPlus 形态：预算 1 ⇒ 1 次取出即耗尽（旧的全局常量是 3）
        val tight = item(id = "tight", attempts = 1, queueReplays = 1)
        assertFalse(RetryQueueLogic.isReplayable(tight, now))
        // 还没取出（attempts=0）时照常可重放
        assertTrue(RetryQueueLogic.isReplayable(item(id = "fresh", queueReplays = 1), now))
    }

    @Test
    fun legacyJsonWithoutBudgetField_defaultsToThree() {
        // 升级前落盘的条目没有 queueReplays 键 ⇒ 默认 3（当时的全局预算，不是猜的）
        val legacy = """[{"id":"l1","url":"https://e.com","payload":"p","attempts":2,"createdAt":$now}]"""
        val parsed = RetryQueueLogic.parse(legacy).single()
        assertEquals(3, parsed.queueReplays)
        assertTrue(RetryQueueLogic.isReplayable(parsed, now))
    }

    @Test
    fun jsonRoundTrip_preservesBudget() {
        val items = listOf(item(id = "tight", queueReplays = 1, attempts = 0))
        val parsed = RetryQueueLogic.parse(RetryQueueLogic.toJson(items)).single()
        assertEquals(1, parsed.queueReplays)
    }

    @Test
    fun purge_dropsBudgetExhausted() {
        val items = listOf(
            item(id = "ok", queueReplays = 3, attempts = 1),
            item(id = "tight-done", queueReplays = 1, attempts = 1),
        )
        val cleaned = RetryQueueLogic.purge(items, now)
        assertEquals(listOf("ok"), cleaned.map { it.id })
    }

    // ===== purge =====

    @Test
    fun purge_dropsExhaustedAndExpired_keepsEligible() {
        val items = listOf(
            item(id = "ok"),
            item(id = "exhausted", attempts = 3),
            item(id = "expired", createdAt = now - RetryQueueLogic.MAX_AGE_MS - 1),
        )
        val kept = RetryQueueLogic.purge(items, now)
        assertEquals(listOf("ok"), kept.map { it.id })
    }

    @Test
    fun purge_keepsItemsInCooldown_notYetReplayableButAlive() {
        val cooling = item(nextAttemptAt = now + RetryQueueLogic.COOLDOWN_MS)
        assertEquals(1, RetryQueueLogic.purge(listOf(cooling), now).size)
    }

    // ===== applyCap =====

    @Test
    fun cap_keepsNewest50() {
        val items = (0 until 60).map { item(id = "r$it", createdAt = now + it) }
        val capped = RetryQueueLogic.applyCap(items)
        assertEquals(RetryQueueLogic.MAX_RECORDS, capped.size)
        // 保留 createdAt 最新的 50 条（r10..r59）
        assertEquals("r10", capped.minByOrNull { it.createdAt }?.id)
        assertEquals("r59", capped.maxByOrNull { it.createdAt }?.id)
    }

    @Test
    fun cap_noop_whenUnderLimit() {
        val items = (0 until 10).map { item(id = "r$it") }
        assertEquals(items, RetryQueueLogic.applyCap(items))
    }

    // ===== JSON 序列化 roundtrip =====

    @Test
    fun jsonRoundtrip_preservesAllFields() {
        val original = listOf(
            item(id = "a", attempts = 1, nextAttemptAt = now + 123, createdAt = now),
            item(id = "b", attempts = 2),
        )
        val parsed = RetryQueueLogic.parse(RetryQueueLogic.toJson(original))
        assertEquals(original, parsed)
    }

    @Test
    fun headersSurviveRoundtripAndForbiddenOnesAreDroppedOnRead() {
        // 重放读的是队列里那一份，不是当时的配置 ⇒ 头必须落盘；
        // 而落盘之后仍要过一遍白名单（手改过的队列文件不能成为绕过闸门的入口）。
        val original = listOf(item().copy(headers = mapOf("X-Api-Key" to "k-1")))
        assertEquals(original, RetryQueueLogic.parse(RetryQueueLogic.toJson(original)))

        val forged = """
            [{"id":"r1","url":"https://example.com/hook","payload":"{}","webhookType":"GENERIC",
              "secret":"","contentType":"application/json","recordId":"rec","attempts":0,
              "nextAttemptAt":$now,"createdAt":$now,
              "headers":{"Host":"evil.example","X-Api-Key":"k-1"}}]
        """.trimIndent()
        val parsedForged = RetryQueueLogic.parse(forged)
        assertEquals(mapOf("X-Api-Key" to "k-1"), parsedForged.single().headers)
    }

    @Test
    fun parse_garbageJson_returnsEmpty() {
        assertEquals(emptyList<RetryItem>(), RetryQueueLogic.parse("not json"))
        assertEquals(emptyList<RetryItem>(), RetryQueueLogic.parse("[{broken"))
    }

    // ===== 冷却时间 =====

    @Test
    fun nextAttemptAfter_is15MinutesLater() {
        assertEquals(now + RetryQueueLogic.COOLDOWN_MS, RetryQueueLogic.nextAttemptAfter(now))
        assertNotEquals(now, RetryQueueLogic.nextAttemptAfter(now))
    }
}
