package com.fnthink.notice

import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
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

        @Volatile private var isActive = true
        private val scope = CoroutineScope(Dispatchers.IO)

        private val client: OkHttpClient by lazy {
            OkHttpClient.Builder()
                .connectTimeout(15, TimeUnit.SECONDS)
                .writeTimeout(15, TimeUnit.SECONDS)
                .readTimeout(15, TimeUnit.SECONDS)
                .retryOnConnectionFailure(false)
                // SSL 证书固定：防止中间人攻击。将以下 SHA256 改为你服务器的真实证书指纹。
                // 使用 openssl s_client -connect notice.fnthink.top:443 -servername notice.fnthink.top 2>/dev/null | openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl base64
                // 如需启用，取消下面注释并在 CERT_PINS 中填入你的证书 SHA256 base64 哈希：
                // .certificatePinner(
                //     CertificatePinner.Builder()
                //         .add("notice.fnthink.top", CERT_PINS)
                //         .add("xget.fnthink.top", CERT_PINS)
                //         .build()
                // )
                .build()
        }

        fun sendWithRetry(
            url: String,
            payload: String,
            tag: String = "webhook"
        ) {
            if (!isActive) return
            scope.launch {
                var retryCount = 0

                while (retryCount < MAX_RETRIES) {
                    try {
                        val body = payload.toRequestBody("application/json; charset=utf-8".toMediaType())
                        val request = Request.Builder()
                            .url(url)
                            .post(body)
                            .addHeader("User-Agent", "NotificationMonitor/1.0")
                            .build()

                        client.newCall(request).execute().use { response ->
                            if (response.isSuccessful) {
                                Log.d(TAG, "$tag Webhook sent successfully (attempt ${retryCount + 1})")
                                return@launch
                            } else {
                                Log.e(TAG, "$tag Webhook failed: HTTP ${response.code} (attempt ${retryCount + 1})")
                            }
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "$tag Webhook send error (attempt ${retryCount + 1})")
                    }

                    retryCount++
                    if (retryCount < MAX_RETRIES) {
                        delay(RETRY_DELAY_MS * retryCount)
                    }
                }
            }
        }

        fun destroy() {
            isActive = false
            Log.d(TAG, "NetworkClient deactivated")
        }

        fun activate() {
            isActive = true
            Log.d(TAG, "NetworkClient activated")
        }
    }
}
