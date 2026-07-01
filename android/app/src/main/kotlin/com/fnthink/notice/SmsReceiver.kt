package com.fnthink.notice

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.telephony.SmsMessage
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit

class SmsReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "SmsReceiver"
        private const val SMS_RECEIVED = "android.provider.Telephony.SMS_RECEIVED"

        private fun readDeviceNameFromFile(context: Context): String {
            return try {
                val file = java.io.File(context.filesDir, "device_name.txt")
                if (file.exists()) file.readText().trim() else ""
            } catch (_: Exception) {
                ""
            }
        }
    }

    private val okHttpClient: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .writeTimeout(15, TimeUnit.SECONDS)
            .readTimeout(15, TimeUnit.SECONDS)
            .retryOnConnectionFailure(true)
            .build()
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        context ?: return
        intent ?: return

        if (intent.action != SMS_RECEIVED) return

        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val webhookUrl = prefs.getString("flutter.webhook_url", "") ?: ""
            var deviceName = readDeviceNameFromFile(context)
            if (deviceName.isEmpty()) {
                deviceName = prefs.getString("flutter.device_name", "") ?: ""
            }
            if (deviceName.isEmpty()) {
                deviceName = android.os.Build.MODEL
            }

            if (webhookUrl.isEmpty()) return

            val bundle = intent.extras ?: return
            val pdus = bundle.get("pdus") as Array<*>?
            if (pdus == null || pdus.isEmpty()) return

            val format = bundle.getString("format")
            var sender = ""
            var message = ""
            var timestamp = 0L

            for (pdu in pdus) {
                val smsMessage = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    SmsMessage.createFromPdu(pdu as ByteArray, format)
                } else {
                    @Suppress("DEPRECATION")
                    SmsMessage.createFromPdu(pdu as ByteArray)
                }

                if (sender.isEmpty()) {
                    sender = smsMessage.originatingAddress ?: "未知号码"
                    timestamp = smsMessage.timestampMillis
                }
                message += smsMessage.messageBody ?: ""
            }

            if (message.isNotEmpty()) {
                Log.d(TAG, "收到短信: 来自 $sender")

                val timeStr = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
                    .format(Date(timestamp))

                sendWebhook(
                    context = context,
                    sender = sender,
                    message = message,
                    timestamp = timestamp,
                    timeStr = timeStr,
                    webhookUrl = webhookUrl,
                    deviceName = deviceName
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "处理短信失败", e)
        }
    }

    private fun sendWebhook(
        context: Context,
        sender: String,
        message: String,
        timestamp: Long,
        timeStr: String,
        webhookUrl: String,
        deviceName: String
    ) {
        try {
            val intent = Intent(MainActivity.ACTION_NOTIFICATION_RECEIVED).apply {
                setPackage(context.packageName)
                val json = org.json.JSONObject().apply {
                    put("type", "sms")
                    put("id", "sms_${timestamp}_${sender.hashCode()}")
                    put("title", "短信 - $sender")
                    put("sender", sender)
                    put("content", message)
                    put("message", message)
                    put("packageName", "com.android.mms")
                    put("appName", "短信")
                    put("postTime", timestamp)
                    put("time", timeStr)
                    put("deviceName", deviceName)
                    put("timestamp", System.currentTimeMillis())
                }
                putExtra(MainActivity.EXTRA_NOTIFICATION_DATA, json.toString())
            }
            context.sendBroadcast(intent)
        } catch (e: Exception) {
            Log.e(TAG, "发送短信广播失败", e)
        }

        val webhookType = WebhookPayloadBuilder.detectType(webhookUrl)
        val payload = WebhookPayloadBuilder.buildSmsPayload(
            type = webhookType,
            sender = sender,
            message = message,
            time = timeStr,
            deviceName = deviceName
        )

        CoroutineScope(Dispatchers.IO).launch {
            var retryCount = 0
            val maxRetries = 3

            while (retryCount < maxRetries) {
                try {
                    val body = payload.toRequestBody("application/json; charset=utf-8".toMediaType())
                    val request = Request.Builder()
                        .url(webhookUrl)
                        .post(body)
                        .addHeader("User-Agent", "NotificationMonitor/1.0")
                        .build()

                    okHttpClient.newCall(request).execute().use { response ->
                        if (response.isSuccessful) {
                            Log.d(TAG, "短信Webhook发送成功 (尝试 ${retryCount + 1})")
                            return@launch
                        } else {
                            val respBody = response.body?.string() ?: ""
                            Log.e(TAG, "短信Webhook失败: ${response.code} - ${respBody.take(200)} (尝试 ${retryCount + 1})")
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "短信Webhook发送错误 (尝试 ${retryCount + 1})", e)
                }

                retryCount++
                if (retryCount < maxRetries) {
                    try {
                        Thread.sleep(2000L * retryCount)
                    } catch (_: InterruptedException) {}
                }
            }
        }
    }
}
