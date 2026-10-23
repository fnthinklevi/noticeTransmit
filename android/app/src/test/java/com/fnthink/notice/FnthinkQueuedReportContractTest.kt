package com.fnthink.notice

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * T175 ①：幻念设备档**入队即报 `queued`**，并一路映射到 Dart 的 `queued`。
 *
 * 旧形状只在后台 worker 真跑完发送之后才写回执。锁屏/被杀时那一轮可能一直不跑，
 * 历史那一格就停在「发送中」—— 而本机其实早就把这条交进待发队列了。
 * 这条链跨三处（原生枚举 → 广播 → Dart 归一），任何一处漏掉都会让状态回落成
 * `failed` 或永远 `pending`，且在单端测试里都看不出来。
 */
class FnthinkQueuedReportContractTest {

    private fun repoFile(rel: String): File {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            val candidate = File(dir, rel)
            if (candidate.exists()) return candidate
            dir = dir.parentFile
        }
        throw IllegalStateException("未找到 $rel（cwd=${File("").absolutePath}）")
    }

    private fun kotlin(rel: String) = stripComments(
        repoFile("app/src/main/kotlin/com/fnthink/notice/$rel").readText(Charsets.UTF_8),
    )

    private fun functionBody(src: String, signature: String): String {
        val start = src.indexOf(signature)
        if (start < 0) return ""
        val anchors = listOf("\n    private fun ", "\n    internal fun ", "\n    fun ", "\n}")
            .mapNotNull { anchor ->
                val at = src.indexOf(anchor, start + 1)
                if (at > start) at else null
            }
        val end = anchors.minOrNull() ?: src.length
        return src.substring(start, end)
    }

    @Test
    fun `入队之后立刻回 QUEUED，不等后台那一轮`() {
        val src = kotlin("NotificationMonitorService.kt")
        val fn = functionBody(src, "private fun dispatchFnthink(")
        assertTrue("没找到 dispatchFnthink 函数体", fn.isNotEmpty())
        val enqueueAt = fn.indexOf("queue.enqueue(")
        val queuedAt = fn.indexOf("DeliveryStatus.QUEUED")
        assertTrue("dispatchFnthink 没有回 QUEUED —— 锁屏时那一格会一直「发送中」", queuedAt >= 0)
        assertTrue(
            "QUEUED 必须在入队之后回（否则队列还没收下就先报了个状态）",
            enqueueAt >= 0 && queuedAt > enqueueAt,
        )
        assertTrue(
            "QUEUED 回执必须走 DeliveryNotifier 的 fnthink 那一发",
            Regex("""DeliveryNotifier\.notify\([\s\S]*?"fnthink"[\s\S]*?QUEUED""")
                .containsMatchIn(fn.substring(enqueueAt)),
        )
    }

    @Test
    fun `QUEUED 不算通道失败`() {
        val src = kotlin("ChannelAvailability.kt")
        val note = functionBody(src, "fun noteResult(")
        assertTrue(
            "noteResult 没排除 QUEUED ⇒ 幻念设备档排队会把主通道记成连续失败",
            note.contains("DeliveryStatus.QUEUED"),
        )
    }

    @Test
    fun `Dart 收到 QUEUED 归一为 queued 而不是 failed`() {
        val dart = repoFile("lib/services/notification_service.dart")
            .readText(Charsets.UTF_8)
        assertTrue(
            "Dart 的 updateDelivery 没认 QUEUED ⇒ 入队会被默认分支写成 failed",
            dart.contains("'QUEUED' => 'queued'"),
        )
    }
}
