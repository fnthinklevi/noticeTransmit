package com.fnthink.notice

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * T196：后台收货诊断读数的接线与跨语言键名守卫。
 *
 * 这一族的失败都是静默的：原生不写/写错键 ⇒ 界面只显示 0 或"还没有记录"，
 * 看起来像"这台确实没醒过"，而真正的原因是读数根本没接上。所以钉三件事：
 *  - 四个写入点（闹钟到点 / worker 开始 / worker 结束 / 服务启动）都还在；
 *  - `fnthinkPresenceStatus` 确实把 `diag` 快照交出去；
 *  - Dart 写 FlutterSharedPreferences 的三枚裸键与 Kotlin 读的 `flutter.` 前缀键逐字对应。
 */
class FnthinkDiagSourceGuardTest {

    private val diag: String by lazy {
        stripComments(File(SRC + "FnthinkDiag.kt").readText(Charsets.UTF_8))
    }
    private val handler: String by lazy {
        stripComments(
            File(SRC + "channels/FnthinkChannelHandler.kt").readText(Charsets.UTF_8),
        )
    }
    private val receiver: String by lazy {
        stripComments(File(SRC + "FnthinkPresenceReceiver.kt").readText(Charsets.UTF_8))
    }
    private val worker: String by lazy {
        stripComments(File(SRC + "FnthinkPresenceWorker.kt").readText(Charsets.UTF_8))
    }
    private val service: String by lazy {
        stripComments(File(SRC + "NotificationMonitorService.kt").readText(Charsets.UTF_8))
    }
    private val dart: String by lazy {
        repoFile("lib/services/fnthink_diag.dart").readText(Charsets.UTF_8)
    }
    private val scheduler: String by lazy {
        repoFile("lib/services/fnthink_presence_scheduler.dart").readText(Charsets.UTF_8)
    }

    @Test
    fun diagReadoutIsWiredIntoTheStatusAndTheFourWritePoints() {
        assertTrue(
            "diag 快照必须由 fnthinkPresenceStatus 交出去；漏了这一行，页面永远读不到四格读数",
            handler.contains("\"diag\" to FnthinkDiag.snapshot(context)"),
        )
        assertTrue("闹钟到点要写 lastAlarmFiredAt", receiver.contains("FnthinkDiag.markAlarmFired(context)"))
        assertTrue("worker 开始要写 lastWorkerStartedAt", worker.contains("FnthinkDiag.markWorkerStarted"))
        assertTrue("worker 结束要写结果与时刻", worker.contains("FnthinkDiag.markWorkerFinished"))
        assertTrue(
            "服务启动要写 serviceStartedAt/processStartedAt",
            service.contains("FnthinkDiag.markServiceStarted(this)"),
        )
    }

    @Test
    fun dartWriterKeysAndNativeReaderKeysAreTheSamePair() {
        // Kotlin 读 FlutterSharedPreferences 时必须带 `flutter.` 前缀；Dart 写裸键。
        for (pair in listOf(
            "fnthink_diag_last_poll_at" to "DART_KEY_LAST_POLL_AT",
            "fnthink_diag_last_poll_status" to "DART_KEY_LAST_POLL_STATUS",
            "fnthink_diag_last_stream_byte_at" to "DART_KEY_LAST_STREAM_BYTE_AT",
        )) {
            val (bare, const) = pair
            assertTrue(
                "Kotlin 常量 $const 必须读 flutter.$bare（少一个字符就永远读到 0）",
                diag.contains("$const = \"flutter.$bare\""),
            )
            assertTrue(
                "Dart 写的那枚键必须是 $bare（与 Kotlin 的 flutter. 前缀是一对）",
                dart.contains("'$bare'"),
            )
        }
        assertTrue(
            "状态解析必须认 diag 这一格；缺了它页面永远不画四格读数",
            scheduler.contains("raw?['diag']") && scheduler.contains("FnthinkDiagSnapshot.fromMap"),
        )
    }

    private fun repoFile(rel: String): File {
        val candidates = listOf(File("../.."), File("."), File(".."))
        for (root in candidates) {
            val f = File(root, rel)
            if (f.exists()) return f
        }
        return File("../../$rel")
    }

    private companion object {
        const val SRC = "src/main/kotlin/com/fnthink/notice/"
    }
}
