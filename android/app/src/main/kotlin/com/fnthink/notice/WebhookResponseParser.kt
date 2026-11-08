package com.fnthink.notice

import org.json.JSONObject

/**
 * Webhook 平台响应解析器
 *
 * 解决问题：原代码只看 HTTP 2xx 即视为成功，但企微/钉钉/飞书即使推送失败也返回 200，
 * 错误在 body 的 errcode/code 字段里，导致"已发送"但实际未送达。
 *
 * 平台响应规则：
 * - 企业微信群机器人：errcode == 0 为成功；errcode==45009 限流
 * - 钉钉群机器人：errcode == 0 为成功；errcode==130101 限流
 * - 飞书群机器人：code == 0 / StatusCode == 0 / FalconCode == 0 为成功
 * - Bark：code == 200 为成功
 * - 通用：HTTP 2xx 即成功
 */
object WebhookResponseParser {
    enum class DeliveryStatus {
        SUCCESS, // 已送达
        QUEUED, // 已交给本机待发队列（幻念设备档），还没有送达事实
        PAUSED, // 推送被用户暂停（监听继续，仅跳过发送）
        BIZ_FAIL, // 业务错误（不重试，例如 errcode!=0）
        HTTP_FAIL, // HTTP 错误（可重试，例如 5xx/4xx）
        RATE_LIMITED, // 限流（延迟重试，例如 errcode==45009）
        NETWORK_FAIL // 网络异常（可重试，例如超时）
    }

    data class ParseResult(
        val status: DeliveryStatus,
        val httpCode: Int,
        val message: String,
        val retryable: Boolean,
        // T220：这一发**实际试了几次、共花了多少毫秒**。默认 0 = 这条链没报这件事
        // （配置/暂停/未激活那种"一个请求都没发出去"的结局，以及口径不同的短信/邮件链路）。
        // 0 在 Dart 侧表示"未知"，不会覆盖上一次的真读数。
        val attempts: Int = 0,
        val elapsedMs: Int = 0,
        // T248：限流响应官方给出的等待秒数（Telegram parameters.retry_after /
        // Slack+Discord 的 Retry-After 头）。null = 对端没给或非限流——发送层据此
        // 校准限流退避；队列重放冷却不受它影响（冷却另有 15 分钟纪律）。
        val retryAfterSeconds: Int? = null,
    )

    fun parse(
        type: WebhookPayloadBuilder.WebhookType,
        httpCode: Int,
        responseBody: String,
        retryAfterHeader: Int? = null,
    ): ParseResult = parseBySpec(ChannelRegistry.spec(type), type, httpCode, responseBody, retryAfterHeader)

    /**
     * T248：429 响应体里的 Telegram 官方语义 `parameters.retry_after`（秒）。
     * 头里的 Retry-After 优先（Slack/Discord 官方语义）；两者都缺 → null。
     */
    private fun retryAfterFromBody(responseBody: String): Int? = try {
        val params = JSONObject(responseBody).optJSONObject("parameters")
        params?.optInt("retry_after", -1)?.takeIf { it > 0 }
    } catch (_: Exception) {
        null
    }

    /**
     * 按**描述符**判定（第 4 步）：不查全局注册表，因此未登记的合成描述符也能走同一条路。
     * [type] 仅用于给业务码判定回传原始类型（parse lambda 的既有签名），可为 null。
     * [retryAfterHeader]：HTTP `Retry-After` 头的秒数（T248，Slack/Discord 官方语义）——
     * 仅在 429 终点回传时挂到结果上。
     */
    internal fun parseBySpec(
        spec: ChannelSpec,
        type: WebhookPayloadBuilder.WebhookType?,
        httpCode: Int,
        responseBody: String,
        retryAfterHeader: Int? = null,
    ): ParseResult {
        // HTTP 5xx → 可重试
        if (httpCode in 500..599) {
            return ParseResult(
                DeliveryStatus.HTTP_FAIL, httpCode,
                "服务器错误 HTTP $httpCode: ${responseBody.take(200)}", true
            )
        }
        // HTTP 429 → 限流
        if (httpCode == 429) {
            return ParseResult(
                DeliveryStatus.RATE_LIMITED, httpCode,
                "限流 HTTP 429: ${responseBody.take(200)}", true,
                retryAfterSeconds = retryAfterHeader ?: retryAfterFromBody(responseBody),
            )
        }
        // HTTP 4xx → 业务失败不重试（除 429）
        if (httpCode in 400..499) {
            return ParseResult(
                DeliveryStatus.HTTP_FAIL, httpCode,
                "客户端错误 HTTP $httpCode: ${responseBody.take(200)}", false
            )
        }

        // HTTP 2xx：解析 body 判断业务状态
        val body = responseBody.trim()
        if (body.isEmpty()) {
            // HTTP 2xx 且 body 为空：视为成功
            return ParseResult(DeliveryStatus.SUCCESS, httpCode, "OK (empty body)", false)
        }

        return try {
            val json = JSONObject(body)
            parseBusinessCode(spec, httpCode, json, body)
        } catch (e: Exception) {
            // body 非 JSON 时不能一律按 HTTP 2xx 判成功：反代 / 认证门户 / 风控网关常回
            // 200 + HTML，此时消息其实没送达，历史却显示「已送达」——属「假成功 +
            // 静默丢内容」，比报失败危险得多（失败至少会提示、还能手动重推）。
            //
            // 只对**契约要求 JSON 业务码的平台**判失败（企微/钉钉/飞书/Telegram/Bark/
            // Server酱/PushPlus）：
            //  - GENERIC 排除：自建端点回 200 + "OK" 纯文本完全合法，其 parse 本就按
            //    「HTTP 成功」兜底，判失败会造成大面积误报；
            //  - 未登记 parse 的通道（ntfy / Gotify / Slack / Discord）排除：语义就是
            //    HTTP 状态码（ntfy 回 text/plain，Discord 回 204 空 body）。
            // 声明位：响应契约由描述符给出（此前写成 type != GENERIC && parse != null 的间接推断）
            val jsonContractPlatform = spec.requiresJsonContract
            return if (jsonContractPlatform) {
                ParseResult(
                    DeliveryStatus.BIZ_FAIL,
                    httpCode,
                    "响应非 JSON，无法确认送达：${body.take(120)}",
                    false
                )
            } else {
                ParseResult(DeliveryStatus.SUCCESS, httpCode, body.take(200), false)
            }
        }
    }

    /**
     * 业务码判定 —— 分派经 [ChannelRegistry] 描述符表（新增通道只需改表）。
     * 未登记 parse 的通道按「HTTP 2xx 即成功」兜底（与原行为一致）。
     */
    private fun parseBusinessCode(
        spec: ChannelSpec,
        httpCode: Int,
        json: JSONObject,
        rawBody: String
    ): ParseResult = spec.parse?.invoke(httpCode, json, rawBody)
        ?: ParseResult(DeliveryStatus.SUCCESS, httpCode, rawBody.take(200), false)
}
