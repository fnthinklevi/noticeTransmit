package com.fnthink.notice

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * T240 深睡重放门控的纯判据测试。
 *
 * 判据：深睡（deep Doze）且未豁免电池优化 ⇒ 延后重放（不取出、不 attempts++）。
 * 官方语义（developer.android.com / Optimize for Doze and App Standby）：
 * "An app that is partially exempt can use the network and hold partial wake locks
 * during Doze and App Standby." —— 豁免用户的深睡窗口网络可用，照常重放。
 *
 * 真机依据（E3/E5，2026-11-07 MEIZU 21）：未豁免用户的深睡窗口里重放注定失败，
 * 而 replayIfEligible 取出即烧次数（3 次 × 15 分钟冷却 = 45 分钟长锁屏烧空队列）。
 */
class RetryIdleGatePolicyTest {

    @Test
    fun deepIdleWithoutExemption_defers() {
        // 教科书 Doze 形态：深睡 + 未豁免 ⇒ 延后（这是本任务要救的那个窗口）
        assertTrue(RetryIdleGatePolicy.shouldDefer(deviceIdle = true, batteryExempt = false))
    }

    @Test
    fun deepIdleWithExemption_doesNotDefer() {
        // 豁免用户：官方保证深睡下网络可用 ⇒ 重放照常
        assertFalse(RetryIdleGatePolicy.shouldDefer(deviceIdle = true, batteryExempt = true))
    }

    @Test
    fun notIdle_neverDefers() {
        // 非深睡（亮屏 / 灭屏未入睡 / 轻度 Doze）：网络可用概率高，不过度门控（D4 拍板）
        assertFalse(RetryIdleGatePolicy.shouldDefer(deviceIdle = false, batteryExempt = false))
        assertFalse(RetryIdleGatePolicy.shouldDefer(deviceIdle = false, batteryExempt = true))
    }
}
