package com.fnthink.notice

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * T239 重放触发面的纯判据测试：5 秒节流。
 *
 * 背景（E2 真机实证，2026-11-07）：RetryQueue 的重放触发面原本只有「服务 onCreate」与
 * 「网络回调 onAvailable」——解锁/亮屏不在其中，长锁屏期间排队的推送无人叫醒。本判据
 * 是新触发源（ACTION_USER_PRESENT / ACTION_SCREEN_ON）的止损阀。
 */
class RetryQueueWakePolicyTest {

    private val now = 1_700_000_000_000L

    @Test
    fun withinThrottleWindow_isSkipped() {
        // 解锁 + 亮屏经常连着来：间隔 0ms / 1ms / 4999ms 都必须被挡
        assertFalse(RetryQueueWake.shouldWake(now, now))
        assertFalse(RetryQueueWake.shouldWake(now, now + 1))
        assertFalse(
            "节流窗口内（< 5s）不许重放",
            RetryQueueWake.shouldWake(now, now + RetryQueueWakePolicy.THROTTLE_MS - 1),
        )
    }

    @Test
    fun atThrottleBoundary_isAllowed() {
        // 恰好 5s：允许（与 FnthinkPresenceWakePolicy 同一口径：now - last >= THROTTLE）
        assertTrue(
            RetryQueueWake.shouldWake(now, now + RetryQueueWakePolicy.THROTTLE_MS),
        )
    }

    @Test
    fun afterThrottleWindow_isAllowed() {
        assertTrue(RetryQueueWake.shouldWake(now, now + RetryQueueWakePolicy.THROTTLE_MS + 1))
        assertTrue(RetryQueueWake.shouldWake(now, now + 60_000))
    }

    @Test
    fun firstWakeEver_isAllowed() {
        // lastWakeAt 初始为 0：进程生命周期内第一次触发必须放行
        assertTrue(RetryQueueWake.shouldWake(0L, now))
    }
}
