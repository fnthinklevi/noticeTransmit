package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * T220 片2：送达取证（`attempts` / `elapsedMs`）的**跨三处接线**守卫。
 *
 * 这三处的失效都是静默的：原生不写 ⇒ 界面显示"没报"；写成不同键名 ⇒ 那条路径永远 0；
 * 广播与持久化队列只补一边 ⇒ 同一条通知"实时"与"补拉"给出两套读数。所以钉三件事：
 *  - 原生只在**真的发过请求**的那条路上打这两枚数（早退那两条不许打：一个请求都没发）；
 *  - 两条回传路径（广播 extra 与 `DeliveryResultStore`）用同一组键名；
 *  - Dart 的两个读口（实时 `onDeliveryResult`、补拉 `drainDeliveryResults`）读同一对键。
 */
class DeliveryTelemetrySourceGuardTest {

    private val network: String by lazy {
        stripComments(File(SRC + "NetworkClient.kt").readText(Charsets.UTF_8))
    }
    private val notifier: String by lazy {
        stripComments(File(SRC + "DeliveryNotifier.kt").readText(Charsets.UTF_8))
    }
    private val store: String by lazy {
        stripComments(File(SRC + "DeliveryResultStore.kt").readText(Charsets.UTF_8))
    }
    private val activity: String by lazy {
        stripComments(File(SRC + "MainActivity.kt").readText(Charsets.UTF_8))
    }
    private val service: String by lazy {
        repoFile("lib/services/notification_service.dart").readText(Charsets.UTF_8)
    }
    private val mainPage: String by lazy {
        repoFile("lib/pages/main_page.dart").readText(Charsets.UTF_8)
    }

    @Test
    fun networkClientStampsEveryTerminalResultThatActuallySent() {
        // 成功 / 不可重试 / 重试耗尽 —— 三个终点各打一次；早退那两条（未激活、推送暂停）
        // 不该打：它们一个请求都没发，attempts 必须是 0（未知）而不是 1。
        assertEquals(
            "打戳的点必须是「真发过请求」的三个终点",
            3,
            // 只数调用点：定义那一行是 `.withTelemetry(` 换行后接参数，不会命中这个模式。
            Regex("""\.withTelemetry\(startedAtMs""").findAll(network).count(),
        )
        assertTrue(
            "戳必须写在这两格上（Dart 侧按这两枚读）",
            network.contains("attempts = attemptCount") &&
                network.contains("elapsedMs = "),
        )
    }

    @Test
    fun bothNativeResultPathsCarryTheSameKeyPair() {
        assertTrue(
            "广播必须带 attempts/elapsed_ms",
            notifier.contains("putExtra(\"attempts\"") &&
                notifier.contains("putExtra(\"elapsed_ms\""),
        )
        assertTrue(
            "持久化队列也必须带（只补一边 ⇒ 实时与补拉两套读数）",
            notifier.contains("result.attempts") && notifier.contains("result.elapsedMs"),
        )
        assertTrue(
            "队列落盘用同名键",
            store.contains("put(\"attempts\"") && store.contains("put(\"elapsedMs\""),
        )
        assertTrue(
            "队列出队也要交出去（少这一行 ⇒ 补拉那一路永远 0）",
            store.contains("\"attempts\" to") && store.contains("\"elapsedMs\" to"),
        )
        assertTrue(
            "Activity 读广播 extra 时必须映射回同名键",
            activity.contains("getIntExtra(\"attempts\"") &&
                activity.contains("getIntExtra(\"elapsed_ms\""),
        )
    }

    @Test
    fun bothDartReadersReadTheSameKeyPair() {
        // 两个读口：补拉（notification_service）与实时（main_page）。键名逐字为
        // attempts / elapsedMs —— 与原生出队 map 的那两枚是同一对。
        for (source in listOf(service, mainPage)) {
            assertTrue(
                "两条 Dart 读口都要读 attempts/elapsedMs（少一边 ⇒ 一半的送达没有取证）",
                source.contains("['attempts']") && source.contains("['elapsedMs']"),
            )
        }
        assertTrue(
            "写口必须把这两枚落进送达格",
            service.contains("'attempts': tried") && service.contains("'elapsedMs': spent"),
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
