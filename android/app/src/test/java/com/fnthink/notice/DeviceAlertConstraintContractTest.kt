package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * T23：设备态告警（电量/温度）接受约束 —— 语义 + 接线两条都钉。
 *
 * 现状的洞：两条设备态触发路（`BatteryMonitor` 轮询、`ACTION_BATTERY_CHANGED` 广播）
 * 汇到告警之后**各自直接** `dispatchToChannels`，把"这条要不要转"的那套约束整个绕过了。
 * 用户拉黑了"验证码"，一条电量告警里带着这三个字照样推出去。
 *
 * 开关默认关 ⇒ 今天所有设备的行为逐字节不变；开启后走的是**同一个** `FilterEngine`
 * （约束只该有一套语义，抄第二份迟早一份松一份紧），并且刻意不带 `sourceType = "notification"`
 * —— 设备态告警由本机自己产生，让它受"只转发这些应用"管辖，得到的只会是
 * "配了白名单之后电量告警永远不来"。
 *
 * 两条判据分工：
 *  - [deviceAlertsHonorKeywordsButIgnoreAppFilter] 钉**语义**（纯函数，真跑）；
 *  - [bothBatteryPathsGoThroughTheGate] 钉**接线**（源码契约：漏一条路 = 那条路上的告警不受约束，
 *    而开关看起来是生效的 —— 这类"只管一半"的缺陷静态测不出来就只能靠人肉记）。
 */
class DeviceAlertConstraintContractTest {

    private val repoRoot: File = run {
        val candidates = listOf(File("../.."), File("."), File(".."))
        candidates.firstOrNull {
            File(it, "android/app/src/main/kotlin/com/fnthink/notice").isDirectory
        } ?: error("无法定位仓库根目录（cwd=${File(".").absolutePath}）")
    }

    private fun source(rel: String): String =
        File(repoRoot, rel).readText()

    private val servicePath =
        "android/app/src/main/kotlin/com/fnthink/notice/NotificationMonitorService.kt"

    @Test
    fun deviceAlertsHonorKeywordsButIgnoreAppFilter() {
        // 应用白名单模式：只允许 com.other。设备态告警的包名是本机自己 ⇒ 若是
        // "notification" 会被应用过滤拦掉，而 sourceType="device" 不适用应用过滤。
        val appOnly = FilterEngine.filter(
            packageName = "com.fnthink.notice",
            title = "电量低于20%",
            content = "当前 15%",
            subText = "",
            whitelistKeywords = emptyList(),
            enabledPackages = setOf("com.other"),
            blacklistKeywords = emptyList(),
            filterMode = "allow",
            sourceType = "device",
        )
        assertTrue("设备态告警不该被应用白名单拦死（那等于配了白名单就再也没有电量告警）", appOnly.allowed)
        assertFalse(
            "对照组：同一条按 notification 判必须被应用过滤拦下（否则上面那条是空话）",
            FilterEngine.filter(
                packageName = "com.fnthink.notice",
                title = "电量低于20%",
                content = "当前 15%",
                subText = "",
                whitelistKeywords = emptyList(),
                enabledPackages = setOf("com.other"),
                blacklistKeywords = emptyList(),
                filterMode = "allow",
                sourceType = "notification",
            ).allowed,
        )

        val blocked = FilterEngine.filter(
            packageName = "com.fnthink.notice",
            title = "电量低于20%",
            content = "当前 15%",
            subText = "",
            whitelistKeywords = emptyList(),
            enabledPackages = emptySet(),
            blacklistKeywords = listOf("电量"),
            filterMode = "allow",
            sourceType = "device",
        )
        assertFalse("关键词黑名单命中必须同样作用于设备态告警", blocked.allowed)
        assertEquals(FilterSource.BLACKLIST, blocked.source)

        val tag = FilterEngine.filter(
            packageName = "com.fnthink.notice",
            title = "电量低于20%",
            content = "当前 15%",
            subText = "",
            whitelistKeywords = listOf("电量"),
            enabledPackages = setOf("com.other"),
            blacklistKeywords = emptyList(),
            filterMode = "allow",
            sourceType = "device",
        )
        assertTrue(tag.allowed)
        assertEquals(FilterSource.WHITELIST, tag.source)
    }

    @Test
    fun everyDeviceStatePathGoesThroughTheGate() {
        val src = source(servicePath)
        // 三条路：轮询回调（setNotificationCallback）、电量广播 receiver、T24 的亮度/网络监听。
        // ⚠ 计数只认**调用形状** `dispatchDeviceAlert(x)`：定义那行带类型标注、注释里写的是
        //   空括号，都不该算进来（本仓库反复踩过"注释里的字符串把判据做真"，这里连撞一次）。
        assertEquals(
            "设备态告警的出站必须只有 dispatchDeviceAlert 一个口（轮询、广播、监听三处调用）",
            3,
            Regex("""dispatchDeviceAlert\(\w+\)""").findAll(src).count(),
        )
        assertEquals(
            "出口函数只能有一个定义",
            1,
            Regex("""fun dispatchDeviceAlert\(""").findAll(src).count(),
        )
        assertFalse(
            "还有一条路直接 dispatchToChannels(batteryInfo) ⇒ 开关只管一半，看起来却像生效了",
            Regex("""dispatchToChannels\(\s*batteryInfo""").containsMatchIn(src),
        )

        val gate = src.substring(src.indexOf("private fun dispatchDeviceAlert("))
        val body = gate.substring(0, gate.indexOf("\n    }\n") + 6)
        assertTrue(
            "开关不判就直接放行 ⇒ 默认关的语义变成了永远开",
            body.contains("if (config.deviceAlertConstraint)"),
        )
        assertTrue(
            "约束判定必须复用 notificationProcessor.filter（FilterEngine 那一个点）",
            body.contains("notificationProcessor.filter("),
        )
        assertTrue(
            "sourceType 必须是 device：写成 notification 会让应用白名单把设备态告警全拦掉",
            body.contains("""sourceType = "device""""),
        )
        // 不静默丢失：拦下来要留痕（历史 + 送达状态），否则用户只看到"今天没响"。
        assertTrue(body.contains("webhookSender.sendBroadcast(info)"))
        assertTrue(body.contains("\"FILTER\""))
        assertTrue(
            "缺了原因文本，历史里那条记录就只剩「没推出去」而已",
            body.contains("blockReason()"),
        )
    }

    @Test
    fun switchKeyIsTheSameStringOnBothSides() {
        val configManager = source(
            "android/app/src/main/kotlin/com/fnthink/notice/ConfigManager.kt",
        )
        val batteryService = source("lib/services/battery_service.dart")
        // 原生读 flutter.<key>，Dart 侧 SharedPreferences 自动加 flutter. 前缀 ⇒
        // 两端各自写的字符串必须正好差这一个前缀（写错一个字母 = 开关永久无效且两侧都绿）。
        assertTrue(
            configManager.contains("\"flutter.device_alert_constraint_enabled\""),
        )
        val dartKey = Regex("""'device_alert_constraint_enabled'""").findAll(batteryService).count()
        assertTrue("Dart 侧没写这把键 ⇒ 原生读到的一直是默认值 false", dartKey >= 2)
        assertTrue(
            "默认值必须是 false：开启会改变已有设备的告警行为",
            configManager.contains("getBoolean(KEY_DEVICE_ALERT_CONSTRAINT, false)"),
        )
        assertEquals(
            "原生不许自己写这把键（唯一写入者是 Dart）",
            0,
            Regex("putBoolean\\(KEY_DEVICE_ALERT_CONSTRAINT").findAll(configManager).count(),
        )
    }
}
