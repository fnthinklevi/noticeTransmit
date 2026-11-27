package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 监听器重绑退避（P1-2 漏读）。
 *
 * 语义矩阵：
 * - 首次 15 秒（刚断开最常是"马上就好"，等长反而拖慢恢复）；
 * - 之后每档翻倍，封顶 5 分钟；
 * - 任何一档**都不许是 0**（0 会让 postDelayed 变成同步递归，在 Doze 期间打满主线程）；
 * - 档位表之外继续问，永远拿到封顶值（"一直试到连上"）。
 */
class RebindBackoffTest {

    @Test
    fun firstDelay_isFifteenSeconds() {
        assertEquals(15_000L, RebindBackoff.delayFor(0))
    }

    @Test
    fun delays_growThenCap() {
        assertEquals(15_000L, RebindBackoff.delayFor(0))
        assertEquals(30_000L, RebindBackoff.delayFor(1))
        assertEquals(60_000L, RebindBackoff.delayFor(2))
        assertEquals(120_000L, RebindBackoff.delayFor(3))
        assertEquals(300_000L, RebindBackoff.delayFor(4))
    }

    @Test
    fun beyondTable_keepsCapForever() {
        // "一直试到连上"：不设上限次数，第 5 次、第 100 次、第 100000 次都还是封顶值。
        assertEquals(RebindBackoff.MAX_DELAY_MS, RebindBackoff.delayFor(5))
        assertEquals(RebindBackoff.MAX_DELAY_MS, RebindBackoff.delayFor(100))
        assertEquals(RebindBackoff.MAX_DELAY_MS, RebindBackoff.delayFor(100_000))
    }

    @Test
    fun neverReturnsZero() {
        // 0 会让 postDelayed 在同一次循环里立刻回调 ⇒ 重试变成忙等。
        for (attempt in -5..10_000) {
            assertTrue(
                "attempt=$attempt 拿到 0",
                RebindBackoff.delayFor(attempt) > 0L
            )
        }
    }

    @Test
    fun negativeAttempt_treatedAsFirst() {
        assertEquals(15_000L, RebindBackoff.delayFor(-1))
        assertEquals(15_000L, RebindBackoff.delayFor(-100))
    }

    @Test
    fun maxDelayMatchesLastTier() {
        // 封顶值必须真的等于最后一档，否则 delayFor(4) 与 MAX_DELAY_MS 会各说一段。
        assertEquals(RebindBackoff.DELAYS_MS.last(), RebindBackoff.MAX_DELAY_MS)
    }
}
