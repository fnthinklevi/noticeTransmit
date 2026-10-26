package com.fnthink.notice

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * T205：监听总开关/「仅电话与短信」门控的纯逻辑与源码守卫。
 *
 * 这组用例刻意分成两半：
 *  - `allowChain`/`allowSms` 的真值表 —— 证明判据本身正确；
 *  - 源码结构 —— 证明两条广播链真的在发送/留痕之前读了它，而不是“函数写对了没人用”。
 *    后者是这一行 P0 的病根：来电/短信链根本不在监听总开关的读者名单里。
 */
class CallSmsForwardingGateTest {

    // ===== 纯逻辑：allowChain =====

    @Test
    fun monitoringOn_alwaysAllowsChain() {
        assertTrue(CallSmsForwardingGate.allowChain(true, false))
        assertTrue(CallSmsForwardingGate.allowChain(true, true))
    }

    @Test
    fun monitoringOff_callSmsOn_allowsOnlyThatChain() {
        assertTrue(CallSmsForwardingGate.allowChain(false, true))
    }

    @Test
    fun bothOff_blocksChain() {
        assertFalse(CallSmsForwardingGate.allowChain(false, false))
    }

    // ===== 纯逻辑：短信合成式 =====

    @Test
    fun sms_monitoringOffCallSmsOn_smsSwitchStillWins() {
        // 监听关、独立开关开、短信子开关关 ⇒ 短信不发（只转电话是合法的一格）
        assertFalse(
            CallSmsForwardingGate.allowSms(
                monitoringEnabled = false,
                callSmsForwarding = true,
                smsMonitorEnabled = false,
                filterSlot = null,
                simSlot = null,
                codeMonitorEnabled = true,
                extractedCode = null,
            ),
        )
    }

    @Test
    fun sms_allThreeOn_allows() {
        assertTrue(
            CallSmsForwardingGate.allowSms(
                monitoringEnabled = false,
                callSmsForwarding = true,
                smsMonitorEnabled = true,
                filterSlot = null,
                simSlot = 0,
                codeMonitorEnabled = true,
                extractedCode = null,
            ),
        )
    }

    @Test
    fun sms_monitoringOn_zeroBehaviorChange() {
        assertTrue(
            CallSmsForwardingGate.allowSms(
                monitoringEnabled = true,
                callSmsForwarding = false,
                smsMonitorEnabled = true,
                filterSlot = 0,
                simSlot = 0,
                codeMonitorEnabled = true,
                extractedCode = null,
            ),
        )
    }

    @Test
    fun sms_newSwitchDoesNotOverrideSimFilterOrCodeGate() {
        assertFalse(
            CallSmsForwardingGate.allowSms(
                monitoringEnabled = false,
                callSmsForwarding = true,
                smsMonitorEnabled = true,
                filterSlot = 0,
                simSlot = 1,
                codeMonitorEnabled = true,
                extractedCode = null,
            ),
        )
        assertFalse(
            CallSmsForwardingGate.allowSms(
                monitoringEnabled = true,
                callSmsForwarding = false,
                smsMonitorEnabled = true,
                filterSlot = null,
                simSlot = null,
                codeMonitorEnabled = false,
                extractedCode = "123456",
            ),
        )
    }

    // ===== 源码守卫：键/默认值只有一位作者 =====

    private val forwardPrefs: String by lazy {
        stripComments(read("ForwardingPrefs.kt"))
    }
    private val receiver: String by lazy {
        stripComments(read("PhoneCallReceiver.kt"))
    }
    private val dispatcher: String by lazy {
        stripComments(read("SmsDispatcher.kt"))
    }
    private val service: String by lazy {
        stripComments(read("NotificationMonitorService.kt"))
    }
    private val widget: String by lazy {
        stripComments(read("PushToggleWidgetProvider.kt"))
    }

    @Test
    fun prefsKeysAndDefaultsAreInOnePlace() {
        assertTrue(
            "共享键少了 monitoring_enabled",
            forwardPrefs.contains("const val MONITORING_ENABLED = \"flutter.monitoring_enabled\""),
        )
        assertTrue(
            "共享键少了 call_sms_forwarding",
            forwardPrefs.contains("const val CALL_SMS_FORWARDING = \"flutter.call_sms_forwarding\""),
        )
        assertTrue(
            "监听总开关缺键必须取 true（与既有服务侧一致）",
            forwardPrefs.contains("getBoolean(MONITORING_ENABLED, true)"),
        )
        assertTrue(
            "新开关缺键必须取 false（默认不发）",
            forwardPrefs.contains("getBoolean(CALL_SMS_FORWARDING, false)"),
        )
    }

    @Test
    fun phoneChainGateRunsBeforeRoutingAndReadsDisk() {
        assertTrue(
            "来电链必须读盘的 monitoring_enabled",
            receiver.contains("ForwardingPrefs.monitoringEnabled(context)"),
        )
        assertTrue(
            "来电链必须过 allowChain",
            receiver.contains("CallSmsForwardingGate.allowChain"),
        )
        val gate = receiver.indexOf("CallSmsForwardingGate.allowChain")
        val routing = receiver.indexOf("WebhookRouting.routeWebhooks")
        assertTrue("来电链找不到 routeWebhooks ⇒ 这条守卫钉不住", routing > 0)
        assertTrue("闸必须在 routeWebhooks 之前（放发送口会造出历史落了、对面没收到）", gate < routing)
    }

    @Test
    fun smsChainGateRunsBeforeDedupAndRouting() {
        assertTrue(
            "短信链必须过 allowSms 合成式",
            dispatcher.contains("CallSmsForwardingGate.allowSms"),
        )
        val gate = dispatcher.indexOf("CallSmsForwardingGate.allowSms")
        val dedup = dispatcher.indexOf("val key = dedupKey(sender, message)")
        val routing = dispatcher.indexOf("WebhookRouting.routeWebhooks")
        assertTrue("短信链找不到 dedup 调用 ⇒ 守卫钉不住", dedup > 0)
        assertTrue("短信链找不到 routeWebhooks ⇒ 守卫钉不住", routing > 0)
        assertTrue("闸必须在去重之前", gate < dedup)
        assertTrue("闸必须在 routeWebhooks 之前", gate < routing)
    }

    @Test
    fun notificationPipeStillUsesMonitoringOnly() {
        assertTrue(
            "服务通知管道仍要读监听总开关",
            service.contains("if (!monitoringEnabled) return"),
        )
        assertFalse(
            "新开关只豁免电话/短信，不许在通知管道里当第二把总开关",
            service.contains("ForwardingPrefs.callSmsForwarding"),
        )
    }

    @Test
    fun widgetReadsTheSameNewKey() {
        assertTrue(
            "小部件必须从共享键读新开关",
            widget.contains("KEY_CALL_SMS_FORWARDING = ForwardingPrefs.CALL_SMS_FORWARDING"),
        )
        assertTrue(
            "小部件把新开关喂进 resolve",
            widget.contains("callSmsForwarding = flutter.getBoolean(KEY_CALL_SMS_FORWARDING, false)"),
        )
    }

    private fun read(name: String): String =
        File(SRC + name).readText()

    private companion object {
        const val SRC = "src/main/kotlin/com/fnthink/notice/"
    }
}
