package com.fnthink.notice

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * T147②：一条规则扇出的历史组行，依赖**原生把组 id 随广播交给 Dart**。
 *
 * 这一条守卫钉的是那条跨语言接缝：组 id 只在原生算得出来（merge 的 `mergedId()` /
 * delay 的 fireAt），Dart 侧只是照单存映射。少传一个字段，历史页就永远没有组行，
 * 而两端各自的单元测试都绿 —— 这正是本仓反复踩过的"键名两处各写一份"的形状。
 */
class HistoryGroupContractTest {

    private fun appFile(rel: String): File {
        var dir = File("").absoluteFile
        while (true) {
            val f = File(dir, "android/app/$rel")
            if (f.exists()) return f
            dir = dir.parentFile ?: break
        }
        error("找不到 android/app/$rel")
    }

    private fun source(rel: String): String =
        stripComments(appFile("src/main/kotlin/com/fnthink/notice/$rel").readText())

    private fun stripComments(src: String): String =
        src
            .replace(Regex("(?s)/\\*.*?\\*/"), "")
            .lines()
            .filterNot { it.trimStart().startsWith("//") }
            .joinToString("\n")

    @Test
    fun `组 id 从原生随广播交出去（两个生产者各一枚）`() {
        val service = source("NotificationMonitorService.kt")
        assertTrue(
            "merge 成员必须带 append 决定的组 id（不是页面自己再拼一次）",
            Regex(
                """sendBroadcast\(\s*info,\s*appendResult\.memberGroupId,\s*"merge",?\s*\)""",
            ).containsMatchIn(service),
        )
        assertTrue(
            "delay 成员必须带同一 fireAt 的组 id（不是空串或写死的 0）",
            Regex(
                """sendBroadcast\(\s*info,\s*"delay:\$\{decision\.fireAt\}",\s*"delay",?\s*\)""",
            ).containsMatchIn(service),
        )
    }

    @Test
    fun `广播 JSON 真的有这两个字段（键名只此一处）`() {
        val sender = source("WebhookSender.kt")
        assertTrue(
            "historyGroupId 必须进广播 JSON",
            sender.contains("put(\"historyGroupId\", historyGroupId)"),
        )
        assertTrue(
            "historyGroupKind 必须进广播 JSON",
            sender.contains("put(\"historyGroupKind\", historyGroupKind)"),
        )
    }

    @Test
    fun `组 id 的拼法只有一个作者`() {
        val merge = source("MergePushManager.kt")
        assertTrue(
            "纯函数是唯一作者",
            merge.contains("fun memberGroupId(key: String, windowEnd: Long)"),
        )
        assertTrue(
            "mergedId() 也走这一枚，不许再手拼一遍",
            merge.contains("fun mergedId(): String = MergePushLogic.memberGroupId(key, windowEnd)"),
        )
        assertTrue(
            "AppendResult 把这一枚交回调用方",
            merge.contains("val memberGroupId: String"),
        )
    }
}
