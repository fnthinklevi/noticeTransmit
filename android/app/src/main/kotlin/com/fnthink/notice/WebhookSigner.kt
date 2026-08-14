package com.fnthink.notice

import android.util.Base64
import android.util.Log
import org.json.JSONObject
import java.net.URLEncoder
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * Webhook 签名器
 *
 * 解决问题：原代码无签名机制，任何人都能伪造 webhook 请求。
 *
 * 平台签名规范：
 * - 企业微信群机器人：URL 追加 &timestamp=xxx&sign=base64(HMAC-SHA256(timestamp+"\n"+secret, secret))
 *   参考：https://developer.work.weixin.qq.com/document/path/91770
 * - 钉钉群机器人：URL 追加 &timestamp=xxx&sign=base64(HMAC-SHA256(timestamp+"\n"+secret, secret))
 *   钉钉 HMAC 的 key 是 secret 的 UTF8 字节，data 是 timestamp+"\n"+secret
 *   参考：https://open.dingtalk.com/document/robots/customize-robot-security-settings
 * - 飞书群机器人 v1：payload 增加 timestamp（秒）+ sign=base64(HMAC-SHA256(timestamp+"\n"+secret, secret))
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
     * @param type webhook 平台类型
     * @param url 原始 URL
     * @param payload 原始 JSON payload
     * @param secret 用户配置的密钥（null/empty 时不签名）
     */
    fun sign(
        type: WebhookPayloadBuilder.WebhookType,
        url: String,
        payload: String,
        secret: String?
    ): SignedRequest {
        if (secret.isNullOrEmpty()) {
            return SignedRequest(url, payload, emptyMap())
        }

        return try {
            when (type) {
                WebhookPayloadBuilder.WebhookType.WECHAT_WORK -> signWechatWork(url, payload, secret)
                WebhookPayloadBuilder.WebhookType.DINGTALK -> signDingTalk(url, payload, secret)
                WebhookPayloadBuilder.WebhookType.FEISHU -> signFeishu(url, payload, secret)
                WebhookPayloadBuilder.WebhookType.GENERIC -> signGeneric(url, payload, secret)
                WebhookPayloadBuilder.WebhookType.TELEGRAM -> SignedRequest(url, payload, emptyMap())
                WebhookPayloadBuilder.WebhookType.BARK -> SignedRequest(url, payload, emptyMap())
                WebhookPayloadBuilder.WebhookType.SERVER_CHAN,
                WebhookPayloadBuilder.WebhookType.PUSH_PLUS -> SignedRequest(url, payload, emptyMap())
            }
        } catch (e: Exception) {
            Log.e(TAG, "Sign failed for $type: ${e.message}", e)
            // 签名失败：返回原始请求，避免阻塞推送
            SignedRequest(url, payload, emptyMap())
        }
    }

    /**
     * 企业微信群机器人：URL 追加 timestamp + sign
     */
    private fun signWechatWork(url: String, payload: String, secret: String): SignedRequest {
        val timestamp = System.currentTimeMillis() / 1000
        val stringToSign = "$timestamp\n$secret"
        val sign = hmacSha256Base64(stringToSign.toByteArray(Charsets.UTF_8), secret.toByteArray(Charsets.UTF_8))
        val signedUrl = appendQuery(url, "timestamp=$timestamp&sign=${urlEncode(sign)}")
        Log.d(TAG, "WeChat Work signed: timestamp=$timestamp")
        return SignedRequest(signedUrl, payload, emptyMap())
    }

    /**
     * 钉钉群机器人：URL 追加 timestamp + sign
     * 钉钉官方文档：HMAC-SHA256(data=timestamp+"\n"+secret, key=secret)，输出 base64
     */
    private fun signDingTalk(url: String, payload: String, secret: String): SignedRequest {
        val timestamp = System.currentTimeMillis()
        val stringToSign = "$timestamp\n$secret"
        val sign = hmacSha256Base64(stringToSign.toByteArray(Charsets.UTF_8), secret.toByteArray(Charsets.UTF_8))
        val signedUrl = appendQuery(url, "timestamp=$timestamp&sign=${urlEncode(sign)}")
        Log.d(TAG, "DingTalk signed: timestamp=$timestamp")
        return SignedRequest(signedUrl, payload, emptyMap())
    }

    /**
     * 飞书群机器人 v1：payload 增加 timestamp + sign
     * 飞书官方文档：sign = base64(HMAC-SHA256(string_to_sign, secret))
     *   string_to_sign = timestamp + "\n" + secret
     *   timestamp 是秒级
     */
    private fun signFeishu(url: String, payload: String, secret: String): SignedRequest {
        val timestamp = System.currentTimeMillis() / 1000
        val stringToSign = "$timestamp\n$secret"
        val sign = hmacSha256Base64(stringToSign.toByteArray(Charsets.UTF_8), secret.toByteArray(Charsets.UTF_8))

        // 飞书在 payload 顶层增加 timestamp 和 sign 字段
        val signedPayload = try {
            val json = JSONObject(payload)
            json.put("timestamp", timestamp.toString())
            json.put("sign", sign)
            json.toString()
        } catch (e: Exception) {
            // payload 非 JSON（理论不会发生，飞书只接受 JSON），原样返回
            payload
        }
        Log.d(TAG, "Feishu signed: timestamp=$timestamp")
        return SignedRequest(url, signedPayload, emptyMap())
    }

    /**
     * 通用 webhook：HTTP Header 签名
     * X-Signature: sha256=<hex(HMAC-SHA256(body, secret))>
     * X-Timestamp: <milliseconds>
     * 自建服务端可校验签名防伪造
     */
    private fun signGeneric(url: String, payload: String, secret: String): SignedRequest {
        val timestamp = System.currentTimeMillis()
        val signHex = hmacSha256Hex(payload.toByteArray(Charsets.UTF_8), secret.toByteArray(Charsets.UTF_8))
        val headers = mapOf(
            "X-Signature" to "sha256=$signHex",
            "X-Timestamp" to timestamp.toString()
        )
        Log.d(TAG, "Generic signed with X-Signature header")
        return SignedRequest(url, payload, headers)
    }

    // ========== HMAC 工具 ==========

    private fun hmacSha256Base64(data: ByteArray, key: ByteArray): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        val raw = mac.doFinal(data)
        return Base64.encodeToString(raw, Base64.NO_WRAP)
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
