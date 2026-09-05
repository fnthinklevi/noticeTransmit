package com.fnthink.notice

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * TemplateEngine 单元测试（纯逻辑，JVM 直测）。
 * 覆盖：变量替换、JSON/XML 转义、平台 payload 包裹、格式兼容性判定。
 */
class TemplateEngineTest {

    private val vars = TemplateEngine.Vars(
        appName = "测试应用",
        title = "标题",
        content = "内容\"引号\"&<标签>",
        time = "2026-01-01 12:00:00",
        deviceName = "Pixel",
        packageName = "com.a.b",
        notifyType = "notification",
        timestamp = 1700000000000L
    )

    @Test
    fun render_replacesAllPlaceholders() {
        val out = TemplateEngine.render(
            "%appName%|%title%|%content%|%time%|%deviceName%|%packageName%|%notifyType%",
            vars
        )
        assertEquals("测试应用|标题|内容\"引号\"&<标签>|2026-01-01 12:00:00|Pixel|com.a.b|notification", out)
    }

    @Test
    fun render_emptyTemplateReturnsEmpty() {
        assertEquals("", TemplateEngine.render("", vars))
    }

    @Test
    fun render_unknownPlaceholderKeptAsIs() {
        assertEquals("%noSuchVar%", TemplateEngine.render("%noSuchVar%", vars))
    }

    @Test
    fun render_jsonTemplateEscapesQuoteAndBackslash() {
        val out = TemplateEngine.render("""{"c":"%content%"}""", vars)
        val json = JSONObject(out)
        assertEquals("内容\"引号\"&<标签>", json.getString("c"))
    }

    @Test
    fun render_xmlTemplateEscapesXmlEntities() {
        val out = TemplateEngine.render("<n>%content%</n>", vars)
        assertFalse(out.contains("<标签>"))
        assertTrue(out.contains("&amp;&lt;标签&gt;"))
    }

    @Test
    fun render_nullOptionalVarsBecomeEmpty() {
        val out = TemplateEngine.render("[%sender%][%simInfo%]", vars)
        assertEquals("[][]", out)
    }

    @Test
    fun isPlatformSupported_matrix() {
        assertTrue(TemplateEngine.isPlatformSupported("default"))
        assertTrue(TemplateEngine.isPlatformSupported("text"))
        assertTrue(TemplateEngine.isPlatformSupported("markdown"))
        assertFalse(TemplateEngine.isPlatformSupported("json"))
        assertFalse(TemplateEngine.isPlatformSupported("xml"))
    }

    @Test
    fun buildGenericBody_contentTypePerFormat() {
        val json = TemplateEngine.buildGenericBody("json", """{"t":"%title%"}""", vars)!!
        assertEquals("application/json; charset=utf-8", json.second)
        val xml = TemplateEngine.buildGenericBody("xml", "<t>%title%</t>", vars)!!
        assertEquals("application/xml; charset=utf-8", xml.second)
        val text = TemplateEngine.buildGenericBody("text", "%title%", vars)!!
        assertEquals("text/plain; charset=utf-8", text.second)
    }

    @Test
    fun buildGenericBody_defaultFormatReturnsNull() {
        assertNull(TemplateEngine.buildGenericBody("default", "", vars))
    }

    @Test
    fun buildPlatformPayload_defaultReturnsNull() {
        assertNull(
            TemplateEngine.buildPlatformPayload(
                WebhookPayloadBuilder.WebhookType.WECHAT_WORK, "default", "", vars
            )
        )
    }

    @Test
    fun buildPlatformPayload_wechatWorkText() {
        val payload = TemplateEngine.buildPlatformPayload(
            WebhookPayloadBuilder.WebhookType.WECHAT_WORK, "text", "T:%title%", vars
        )!!
        val json = JSONObject(payload)
        assertEquals("text", json.getString("msgtype"))
        assertEquals("T:标题", json.getJSONObject("text").getString("content"))
    }

    @Test
    fun buildPlatformPayload_dingtalkMarkdownKeepsTitle() {
        val payload = TemplateEngine.buildPlatformPayload(
            WebhookPayloadBuilder.WebhookType.DINGTALK, "markdown", "## %title%", vars
        )!!
        val json = JSONObject(payload)
        assertEquals("markdown", json.getString("msgtype"))
        assertEquals("标题", json.getJSONObject("markdown").getString("title"))
    }

    @Test
    fun buildPlatformPayload_feishuMarkdownDowngradesToText() {
        // 飞书自定义机器人不支持 markdown msg_type，必须降级为 text 保证送达
        val payload = TemplateEngine.buildPlatformPayload(
            WebhookPayloadBuilder.WebhookType.FEISHU, "markdown", "## %title%", vars
        )!!
        val json = JSONObject(payload)
        assertEquals("text", json.getString("msg_type"))
        assertEquals("## 标题", json.getJSONObject("content").getString("text"))
    }

    @Test
    fun buildPlatformPayload_jsonUnsupportedForPlatforms() {
        assertNull(
            TemplateEngine.buildPlatformPayload(
                WebhookPayloadBuilder.WebhookType.WECHAT_WORK, "json", "{}", vars
            )
        )
    }

    @Test
    fun buildPlatformPayload_serverChanAndPushPlusNotWrapped() {
        assertNull(
            TemplateEngine.buildPlatformPayload(
                WebhookPayloadBuilder.WebhookType.SERVER_CHAN, "text", "%title%", vars
            )
        )
        assertNull(
            TemplateEngine.buildPlatformPayload(
                WebhookPayloadBuilder.WebhookType.PUSH_PLUS, "text", "%title%", vars
            )
        )
    }
}
