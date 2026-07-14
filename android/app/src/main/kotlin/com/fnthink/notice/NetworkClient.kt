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

        private val job = SupervisorJob()
        private val scope = CoroutineScope(job + Dispatchers.IO)

        private val client: OkHttpClient by lazy {
            OkHttpClient.Builder()
                .connectTimeout(15, TimeUnit.SECONDS)
                .writeTimeout(15, TimeUnit.SECONDS)
                .readTimeout(15, TimeUnit.SECONDS)
                .retryOnConnectionFailure(true)
                .build()
        }

        fun sendWithRetry(
            url: String,
            payload: String,
            tag: String = "webhook"
        ) {
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
                                Log.d(TAG, "$tag Webhook sent successfully to ${url.take(30)}... (attempt ${retryCount + 1})")
                                return@launch
                            } else {
                                val respBody = response.body?.string() ?: ""
                                Log.e(TAG, "$tag Webhook failed for ${url.take(30)}...: ${response.code} - ${respBody.take(200)} (attempt ${retryCount + 1})")
                            }
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "$tag Webhook send error for ${url.take(30)}... (attempt ${retryCount + 1})", e)
                    }

                    retryCount++
                    if (retryCount < MAX_RETRIES) {
                        delay(RETRY_DELAY_MS * retryCount)
                    }
                }
            }
        }

        fun destroy() {
            job.cancel()
            Log.d(TAG, "NetworkClient scope cancelled")
        }
    }
}
