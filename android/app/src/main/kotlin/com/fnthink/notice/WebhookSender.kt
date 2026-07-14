package com.fnthink.notice

import android.content.Context
import android.content.Intent
import android.util.Log
import org.json.JSONObject

class WebhookSender(private val context: Context) {
    companion object {
        private const val TAG = "WebhookSender"
    }

    private var webhookUrls = emptyList<String>()
    private var deviceName: String = ""

    fun destroy() {
        NetworkClient.destroy()
        Log.d(TAG, "WebhookSender destroyed")
    }

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

    fun sendToWebhooks(info: NotificationInfo) {
        if (webhookUrls.isEmpty()) return

        for (url in webhookUrls) {
            sendToSingleUrl(url, info)
        }
    }

    fun sendBroadcast(info: NotificationInfo) {
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

    fun saveNotificationRecord(info: NotificationInfo) {
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

            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val recordsJson = prefs.getString("flutter.notification_records", "[]")
            val records = org.json.JSONArray(recordsJson)
            records.put(0, json)

            while (records.length() > 100) {
                records.remove(records.length() - 1)
            }

            prefs.edit().putString("flutter.notification_records", records.toString()).apply()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save notification record", e)
        }
    }

    private fun sendToSingleUrl(url: String, info: NotificationInfo) {
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
        NetworkClient.sendWithRetry(url, payload, "notification")
    }
}