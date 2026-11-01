package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * T188 片1 第②刀：自定义请求头的白名单（`HttpHeaders`）。
 *
 * 这一层是"用户能改 HTTP 请求"的**唯一闸门**。写反的三种方式都很安静：
 *  - 放行 `host` / `content-length` ⇒ 请求形状由配置说了算，对面收到的是另一个请求；
 *  - 放行 `x-signature` ⇒ 本机签名被用户值覆盖，对面只会说"签名不对"；
 *  - 静默丢空名/超长/非法字符 ⇒ 用户以为填了，实际一条都没带上。
 */
class HttpHeadersTest {

    @Test
    fun forbiddenNamesAreDroppedAndReported() {
        val input = mapOf(
            "Host" to "evil.example",
            "Content-Length" to "999",
            "Content-Type" to "text/plain",
            "X-Signature" to "forged",
            "X-Timestamp" to "1",
            "Transfer-Encoding" to "chunked",
            "X-Api-Key" to "k-123",
        )
        val result = HttpHeaders.sanitize(input)
        assertEquals(mapOf("X-Api-Key" to "k-123"), result.accepted)
        // 被丢掉的那几条要说得出名字：界面据此提示"这几条没带上"，
        // 否则用户看到的是"填了、对面没收到"，与"根本没填"长得一样。
        assertTrue(result.rejected.containsAll(
            listOf("Host", "Content-Length", "Content-Type", "X-Signature", "X-Timestamp", "Transfer-Encoding")
        ))
    }

    @Test
    fun invalidNamesAndValuesAreDropped() {
        val result = HttpHeaders.sanitize(
            mapOf(
                "bad name" to "v", // 空格不在 tchar 里
                "X-Bad:Colon" to "v",
                "X-Empty" to "   ",
                "" to "v",
                "X-Ok" to "  v  ",
            )
        )
        assertEquals(mapOf("X-Ok" to "v"), result.accepted)
        assertEquals(4, result.rejected.size)
    }

    @Test
    fun sameNameLastWins_caseInsensitively() {
        // 用户改过的那一条应该赢（界面里同一格改名后旧值还在 Map 里时尤其要这样）。
        val result = HttpHeaders.sanitize(
            linkedMapOf("X-Token" to "old", "x-token" to "new")
        )
        assertEquals(mapOf("x-token" to "new"), result.accepted)
        assertTrue(result.rejected.isEmpty())
    }

    @Test
    fun tooManyHeadersAreCappedNotSilentlyAccepted() {
        val input = (1..HttpHeaders.MAX_HEADERS + 2).associate { "X-H$it" to "v$it" }
        val result = HttpHeaders.sanitize(input)
        assertEquals(HttpHeaders.MAX_HEADERS, result.accepted.size)
        assertEquals(2, result.rejected.size)
    }

    @Test
    fun emptyAndNullInputsAreNoOps() {
        assertTrue(HttpHeaders.normalize(null).isEmpty())
        assertTrue(HttpHeaders.normalize(emptyMap()).isEmpty())
    }

    @Test
    fun authorizationIsAllowedForGenericGateways() {
        // 自建网关常用 Authorization；通用通道不走 ntfy 那条 Bearer 分支，二者不会打架。
        val result = HttpHeaders.sanitize(mapOf("Authorization" to "Bearer abc"))
        assertEquals(mapOf("Authorization" to "Bearer abc"), result.accepted)
    }

    // 头这一刀真正的落点是 plan：描述符不给这一档的通道，**一条都不带**。
    // 只测 HttpHeaders 会漏掉"平台通道也把用户头带出去"这种错（那样配置页看着对、
    // 对面收到一个平台契约之外的请求）。
    @Test
    fun planCarriesCustomHeadersOnlyWhereTheDescriptorAllowsIt() {
        fun input(headers: Map<String, String>) = OutboundInput(
            url = "https://gw.example/hook",
            configuredHeaders = headers,
            secret = null,
            chatId = "",
            urlToken = "",
            overrideBody = { null },
            platformBody = { null },
            rawTemplateBody = { null },
            defaultBody = { "{}" },
        )

        val generic = ChannelDispatch.plan(
            ChannelRegistry.spec(WebhookPayloadBuilder.WebhookType.GENERIC),
            input(mapOf("X-Api-Key" to "k", "Host" to "evil.example")),
        )
        assertEquals(mapOf("X-Api-Key" to "k"), generic.customHeaders)

        val platform = ChannelDispatch.plan(
            ChannelRegistry.spec(WebhookPayloadBuilder.WebhookType.WECHAT_WORK),
            input(mapOf("X-Api-Key" to "k")),
        )
        assertTrue(
            "平台通道不许把用户头带出去（它的头是平台契约的一部分）",
            platform.customHeaders.isEmpty(),
        )
    }
}
