package com.fnthink.notice

import com.fnthink.notice.WebhookPayloadBuilder.WebhookType
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * WebhookPayloadBuilder 单元测试（纯逻辑，JVM 直测）。
 * 覆盖：平台类型探测（host 精确匹配）、各平台 payload 结构、URL 参数提取、form body 编码。
 */
class WebhookPayloadBuilderTest {

    private val B = WebhookPayloadBuilder

    // ===== detectType：host 精确匹配（不允许子串误判）=====

    @Test
    fun detectType_matchesAllPlatformHosts() {
        assertEquals(WebhookType.WECHAT_WORK, B.detectType("https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=k"))
        assertEquals(WebhookType.DINGTALK, B.detectType("https://oapi.dingtalk.com/robot/send?access_token=x"))
        assertEquals(WebhookType.FEISHU, B.detectType("https://open.feishu.cn/open-apis/bot/v2/hook/x"))
        assertEquals(WebhookType.FEISHU, B.detectType("https://open.larksuite.com/open-apis/bot/v2/hook/x"))
        assertEquals(WebhookType.TELEGRAM, B.detectType("https://api.telegram.org/bot123/sendMessage?chat_id=1"))
        assertEquals(WebhookType.BARK, B.detectType("https://api.day.app/abc/内容"))
        assertEquals(WebhookType.SERVER_CHAN, B.detectType("https://sctapi.ftqq.com/SCT.send"))
        assertEquals(WebhookType.PUSH_PLUS, B.detectType("https://www.pushplus.plus/send?token=t"))
    }

    @Test
    fun detectType_unknownOrInvalidUrlFallsBackToGeneric() {
        assertEquals(WebhookType.GENERIC, B.detectType("https://example.com/hook"))
        assertEquals(WebhookType.GENERIC, B.detectType("not a url"))
        assertEquals(WebhookType.GENERIC, B.detectType(""))
    }

    @Test
    fun detectType_stripsCredentialsPortAndCase() {
        // userinfo / 端口 / 大写 host 均不影响判定
        assertEquals(
            WebhookType.WECHAT_WORK,
            B.detectType("https://user:pass@QYAPI.WEIXIN.QQ.COM:443/cgi-bin/webhook/send")
        )
    }

    @Test
    fun detectType_hostSubstringDoesNotMatch() {
        // 仿冒 host（平台域名作为子串）不得命中平台规则
        assertEquals(WebhookType.GENERIC, B.detectType("https://qyapi.weixin.qq.com.evil.io/send"))
    }

    // ===== buildPayload：平台结构 =====

    private fun build(type: WebhookType, chatId: String = "") = B.buildPayload(
        type = type,
        title = "标题",
        content = "内容",
        appName = "应用",
        packageName = "com.a.b",
        time = "12:00",
        deviceName = "Pixel",
        notifyType = "notification",
        chatId = chatId
    )

    @Test
    fun buildPayload_wechatWork_textStructure() {
        val json = JSONObject(build(WebhookType.WECHAT_WORK))
        assertEquals("text", json.getString("msgtype"))
        val text = json.getJSONObject("text").getString("content")
        assertTrue(text.contains("标题"))
        assertTrue(text.contains("内容"))
        assertTrue(text.contains("应用"))
    }

    @Test
    fun buildPayload_dingTalk_textStructure() {
        val json = JSONObject(build(WebhookType.DINGTALK))
        assertEquals("text", json.getString("msgtype"))
        assertTrue(json.getJSONObject("text").getString("content").contains("标题"))
    }

    @Test
    fun buildPayload_feishu_textStructure() {
        val json = JSONObject(build(WebhookType.FEISHU))
        assertEquals("text", json.getString("msg_type"))
        assertTrue(json.getJSONObject("content").getString("text").contains("内容"))
    }

    @Test
    fun buildPayload_telegram_injectsChatIdAndDisablesPreview() {
        val json = JSONObject(build(WebhookType.TELEGRAM, chatId = "-100123"))
        assertEquals("-100123", json.getString("chat_id"))
        assertEquals(true, json.getBoolean("disable_web_page_preview"))
        assertTrue(json.getString("text").contains("内容"))
    }

    @Test
    fun buildPayload_telegram_textTruncatedTo4096() {
        val longText = "a".repeat(5000)
        val json = JSONObject(B.buildTelegramMessage(longText))
        assertEquals(4096, json.getString("text").length)
    }

    @Test
    fun buildPayload_bark_titleAndBody() {
        val json = JSONObject(build(WebhookType.BARK))
        assertEquals("标题", json.getString("title"))
        assertTrue(json.getString("body").contains("内容"))
    }

    @Test
    fun buildPayload_generic_jsonFields() {
        val json = JSONObject(build(WebhookType.GENERIC))
        assertEquals("标题", json.getString("title"))
        assertEquals("内容", json.getString("content"))
        assertEquals("应用", json.getString("appName"))
        assertEquals("com.a.b", json.getString("packageName"))
    }

    // ===== URL 提取与 form body =====

    @Test
    fun extractChatIdFromUrl_basicAndMissing() {
        assertEquals("-100123", B.extractChatIdFromUrl("https://api.telegram.org/bot1/sendMessage?chat_id=-100123"))
        assertEquals("", B.extractChatIdFromUrl("https://api.telegram.org/bot1/sendMessage"))
        assertEquals("", B.extractChatIdFromUrl("https://api.telegram.org/bot1/sendMessage?chat_id="))
    }

    @Test
    fun extractTokenFromUrl_basic() {
        assertEquals("abc123", B.extractTokenFromUrl("https://www.pushplus.plus/send?token=abc123&x=1"))
        assertEquals("", B.extractTokenFromUrl("https://www.pushplus.plus/send"))
    }

    @Test
    fun buildServerChanFormBody_urlEncodesContent() {
        val body = B.buildServerChanFormBody(
            title = "标题 A",
            content = "内容&B",
            deviceName = "Pixel",
            time = "12:00"
        )
        // form 语义：title/desp 键 + URL 编码值；& 不允许裸出现在值中
        assertTrue(body.startsWith("title="))
        assertTrue(body.contains("&desp="))
        assertFalse(body.substringAfter("desp=").contains("&"))
    }

    @Test
    fun buildPushPlusPayload_carriesTokenAndTxtTemplate() {
        val json = JSONObject(
            B.buildPushPlusPayload(
                title = "标题", content = "内容", deviceName = "Pixel",
                time = "12:00", token = "tk"
            )
        )
        assertEquals("tk", json.getString("token"))
        assertEquals("txt", json.getString("template"))
        assertEquals("标题", json.getString("title"))
    }
}
