package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 幻念推送收件显示的形状判定（`FnthinkInboxDisplay.specFor`）。
 *
 * 为什么这几条要跑在 JVM 上而不是等真机：一条通知"显示得对不对"里，只有画面上那两个字需要眼睛，
 * 其余全是**身份与归组**的算术 —— 而算术错了的后果是静默的：
 *  ① `id` 撞车 ⇒ 后一条把先一条从通知栏**抹掉**，用户以为没收到（这就是为什么 id 固定、
 *     区分全靠 tag；把 `messageId.hashCode()` 当 id 看着也行，直到它撞一次）；
 *  ② group 不跟着发送方走 ⇒ 一台 NAS 推十条会把通知栏刷满，而不是收成一组；
 *  ③ 标题为空不兜底 ⇒ 端点那一侧很多平台只给一个 `message` 字段，通知栏就是一片空白。
 */
class FnthinkInboxDisplayTest {

    private fun spec(
        messageId: String = "m_0123456789abcdef",
        sender: String = "8K3FJ6QPTM9WZ4VHNS",
        title: String = "机箱温度",
        body: String = "温度 63 度",
    ) = FnthinkInboxDisplay.specFor(
        messageId = messageId,
        sender = sender,
        title = title,
        body = body,
    )

    /** 从一个源文件里抠出 `CHANNEL_ID = "..."` 那个字面量。 */
    private fun channelLiteralIn(relativePath: String): String {
        val text = appFile(relativePath).readText()
        val found = Regex("CHANNEL_ID\\s*=\\s*\"([^\"]+)\"").find(text)
        return found?.groupValues?.get(1)
            ?: error("$relativePath 里找不到 CHANNEL_ID 字面量（那条断言就成了空转）")
    }

    /**
     * JVM 测试的 cwd 是 Gradle 模块根（`android/app`），所以相对路径从那里起算；
     * 向上找几层是为了在 IDE 里换 cwd 跑时仍然命中同一个文件 —— 直接拼 `user.dir` 会拼出
     * `android/app/android/app/...`，那条断言当场变成"文件不存在"，而这与"渠道其实重名了"
     * 在报告里长得不一样、却都指向同一条结论：这条守卫当时并没有在做事。
     */
    private fun appFile(rel: String): java.io.File {
        var dir: java.io.File? = java.io.File("").absoluteFile
        while (dir != null) {
            val candidate = java.io.File(dir, rel)
            if (candidate.exists()) return candidate
            dir = dir.parentFile
        }
        throw IllegalStateException("未找到 $rel（cwd=${java.io.File("").absolutePath}）")
    }

    @Test
    fun `区分靠 tag，id 是固定常量`() {
        val a = spec(messageId = "m_a")
        val b = spec(messageId = "m_b")
        assertEquals("m_a", a.tag)
        assertEquals("m_b", b.tag)
        assertEquals(
            "id 必须是常量：撞号的后果是一条把另一条顶掉",
            FnthinkInboxDisplay.NOTIFICATION_ID,
            a.notificationId,
        )
        assertEquals(FnthinkInboxDisplay.NOTIFICATION_ID, b.notificationId)
        assertNotEquals("同一条队列里的两条消息不能共用 tag", a.tag, b.tag)
    }

    @Test
    fun `同一条消息重发得到同一个形状，所以是替换不是叠两条`() {
        val first = spec(messageId = "m_dup")
        val again = spec(messageId = "m_dup", body = "同一件事的第二次投递")
        assertEquals(first.tag, again.tag)
        assertEquals(first.notificationId, again.notificationId)
        assertEquals(first.groupKey, again.groupKey)
    }

    @Test
    fun `归组按发送方：两个发送方不共用一组`() {
        assertEquals(
            "fnthink:8K3FJ6QPTM9WZ4VHNS",
            spec(sender = "8K3FJ6QPTM9WZ4VHNS").groupKey,
        )
        assertNotEquals(
            "端点来源与设备来源必须分组",
            spec(sender = "8K3FJ6QPTM9WZ4VHNS").groupKey,
            spec(sender = "endpoint:ep_7").groupKey,
        )
    }

    @Test
    fun `空标题退回正文第一行，两个都空才是空`() {
        assertEquals("温度 63 度", spec(title = "  ", body = "温度 63 度").title)
        assertEquals(
            "多行正文要取第一行，不是整段塞进标题位",
            "第一行",
            spec(title = "", body = "第一行\n第二行").title,
        )
        assertEquals("", spec(title = "", body = "   \n  ").title)
        assertEquals(
            "正文本身原样带着，不被标题逻辑改写",
            "第一行\n第二行",
            spec(title = "", body = "第一行\n第二行").text,
        )
    }

    @Test
    fun `渠道与前台服务那条常驻通知分开（读两个源文件比对，不为测试放宽可见性）`() {
        assertEquals("fnthink_inbox_v2", FnthinkInboxDisplay.CHANNEL_ID)
        assertEquals(FnthinkInboxDisplay.CHANNEL_ID, spec().channel)
        assertNotEquals(
            "混用渠道会让收件跟着服务通知的 IMPORTANCE_LOW 走（不响、不弹横幅）",
            channelLiteralIn(
                "src/main/kotlin/com/fnthink/notice/NotificationMonitorService.kt",
            ),
            FnthinkInboxDisplay.CHANNEL_ID,
        )
    }

    // ── T55：上岛 + 锁屏 + 角标（2026-10-05 维护者拍板走"换 CHANNEL_ID"那条路）──
    // 这三条里只有"角标那个数"是纯算术，能在 JVM 上断；另两条是**渠道建出来时的形状**，
    // JVM 测不到（要真机），所以下面两条用**读源文件**的方式钉住写没写 ——
    // 钉不住的那一半在 T55 的验收里，由真机那一格负责。

    @Test
    fun `T55 角标那个数随 spec 走，负数按 0 算`() {
        assertEquals(
            3,
            FnthinkInboxDisplay.specFor("m_1", "8K3FJ6QPTM9WZ4VHNS", "t", "b", unreadCount = 3)
                .unreadCount,
        )
        assertEquals(
            "负数会让部分桌面把角标画成\"消失\"，而调用方传负数的唯一原因是\"没数到\"",
            0,
            FnthinkInboxDisplay.specFor("m_1", "8K", "t", "b", unreadCount = -5).unreadCount,
        )
        assertEquals(
            "不给这个数时必须是 0 而不是抛：老 Dart 与通道被直调都会少这个键",
            0,
            FnthinkInboxDisplay.specFor("m_1", "8K", "t", "b").unreadCount,
        )
    }

    @Test
    fun `T55 上岛与锁屏写进渠道与通知两层（读源文件，不为测试放宽）`() {
        val src = appFile("src/main/kotlin/com/fnthink/notice/FnthinkInboxDisplay.kt")
            .readText()
        val body = stripComments(src)
        assertTrue(
            "渠道必须是 IMPORTANCE_HIGH：DEFAULT 进通知栏但不弹 heads-up（T55 ①）",
            body.contains("NotificationManager.IMPORTANCE_HIGH"),
        )
        assertTrue(
            "渠道层要写 lockscreenVisibility：这一层才是用户在系统设置里改的那一档（T55 ②）",
            body.contains("lockscreenVisibility = Notification.VISIBILITY_PUBLIC"),
        )
        assertTrue(
            "通知层要写 setVisibility：只写渠道那一层，通知仍可能落到 PRIVATE（T55 ②）",
            body.contains("setVisibility(NotificationCompat.VISIBILITY_PUBLIC)"),
        )
        assertTrue(
            "角标：渠道层显式 setShowBadge(true) ＋ 通知层 setNumber(T55 ③)",
            body.contains("setShowBadge(true)") && body.contains("setNumber(spec.unreadCount)"),
        )
        assertTrue(
            "换 id 之后必须留得住旧 id 的名字，否则\"上一版用的是哪个\"无从查证",
            body.contains("LEGACY_CHANNEL_ID"),
        )
        assertTrue(
            "DEFAULT 必须已经从渠道创建里消失（留着就是\"渠道建完还是 DEFAULT\"）",
            !body.contains("NotificationManager.IMPORTANCE_DEFAULT"),
        )
    }

    @Test
    fun `点通知带的 extra 键与消息 id 一起决定跳去哪条`() {
        assertEquals("extra_fnthink_message_id", FnthinkInboxDisplay.EXTRA_MESSAGE_ID)
        assertTrue(
            "消息 id 必须原样带进 spec（原生只负责把它塞进 Intent）",
            spec(messageId = "m_x7").messageId == "m_x7",
        )
    }

    /**
     * T55：**上岛 / 悬浮通知那一份提升只给推送那两枚渠道**，监控服务那条常驻通知不许动。
     *
     * ⚠ 这条钉的是**归属**，不是"有没有写那个 flag"：维护者 2026-10-05 纠正过一次 ——
     * 我原先把监控那条渠道从 LOW 升到 HIGH，理由是"靠悬浮通知发现设备被取消"，
     * 而那会让**被拦下的每一条通知都跟着弹一次横幅**（常驻通知每次更新都带最新内容）。
     * 真正的落点是：收件 / 远程执行那两条（用户据此察觉的东西）要提升，
     * 常驻那条**维持 LOW、安静待在通知栏**。
     */
    @Test
    fun 上岛提升只归推送那两枚_监控那条常驻通知维持原样() {
        val inbox = appFile("src/main/kotlin/com/fnthink/notice/FnthinkInboxDisplay.kt")
            .readText()
        val exec = appFile("src/main/kotlin/com/fnthink/notice/FnthinkRemoteExecDisplay.kt")
            .readText()
        val monitor = appFile("src/main/kotlin/com/fnthink/notice/NotificationMonitorService.kt")
            .readText()

        assertTrue(
            "收件那一枚要请求提升（它是用户看见「有消息到」的那条）",
            inbox.contains("NotificationPromoted.applyIfGranted"),
        )
        assertTrue(
            "远程执行那枚同样要（有人要动你的设备，更该弹出来）",
            exec.contains("NotificationPromoted.applyIfGranted"),
        )
        assertTrue(
            "监控服务那条常驻通知**不许**带提升 flag：它一动，被拦下的每一条通知都会跟着弹横幅",
            !monitor.contains("NotificationPromoted"),
        )
        assertTrue(
            "监控那条渠道必须维持 IMPORTANCE_LOW（LOW 只进通知栏、不弹悬浮通知）",
            monitor.contains("NotificationManager.IMPORTANCE_LOW"),
        )
        assertTrue(
            "渠道 id 也不许换：换 id 会让用户丢���那一枚渠道上的既有设置",
            monitor.contains("\"notification_monitor_channel\""),
        )
    }
}
