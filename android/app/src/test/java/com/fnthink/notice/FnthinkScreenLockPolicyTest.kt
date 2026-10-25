package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** T197 片2：锁屏持锁的纯判据（接收开 + 高可靠开关开 + 屏幕灭）。 */
class FnthinkScreenLockPolicyTest {

    @Test
    fun holdsOnlyWhenReceiveAndKeepaliveAndScreenOff() {
        assertTrue(
            FnthinkScreenLockPolicy.shouldHold(
                receiveEnabled = true,
                keepaliveEnabled = true,
                screenOn = false,
            ),
        )
    }

    @Test
    fun screenOnNeverHolds() {
        assertFalse(
            FnthinkScreenLockPolicy.shouldHold(
                receiveEnabled = true,
                keepaliveEnabled = true,
                screenOn = true,
            ),
        )
    }

    @Test
    fun receiveOffNeverHolds() {
        assertFalse(
            FnthinkScreenLockPolicy.shouldHold(
                receiveEnabled = false,
                keepaliveEnabled = true,
                screenOn = false,
            ),
        )
    }

    @Test
    fun keepaliveOffNeverHolds() {
        assertFalse(
            FnthinkScreenLockPolicy.shouldHold(
                receiveEnabled = true,
                keepaliveEnabled = false,
                screenOn = false,
            ),
        )
    }

    @Test
    fun renewWindowIsShorterThanWakeTimeout() {
        assertTrue(
            "续期必须早于过期，否则锁会在两次续期之间掉",
            FnthinkScreenLock.RENEW_MS < FnthinkScreenLock.WAKE_TIMEOUT_MS,
        )
        assertEquals(10 * 60 * 1000L, FnthinkScreenLock.WAKE_TIMEOUT_MS)
        assertEquals(5 * 60 * 1000L, FnthinkScreenLock.RENEW_MS)
    }
}
