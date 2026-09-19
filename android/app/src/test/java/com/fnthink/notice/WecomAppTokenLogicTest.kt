package com.fnthink.notice

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 企业微信自建应用纯逻辑单元测试（URL/载荷构造、gettoken 响应解析、缓存判定）。
 * ⚠ 全部使用假凭据字面量（测试专用，非真实凭据）。
 */
class WecomAppTokenLogicTest {

    // ===== normalizeBase =====

    @Test
    fun normalizeBase_officialFallbackWhenEmpty() {
        assertEquals("https://qyapi.weixin.qq.com", WecomAppTokenLogic.normalizeBase(""))
        assertEquals("https://qyapi.weixin.qq.com", WecomAppTokenLogic.normalizeBase("  "))
    }

    @Test
    fun normalizeBase_trimsTrailingSlash() {
        assertEquals(
            "https://qyapi.example.com",
            WecomAppTokenLogic.normalizeBase("https://qyapi.example.com/")
        )
    }

    @Test(expected = IllegalArgumentException::class)
    fun normalizeBase_rejectsNonHttp() {
        WecomAppTokenLogic.normalizeBase("ftp://qyapi.example.com")
    }

    // ===== tokenUrl / sendUrl =====

    @Test
    fun tokenUrl_encodesQuery() {
        val url = WecomAppTokenLogic.tokenUrl(
            "https://qyapi.weixin.qq.com", "corp-id-1", "sec/ret+1"
        )
        assertTrue(url.startsWith("https://qyapi.weixin.qq.com/cgi-bin/gettoken?corpid="))
        assertTrue(url.contains("corpsecret=sec%2Fret%2B1"))
    }

    @Test
    fun sendUrl_appendsPathAndToken() {
        val url = WecomAppTokenLogic.sendUrl("https://qyapi.weixin.qq.com/", "TOKEN1")
        assertEquals("https://qyapi.weixin.qq.com/cgi-bin/message/send?access_token=TOKEN1", url)
    }

    // ===== parseTokenResponse =====

    @Test
    fun parseTokenResponse_ok() {
        val (token, expiresIn) = WecomAppTokenLogic.parseTokenResponse(
            """{"errcode":0,"errmsg":"ok","access_token":"abc","expires_in":7200}"""
        )
        assertEquals("abc", token)
        assertEquals(7200, expiresIn)
    }

    @Test
    fun parseTokenResponse_errcodeThrows() {
        try {
            WecomAppTokenLogic.parseTokenResponse("""{"errcode":40013,"errmsg":"invalid corpid"}""")
            throw AssertionError("应抛出 TokenFetchException")
        } catch (e: WecomAppTokenManager.TokenFetchException) {
            assertEquals(40013, e.errcode)
        }
    }

    @Test
    fun parseTokenResponse_nonJsonThrows() {
        try {
            WecomAppTokenLogic.parseTokenResponse("<html>err</html>")
            throw AssertionError("应抛出 TokenFetchException")
        } catch (e: WecomAppTokenManager.TokenFetchException) {
            assertEquals(-1, e.errcode)
        }
    }

    // ===== buildSendPayload =====

    @Test
    fun buildSendPayload_textMode() {
        val payload = WecomAppTokenLogic.buildSendPayload(
            1000002, "@all", "内容", markdown = false
        )
        val json = JSONObject(payload)
        assertEquals("text", json.getString("msgtype"))
        assertEquals("内容", json.getJSONObject("text").getString("content"))
        assertEquals(1000002L, json.getLong("agentid"))
        assertEquals("@all", json.getString("touser"))
    }

    @Test
    fun buildSendPayload_markdownMode() {
        val json = JSONObject(
            WecomAppTokenLogic.buildSendPayload(1, "user1|user2", "内容", markdown = true)
        )
        assertEquals("markdown", json.getString("msgtype"))
        assertEquals("内容", json.getJSONObject("markdown").getString("content"))
        assertEquals("user1|user2", json.getString("touser"))
    }

    @Test(expected = IllegalArgumentException::class)
    fun buildSendPayload_invalidAgentidRejected() {
        WecomAppTokenLogic.buildSendPayload(0, "@all", "内容", markdown = false)
    }

    // ===== needsRefresh / isTokenErrorMessage =====

    @Test
    fun needsRefresh_nullOrKeyChangeOrNearExpiry() {
        val now = 1_000_000_000_000L
        val fresh = WecomAppTokenManager.CachedToken("k1", "t1", now + 10 * 60_000L)
        assertFalse(WecomAppTokenManager.needsRefresh(fresh, "k1", now))
        // 距过期不足 5 分钟 → 刷新
        val nearExpiry = WecomAppTokenManager.CachedToken("k1", "t1", now + 4 * 60_000L)
        assertTrue(WecomAppTokenManager.needsRefresh(nearExpiry, "k1", now))
        // key 变更（换通道凭据）→ 刷新
        assertTrue(WecomAppTokenManager.needsRefresh(fresh, "k2", now))
        // 无缓存 → 刷新
        assertTrue(WecomAppTokenManager.needsRefresh(null, "k1", now))
    }

    @Test
    fun isTokenErrorMessage_matchesKnownCodes() {
        assertTrue(WecomAppTokenManager.isTokenErrorMessage("业务失败 errcode=42001: expired"))
        assertTrue(WecomAppTokenManager.isTokenErrorMessage("业务失败 errcode=40014: invalid token"))
        assertFalse(WecomAppTokenManager.isTokenErrorMessage("业务失败 errcode=81013: bad touser"))
        assertFalse(WecomAppTokenManager.isTokenErrorMessage("OK"))
    }

    // ===== truncateForWecomApp（2048 字节 UTF-8 上限）=====

    @Test
    fun truncateForWecomApp_shortTextUnchanged() {
        val text = "中文字符串"
        assertEquals(text, WebhookPayloadBuilder.truncateForWecomApp(text))
    }

    @Test
    fun truncateForWecomApp_longTextWithinByteLimit() {
        val text = "测".repeat(1500) // 4500 字节 > 2048
        val truncated = WebhookPayloadBuilder.truncateForWecomApp(text)
        assertTrue(truncated.toByteArray(Charsets.UTF_8).size <= 2048)
        assertTrue(truncated.length < text.length)
    }
}
