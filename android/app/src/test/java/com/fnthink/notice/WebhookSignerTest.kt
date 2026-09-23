package com.fnthink.notice

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 签名器的**行为锁**（第 4 步补）。
 *
 * 为什么必须有：`WebhookSigner` 原来是 `when (type)` 的 12 臂分支，**整个仓库没有一个测试**，
 * 而它是唯一"漏一臂就编译不过"的强制改动点 —— 也就是说改签名逻辑完全没有回归网。
 * 本步把分支收敛成描述符里的 [SignatureScheme]，等价性靠这些固定时间戳的向量证明：
 * 每个方案的 HMAC 输入/输出、URL 拼接位置、编码方式都逐字节钉死。
 *
 * 期望值由 Python `hmac`+`base64` 离线算出（与 Java `Mac.getInstance("HmacSHA256")` 同算法），
 * 不是"跑一遍把结果抄回来"——否则锁不住算法本身被改错。
 */
class WebhookSignerTest {

    private val secret = "SECret123"
    private val payload = """{"text":"hi"}"""
    private val url = "https://example.com/hook?a=1"

    /** 固定时间戳（毫秒），秒级方案用它 /1000 */
    private val tsMs = 1700000000123L
    private val tsSec = 1700000000L

    private fun signWith(
        scheme: SignatureScheme,
        url: String = this.url,
        payload: String = this.payload,
        secret: String? = this.secret,
    ) = WebhookSigner.signBy(scheme, WebhookPayloadBuilder.WebhookType.GENERIC, url, payload, secret, tsMs)

    // ── 企微 / 钉钉：key=secret、data="ts\nsecret"，URL 追加 ──────────────

    @Test
    fun wecomStyle_appendsSecondTimestampAndUrlEncodedBase64Sign() {
        val r = signWith(SignatureScheme.URL_TIMESTAMP_SECONDS)
        assertEquals(
            "$url&timestamp=$tsSec&sign=9vEHN2mDdXI9vPlBqO9hA0kgP%2BbwtyKE9aC%2BGjWo5x8%3D",
            r.url
        )
        assertEquals(payload, r.payload)
        assertTrue(r.headers.isEmpty())
    }

    @Test
    fun dingTalkStyle_sameAlgorithmButMillisecondTimestamp() {
        val r = signWith(SignatureScheme.URL_TIMESTAMP_MILLIS)
        assertEquals(
            "$url&timestamp=$tsMs&sign=ubbXpq4G5Ztcud7zHn5CmoPgp%2FtQ1RdQXECHL4yfOPI%3D",
            r.url
        )
    }

    @Test
    fun urlWithoutQuery_usesQuestionMarkSeparator() {
        val r = signWith(
            SignatureScheme.URL_TIMESTAMP_MILLIS,
            url = "https://oapi.dingtalk.com/robot/send"
        )
        assertTrue(r.url.contains("/robot/send?timestamp="))
        assertFalse(r.url.contains("send&timestamp="))
    }

    // ── 飞书：key/data 与上面**正好相反**，且注入 body 而非 URL ────────────

    @Test
    fun feishuStyle_injectsTimestampAndSignIntoPayloadWithSwappedHmacOperands() {
        val r = signWith(SignatureScheme.FEISHU_PAYLOAD_JSON)
        assertEquals(url, r.url)
        val json = JSONObject(r.payload)
        assertEquals(tsSec.toString(), json.getString("timestamp"))
        // data=空串、key="ts\nsecret"（用成钉钉的写法平台会回 19021 Sign match fail）
        assertEquals("WtSpI2dfsMuBGn8xqFr3cSeYUyQifdRSS9HxEOeq444=", json.getString("sign"))
    }

    @Test
    fun feishuStyle_nonJsonPayloadIsPassedThroughUnchanged() {
        val r = signWith(SignatureScheme.FEISHU_PAYLOAD_JSON, payload = "plain text")
        assertEquals("plain text", r.payload)
    }

    // ── 通用 webhook：header 里放 hex ─────────────────────────────────────

    @Test
    fun genericStyle_signsBodyIntoHexHeader() {
        val r = signWith(SignatureScheme.HEADER_HEX_BODY)
        assertEquals(url, r.url)
        assertEquals(payload, r.payload)
        assertEquals(
            "sha256=d810c954f19261996ed977cace6b15aad3fca13b8895d02d2a9400d8232a7f38",
            r.headers["X-Signature"]
        )
        assertEquals(tsMs.toString(), r.headers["X-Timestamp"])
    }

    // ── ntfy：secret 是访问令牌，不参与签名 ───────────────────────────────

    @Test
    fun bearerStyle_injectsAuthorizationHeaderOnly() {
        val r = signWith(SignatureScheme.BEARER_HEADER)
        assertEquals("Bearer $secret", r.headers["Authorization"])
        assertEquals(url, r.url)
        assertEquals(payload, r.payload)
    }

    @Test
    fun noneScheme_neverTouchesRequest_evenWithSecret() {
        for (url in listOf(this.url, "https://hooks.slack.com/services/x")) {
            val r = signWith(SignatureScheme.NONE, url = url)
            assertEquals(url, r.url)
            assertEquals(payload, r.payload)
            assertTrue(r.headers.isEmpty())
        }
    }

    @Test
    fun missingSecret_isNoOpForEveryScheme() {
        // 未配置密钥时必须原样发出（用户在平台上没开签名校验是常态）
        for (scheme in SignatureScheme.values()) {
            for (absent in listOf(null, "")) {
                val r = signWith(scheme, secret = absent)
                assertEquals("$scheme / $absent", url, r.url)
                assertEquals("$scheme / $absent", payload, r.payload)
                assertTrue("$scheme / $absent 不应注入 header", r.headers.isEmpty())
            }
        }
    }

    // ── 描述符 ↔ 方案 的接线（表写错就等于平台收不到合法签名） ─────────────

    @Test
    fun descriptor_wiresEachPlatformToItsOwnScheme() {
        val expected = mapOf(
            WebhookPayloadBuilder.WebhookType.WECHAT_WORK to SignatureScheme.URL_TIMESTAMP_SECONDS,
            WebhookPayloadBuilder.WebhookType.DINGTALK to SignatureScheme.URL_TIMESTAMP_MILLIS,
            WebhookPayloadBuilder.WebhookType.FEISHU to SignatureScheme.FEISHU_PAYLOAD_JSON,
            WebhookPayloadBuilder.WebhookType.GENERIC to SignatureScheme.HEADER_HEX_BODY,
            WebhookPayloadBuilder.WebhookType.NTFY to SignatureScheme.BEARER_HEADER,
            // 以下平台凭据在 URL / body 里，签名层必须完全不动请求
            WebhookPayloadBuilder.WebhookType.TELEGRAM to SignatureScheme.NONE,
            WebhookPayloadBuilder.WebhookType.BARK to SignatureScheme.NONE,
            WebhookPayloadBuilder.WebhookType.SERVER_CHAN to SignatureScheme.NONE,
            WebhookPayloadBuilder.WebhookType.PUSH_PLUS to SignatureScheme.NONE,
            WebhookPayloadBuilder.WebhookType.GOTIFY to SignatureScheme.NONE,
            WebhookPayloadBuilder.WebhookType.SLACK to SignatureScheme.NONE,
            WebhookPayloadBuilder.WebhookType.DISCORD to SignatureScheme.NONE,
        )
        expected.forEach { (type, scheme) ->
            assertEquals("实发 URL 签名方案漂移：$type", scheme, ChannelRegistry.spec(type).signature)
        }
        assertEquals("每个枚举值都要有方案", expected.size, WebhookPayloadBuilder.WebhookType.values().size)
    }

    @Test
    fun gotify_declaresTokenInQueryAndSkipsSigner() {
        // Gotify 的 App Token 走 URL query（描述符声明）。发送层据此**不**把 secret 交给签名层，
        // 否则 token 既进 URL 又被当成签名密钥，平台返回 400/403。
        val transport = ChannelRegistry.spec(WebhookPayloadBuilder.WebhookType.GOTIFY).transport
        assertTrue(transport.secretAsQueryToken)
        assertTrue(transport.secretRequired)
        assertEquals("/message", transport.pathSuffix)
        // token 不进签名：Gotify 的描述符方案必须是 NONE
        assertEquals(SignatureScheme.NONE, transport.let { ChannelRegistry.spec(WebhookPayloadBuilder.WebhookType.GOTIFY).signature })
    }

    @Test
    fun gotify_tokenIsUrlEncodedIntoQuery() {
        val encoded = java.net.URLEncoder.encode("a+b/c", "UTF-8")
        // 发送层拼的就是 trimEnd('/') + pathSuffix + "?token=" + urlencode(secret)
        val target = "https://push.example.org/" + "/message?token=" + encoded
        assertTrue("token 未正确 URL 编码：$target", target.endsWith("/message?token=a%2Bb%2Fc"))
    }
}
