package com.fnthink.notice

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File

/**
 * T12 发送层主备策略的契约守卫。
 *
 * 钉四件事，每件都对应一个"错了不会报错、只是行为不对"的静默故障：
 * 1. [ChannelRole.parse] 的取值矩阵 —— **认不出的一律 PRIMARY**。归成 NONE 的代价是
 *    某条通道从此静默收不到通知，归错方向不可接受。
 * 2. 跨语言的线值（`primary`/`backup`/`none`）与 Dart 侧 `ChannelConfigCodec` 一致。
 *    两边各写一份字符串，改一侧不会有编译期报错 —— 表现就是"设了备用，原生当主通道推"。
 * 3. 三个配置源（webhook / 自建应用 / 邮件）都排除 NONE；但「按 id 找通道」不排除，
 *    否则"不参与推送"的通道连手动测试都做不了。
 * 4. 扇出仍只有一个入口 [NotificationMonitorService.dispatchToChannels]。
 *    退回"三行在 7 个地方各写一遍"的形状，主备策略就会对新加的路径静默失效。
 */
class ChannelRoutingContractTest {

    // JUnit 的参数顺序是 (message, value)，与 kotlin.test 相反。守卫里"解释为什么红了"
    // 的文案比断言本身更有价值，所以统一走这两个尾置 message 的小助手。
    private fun assertTrue(condition: Boolean, message: String) =
        org.junit.Assert.assertTrue(message, condition)

    private fun <T> assertEquals(expected: T, actual: T, message: String) =
        org.junit.Assert.assertEquals(message, expected, actual)

    private fun repoFile(rel: String): File {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            val candidate = File(dir, rel)
            if (candidate.exists()) return candidate
            dir = dir.parentFile
        }
        throw IllegalStateException("未找到 $rel（cwd=${File("").absolutePath}）")
    }

    private fun native(rel: String) = stripComments(
        repoFile("app/src/main/kotlin/com/fnthink/notice/$rel").readText(Charsets.UTF_8)
    )

    @Test
    fun `角色解析：只有 backup 与 none 是例外，其余全是主通道`() {
        assertEquals(ChannelRole.BACKUP, ChannelRole.parse("backup"))
        assertEquals(ChannelRole.BACKUP, ChannelRole.parse("  BACKUP  "))
        assertEquals(ChannelRole.NONE, ChannelRole.parse("none"))
        assertEquals(ChannelRole.NONE, ChannelRole.parse("None"))
        // 缺省方向：缺列（老配置）、空串、认不出的值都必须是 PRIMARY
        assertEquals(ChannelRole.PRIMARY, ChannelRole.parse(null))
        assertEquals(ChannelRole.PRIMARY, ChannelRole.parse(""))
        assertEquals(ChannelRole.PRIMARY, ChannelRole.parse("tertiary"))
        assertEquals(ChannelRole.PRIMARY, ChannelRole.parse("null"))
    }

    @Test
    fun `线值与 Dart 侧 ChannelConfigCodec 一致`() {
        val codec = repoFile("lib/services/channel_config_codec.dart")
            .readText(Charsets.UTF_8)
        for (wire in listOf(ChannelRole.WIRE_PRIMARY, ChannelRole.WIRE_BACKUP, ChannelRole.WIRE_NONE)) {
            assertTrue(
                Regex("""'$wire'""").containsMatchIn(codec),
                "Dart 侧没有 '$wire'：跨端线值漂移，原生会把这一档读成主通道"
            )
        }
    }

    @Test
    fun `三个配置源都排除不参与，但按 id 找通道不排除`() {
        val cfg = native("ConfigManager.kt")
        val mail = native("EmailManager.kt")

        assertTrue(
            cfg.contains("if (role == ChannelRole.NONE) continue"),
            "webhook 配置源没排除 NONE：标记不参与的通道照旧被推"
        )
        assertTrue(
            cfg.contains("parseAppChannelConfigs().filter { it.role != ChannelRole.NONE }"),
            "自建应用配置源没排除 NONE"
        )
        assertTrue(
            mail.contains("if (role == ChannelRole.NONE) continue"),
            "邮件配置源没排除 NONE"
        )
        // 「测试」按钮按 id 取通道，必须看得见 NONE 的通道 —— 它用的是全量视图
        val byId = cfg.substringAfter("fun findAppChannelById(")
        assertTrue(
            byId.contains("parseAppChannelConfigs()") && !byId.contains("getAppChannelConfigs()"),
            "findAppChannelById 走了过滤后的视图：不参与推送的通道将无法手动测试"
        )
    }

    @Test
    fun `旧配置没有 role 字段时默认主通道`() {
        // 数据类默认值就是"升级后行为不变"的那道保险
        val legacy = AppChannelConfig(
            id = "app-1",
            name = "老通道",
            type = "wecom_app",
            baseUrl = "https://qyapi.weixin.qq.com",
            secret = "s",
            config = JSONObject(),
            messageFormat = "default",
            enabled = true,
        )
        assertEquals(ChannelRole.PRIMARY, legacy.role)
    }

    @Test
    fun `扇出只有一个入口，七个调用点都走它`() {
        val svc = native("NotificationMonitorService.kt")

        // 三行扇出（webhook + 应用 + 邮件）只允许出现在 dispatchToChannels 内部一次
        assertEquals(
            1,
            Regex("""webhookSender\.sendWebhooksOnly\(""").findAll(svc).count(),
            "webhook 扇出又出现第二处 ⇒ 主备策略会对新路径静默失效"
        )
        assertEquals(
            1,
            Regex("""appChannelSender\.sendOnly\(""").findAll(svc).count(),
            "自建应用扇出又出现第二处"
        )
        assertEquals(
            0,
            Regex("""webhookSender\.sendNotification\(""").findAll(svc).count(),
            "还在用绕过收口函数的旧写法"
        )
        // 定义 1 处 + 调用 ≥6 处（通知到达 / 延迟 / 聚合单条 / 聚合 flush / 手动 /
        // 设备态告警收口 dispatchDeviceAlert 内部那一处）
        assertTrue(
            Regex("""dispatchToChannels\(""").findAll(svc).count() >= 7,
            "收口后的调用点数量异常（应至少 7 处：1 个定义 + 6 个调用）",
        )
        // T23：设备态路不再直接扇出，改走带约束判定的 dispatchDeviceAlert。
        // 这层间接只允许有一个入口 —— 漏一条路 = 开关只管一半，而看起来仍然生效。
        // ⚠ 只认调用形状（带参数名）：定义行与注释里写的 `dispatchDeviceAlert()` 都不算 ——
        //   "注释里提一句"就能把裸计数做真，是本仓库反复踩过的那类假守卫。
        assertEquals(
            "设备态告警的出站调用必须是 3 处" +
                "（电量轮询、电量广播、T24 亮度/网络监听）",
            3,
            Regex("""dispatchDeviceAlert\(\w+\)""").findAll(svc).count(),
        )
        assertEquals(
            "出口函数只能有一个定义",
            1,
            Regex("""fun dispatchDeviceAlert\(""").findAll(svc).count(),
        )

        // 收口函数自己必须把三族都发出去，并且把 webhook 的汇总回调透传给聚合链路
        // （不透传 = 聚合成员又回到"写死成功"的老缺陷）。
        val funnel = svc.substringAfter("private fun dispatchToChannels(")
            .substringBefore("private class RoutedChannels(")
        // 具名参数各占一行是格式化器的结果，所以按"每个参数在三族调用里各出现一次"断言，
        // 不按整行文本匹配（整行匹配会随排版静默失效）。
        for ((pattern, why) in listOf(
            """force = force,""" to "暂停开关断了：暂停时手动补推推不出东西",
            """configs = routed\.\w+,""" to "路由子集断了：不参与本轮的通道照收通知",
            """viaBackup = routed\.viaBackup,""" to
                "降级标记断了：那一族的历史记录永远不会标「备用」，用户看不出消息换了出口",
        )) {
            assertEquals(
                3,
                Regex(pattern).findAll(funnel).count(),
                "收口函数调三族时 `$pattern` 不是恰好 3 处 —— $why"
            )
        }
        assertTrue(
            funnel.contains("onAllComplete = webhookCallback"),
            "收口函数没把汇总回调接上 webhook ⇒ 聚合成员回到「写死成功」"
        )
        assertTrue(
            funnel.contains("outer(r, routed.viaBackup)"),
            "webhook 汇总回调没带上降级标记 ⇒ 聚合链路的成员记录永远不标备用"
        )
        // 历史记录只在主链路写一次（补推/flush/手动都不得再播）
        assertTrue(funnel.contains("if (alsoBroadcastRecord) webhookSender.sendBroadcast(info)"),
            "写历史的条件没了 ⇒ 延迟补推会多出一条历史记录")
    }

    @Test
    fun `备用标记贯穿到送达回传的每一步`() {
        // 降级事实只有一份来源（路由决策），但要在**每一条**出口链路上传到底：
        // 广播 → MainActivity、持久化队列 → drain、以及扇出的三族。任何一环漏掉，
        // 表现都是"有时标有时不标"——比全不标更难排查，因为看起来像随机丢。
        val notifier = native("DeliveryNotifier.kt")
        assertTrue(
            notifier.contains("""putExtra("via_backup", viaBackup)"""),
            "实时广播链路没带 via_backup"
        )
        assertTrue(
            notifier.contains("DeliveryResultStore.push(") && notifier.contains("viaBackup"),
            "持久化兜底队列没写 via_backup ⇒ Activity 被杀期间的结果丢标记"
        )
        val store = native("DeliveryResultStore.kt")
        assertTrue(
            store.contains("""put("viaBackup", viaBackup)""") &&
                store.contains(""""viaBackup" to item.optBoolean("viaBackup", false)"""),
            "兜底队列的入队/出队字段不成对 ⇒ drain 回来永远是 false"
        )
        val main = native("MainActivity.kt")
        assertTrue(
            main.contains(""""viaBackup" to intent.getBooleanExtra("via_backup", false)"""),
            "MainActivity 转发时丢了 via_backup ⇒ 实时链路的历史记录不标备用"
        )
        // 聚合成员走 MERGE 伪通道，必须逐成员透传（否则聚合是唯一不标降级的路径）
        val merge = native("MergePushManager.kt")
        assertTrue(
            merge.contains("fun markMembersDelivered(") &&
                Regex("""notify\([\s\S]{0,120}viaBackup = viaBackup""").containsMatchIn(merge),
            "markMembersDelivered 没把降级标记传给每个成员"
        )
        // 暂停分支**不该**带标记（根本没投递），其余真实结果分支必须带
        val svc = native("NotificationMonitorService.kt")
        val email = svc.substringAfter("private fun dispatchEmail(")
        assertEquals(
            1,
            Regex("""notify\(this, info\.id, "EMAIL", \w+, viaBackup = viaBackup\)""").findAll(email).count(),
            "邮件真实结果没带降级标记（paused 分支应保持不带：那条消息没发出去）"
        )
        assertEquals(
            0,
            Regex("""paused, viaBackup""").findAll(email).count(),
            "邮件 paused 分支带了降级标记 ⇒ 未投递的记录被标成走了备用"
        )
        // Dart 侧：标记必须落到送达条目并粘滞（后到的结果不得抹掉已发生过的降级）
        val dart = stripComments(
            repoFile("lib/services/notification_service.dart").readText(Charsets.UTF_8)
        )
        assertTrue(
            dart.contains("viaBackup: map['viaBackup'] == true"),
            "Dart 兜底 drain 没读 viaBackup ⇒ 补偿路径不标备用"
        )
        assertTrue(
            dart.contains("""if (marked) 'viaBackup': true"""),
            "Dart 送达条目没有粘滞的 viaBackup 字段"
        )
    }
}
