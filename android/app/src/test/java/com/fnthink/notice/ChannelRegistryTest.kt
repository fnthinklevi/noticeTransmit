package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 通道描述符表完整性守卫。
 *
 * 背景：通道行为已从 6 处散落的 `when` 收敛到 [ChannelRegistry] 描述符表——
 * 「新增通道只改表」的前提是**表必须完整**：加枚举值却漏登记表项，
 * 运行时会退化为 GENERIC（能推送但结构错误、状态判定错误，且**不报错**）。
 * 本类把「完整性」变成测试失败：
 *
 * 1. 每个 `WebhookType` 枚举值必须有且仅有一个表项；
 * 2. 表项的 notify/test/sms/call 四类载荷必须齐全（构造时非空，且可实际调用）；
 * 3. 每个表项必须登记 `parse`（响应判定）——漏登记会静默变成"HTTP 2xx 即成功"；
 * 4. host 规则不得重复（重复会导致识别结果依赖表顺序、行为不可预期）；
 * 5. GENERIC 不得占用 host（否则任何未知 URL 都会被识别成通用通道）。
 *
 * ⚠ 行为等价性由 `ChannelBehaviorGoldenTest` 逐字节快照锁定，本类只保证「结构完整」。
 */
class ChannelRegistryTest {

    private val specs = ChannelRegistry.CHANNELS

    private fun minimalNotifyInput() = NotifyInput(
        title = "t", content = "c", appName = "a", packageName = "p",
        time = "2026-01-01 10:00:00", deviceName = "d",
        notifyType = "notification", chatId = "1", extras = emptyMap(),
    )

    private fun minimalTestInput() = TestInput(
        title = "t", content = "c", deviceLabel = "d", sep = ":",
        deviceName = "d", chatId = "1",
    )

    private fun minimalSmsInput() = SmsInput(
        title = "t", sender = "s", message = "m", time = "2026-01-01 10:00:00",
        deviceName = "d", simInfo = null, simFooter = null, chatId = "1",
    )

    private fun minimalCallInput() = CallInput(
        state = "ringing", phoneNumber = "13800138000", time = "2026-01-01 10:00:00",
        durationStr = "", deviceName = "d", simInfo = null, simFooter = null, chatId = "1",
    )

    @Test
    fun everyEnumValueHasExactlyOneSpec() {
        val enumValues = WebhookPayloadBuilder.WebhookType.values()
        val specTypes = specs.map { it.type }
        val missing = enumValues.filter { it !in specTypes }
        assertTrue(
            "以下通道枚举值未在 ChannelRegistry 登记表项（会静默退化为 GENERIC）：$missing",
            missing.isEmpty()
        )
        assertEquals(
            "表项数（${specs.size}）与枚举值数（${enumValues.size}）不一致——存在重复表项",
            enumValues.size,
            specTypes.size
        )
        assertEquals(
            "存在重复的通道表项：${specTypes.groupingBy { it }.eachCount().filter { it.value > 1 }}",
            enumValues.size,
            specTypes.toSet().size
        )
    }

    @Test
    fun everySpecProvidesAllFourPayloadKindsAndActuallyRuns() {
        for (spec in specs) {
            val notify = spec.notify(minimalNotifyInput())
            val test = spec.test(minimalTestInput())
            val sms = spec.sms(minimalSmsInput())
            val call = spec.call(minimalCallInput())
            assertTrue("${spec.type} 通知载荷为空", notify.isNotBlank())
            assertTrue("${spec.type} 测试载荷为空", test.isNotBlank())
            assertTrue("${spec.type} 短信载荷为空", sms.isNotBlank())
            assertTrue("${spec.type} 通话载荷为空", call.isNotBlank())
        }
    }

    @Test
    fun everySpecRegistersParse() {
        val missing = specs.filter { it.parse == null }.map { it.type }
        assertTrue(
            "以下通道未登记 parse（响应判定会退化为「HTTP 2xx 即成功」）：$missing",
            missing.isEmpty()
        )
        // 可调用性：代表性成功响应不得抛异常
        for (spec in specs) {
            val result = spec.parse!!.invoke(
                200,
                org.json.JSONObject().apply { put("code", 0) },
                """{"code":0}"""
            )
            assertNotNull("${spec.type} parse 返回 null", result)
        }
    }

    @Test
    fun platformPayloadRegisteredForEnvelopeChannels() {
        // 支持平台模板包装的 5 个通道必须有 platformPayload；其余必须为 null（走文本路径）
        val expected = setOf(
            WebhookPayloadBuilder.WebhookType.WECHAT_WORK,
            WebhookPayloadBuilder.WebhookType.DINGTALK,
            WebhookPayloadBuilder.WebhookType.FEISHU,
            WebhookPayloadBuilder.WebhookType.TELEGRAM,
            WebhookPayloadBuilder.WebhookType.BARK,
        )
        for (spec in specs) {
            if (spec.type in expected) {
                assertNotNull("${spec.type} 缺少 platformPayload（自定义模板 + 平台格式会失效）", spec.platformPayload)
            } else {
                assertEquals("${spec.type} 不应登记 platformPayload", null, spec.platformPayload)
            }
        }
    }

    @Test
    fun hostsAreUniqueAndGenericHasNone() {
        val allHosts = specs.flatMap { it.hosts }
        val dup = allHosts.groupingBy { it }.eachCount().filter { it.value > 1 }
        assertTrue("host 规则重复（识别结果将依赖表顺序）：$dup", dup.isEmpty())

        val generic = specs.first { it.type == WebhookPayloadBuilder.WebhookType.GENERIC }
        assertTrue(
            "GENERIC 不得占用 host——否则未知 URL 会被误识别为通用通道",
            generic.hosts.isEmpty()
        )
        // 自动识别仍能命中既有平台（防表内 hosts 写错导致识别回归）
        assertEquals(
            WebhookPayloadBuilder.WebhookType.WECHAT_WORK,
            ChannelRegistry.typeByHost("qyapi.weixin.qq.com")
        )
        assertEquals(
            WebhookPayloadBuilder.WebhookType.TELEGRAM,
            ChannelRegistry.typeByHost("api.telegram.org")
        )
        assertEquals(null, ChannelRegistry.typeByHost("example.com"))
    }

    @Test
    fun detectTypeStillWorksEndToEnd() {
        // 覆盖既有 detectType 契约（原 WebhookPayloadBuilderTest 的用例继续保留）
        assertEquals(
            WebhookPayloadBuilder.WebhookType.DINGTALK,
            WebhookPayloadBuilder.detectType("https://oapi.dingtalk.com/robot/send?access_token=x")
        )
        assertEquals(
            WebhookPayloadBuilder.WebhookType.GENERIC,
            WebhookPayloadBuilder.detectType("not a url")
        )
    }
}
