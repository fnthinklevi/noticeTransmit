package com.fnthink.notice

import android.util.Log
import org.json.JSONObject
import java.net.URLEncoder
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi

/**
 * Webhook 签名器
 *
 * **本文件不按平台分支**：签名方式是从 `ChannelRegistry` 描述符里取的 [SignatureScheme]
 * （第 4 步把原来的 12 臂 `when (type)` 消掉了——那是"新增通道必须改核心"的强制改动点之一）。
 *
 * 平台签名规范：
 * - 企业微信群机器人：URL 追加 &timestamp=xxx&sign=base64(HMAC-SHA256(timestamp+"\n"+secret, secret))
 *   参考：https://developer.work.weixin.qq.com/document/path/91770
 * - 钉钉群机器人：同企微算法，但时间戳是**毫秒**
 *   参考：https://open.dingtalk.com/document/robots/customize-robot-security-settings
 * - 飞书群机器人 v1：payload 增加 timestamp（秒）+ sign=base64(HMAC-SHA256(key=timestamp+"\n"+secret, data=空))
 *   参考：https://open.feishu.cn/document/uAjLw4CM/ukTMukTMukTM/bot-v3/use-custom-bots-in-a-group
 * - 通用 webhook：HTTP Header X-Signature: sha256=<hex(HMAC-SHA256(body, secret))> + X-Timestamp
 *   自建服务端校验签名防止伪造
 */
object WebhookSigner {
    private const val TAG = "WebhookSigner"

    data class SignedRequest(
        val url: String,
        val payload: String,
        val headers: Map<String, String>
    )

    /**
     * 对 webhook 请求进行签名
     * @param type webhook 平台类型（只用于查描述符的 [SignatureScheme]）
     * @param url 原始 URL
     * @param payload 原始 JSON payload
     * @param secret 用户配置的密钥（null/empty 时不签名）
     */
    fun sign(
        type: WebhookPayloadBuilder.WebhookType,
        url: String,
        payload: String,
        secret: String?
    ): SignedRequest =
        signBy(ChannelRegistry.spec(type).signature, type, url, payload, secret)

    /** 按**方案**签名（[sign] 的实现体，独立出来供守卫测试直接驱动） */
    internal fun signBy(
        scheme: SignatureScheme,
        type: WebhookPayloadBuilder.WebhookType,
        url: String,
        payload: String,
        secret: String?,
        timestampMs: Long = System.currentTimeMillis()
    ): SignedRequest {
        if (secret.isNullOrEmpty() || scheme == SignatureScheme.NONE) {
            return SignedRequest(url, payload, emptyMap())
        }

        return try {
            when (scheme) {
                SignatureScheme.URL_TIMESTAMP_SECONDS,
                SignatureScheme.URL_TIMESTAMP_MILLIS -> {
                    // 企微用秒、钉钉用毫秒：唯一差别就是时间戳单位（算法一致）
                    val ts = if (scheme == SignatureScheme.URL_TIMESTAMP_SECONDS) {
                        timestampMs / 1000
                    } else {
                        timestampMs
                    }
                    val stringToSign = "$ts\n$secret"
                    val sign = hmacSha256Base64(
                        stringToSign.toByteArray(Charsets.UTF_8),
                        secret.toByteArray(Charsets.UTF_8)
                    )
                    Log.d(TAG, "$type signed: timestamp=$ts")
                    SignedRequest(
                        appendQuery(url, "timestamp=$ts&sign=${urlEncode(sign)}"),
                        payload,
                        emptyMap()
                    )
                }

                SignatureScheme.FEISHU_PAYLOAD_JSON -> {
                    val ts = timestampMs / 1000
                    val stringToSign = "$ts\n$secret"
                    // 飞书的 key/data 与钉钉企微**正好相反**（data 为空），
                    // 用错算法平台回 code 19021 Sign match fail
                    val sign = hmacSha256Base64(
                        ByteArray(0),
                        stringToSign.toByteArray(Charsets.UTF_8)
                    )
                    val signedPayload = try {
                        JSONObject(payload).apply {
                            put("timestamp", ts.toString())
                            put("sign", sign)
                        }.toString()
                    } catch (e: Exception) {
                        // payload 非 JSON（理论不会发生，飞书只接受 JSON），原样返回
                        payload
                    }
                    Log.d(TAG, "Feishu signed: timestamp=$ts")
                    SignedRequest(url, signedPayload, emptyMap())
                }

                SignatureScheme.HEADER_HEX_BODY -> {
                    val signHex = hmacSha256Hex(
                        payload.toByteArray(Charsets.UTF_8),
                        secret.toByteArray(Charsets.UTF_8)
                    )
                    Log.d(TAG, "Generic signed with X-Signature header")
                    SignedRequest(
                        url,
                        payload,
                        mapOf(
                            "X-Signature" to "sha256=$signHex",
                            "X-Timestamp" to timestampMs.toString()
                        )
                    )
                }

                // ntfy：secret 是访问令牌（Bearer），签名豁免但必须注入鉴权 header
                SignatureScheme.BEARER_HEADER ->
                    SignedRequest(url, payload, mapOf("Authorization" to "Bearer $secret"))

                SignatureScheme.NONE -> SignedRequest(url, payload, emptyMap())
            }
        } catch (e: Exception) {
            Log.e(TAG, "Sign failed for $type: ${e.message}", e)
            // 签名失败：返回原始请求，避免阻塞推送
            SignedRequest(url, payload, emptyMap())
        }
    }

    // ========== HMAC 工具 ==========

    @OptIn(ExperimentalEncodingApi::class)
    private fun hmacSha256Base64(data: ByteArray, key: ByteArray): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        val raw = mac.doFinal(data)
        // 与旧的 android.util.Base64.NO_WRAP 输出逐字节相同（标准字母表 + "=" 填充、无换行），
        // 换成纯 Kotlin 实现是为了能在 JVM 单元测试里真跑一遍：android.util.* 未 mock 即抛，
        // 异常会被 signBy 的 catch 吞掉并"原样返回"，签名逻辑等于永远测不到（第 4 步踩过）。
        return Base64.encode(raw)
    }

    private fun hmacSha256Hex(data: ByteArray, key: ByteArray): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        val raw = mac.doFinal(data)
        return raw.joinToString("") { "%02x".format(it) }
    }

    private fun appendQuery(url: String, query: String): String {
        val separator = if (url.contains("?")) "&" else "?"
        return "$url$separator$query"
    }

    private fun urlEncode(value: String): String {
        return URLEncoder.encode(value, "UTF-8")
    }
}
