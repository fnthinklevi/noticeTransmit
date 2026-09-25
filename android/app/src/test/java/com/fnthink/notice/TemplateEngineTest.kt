package com.fnthink.notice

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
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
    fun formatOptionsAreTheSingleSourceAndAllUsable() {
        // T08-B：档位名单在原生只有一份（Dart 经 getChannelDescriptors 取用）。
        // 名单里每个非 default 档位都必须真的有预置模板 —— 否则用户在界面上选了它，
        // 发出去的却和没选一样；反过来 default 与未知值必须回 null（交给平台包装）。
        assertEquals(
            "档位名单不得重复（Dart 选择器会出现两个同名项）",
            TemplateEngine.formatOptions.size,
            TemplateEngine.formatOptions.toSet().size,
        )
        assertEquals(
            "default 必须是第一项：它表示\"不覆写平台包装\"，是新增通道的缺省档",
            "default",
            TemplateEngine.formatOptions.first(),
        )
        for (format in TemplateEngine.formatOptions.drop(1)) {
            assertNotNull(
                "$format 在名单里却没有预置模板：选了它等于选了一个没用的档位",
                TemplateEngine.presetTemplate(format),
            )
        }
        assertNull("'default' 不该有预置模板", TemplateEngine.presetTemplate("default"))
        assertNull(
            "未知档位必须回 null（存量数据里出现过的值不能凭空造模板）",
            TemplateEngine.presetTemplate("noSuchFormat"),
        )
    }

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
