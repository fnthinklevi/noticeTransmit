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
        nextAttemptAt = nextAttemptAt,
        createdAt = createdAt,
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
