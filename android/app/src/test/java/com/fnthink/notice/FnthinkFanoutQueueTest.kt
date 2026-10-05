package com.fnthink.notice

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * T94 片4「收到通知就转」那条链的契约守卫。
 *
 * 这一族错起来全是静默的，而症状高度相似 —— "通知到了、哪儿都没转"。所以逐条钉住
 * 每一处**会让这一族彻底不工作**的接缝：
 *  1. 落队这一发只允许出现在收口函数 `dispatchToChannels` 里（多一处 = 有路径绕过了
 *     "本轮该不该推"的裁决，而看起来仍然生效）；
 *  2. 设备目标必须真的落队 —— 走成 webhook 那一半的话，签名私钥与载荷在 Dart，
 *     原生直接 POST 会发出一个对端必然拒收的请求，而日志里是一条"成功"；
 *  3. 队列落进 `FlutterSharedPreferences`（后台那一侧的 Dart isolate 只读得到这一个文件），
 *     且键名与 Dart 侧那一串同形；
 *  4. 引擎那一侧必须有 `fanoutDone` 回报口，没有它 worker 只能等到超时。
 */
class FnthinkFanoutQueueTest {

    // 本项目用 JUnit 4（`message` 在前）。下面两个成员把三参调用改回 JUnit 5 的顺序，
    // 免得每一条断言都得把文案写在最前面 —— 文案比断言本身更有价值。
    private fun assertTrue(condition: Boolean, message: String) =
        org.junit.Assert.assertTrue(message, condition)

    private fun <T> assertEquals(expected: T, actual: T, message: String) =
        org.junit.Assert.assertEquals(message, expected, actual)

    private fun native(rel: String) = stripComments(
        repoFile("app/src/main/kotlin/com/fnthink/notice/$rel").readText(Charsets.UTF_8)
    )

    private fun repoFile(rel: String): File {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            val candidate = File(dir, rel)
            if (candidate.exists()) return candidate
            dir = dir.parentFile
        }
        throw IllegalStateException("未找到 $rel（cwd=${File("").absolutePath}）")
    }

    private fun info(id: String = "n1") = NotificationInfo(
        id = id, title = "标题", content = "正文", subText = "", packageName = "pkg",
        appName = "应用", postTime = 0L, time = "12:00", type = "normal", deviceName = "机器",
    )

    private fun target(
        id: String = "c1",
        kind: String = "device",
        role: ChannelRole = ChannelRole.PRIMARY,
    ) = FnthinkChannelConfig(id, "通道", kind, "target", role)

    // ===== 落队这一发只有一处 =====

    @Test
    fun `落队与排引擎只出现在 dispatchToChannels 里`() {
        val svc = native("NotificationMonitorService.kt")
        assertEquals(
            1,
            Regex("""FnthinkFanoutQueue\(""").findAll(svc).count(),
            "幻念落队点出现了第二处 ⇒ 有一条路径绕过了收口函数的推送暂停与主备裁决"
        )
        assertEquals(
            1,
            Regex("""FnthinkFanoutWorker\.schedule\(""").findAll(svc).count(),
            "排引擎出现了第二处 ⇒ 那一处多半没排在落队之后（队列会攒着不发）"
        )
        // 两件事必须**相邻**：先排后落队的表现是这一轮起引擎时读到空队列，
        // 而那一条会一直留到下一条通知才被带出去。
        val funnel = svc.substringAfter("private fun dispatchFnthink(").substringBefore("\n    }\n")
        val enqueueAt = funnel.indexOf("queue.enqueue(")
        val scheduleAt = funnel.indexOf("FnthinkFanoutWorker.schedule(")
        assertTrue(
            enqueueAt >= 0 && scheduleAt >= 0 && enqueueAt < scheduleAt,
            "必须先落队再排引擎（源码里顺序反了）"
        )
    }

    @Test
    fun `webhook 那一半不许走 Dart 队列`() {
        val svc = native("NotificationMonitorService.kt")
        val funnel = svc.substringAfter("private fun dispatchFnthink(").substringBefore("\n    }\n")
        assertTrue(
            Regex("""filterNot \{ it\.isWebhook \}""").containsMatchIn(funnel),
            "队列那一半必须是「非 webhook 的那些」—— 把 webhook 目标也塞进队列的表现是 " +
                "原生自己 POST 一个签名不存在的请求，日志里还显示已发出"
        )
        assertTrue(
            Regex("""dispatchFnthinkHook\(info, it""").containsMatchIn(funnel),
            "webhook 目标必须走原生那一半（NetworkClient 有重试、健康度与送达回执）"
        )
    }

    // ===== 队列的形状（纯函数）=====

    @Test
    fun `目标为空时不落队`() {
        assertNull(FnthinkFanoutQueue.buildItem(info(), emptyList(), false))
    }

    @Test
    fun `落队项带上这一轮的目标与降级标记`() {
        val item = FnthinkFanoutQueue.buildItem(info(), listOf(target(), target("c2")), true)!!
        assertEquals("n1", item.getString("id"))
        assertEquals("标题", item.getString("title"))
        assertEquals("正文", item.getString("content"))
        assertTrue(item.getBoolean("viaBackup"))
        assertEquals(2, item.getJSONArray("targets").length())
        assertEquals("device", item.getJSONArray("targets").getJSONObject(0).getString("target_kind"))
    }

    @Test
    fun `坏 JSON 退化成空数组而不是抛`() {
        assertEquals(0, FnthinkFanoutQueue.parseArray("not json").length())
        assertEquals(0, FnthinkFanoutQueue.parseArray(null).length())
        assertEquals(2, FnthinkFanoutQueue.parseArray("[{\"a\":1},{\"b\":2}]").length())
    }

    @Test
    fun `超出上限丢最旧并报出丢了多少`() {
        val arr = JSONArray()
        assertEquals(0, FnthinkFanoutQueue.mergeIntoArray(arr, JSONObject().put("id", "1"), 2))
        FnthinkFanoutQueue.mergeIntoArray(arr, JSONObject().put("id", "2"), 2)
        assertEquals(1, FnthinkFanoutQueue.mergeIntoArray(arr, JSONObject().put("id", "3"), 2))
        assertEquals(2, arr.length())
        assertEquals("2", arr.getJSONObject(0).getString("id"))
    }

    // ===== 跨语言接缝 =====

    @Test
    fun `队列落在后台那一侧读得到的那个文件里`() {
        val queue = native("FnthinkFanoutQueue.kt")
        assertTrue(
            queue.contains("ConfigManager.FLUTTER_PREFS_NAME"),
            "队列必须落进 FlutterSharedPreferences —— 另开一个 prefs 文件的话，后台 isolate " +
                "那一侧的 Dart 根本读不到（它的 SharedPreferences 只认这一个）"
        )
        assertTrue(
            Regex("""KEY_PENDING = "flutter\.fnthink_fanout_pending"""").containsMatchIn(queue),
            "待发键名变了 —— Dart 侧那一串（kFnthinkFanoutPendingKey）会读到空队列，" +
                "表现是每条通知都落队然后没人发"
        )
        val dart = repoFile("../lib/services/fnthink_fanout_entrypoint.dart").readText(Charsets.UTF_8)
        assertTrue(
            dart.contains("const String kFnthinkFanoutPendingKey = 'fnthink_fanout_pending'"),
            "Dart 侧那一串与原生不同形 ⇒ 读到空队列"
        )
    }

    @Test
    fun `入口键与回报口成对存在`() {
        val worker = native("FnthinkFanoutWorker.kt")
        assertTrue(
            Regex("""KEY_HANDLE = "flutter\.fnthink_fanout_handle"""").containsMatchIn(worker),
            "入口 handle 的键名变了 ⇒ 原生永远读到 0，日志一行 no-entry-handle"
        )
        assertTrue(
            Regex("""call\.method == "fanoutDone"""").containsMatchIn(worker),
            "没有 fanoutDone 回报口 ⇒ worker 只能等到超时，队列被取走却没人知道发没发成"
        )
        assertTrue(
            Regex("""enqueueUniqueWork\(UNIQUE_WORK, ExistingWorkPolicy\.KEEP""").containsMatchIn(worker),
            "必须用唯一工作名 + KEEP ⇒ 连着到的多条通知会各起一次引擎"
        )
    }
}