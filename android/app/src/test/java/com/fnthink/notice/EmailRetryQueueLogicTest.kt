package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * T243 邮件重试队列纯逻辑测试。
 *
 * 参数纪律（PRD D2=A）：形状与 RetryQueueLogic 同源，数值按邮件场景放宽——
 * 冷却 30 分钟（重放 = 再寄一封，取宽防骚扰）/ 每条最多 2 次 / 上限 20 / TTL 24h。
 */
class EmailRetryQueueLogicTest {

    private val now = 1_700_000_000_000L

    private fun item(
        id: String = "m1",
        configId: String = "cfg1",
        recordId: String = "rec1",
        attempts: Int = 0,
        nextAttemptAt: Long = now,
        createdAt: Long = now,
    ) = EmailRetryItem(
        id = id,
        configId = configId,
        subject = "🔔 %appName% — 标题",
        body = "【通知转发】内容",
        recordId = recordId,
        attempts = attempts,
        nextAttemptAt = nextAttemptAt,
        createdAt = createdAt,
    )

    @Test
    fun replayable_onlyAfterCooldown() {
        // 冷却窗口内不许重放（防「失败后立即重打」叠加成风暴）
        assertFalse(
            EmailRetryQueueLogic.isReplayable(item(nextAttemptAt = now + 1), now),
        )
        assertTrue(
            EmailRetryQueueLogic.isReplayable(
                item(nextAttemptAt = now + EmailRetryQueueLogic.COOLDOWN_MS),
                now + EmailRetryQueueLogic.COOLDOWN_MS,
            ),
        )
    }

    @Test
    fun replayable_respectsAttemptCap() {
        // 每条最多 2 次：第 2 次之后（attempts=2）不再重放
        assertFalse(
            EmailRetryQueueLogic.isReplayable(
                item(attempts = EmailRetryQueueLogic.MAX_ATTEMPTS),
                now,
            ),
        )
        assertTrue(
            EmailRetryQueueLogic.isReplayable(
                item(attempts = EmailRetryQueueLogic.MAX_ATTEMPTS - 1),
                now,
            ),
        )
    }

    @Test
    fun replayable_respectsTtl() {
        // 恰好 24h 仍可重放，超过才过期（与 RetryQueueLogic 的边界口径一致）
        assertTrue(
            EmailRetryQueueLogic.isReplayable(item(createdAt = now - EmailRetryQueueLogic.MAX_AGE_MS), now),
        )
        assertFalse(
            EmailRetryQueueLogic.isReplayable(
                item(createdAt = now - EmailRetryQueueLogic.MAX_AGE_MS - 1),
                now,
            ),
        )
    }

    @Test
    fun purge_dropsExhaustedAndExpired() {
        val items = listOf(
            item(id = "keep", attempts = 0, createdAt = now),
            item(id = "exhausted", attempts = EmailRetryQueueLogic.MAX_ATTEMPTS, createdAt = now),
            item(id = "expired", attempts = 0, createdAt = now - EmailRetryQueueLogic.MAX_AGE_MS - 1),
        )
        val cleaned = EmailRetryQueueLogic.purge(items, now)
        assertEquals(listOf("keep"), cleaned.map { it.id })
    }

    @Test
    fun cap_keepsNewest() {
        val items = (0 until EmailRetryQueueLogic.MAX_RECORDS + 5).map {
            item(id = "m$it", createdAt = now + it)
        }
        val capped = EmailRetryQueueLogic.applyCap(items)
        assertEquals(EmailRetryQueueLogic.MAX_RECORDS, capped.size)
        // 保留最新：最旧的 5 条（m0..m4）被挤掉
        assertFalse(capped.any { it.id == "m0" })
        assertTrue(capped.any { it.id == "m${EmailRetryQueueLogic.MAX_RECORDS + 4}" })
    }

    @Test
    fun jsonRoundTrip_preservesAllFields() {
        val items = listOf(
            item(attempts = 1, nextAttemptAt = now + EmailRetryQueueLogic.COOLDOWN_MS),
            item(id = "m2", configId = "cfg2", recordId = "rec2", createdAt = now + 5),
        )
        val parsed = EmailRetryQueueLogic.parse(EmailRetryQueueLogic.toJson(items))
        assertEquals(items, parsed)
    }

    @Test
    fun parse_garbageJson_degradesToEmpty() {
        // 坏 JSON 一律退化成空数组（抛在这里等于整个队列失效——与 RetryQueueLogic 同因）
        assertEquals(emptyList<EmailRetryItem>(), EmailRetryQueueLogic.parse("not json at all"))
    }

    @Test
    fun cooldown_isLongerThanWebhookQueue() {
        // 邮件重放=再寄一封，冷却必须比 webhook 的 15 分钟宽（防骚扰的产品纪律）
        assertTrue(
            "邮件冷却应宽于 webhook 队列的 15 分钟",
            EmailRetryQueueLogic.COOLDOWN_MS > 15 * 60 * 1000L,
        )
    }
}
