package com.fnthink.notice

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * T241：重试耗尽后「已入队」必须改判 QUEUED 的接线守卫。
 *
 * 判据在 [NetworkClient] 的重试耗尽终点：入队成功 ⇒ 历史格读「已转入自动重试」；
 * 入队失败 ⇒ 原失败结果原样回传。两件事都是静默失效（改错一个字，界面就把
 * 「已转自动重试」画成红色失败），所以钉四条接线。
 */
class QueuedTerminalContractTest {
    private val source: String by lazy {
        stripComments(File(SRC + "NetworkClient.kt").readText(Charsets.UTF_8))
    }

    @Test
    fun enqueueOnlyOnNotificationTagAndNotForced() {
        val enqueueAt = source.indexOf("RetryQueue.enqueue(")
        assertTrue("找不到 RetryQueue.enqueue 调用点", enqueueAt > 0)
        val head = source.substring(0, enqueueAt)
        val guardAt = head.lastIndexOf("tag == \"notification\" && !force")
        assertTrue("入队前必须同时满足 tag=notification 且非 force", guardAt > 0)
        for (status in listOf("HTTP_FAIL", "NETWORK_FAIL", "RATE_LIMITED")) {
            assertTrue("$status 必须进入队分支", head.lastIndexOf(status) > guardAt)
        }
    }

    @Test
    fun enqueuedRewritesTerminalToQueued() {
        val at = source.indexOf("if (enqueued && lastResult != null)")
        assertTrue("找不到入队成功的终态分支", at > 0)
        val branch = source.substring(at, at + 800)
        assertTrue("入队成功必须改判 QUEUED", branch.contains("DeliveryStatus.QUEUED"))
        assertTrue("文案必须说清已转自动重试", branch.contains("已转入自动重试"))
    }

    @Test
    fun notEnqueuedKeepsOriginalFailure() {
        val at = source.indexOf("if (enqueued && lastResult != null)")
        val elseAt = source.indexOf("} else {", at)
        assertTrue("找不到 else 分支", elseAt > at)
        val tail = source.substring(elseAt, elseAt + 300)
        assertTrue("未入队时回传原失败结果", tail.contains("lastResult ?:"))
    }

    @Test
    fun terminalIsWhatGetsReported() {
        val at = source.indexOf("val terminal =")
        assertTrue("找不到终态变量", at > 0)
        val after = source.substring(at)
        assertTrue(
            "回传的必须是终态（不是重试结果）",
            after.contains("onResult?.invoke(terminal.withTelemetry"),
        )
    }

    private companion object {
        const val SRC = "src/main/kotlin/com/fnthink/notice/"
    }
}
