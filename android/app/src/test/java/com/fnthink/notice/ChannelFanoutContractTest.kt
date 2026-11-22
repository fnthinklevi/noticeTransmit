package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * P1-2：通道扇出从 `NotificationMonitorService` 搬进 `ChannelFanout` 后的装配守卫。
 *
 * 这一刀最怕两种半拆：
 *  - Service 里还留着一份实现（两处各改一半，暂停/主备语义在真机上才现形）；
 *  - `channelFanout` 还没初始化就被调用（`lateinit` 在 onCreate 之前抛
 *    UninitializedPropertyAccessException，且只在特定启动路径上出现）。
 *
 * 所以这里同时钉"薄壳的形状"与"初始化顺序"，而不只是看类名在不在。
 */
class ChannelFanoutContractTest {

    private val repoRoot: File = run {
        val candidates = listOf(File("../.."), File("."), File(".."))
        candidates.firstOrNull {
            File(it, "android/app/src/main/kotlin/com/fnthink/notice").isDirectory
        } ?: error("无法定位仓库根目录（cwd=${File(".").absolutePath}）")
    }

    private fun source(name: String): String {
        val f = File(repoRoot, "android/app/src/main/kotlin/com/fnthink/notice/$name")
        assertTrue("源文件不存在: ${f.absolutePath}", f.isFile)
        return stripComments(f.readText())
    }

    private fun bodyOf(src: String, signature: String): String {
        val start = src.indexOf(signature)
        assertTrue("未找到 $signature", start >= 0)
        val brace = src.indexOf('{', start)
        var depth = 0
        for (i in brace until src.length) {
            when (src[i]) {
                '{' -> depth++
                '}' -> {
                    depth--
                    if (depth == 0) return src.substring(brace, i + 1)
                }
            }
        }
        error("函数体大括号不配对：$signature")
    }

    @Test
    fun `Service 只留薄壳，实现只在 ChannelFanout`() {
        val service = source("NotificationMonitorService.kt")
        val fanout = source("ChannelFanout.kt")

        val shell = bodyOf(service, "private fun dispatchToChannels(")
        assertTrue("薄壳没有转交 ChannelFanout", shell.contains("channelFanout.dispatch("))
        assertFalse(
            "Service 里还留着扇出实现（webhook 发送体）⇒ 两处各改一半",
            shell.contains("webhookSender.sendWebhooksOnly("),
        )
        assertFalse(
            "Service 里还留着 routeChannels 定义 ⇒ 主备裁决有第二份",
            service.contains("private fun routeChannels("),
        )

        for (needle in listOf(
            "private fun dispatchToChannels(",
            "private class RoutedChannels(",
            "private fun routeChannels(",
            "private fun dispatchFnthink(",
            "private fun dispatchFnthinkHook(",
            "private fun dispatchEmail(",
        )) {
            assertTrue("ChannelFanout 缺 $needle", fanout.contains(needle))
            val expectedInService = if (needle == "private fun dispatchToChannels(") 1 else 0
            assertEquals(
                "$needle 在 Service 里的份数不对（薄壳应为 1，其余应为 0）",
                expectedInService,
                Regex(Regex.escape(needle)).findAll(service).count(),
            )
        }
    }

    @Test
    fun `ChannelFanout 的依赖全部显式传入，且初始化在 configManager 之后`() {
        val fanout = source("ChannelFanout.kt")
        for (needle in listOf(
            "private val context: Context",
            "private val configManager: ConfigManager",
            "private val webhookSender: WebhookSender",
            "private val appChannelSender: AppChannelSender",
            "private val scope: CoroutineScope",
        )) {
            assertTrue("ChannelFanout 缺依赖 $needle", fanout.contains(needle))
        }
        assertFalse(
            "通道扇出不许再直接摸 Service 的字段/单例",
            fanout.contains("NotificationMonitorService.instance"),
        )

        val service = source("NotificationMonitorService.kt")
        val cfgAt = service.indexOf("configManager = ConfigManager(this)")
        val fanoutAt = service.indexOf(
            "channelFanout = ChannelFanout(this, configManager, webhookSender, appChannelSender, serviceScope)",
        )
        assertTrue("Service 没有创建 channelFanout", fanoutAt > -1)
        assertTrue("channelFanout 必须在 configManager 之后创建", fanoutAt > cfgAt)
    }
}
