package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 通道身份贯穿契约（v1.62 第 1 步）。
 *
 * 锁住三件此前会静默出错的事：
 * 1. 送达判定用的平台身份必须来自**调用方显式声明**，只有 GENERIC 才允许按 host 回退；
 *    旧实现在 sendOnce 里无条件 detectType(url)，把传入的 webhookType 丢掉。
 * 2. token 失效识别必须同时认企微的 errcode 与飞书的 code。
 * 3. GENERIC 判定必须识别 errcode（应用通道走私有化域名时 host 匹配不上，否则业务失败被判成功）。
 */
class ChannelIdentityTest {

    private val generic = WebhookPayloadBuilder.WebhookType.GENERIC

    @Test
    fun explicitTypeWinsOverHostDetection() {
        // 自建 Gotify / 私有 ntfy 的域名由用户自填，ChannelRegistry 里 hosts 本就为空
        // （ChannelRegistryTest 锁死了「空 hosts 集合恰为 GENERIC 与 GOTIFY」）；
        // 按 host 重判会让它们退化成 GENERIC 判定，平台业务码规则形同虚设。
        assertEquals(
            WebhookPayloadBuilder.WebhookType.GOTIFY,
            NetworkClient.resolveWebhookType(
                WebhookPayloadBuilder.WebhookType.GOTIFY,
                "https://push.example.com/message?token=abc"
            )
        )
        assertEquals(
            WebhookPayloadBuilder.WebhookType.NTFY,
            NetworkClient.resolveWebhookType(
                WebhookPayloadBuilder.WebhookType.NTFY,
                "https://ntfy.mycorp.internal/topic/alerts"
            )
        )
    }

    @Test
    fun genericFallsBackToHostDetection() {
        // 应用通道（企微/飞书自建应用）复用同一发送管线时传 GENERIC——它们不在
        // WebhookType 体系内；端点是平台官方域名，靠 host 回退才拿得到真实判定。
        // 这条断言防止「修 1a 时顺手把应用通道也判成 GENERIC」的倒退。
        assertEquals(
            WebhookPayloadBuilder.WebhookType.WECHAT_WORK,
            NetworkClient.resolveWebhookType(
                generic,
                "https://qyapi.weixin.qq.com/cgi-bin/message/send?access_token=TK"
            )
        )
        assertEquals(
            WebhookPayloadBuilder.WebhookType.FEISHU,
            NetworkClient.resolveWebhookType(
                generic,
                "https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=chat_id"
            )
        )
    }

    @Test
    fun unknownHostWithGenericStaysGeneric() {
        assertEquals(
            generic,
            NetworkClient.resolveWebhookType(generic, "https://hook.example.com/notify")
        )
    }

    @Test
    fun tokenErrorDetectedForBothParamNames() {
        // 企微回 errcode、飞书回 code；旧正则只匹配 errcode= ⇒ 飞书 token 过期
        // 永远不触发「失效 + 重试一次」，此后每次推送都带旧 token 持续失败。
        assertTrue(
            AppChannelTokenManager.isTokenErrorMessage(
                "业务失败 errcode=${AppChannelTokenManager.ERR_TOKEN_EXPIRED}: access_token expired"
            )
        )
        assertTrue(
            AppChannelTokenManager.isTokenErrorMessage(
                "业务失败 code=${AppChannelTokenManager.ERR_FEISHU_TOKEN_INVALID}: access token invalid"
            )
        )
        // 非 token 类业务失败不得误判（否则每次失败都白刷一次 token）
        assertFalse(AppChannelTokenManager.isTokenErrorMessage("业务失败 code=500: server error"))
        assertFalse(AppChannelTokenManager.isTokenErrorMessage("响应非 JSON，无法确认送达：<html>502</html>"))
    }

    @Test
    fun genericVerdictReadsErrcode() {
        val failed = WebhookResponseParser.parse(
            generic, 200, """{"errcode":${AppChannelTokenManager.ERR_TOKEN_EXPIRED},"errmsg":"invalid credential"}"""
        )
        assertEquals(WebhookResponseParser.DeliveryStatus.BIZ_FAIL, failed.status)

        val ok = WebhookResponseParser.parse(generic, 200, """{"errcode":0,"errmsg":"ok"}""")
        assertEquals(WebhookResponseParser.DeliveryStatus.SUCCESS, ok.status)

        // 既无 code 也无 errcode 的自建端点仍按 HTTP 成功（原语义，不得收紧成误报）
        val plain = WebhookResponseParser.parse(generic, 200, """{"status":"received"}""")
        assertEquals(WebhookResponseParser.DeliveryStatus.SUCCESS, plain.status)
    }
}
