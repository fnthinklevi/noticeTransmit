package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * 启动补扫水位逻辑测试（RecoveryWatermark，N9 漏通知修复的核心判定）。
 *
 * 语义矩阵：
 * - 首次安装（无心跳）→ 不补扫（避免回放通知栏既有历史通知）
 * - 心跳新鲜（服务未中断，< 30s）→ 不补扫（事件不会丢）
 * - 心跳陈旧（服务中断过）→ 补扫，下界 = max(心跳, 上次补扫水位, now - 6h)
 */
class RecoveryWatermarkTest {

    private val now = 1_700_000_000_000L
    private val sixHours = RecoveryWatermark.MAX_LOOKBACK_MS
    private val minGap = RecoveryWatermark.MIN_GAP_MS

    @Test
    fun firstInstall_noHeartbeat_noRecovery() {
        // lastAlive = 0：首次安装，通知栏里的既有通知是历史而非漏读
        assertNull(RecoveryWatermark.scanSinceOrNull(lastAliveAt = 0L, lastScanAt = 0L, now = now))
    }

    @Test
    fun freshHeartbeat_noRecovery() {
        // 服务一直活着（10 秒前还有心跳）→ 事件不会丢
        assertNull(
            RecoveryWatermark.scanSinceOrNull(
                lastAliveAt = now - 10_000L, lastScanAt = 0L, now = now
            )
        )
    }

    @Test
    fun staleHeartbeat_recoverFromLastAlive() {
        // 服务中断 5 分钟：从心跳时刻开始补扫
        val lastAlive = now - 5 * 60_000L
        assertEquals(
            lastAlive,
            RecoveryWatermark.scanSinceOrNull(lastAliveAt = lastAlive, lastScanAt = 0L, now = now)
        )
    }

    @Test
    fun lastScanWatermark_wins_whenNewerThanHeartbeat() {
        // 上次补扫水位比心跳更新（补扫后服务又中断）→ 从上次补扫水位开始，
        // 防止同一段通知被重复回放
        val lastScan = now - 60_000L
        val lastAlive = now - 10 * 60_000L
        assertEquals(
            lastScan,
            RecoveryWatermark.scanSinceOrNull(lastAliveAt = lastAlive, lastScanAt = lastScan, now = now)
        )
    }

    @Test
    fun maxLookback_clampsVeryLongGap() {
        // 中断 3 天：只回放最近 6 小时，避免冷启动回放大量陈旧通知
        val lastAlive = now - 3 * 24 * 60 * 60_000L
        assertEquals(
            now - sixHours,
            RecoveryWatermark.scanSinceOrNull(lastAliveAt = lastAlive, lastScanAt = 0L, now = now)
        )
    }

    @Test
    fun minGapBoundary_exactlyAtThreshold_triggersRecovery() {
        // 边界：恰好达到 30s（>= 语义）→ 判定为中断过，触发补扫
        val lastAlive = now - minGap
        assertEquals(
            lastAlive,
            RecoveryWatermark.scanSinceOrNull(lastAliveAt = lastAlive, lastScanAt = 0L, now = now)
        )
    }

    @Test
    fun bothWatermarksZero_behavesLikeFirstInstall() {
        assertNull(RecoveryWatermark.scanSinceOrNull(lastAliveAt = 0L, lastScanAt = 0L, now = now))
    }
}
