package com.fnthink.notice

import android.content.Context
import android.content.Intent
import android.util.Log
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class WebhookSender(private val context: Context) {
    companion object {
        private const val TAG = "WebhookSender"
        private const val MAX_RETRIES = 3
        private const val RETRY_DELAY_MS = 2000L
    }

    private val okHttpClient = OkHttpClient.Builder()
        .connectTimeout(10, java.util.concurrent.TimeUnit.SECONDS)
        .readTimeout(15, java.util.concurrent.TimeUnit.SECONDS)
        .writeTimeout(10, java.util.concurrent.TimeUnit.SECONDS)
        .build()

    private var webhookUrls = emptyList<String>()
    private var deviceName: String = ""

    fun setDeviceName(name: String) {
        deviceName = name
    }

    fun updateUrls(urls: List<String>) {
        webhookUrls = urls.filter { it.isNotEmpty() }
        Log.d(TAG, "Webhook URLs updated: ${webhookUrls.size} URLs")
    }

    fun sendNotification(info: NotificationInfo) {
        sendBroadcast(info)
        saveNotificationRecord(info)

        if (webhookUrls.isEmpty()) return

        for (url in webhookUrls) {
            sendToSingleUrl(url, info)
        }
    }

    private fun sendBroadcast(info: NotificationInfo) {
        try {
            val intent = Intent(MainActivity.ACTION_NOTIFICATION_RECEIVED).apply {
                setPackage(context.packageName)
                val json = JSONObject().apply {
                    put("id", info.id)
                    put("title", info.title)
                    put("content", info.content)
                    put("subText", info.subText)
                    put("packageName", info.packageName)
                    put("appName", info.appName)
                    put("postTime", info.postTime)
                    put("time", info.time)
                    put("type", info.type)
                    put("deviceName", info.deviceName)
                    put("timestamp", System.currentTimeMillis())
                }
                putExtra(MainActivity.EXTRA_NOTIFICATION_DATA, json.toString())
            }
            context.sendBroadcast(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send broadcast", e)
        }
    }

    private fun saveNotificationRecord(info: NotificationInfo) {
        try {
            val json = JSONObject().apply {
                put("id", info.id)
                put("title", info.title)
                put("content", info.content)
                put("packageName", info.packageName)
                put("appName", info.appName)
                put("postTime", info.postTime)
                put("time", info.time)
                put("type", info.type)
                put("deviceName", info.deviceName)
                put("timestamp", System.currentTimeMillis())
            }

            val prefs = context.getSharedPreferences("notification_records", Context.MODE_PRIVATE)
            val recordsJson = prefs.getString("records", "[]")
            val records = org.json.JSONArray(recordsJson)
            records.put(0, json)

            while (records.length() > 100) {
                records.remove(records.length() - 1)
            }

            prefs.edit().putString("records", records.toString()).apply()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save notification record", e)
        }
    }

    private fun sendToSingleUrl(url: String, info: NotificationInfo) {
        CoroutineScope(Dispatchers.IO).launch {
            var retryCount = 0

            while (retryCount < MAX_RETRIES) {
                try {
                    val webhookType = WebhookPayloadBuilder.detectType(url)
                    val payload = WebhookPayloadBuilder.buildPayload(
                        type = webhookType,
                        title = info.title,
                        content = info.content,
                        appName = info.appName,
                        packageName = info.packageName,
                        time = info.time,
                        deviceName = deviceName,
                        notifyType = info.type
                    )

                    val body = payload.toRequestBody("application/json; charset=utf-8".toMediaType())
                    val request = Request.Builder()
                        .url(url)
                        .post(body)
                        .addHeader("User-Agent", "NotificationMonitor/1.0")
                        .build()

                    okHttpClient.newCall(request).execute().use { response ->
                        if (response.isSuccessful) {
                            Log.d(TAG, "Webhook sent successfully to ${url.take(30)}... (attempt ${retryCount + 1})")
                            return@launch
                        } else {
                            val respBody = response.body?.string() ?: ""
                            Log.e(TAG, "Webhook failed for ${url.take(30)}...: ${response.code} - ${respBody.take(200)} (attempt ${retryCount + 1})")
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Webhook send error for ${url.take(30)}... (attempt ${retryCount + 1})", e)
                }

                retryCount++
                if (retryCount < MAX_RETRIES) {
                    try {
                        Thread.sleep(RETRY_DELAY_MS * retryCount)
                    } catch (_: InterruptedException) {}
                }
            }
        }
    }
}