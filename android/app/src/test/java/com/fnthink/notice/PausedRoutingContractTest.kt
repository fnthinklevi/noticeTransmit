package com.fnthink.notice

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * T178：暂停推送不许被算成"通道失败"，也不许驱动主备切换。
 *
 * 两个缺陷各自都能静默发生：
 *  ① `ChannelAvailability.noteResult(..., success = status == SUCCESS)` 把 `PAUSED`
 *    算成一次失败。暂停期间来三条通知，主通道就攒满「连续失败 3 次」；
 *  ② `dispatchToChannels` 先走 `routeChannels`（输入含失败计数，且会 `applyDecision`
 *    锁存备用），再让每个通道各自回 `PAUSED`。于是"暂停"把主备关系永久改了。
 *
 * 行为测试需要真通道 + 暂停态才能复现，所以这里按源码形状钉住两条接线。
 */
class PausedRoutingContractTest {

    private fun source(rel: String): String {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            val candidate = File(dir, rel)
            if (candidate.exists()) {
                return stripComments(candidate.readText(Charsets.UTF_8))
            }
            dir = dir.parentFile
        }
        throw IllegalStateException("未找到 $rel（cwd=${File("").absolutePath}）")
    }

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
    fun `暂停分支在路由之前返回，且不碰备用锁存`() {
        val src = source("app/src/main/kotlin/com/fnthink/notice/NotificationMonitorService.kt")
        val body = functionBody(src, "private fun dispatchToChannels(")
        assertTrue("没找到 dispatchToChannels 函数体 —— 守卫本身失效了", body.isNotEmpty())

        val pauseAt = body.indexOf("!force && !PushToggleManager.isPushActive()")
        assertTrue("dispatchToChannels 里没有暂停分流 —— T178 的修复被删了", pauseAt >= 0)
        val routeAt = body.indexOf("routeChannels(")
        assertTrue("暂停分支之后找不到 routeChannels —— 按新结构重排", routeAt > pauseAt)

        val pausedBranch = body.substring(pauseAt, routeAt)
        assertTrue(
            "暂停分支没有 return —— 它会继续走主备路由，把暂停算成失败",
            pausedBranch.contains("return"),
        )
        assertFalse(
            "暂停分支里出现了 applyDecision/routeChannels 一类锁存调用",
            pausedBranch.contains("applyDecision") || pausedBranch.contains("routeChannels("),
        )
        assertTrue(
            "暂停分支没有给 webhook 族回 PAUSED（历史会停在发送中）",
            pausedBranch.contains("sendWebhooksOnly("),
        )
        assertTrue(
            "暂停分支没有给邮件族回 PAUSED",
            pausedBranch.contains("dispatchEmail("),
        )
        assertTrue(
            "暂停分支没有给幻念族回 PAUSED",
            pausedBranch.contains("dispatchFnthink("),
        )
    }

    @Test
    fun `可用性记账把 PAUSED 排除在外，且所有调用点传状态枚举`() {
        val availability = source(
            "app/src/main/kotlin/com/fnthink/notice/ChannelAvailability.kt",
        )
        val note = functionBody(availability, "fun noteResult(")
        assertTrue("没找到 noteResult 函数体 —— 守卫本身失效了", note.isNotEmpty())
        assertTrue(
            "noteResult 没有排除 PAUSED：暂停会被算成一次通道失败",
            note.contains("DeliveryStatus.PAUSED") && note.contains("return"),
        )

        for (rel in listOf(
            "AppChannelSender.kt",
            "WebhookSender.kt",
            "NotificationMonitorService.kt",
            "PhoneCallReceiver.kt",
            "SmsDispatcher.kt",
        )) {
            val src = source("app/src/main/kotlin/com/fnthink/notice/$rel")
            assertFalse(
                "$rel 还在用 success = result.status == SUCCESS 记账 ⇒ PAUSED 会被算成失败",
                src.contains("success = result.status =="),
            )
            assertTrue(
                "$rel 的 noteResult 没改传状态枚举",
                src.contains("status = result.status,"),
            )
        }
    }
}
