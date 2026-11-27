package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 冷启动补扫的收尾决策（P1-3 漏读）。
 *
 * 语义矩阵：
 * - 不需要补扫（首次安装 / 服务没中断）→ 水位照常推进，不挂欠账；
 * - 需要补扫且扫完了 → 水位推进，不挂欠账；
 * - 需要补扫但**没拿到活跃通知快照** → 水位**不推进**，把这一段挂成 pending
 *   （这是这一条的要点：原实现在这里静默 return，但那一段通知就永远补不回来了）。
 */
class RecoveryWatermarkSettleTest {

    @Test
    fun noScanNeeded_advancesWatermarkWithoutPending() {
        val settle = RecoveryWatermark.settleStartupScan(null, snapshotReadable = true)
        assertTrue(settle.advanceWatermark)
        assertNull(settle.pendingSince)
    }

    @Test
    fun scannedSuccessfully_advancesWatermark() {
        val settle = RecoveryWatermark.settleStartupScan(1_000L, snapshotReadable = true)
        assertTrue(settle.advanceWatermark)
        assertNull(settle.pendingSince)
    }

    @Test
    fun snapshotUnreadable_doesNotAdvance_keepsPendingWatermark() {
        val since = 1_000L
        val settle = RecoveryWatermark.settleStartupScan(since, snapshotReadable = false)
        assertFalse(
            "拿不到快照时推进水位 = 那一段通知永远补不回来",
            settle.advanceWatermark
        )
        assertEquals(since, settle.pendingSince)
    }

    @Test
    fun noScanNeeded_ignoresReadability() {
        // 不需要补扫时，快照读不读得到都不影响结论（本来就没有要补的条）
        assertTrue(
            RecoveryWatermark.settleStartupScan(null, snapshotReadable = false)
                .advanceWatermark
        )
    }
}
