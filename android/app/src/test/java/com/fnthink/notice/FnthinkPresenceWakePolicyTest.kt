package com.fnthink.notice

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** T197 片1：解锁/亮屏/网络补收的纯判据（开关 + 5 秒节流）。 */
class FnthinkPresenceWakePolicyTest {

    @Test
    fun switchOffNeverWakes() {
        assertFalse(
            FnthinkPresenceWakePolicy.shouldWake(
                receiveEnabled = false,
                lastEnqueueAtMs = 0L,
                nowMs = 10_000L,
            ),
        )
    }

    @Test
    fun firstTriggerPasses() {
        assertTrue(
            FnthinkPresenceWakePolicy.shouldWake(
                receiveEnabled = true,
                lastEnqueueAtMs = 0L,
                nowMs = 10_000L,
            ),
        )
    }

    @Test
    fun withinFiveSecondsIsSuppressed() {
        assertFalse(
            FnthinkPresenceWakePolicy.shouldWake(
                receiveEnabled = true,
                lastEnqueueAtMs = 10_000L,
                nowMs = 14_999L,
            ),
        )
    }

    @Test
    fun afterFiveSecondsPasses() {
        assertTrue(
            FnthinkPresenceWakePolicy.shouldWake(
                receiveEnabled = true,
                lastEnqueueAtMs = 10_000L,
                nowMs = 15_000L,
            ),
        )
    }
}
