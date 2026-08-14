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
        SUCCESS,        // 已送达
        BIZ_FAIL,       // 业务错误（不重试，例如 errcode!=0）
        HTTP_FAIL,      // HTTP 错误（可重试，例如 5xx/4xx）
        RATE_LIMITED,   // 限流（延迟重试，例如 errcode==45009）
        NETWORK_FAIL    // 网络异常（可重试，例如超时）
    }

    data class ParseResult(
        val status: DeliveryStatus,
        val httpCode: Int,
        val message: String,
        val retryable: Boolean
    )

    fun parse(
        type: WebhookPayloadBuilder.WebhookType,
        httpCode: Int,
        responseBody: String
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
                "限流 HTTP 429: ${responseBody.take(200)}", true
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
            parseBusinessCode(type, httpCode, json, body)
        } catch (e: Exception) {
            // body 非 JSON：HTTP 2xx 视为成功
            ParseResult(DeliveryStatus.SUCCESS, httpCode, body.take(200), false)
        }
    }

    private fun parseBusinessCode(
        type: WebhookPayloadBuilder.WebhookType,
        httpCode: Int,
        json: JSONObject,
        rawBody: String
    ): ParseResult {
        when (type) {
            WebhookPayloadBuilder.WebhookType.WECHAT_WORK,
            WebhookPayloadBuilder.WebhookType.DINGTALK -> {
                // errcode == 0 为成功
                val errcode = json.optInt("errcode", -1)
                val errmsg = json.optString("errmsg", "")
                return when {
                    errcode == 0 -> ParseResult(
                        DeliveryStatus.SUCCESS, httpCode,
                        if (errmsg.isNotEmpty()) errmsg else "OK", false
                    )
                    errcode == 45009 -> ParseResult(
                        DeliveryStatus.RATE_LIMITED, httpCode,
                        "限流 errcode=$errcode: $errmsg", true
                    )
                    errcode == 130101 -> ParseResult(
                        DeliveryStatus.RATE_LIMITED, httpCode,
                        "限流 errcode=$errcode: $errmsg", true
                    )
                    else -> ParseResult(
                        DeliveryStatus.BIZ_FAIL, httpCode,
                        "业务失败 errcode=$errcode: $errmsg", false
                    )
                }
            }

            WebhookPayloadBuilder.WebhookType.FEISHU -> {
                // 飞书 code == 0 / StatusCode == 0 / FalconCode == 0 为成功
                val code = json.optInt("code", -1)
                val statusCode = json.optInt("StatusCode", -1)
                val falconCode = json.optInt("FalconCode", -1)
                val msg = json.optString("msg", "")
                return when {
                    code == 0 || statusCode == 0 || falconCode == 0 -> ParseResult(
                        DeliveryStatus.SUCCESS, httpCode,
                        if (msg.isNotEmpty()) msg else "OK", false
                    )
                    code == 99991663 || code == 99991664 -> ParseResult(
                        DeliveryStatus.RATE_LIMITED, httpCode,
                        "限流 code=$code: $msg", true
                    )
                    else -> ParseResult(
                        DeliveryStatus.BIZ_FAIL, httpCode,
                        "业务失败 code=$code StatusCode=$statusCode: $msg", false
                    )
                }
            }

            WebhookPayloadBuilder.WebhookType.GENERIC -> {
                // 通用 webhook：尝试解析 code 字段，0 为成功；否则视为 HTTP 成功
                val code = json.optInt("code", -1)
                val message = json.optString("message", json.optString("msg", ""))
                return if (json.has("code") && code != 0) {
                    ParseResult(
                        DeliveryStatus.BIZ_FAIL, httpCode,
                        "业务失败 code=$code: $message", false
                    )
                } else {
                    ParseResult(
                        DeliveryStatus.SUCCESS, httpCode,
                        if (message.isNotEmpty()) message else "OK", false
                    )
                }
            }

            WebhookPayloadBuilder.WebhookType.TELEGRAM,
            WebhookPayloadBuilder.WebhookType.BARK -> {
                // Telegram: {"ok": true/false, "description": "..."}
                // Bark: {"code": 200, "message": "..."}
                val ok = json.optBoolean("ok", true)
                val description = json.optString("description", json.optString("message", ""))
                return if (ok) {
                    ParseResult(
                        DeliveryStatus.SUCCESS, httpCode,
                        if (description.isNotEmpty()) description else "OK", false
                    )
                } else {
                    ParseResult(
                        DeliveryStatus.BIZ_FAIL, httpCode,
                        if (description.isNotEmpty()) description else "失败", false
                    )
                }
            }
        }
    }
}
