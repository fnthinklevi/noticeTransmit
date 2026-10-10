package com.fnthink.notice

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * T131：常驻通知里那句「当日已推送 X 条」凭什么涨。
 *
 * ## 报上来的现象
 * 「继续读取设备通知、但暂停转发推送时，通知栏依然显示当日已推送 X 条，且这个数字还会递增。」
 *
 * ## 三份作者（改之前同一条句子上住着三个）
 * | 作者 | 涨的时机 | 与那句话对不对得上 |
 * |---|---|---|
 * | 服务里的内存计数 `pushCount` | 每次调四族扇出就 +1（五个调用点各写一遍） | **不对**：暂停闸住在每个通道里，拦下了也照样 +1 |
 * | `WidgetDailyCounter` | 每次**写历史**就 +1 | **不对**：被规则拦下的、"仅记录不推送"的都算 |
 * | Flutter 启动/恢复灌回的 `syncDailyPushCount` | DB 的**今日记录数**（同一天还取 maxOf） | **不对**：那是第三个口径，且把前两条的错又补回来 |
 *
 * ## 现在的口径
 * 只有一句：**这一发真的被推出去了才算**。判据是纯函数 [DailyPushCounter.countsAsPush]，
 * 累加点全库只有一处（`dispatchToChannels` 扇出之前）。所以本文件一半测判据、
 * 一半钉形状 —— 形状那半是防"第二份实现长回来"，那是本仓反复在治的那一类。
 */
class DailyPushCounterTest {

    private fun stripComments(src: String): String =
        src
            .replace(Regex("(?s)/\\*.*?\\*/"), "")
            .lines()
            .filterNot { it.trimStart().startsWith("//") }
            .joinToString("\n")

    private fun appFile(rel: String): java.io.File {
        var dir = java.io.File("").absoluteFile
        while (true) {
            val f = java.io.File(dir, "android/app/$rel")
            if (f.exists()) return f
            dir = dir.parentFile ?: break
        }
        throw AssertionError("找不到 $rel")
    }

    /** 取一个方法体：从签名到下一个 4 空格缩进的 `}`（与仓库里各 Kotlin 源码守卫同一口径）。 */
    private fun methodBody(src: String, signature: String): String {
        val start = src.indexOf(signature)
        assertTrue("找不到方法：$signature（签名改了 ⇒ 这条守卫要跟着改口径）", start >= 0)
        val end = src.indexOf("\n    }", start)
        assertTrue("读不到方法体结尾：$signature", end > start)
        return src.substring(start, end)
    }

    // ── 判据（纯函数）：暂停态不涨是这一条缺陷的本体，四个分支各挡一种"数字与那句话不符" ──

    @Test
    fun `暂停转发时扇出一次也不算推过`() {
        assertFalse(
            "T131 的本体：用户按了暂停 ⇒ 这一发根本没出门，栏里的数必须不动",
            DailyPushCounter.countsAsPush(pushActive = false, force = false, targets = 3),
        )
    }

    @Test
    fun `推送开着时扇出一次算一条`() {
        assertTrue(DailyPushCounter.countsAsPush(pushActive = true, force = false, targets = 1))
    }

    @Test
    fun `手动现在推送在暂停态下也算（那是用户明确点的一下）`() {
        assertTrue(
            DailyPushCounter.countsAsPush(pushActive = false, force = true, targets = 1),
        )
    }

    @Test
    fun `一个目标都没有就不算 —— 发无可发计入就是虚报`() {
        assertFalse(DailyPushCounter.countsAsPush(pushActive = true, force = false, targets = 0))
        assertFalse(
            "force 也救不了零目标：手动补推时一条通道都没配，同样什么都没发出去",
            DailyPushCounter.countsAsPush(pushActive = true, force = true, targets = 0),
        )
    }

    @Test
    fun `主备降级的那一轮仍然只算一条（判据不看走了哪条通道）`() {
        // viaBackup 不是这一判据的输入：走了备用也是"推了一发"，逐通道成败由送达记录负责。
        assertTrue(DailyPushCounter.countsAsPush(pushActive = true, force = false, targets = 2))
    }

    // ── 形状：一本账，防"第二份实现长回来" ──

    @Test
    fun `全库只剩一处累加点`() {
        val sources = appFile("src/main/kotlin/com/fnthink/notice")
            .walk()
            .filter { it.extension == "kt" }
            .filterNot { it.name == "DailyPushCounter.kt" }
            .toList()
        val hits = sources.flatMap { f ->
            stripComments(f.readText())
                .lines()
                .filter { it.contains("DailyPushCounter.record(") }
                .map { "${f.name}: ${it.trim()}" }
        }
        assertTrue(
            "「当日已推送」的累加点必须只有一处，实际 ${hits.size} 处：$hits",
            hits.size == 1,
        )
        assertTrue(
            "唯一那处累加点必须住在四族扇出里（`dispatchToChannels`）—— 长在别处就等于" +
                "又开了一个「这一轮推没推」的作者：$hits",
            hits.single().startsWith("NotificationMonitorService.kt"),
        )
    }

    @Test
    fun `三个旧作者不许复活`() {
        val src = appFile("src/main/kotlin/com/fnthink/notice")
            .walk()
            .filter { it.extension == "kt" }
            .joinToString("\n") { stripComments(it.readText()) }
        for (dead in listOf("pushCount", "WidgetDailyCounter", "syncDailyPushCount")) {
            assertFalse(
                "`$dead` 还在源码里 —— 那就是第二份口径又长回来了（T131 收口时它已零命中）",
                src.contains(dead),
            )
        }
    }

    @Test
    fun `常驻通知与桌面小部件读同一个作者`() {
        val service = stripComments(
            appFile("src/main/kotlin/com/fnthink/notice/NotificationMonitorService.kt").readText(),
        )
        val widget = stripComments(
            appFile("src/main/kotlin/com/fnthink/notice/PushToggleWidgetProvider.kt").readText(),
        )
        val body = methodBody(service, "private fun buildForegroundNotification()")
        assertTrue(
            "栏里那两句（监听中／已暂停）的计数不再来自同一个作者 ⇒ 又会分叉",
            body.contains("I18n.serviceListening(DailyPushCounter.todayCount(this))") &&
                body.contains("I18n.servicePushPaused(DailyPushCounter.todayCount(this))"),
        )
        assertTrue(
            "小部件那句「当日已推送」读的不是同一个作者",
            widget.contains("DailyPushCounter.todayCount(context)"),
        )
    }

    @Test
    fun `写历史那一条路上不再累加`() {
        val src = stripComments(
            appFile("src/main/kotlin/com/fnthink/notice/WebhookSender.kt").readText(),
        )
        val body = methodBody(src, "fun sendBroadcast(info: NotificationInfo)")
        assertFalse(
            "sendBroadcast 是「写历史」那一发，被规则拦下的通知也走它 —— 在这里累加" +
                "就等于把记录数冒充推送数",
            body.contains("Counter") || body.contains("updateAllWidgetsIfExists"),
        )
    }

    @Test
    fun `清空历史记录不许把当日计数抹平`() {
        val src = stripComments(
            appFile("src/main/kotlin/com/fnthink/notice/MainActivity.kt").readText(),
        )
        val body = methodBody(src, "internal fun clearNotificationRecords()")
        assertFalse(
            "删记录 ≠ 今天没推过：让 clearNotificationRecords 去动计数，就是让一个作者替另一个口径撒谎",
            body.contains("Counter") || body.contains("pushCount"),
        )
    }
}
