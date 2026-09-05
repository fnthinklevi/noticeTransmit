package com.fnthink.notice

import com.fnthink.notice.WebhookPayloadBuilder.WebhookType
import com.fnthink.notice.WebhookResponseParser.DeliveryStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * WebhookResponseParser 单元测试（纯逻辑，JVM 直测）。
 * 守住「HTTP 2xx 不等于业务送达」的核心语义：各平台业务码判定与限流/重试分类。
 */
class WebhookResponseParserTest {

    private fun parse(type: WebhookType, httpCode: Int, body: String) =
        WebhookResponseParser.parse(type, httpCode, body)

    // ===== HTTP 层 =====

    @Test
    fun http5xx_isRetryableHttpFail() {
        val r = parse(WebhookType.GENERIC, 502, "Bad Gateway")
        assertEquals(DeliveryStatus.HTTP_FAIL, r.status)
        assertTrue(r.retryable)
    }

    @Test
    fun http429_isRateLimited() {
        val r = parse(WebhookType.GENERIC, 429, "Too Many Requests")
        assertEquals(DeliveryStatus.RATE_LIMITED, r.status)
        assertTrue(r.retryable)
    }

    @Test
    fun http4xx_isHttpFailNotRetryable() {
        val r = parse(WebhookType.GENERIC, 403, "Forbidden")
        assertEquals(DeliveryStatus.HTTP_FAIL, r.status)
        assertFalse(r.retryable)
    }

    @Test
    fun http2xxEmptyBody_isSuccess() {
        val r = parse(WebhookType.WECHAT_WORK, 200, "  ")
        assertEquals(DeliveryStatus.SUCCESS, r.status)
    }

    @Test
    fun http2xxNonJsonBody_isSuccess() {
        val r = parse(WebhookType.GENERIC, 200, "ok,plain text")
        assertEquals(DeliveryStatus.SUCCESS, r.status)
    }

    // ===== 企业微信 / 钉钉：errcode =====

    @Test
    fun wechatWork_errcode0_success() {
        val r = parse(WebhookType.WECHAT_WORK, 200, """{"errcode":0,"errmsg":"ok"}""")
        assertEquals(DeliveryStatus.SUCCESS, r.status)
        assertEquals("ok", r.message)
    }

    @Test
    fun wechatWork_errcode45009_rateLimited() {
        val r = parse(WebhookType.WECHAT_WORK, 200, """{"errcode":45009,"errmsg":"freq limited"}""")
        assertEquals(DeliveryStatus.RATE_LIMITED, r.status)
        assertTrue(r.retryable)
    }

    @Test
    fun dingTalk_errcode130101_rateLimited() {
        val r = parse(WebhookType.DINGTALK, 200, """{"errcode":130101,"errmsg":"too fast"}""")
        assertEquals(DeliveryStatus.RATE_LIMITED, r.status)
        assertTrue(r.retryable)
    }

    @Test
    fun dingTalk_errcodeOther_bizFail() {
        val r = parse(WebhookType.DINGTALK, 200, """{"errcode":310000,"errmsg":"sign not match"}""")
        assertEquals(DeliveryStatus.BIZ_FAIL, r.status)
        assertFalse(r.retryable)
    }

    // ===== 飞书：code / StatusCode / FalconCode =====

    @Test
    fun feishu_code0_success() {
        val r = parse(WebhookType.FEISHU, 200, """{"code":0,"msg":"success"}""")
        assertEquals(DeliveryStatus.SUCCESS, r.status)
    }

    @Test
    fun feishu_statusCode0_success() {
        val r = parse(WebhookType.FEISHU, 200, """{"StatusCode":0}""")
        assertEquals(DeliveryStatus.SUCCESS, r.status)
    }

    @Test
    fun feishu_rateLimitCode_rateLimited() {
        val r = parse(WebhookType.FEISHU, 200, """{"code":99991663,"msg":"busy"}""")
        assertEquals(DeliveryStatus.RATE_LIMITED, r.status)
        assertTrue(r.retryable)
    }

    @Test
    fun feishu_otherCode_bizFail() {
        val r = parse(WebhookType.FEISHU, 200, """{"code":19021,"msg":"sign error"}""")
        assertEquals(DeliveryStatus.BIZ_FAIL, r.status)
    }

    // ===== 通用 webhook：code 字段 =====

    @Test
    fun generic_code0_success() {
        val r = parse(WebhookType.GENERIC, 200, """{"code":0,"message":"ok"}""")
        assertEquals(DeliveryStatus.SUCCESS, r.status)
    }

    @Test
    fun generic_codeNonZero_bizFail() {
        val r = parse(WebhookType.GENERIC, 200, """{"code":400,"message":"bad"}""")
        assertEquals(DeliveryStatus.BIZ_FAIL, r.status)
    }

    @Test
    fun generic_noCodeField_httpSuccessWins() {
        val r = parse(WebhookType.GENERIC, 200, """{"status":"done"}""")
        assertEquals(DeliveryStatus.SUCCESS, r.status)
    }

    // ===== Telegram / Bark =====

    @Test
    fun telegram_okTrue_success() {
        val r = parse(WebhookType.TELEGRAM, 200, """{"ok":true,"result":{"message_id":1}}""")
        assertEquals(DeliveryStatus.SUCCESS, r.status)
    }

    @Test
    fun telegram_okFalse_bizFail() {
        val r = parse(WebhookType.TELEGRAM, 200, """{"ok":false,"description":"chat not found"}""")
        assertEquals(DeliveryStatus.BIZ_FAIL, r.status)
        assertEquals("chat not found", r.message)
    }

    @Test
    fun bark_code200Body_successByOkDefault() {
        // Bark 响应无 ok 字段，optBoolean("ok", true) 默认按成功处理
        val r = parse(WebhookType.BARK, 200, """{"code":200,"message":"success"}""")
        assertEquals(DeliveryStatus.SUCCESS, r.status)
    }

    // ===== Server酱 / PushPlus =====

    @Test
    fun serverChan_code0_success() {
        val r = parse(WebhookType.SERVER_CHAN, 200, """{"code":0,"message":"发送成功"}""")
        assertEquals(DeliveryStatus.SUCCESS, r.status)
    }

    @Test
    fun serverChan_codeNonZero_bizFail() {
        val r = parse(WebhookType.SERVER_CHAN, 200, """{"code":40001,"message":"bad key"}""")
        assertEquals(DeliveryStatus.BIZ_FAIL, r.status)
    }

    @Test
    fun pushPlus_code200_success() {
        val r = parse(WebhookType.PUSH_PLUS, 200, """{"code":200,"msg":"发送成功"}""")
        assertEquals(DeliveryStatus.SUCCESS, r.status)
    }

    @Test
    fun pushPlus_codeNot200_bizFail() {
        val r = parse(WebhookType.PUSH_PLUS, 200, """{"code":903,"msg":"invalid token"}""")
        assertEquals(DeliveryStatus.BIZ_FAIL, r.status)
    }
}
