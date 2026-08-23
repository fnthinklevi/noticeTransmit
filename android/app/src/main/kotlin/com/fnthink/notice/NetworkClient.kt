package com.fnthink.notice

import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import okhttp3.CertificatePinner
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit

class NetworkClient {
    companion object {
        private const val TAG = "NetworkClient"
        private const val MAX_RETRIES = 3
        private const val RETRY_DELAY_MS = 2000L
        private const val RATE_LIMIT_RETRY_DELAY_MS = 10_000L // 限流时退避更长

        @Volatile private var isActive = true
        // 作用域在 destroy() 时 cancel，activate() 时重建，避免重试协程在服务销毁后仍回调
        private var scope = newScope()
        private fun newScope() = CoroutineScope(SupervisorJob() + Dispatchers.IO)

        private val client: OkHttpClient by lazy {
            OkHttpClient.Builder()
                .connectTimeout(15, TimeUnit.SECONDS)
                .writeTimeout(15, TimeUnit.SECONDS)
                .readTimeout(15, TimeUnit.SECONDS)
                .retryOnConnectionFailure(false)
                .apply {
                    // SSL 证书固定：防止中间人攻击。默认关闭（CERT_PINS 为空或
                    // ENABLE_CERT_PINNING=false，Debug 构建恒关闭）。
                    // 启用方式：构建时注入环境变量/参数
                    //   CERT_PINS="sha256/xxx;sha256/yyy" ENABLE_CERT_PINNING=true
                    // 获取指纹：
                    //   openssl s_client -connect notice.fnthink.top:443 -servername notice.fnthink.top 2>/dev/null \
                    //     | openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary \
                    //     | openssl base64
                    // 证书轮换与多 pin 策略见 base.md「证书固定」章节。
                    buildCertificatePinner()?.let { certificatePinner(it) }
                }
                .build()
        }

        /**
         * 构建证书固定器。多 pin 用「;」分隔（至少保留 2 个：当前 + 备用），
         * 未启用（Debug / 未注入 / 空指纹）时返回 null，仅做标准 TLS 验证。
         */
        private fun buildCertificatePinner(): CertificatePinner? {
            if (!BuildConfig.ENABLE_CERT_PINNING) return null
            val pins = BuildConfig.CERT_PINS
                .split(';')
                .map { it.trim() }
                .filter { it.isNotEmpty() && it.startsWith("sha256/") }
            if (pins.isEmpty()) return null
            val hosts = listOf("notice.fnthink.top", "xget.fnthink.top")
            return CertificatePinner.Builder().apply {
                for (host in hosts) {
                    for (pin in pins) {
                        add(host, pin)
                    }
                }
            }.build()
        }

        /**
         * 发送 webhook（支持签名 + 送达校验）
         *
         * @param url 原始 webhook URL
         * @param payload JSON payload
         * @param tag 日志标签
         * @param webhookType 平台类型（用于响应解析）
         * @param secret 签名密钥（null/empty 时不签名）
         * @param contentType 请求体 MIME 类型（默认 application/json; charset=utf-8）。
         *                    当使用自定义模板（text/xml/markdown）时由调用方传入对应类型。
         * @param force 强制发送：为 true 时忽略"推送暂停"开关（用于历史记录"现在推送"手动补推）
         * @param onResult 可选回调，返回送达结果（含状态/HTTP 码/消息）
         */
        fun sendWithRetry(
            url: String,
            payload: String,
            tag: String = "webhook",
            webhookType: WebhookPayloadBuilder.WebhookType = WebhookPayloadBuilder.WebhookType.GENERIC,
            secret: String? = null,
            contentType: String = "application/json; charset=utf-8",
            force: Boolean = false,
            onResult: ((WebhookResponseParser.ParseResult) -> Unit)? = null
        ) {
            if (!isActive) {
                onResult?.invoke(
                    WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.NETWORK_FAIL,
                        0, "NetworkClient inactive", false
                    )
                )
                return
            }
            // 推送已暂停（前台通知一键启停）：监听继续，仅跳过 webhook 发送。
            // 手动"现在推送"（force=true）不受暂停开关限制。
            if (!force && !PushToggleManager.isPushActive()) {
                Log.d(TAG, "$tag skipped: push paused")
                onResult?.invoke(
                    WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.PAUSED,
                        0, "Push paused (skipped)", false
                    )
                )
                return
            }
            scope.launch {
                // 发送前签名（仅一次，重试时复用同一签名）
                val signed = WebhookSigner.sign(webhookType, url, payload, secret)

                var retryCount = 0
                var lastResult: WebhookResponseParser.ParseResult? = null

                while (retryCount < MAX_RETRIES) {
                    val result = sendOnce(signed, tag, retryCount, contentType)
                    lastResult = result

                    // 成功或不可重试 → 终止
                    if (result.status == WebhookResponseParser.DeliveryStatus.SUCCESS) {
                        Log.d(TAG, "$tag delivered (attempt ${retryCount + 1}): ${result.message}")
                        onResult?.invoke(result)
                        return@launch
                    }
                    if (!result.retryable) {
                        Log.e(TAG, "$tag delivery failed (no retry): ${result.message}")
                        onResult?.invoke(result)
                        return@launch
                    }

                    Log.w(TAG, "$tag delivery failed (attempt ${retryCount + 1}), will retry: ${result.message}")
                    retryCount++

                    if (retryCount < MAX_RETRIES) {
                        // 限流用更长退避
                        val delayMs = if (result.status == WebhookResponseParser.DeliveryStatus.RATE_LIMITED) {
                            RATE_LIMIT_RETRY_DELAY_MS * retryCount
                        } else {
                            RETRY_DELAY_MS * retryCount
                        }
                        delay(delayMs)
                    }
                }

                // 重试耗尽
                Log.e(TAG, "$tag delivery exhausted retries: ${lastResult?.message}")
                onResult?.invoke(
                    lastResult ?: WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.NETWORK_FAIL,
                        0, "Unknown failure after $MAX_RETRIES attempts", false
                    )
                )
            }
        }

        private fun sendOnce(
            signed: WebhookSigner.SignedRequest,
            tag: String,
            attempt: Int,
            contentType: String = "application/json; charset=utf-8"
        ): WebhookResponseParser.ParseResult {
            return try {
                val requestBuilder = Request.Builder()
                    .url(signed.url)
                    .addHeader("User-Agent", "NotificationMonitor/1.0")

                val body = signed.payload.toRequestBody(contentType.toMediaType())
                requestBuilder.post(body)

                // 通用 webhook 签名头
                for ((k, v) in signed.headers) {
                    requestBuilder.addHeader(k, v)
                }

                val request = requestBuilder.build()

                client.newCall(request).execute().use { response ->
                    val respBody = response.body?.string() ?: ""
                    val parser = WebhookResponseParser.parse(
                        WebhookPayloadBuilder.detectType(signed.url),
                        response.code,
                        respBody
                    )
                    Log.d(TAG, "$tag HTTP ${response.code} (attempt ${attempt + 1}): ${parser.message}")
                    parser
                }
            } catch (e: Exception) {
                Log.e(TAG, "$tag network error (attempt ${attempt + 1}): ${e.message}")
                WebhookResponseParser.ParseResult(
                    WebhookResponseParser.DeliveryStatus.NETWORK_FAIL,
                    0, "Network error: ${e.message}", true
                )
            }
        }

        fun destroy() {
            isActive = false
            // 取消全部进行中的发送/重试协程，避免服务销毁后回调（最长约 34 秒退避）
            scope.cancel()
            Log.d(TAG, "NetworkClient deactivated (coroutines cancelled)")
        }

        fun activate() {
            isActive = true
            if (!scope.isActive) {
                scope = newScope()
            }
            Log.d(TAG, "NetworkClient activated")
        }
    }
}
