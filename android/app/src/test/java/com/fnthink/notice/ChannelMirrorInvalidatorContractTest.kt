package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class ChannelMirrorInvalidatorContractTest {
    private fun source(name: String): String = stripComments(
        File("src/main/kotlin/com/fnthink/notice/$name").readText(),
    )

    private fun dart(name: String): String = stripComments(
        File("../../lib/services/$name").readText(),
    )

    @Test
    fun `四族发送读口都接受持久阻断闸`() {
        val config = source("ConfigManager.kt")
        for (signature in listOf(
            "fun getWebhookUrls()",
            "fun getWebhookChannelConfigs()",
            "fun getAppChannelConfigs()",
            "fun getFnthinkChannelConfigs()",
        )) {
            val start = config.indexOf(signature)
            assertTrue("缺少 $signature", start >= 0)
            val body = config.substring(start, config.indexOf("\n    }", start))
            assertTrue(
                "$signature 没有阻断闸",
                body.contains("ChannelMirrorInvalidator.isPending(context)"),
            )
        }
        val email = source("EmailManager.kt")
        val start = email.indexOf("fun getEnabledConfigs(context: Context)")
        assertTrue(start >= 0)
        val body = email.substring(start, email.indexOf("\n    }", start))
        assertTrue(body.contains("ChannelMirrorInvalidator.isPending(context)"))
    }

    @Test
    fun `失效键覆盖四族旧版回退与旧目标队列且落盘不用 apply`() {
        assertEquals(
            setOf(
                "flutter.webhook_channels",
                "flutter.webhook_urls",
                "flutter.webhook_url",
                "flutter.app_channels",
                "flutter.email_channels",
                "flutter.fnthink_channels",
                "flutter.fnthink_fanout_pending",
            ),
            ChannelMirrorInvalidator.plainKeys,
        )
        assertEquals(
            setOf(
                "secure_webhook_channels",
                "secure_app_channels",
                "email_channel_passwords",
                "webhook_retry_queue",
            ),
            ChannelMirrorInvalidator.secureKeys,
        )
        val invalidator = source("ChannelMirrorInvalidator.kt")
        assertTrue(invalidator.contains("SecurePrefs.isEncrypted(appContext)"))
        assertTrue(invalidator.contains("setOf(\"channels\")"))
        assertTrue(invalidator.contains("setOf(\"passwords\")"))
        assertTrue(invalidator.contains(".commit()"))
        assertFalse(invalidator.contains(".apply()"))
        assertTrue(invalidator.contains("store.prefs.contains(key)"))
    }

    @Test
    fun `pending 键两侧源码同串且只差 shared_preferences 前缀`() {
        val native = Regex("""const val KEY_PENDING = "([^"]+)"""")
            .find(source("ChannelMirrorInvalidator.kt"))
        assertTrue("原生 pending 键常量消失", native != null)
        val dart = Regex(
            """const String kChannelMirrorInvalidationPendingKey\s*=\s*[\r\n\s]*'([^']+)'""",
        ).find(dart("native_channel_invalidator.dart"))
        assertTrue("Dart pending 键常量消失", dart != null)
        assertEquals("flutter.${dart!!.groupValues[1]}", native!!.groupValues[1])
    }

    @Test
    fun `两阶段聚合入口失败必须异步落盘并回错`() {
        val handler = source("channels/ChannelMirrorInvalidationHandler.kt")
        assertTrue(handler.contains("phase == \"begin\""))
        assertTrue(handler.contains("ChannelMirrorInvalidator.begin(context)"))
        assertTrue(handler.contains("ioScope.launch"))
        assertTrue(handler.contains("ChannelMirrorInvalidator.invalidate(context)"))
        assertTrue(handler.contains("postError("))
        assertTrue(handler.contains("NotificationMonitorService.webhookUrls = emptyList()"))
        assertTrue(handler.contains("NotificationMonitorService.ACTION_UPDATE_CONFIG"))
    }

    @Test
    fun `前台与两个后台引擎都装配失效域`() {
        for (file in listOf(
            "MainActivity.kt",
            "FnthinkFanoutWorker.kt",
            "FnthinkPresenceWorker.kt",
        )) {
            assertTrue(
                "$file 没有装配 ChannelMirrorInvalidationHandler",
                source(file).contains("ChannelMirrorInvalidationHandler("),
            )
        }
    }

    private fun assertGateBefore(
        source: String,
        label: String,
        startNeedle: String,
        gateNeedle: String,
        markerNeedle: String,
    ) {
        val start = source.indexOf(startNeedle)
        assertTrue("$label 入口消失", start >= 0)
        val gate = source.indexOf(gateNeedle, start)
        val marker = source.indexOf(markerNeedle, start)
        assertTrue("$label 缺阻断闸", gate >= 0)
        assertTrue("$label 阻断闸晚于关键动作：$markerNeedle", marker >= 0 && gate < marker)
    }

    @Test
    fun `重试与幻念后台发送不能绕过阻断闸`() {
        val retry = source("RetryQueue.kt")
        assertGateBefore(
            retry,
            "RetryQueue.replayIfEligible",
            "fun replayIfEligible()",
            "ChannelMirrorInvalidator.isPending(context)",
            "PushToggleManager.isPushActive()",
        )
        assertGateBefore(
            retry,
            "RetryQueue.sendOne",
            "private fun sendOne(context: Context, item: RetryItem) {",
            "ChannelMirrorInvalidator.isPending(context)",
            "item.appChannelId",
        )
        assertGateBefore(
            source("AppChannelSender.kt"),
            "AppChannelSender.replayStored",
            "fun replayStored(item: RetryItem) {",
            "ChannelMirrorInvalidator.isPending(context)",
            "findAppChannelById",
        )
        assertGateBefore(
            source("FnthinkFanoutWorker.kt"),
            "FnthinkFanoutWorker.doWork",
            "override fun doWork(): Result {",
            "ChannelMirrorInvalidator.isPending(applicationContext)",
            "pendingCount()",
        )
        assertGateBefore(
            dart("fnthink_fanout_entrypoint.dart"),
            "后台幻念轮 claim",
            "Future<void> fnthinkFanoutEntrypoint(List<String>? args) async {",
            "isChannelMirrorInvalidationPending()",
            "claimPendingFanoutBatch()",
        )
        assertGateBefore(
            dart("fnthink_receive_coordinator.dart"),
            "sendNotice",
            "Future<FnthinkSendResult> sendNotice({",
            "isChannelMirrorInvalidationPending()",
            "_resolveSpec(requireEnabled: false)",
        )
    }
}
