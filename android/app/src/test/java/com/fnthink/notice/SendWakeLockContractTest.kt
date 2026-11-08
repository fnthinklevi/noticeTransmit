package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * T244：发送生命周期 wake lock 的接线守卫。
 *
 * 两个失效模式：锁在发送前拿、异常路径不释放（电池被拖住）；或没有硬上限
 * （一次挂死的 TLS 握手把锁持有到进程结束）。纯 JVM 测不了 PowerManager，
 * 所以钉「常量 + 获取顺序 + finally 释放」三处。
 */
class SendWakeLockContractTest {
    private val source: String by lazy {
        stripComments(File(SRC + "NetworkClient.kt").readText(Charsets.UTF_8))
    }

    @Test
    fun hardCapIsSixtySeconds() {
        assertEquals(60_000L, NetworkClient.SEND_WAKE_LOCK_MS)
    }

    @Test
    fun lockAcquiredBeforeSendAndReleasedInFinally() {
        val acquireAt = source.indexOf("val wakeLock = acquireSendWakeLock()")
        assertTrue("找不到发送前获取 wake lock", acquireAt > 0)
        val tryAt = source.indexOf("try {", acquireAt)
        assertTrue("wake lock 必须在发送 try 之前拿", tryAt > acquireAt)
        val finallyAt = source.indexOf("finally {", tryAt)
        assertTrue("必须有 finally 释放", finallyAt > tryAt)
        val tail = source.substring(finallyAt, finallyAt + 200)
        assertTrue("finally 里必须 release", tail.contains("it.release()"))
    }

    @Test
    fun usesPartialLockWithNamedTag() {
        assertTrue(source.contains("PowerManager.PARTIAL_WAKE_LOCK"))
        assertTrue(source.contains("\"fnthink:webhook-send\""))
        assertTrue(source.contains("acquire(SEND_WAKE_LOCK_MS)"))
    }

    @Test
    fun missingContextDegradesToNull() {
        val at = source.indexOf("private fun acquireSendWakeLock")
        assertTrue("找不到 acquireSendWakeLock", at > 0)
        val body = source.substring(at, at + 300)
        assertTrue("无 Context 时必须返回 null（发送照常）", body.contains("appContext ?: return null"))
    }

    private companion object {
        const val SRC = "src/main/kotlin/com/fnthink/notice/"
    }
}
