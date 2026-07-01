package com.fnthink.notice

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.telephony.TelephonyManager
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

class PhoneCallReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "PhoneCallReceiver"
        private var lastState = TelephonyManager.CALL_STATE_IDLE
        private var lastIncomingNumber: String = ""
        private var callStartTime: Long = 0

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

        if (intent.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) return

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

            val stateStr = intent.getStringExtra(TelephonyManager.EXTRA_STATE)
            val incomingNumber = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER) ?: ""

            val state = when (stateStr) {
                TelephonyManager.EXTRA_STATE_RINGING -> TelephonyManager.CALL_STATE_RINGING
                TelephonyManager.EXTRA_STATE_OFFHOOK -> TelephonyManager.CALL_STATE_OFFHOOK
                TelephonyManager.EXTRA_STATE_IDLE -> TelephonyManager.CALL_STATE_IDLE
                else -> TelephonyManager.CALL_STATE_IDLE
            }

            if (state == lastState && incomingNumber == lastIncomingNumber) return

            Log.d(TAG, "电话状态变化: $stateStr, 号码: $incomingNumber")

            when (state) {
                TelephonyManager.CALL_STATE_RINGING -> {
                    callStartTime = System.currentTimeMillis()
                    lastIncomingNumber = incomingNumber
                    if (incomingNumber.isNotEmpty()) {
                        sendIncomingCallWebhook(
                            context = context,
                            phoneNumber = incomingNumber,
                            webhookUrl = webhookUrl,
                            deviceName = deviceName
                        )
                    }
                }
                TelephonyManager.CALL_STATE_OFFHOOK -> {
                    if (lastState == TelephonyManager.CALL_STATE_RINGING) {
                        if (lastIncomingNumber.isNotEmpty()) {
                            sendCallAnsweredWebhook(
                                context = context,
                                phoneNumber = lastIncomingNumber,
                                webhookUrl = webhookUrl,
                                deviceName = deviceName
                            )
                        }
                    }
                }
                TelephonyManager.CALL_STATE_IDLE -> {
                    if (lastState == TelephonyManager.CALL_STATE_RINGING || lastState == TelephonyManager.CALL_STATE_OFFHOOK) {
                        if (lastIncomingNumber.isNotEmpty()) {
                            val duration = if (callStartTime > 0) {
                                System.currentTimeMillis() - callStartTime
                            } else 0L
                            sendCallEndedWebhook(
                                context = context,
                                phoneNumber = lastIncomingNumber,
                                duration = duration,
                                webhookUrl = webhookUrl,
                                deviceName = deviceName
                            )
                        }
                        callStartTime = 0
                    }
                }
            }

            lastState = state
        } catch (e: Exception) {
            Log.e(TAG, "处理电话状态失败", e)
        }
    }

    private fun sendIncomingCallWebhook(
        context: Context,
        phoneNumber: String,
        webhookUrl: String,
        deviceName: String
    ) {
        val now = System.currentTimeMillis()
        val timeStr = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
            .format(Date(now))

        notifyFlutter(
            context = context,
            type = "call_incoming",
            title = "来电 - $phoneNumber",
            content = "来电: $phoneNumber",
            appName = "电话",
            packageName = "com.android.dialer",
            postTime = now,
            time = timeStr,
            extra = mapOf(
                "phoneNumber" to phoneNumber,
                "callState" to "ringing"
            ),
            deviceName = deviceName
        )

        val webhookType = WebhookPayloadBuilder.detectType(webhookUrl)
        val payload = WebhookPayloadBuilder.buildCallPayload(
            type = webhookType,
            state = "ringing",
            phoneNumber = phoneNumber,
            time = timeStr,
            deviceName = deviceName
        )

        CoroutineScope(Dispatchers.IO).launch {
            sendWithRetry(webhookUrl, payload, "来电通知")
        }
    }

    private fun sendCallAnsweredWebhook(
        context: Context,
        phoneNumber: String,
        webhookUrl: String,
        deviceName: String
    ) {
        val now = System.currentTimeMillis()
        val timeStr = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
            .format(Date(now))

        notifyFlutter(
            context = context,
            type = "call_answered",
            title = "通话中 - $phoneNumber",
            content = "已接听: $phoneNumber",
            appName = "电话",
            packageName = "com.android.dialer",
            postTime = now,
            time = timeStr,
            extra = mapOf(
                "phoneNumber" to phoneNumber,
                "callState" to "answered"
            ),
            deviceName = deviceName
        )

        val webhookType = WebhookPayloadBuilder.detectType(webhookUrl)
        val payload = WebhookPayloadBuilder.buildCallPayload(
            type = webhookType,
            state = "answered",
            phoneNumber = phoneNumber,
            time = timeStr,
            deviceName = deviceName
        )

        CoroutineScope(Dispatchers.IO).launch {
            sendWithRetry(webhookUrl, payload, "接听通知")
        }
    }

    private fun sendCallEndedWebhook(
        context: Context,
        phoneNumber: String,
        duration: Long,
        webhookUrl: String,
        deviceName: String
    ) {
        val now = System.currentTimeMillis()
        val timeStr = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
            .format(Date(now))
        val durationSec = duration / 1000
        val durationStr = "${durationSec / 60}分${durationSec % 60}秒"

        notifyFlutter(
            context = context,
            type = "call_ended",
            title = "通话结束 - $phoneNumber",
            content = "通话结束: $phoneNumber, 时长: $durationStr",
            appName = "电话",
            packageName = "com.android.dialer",
            postTime = now,
            time = timeStr,
            extra = mapOf(
                "phoneNumber" to phoneNumber,
                "callState" to "ended",
                "duration" to duration,
                "durationStr" to durationStr
            ),
            deviceName = deviceName
        )

        val webhookType = WebhookPayloadBuilder.detectType(webhookUrl)
        val payload = WebhookPayloadBuilder.buildCallPayload(
            type = webhookType,
            state = "ended",
            phoneNumber = phoneNumber,
            time = timeStr,
            durationStr = durationStr,
            deviceName = deviceName
        )

        CoroutineScope(Dispatchers.IO).launch {
            sendWithRetry(webhookUrl, payload, "挂断通知")
        }
    }

    private fun notifyFlutter(
        context: Context,
        type: String,
        title: String,
        content: String,
        appName: String,
        packageName: String,
        postTime: Long,
        time: String,
        extra: Map<String, Any> = emptyMap(),
        deviceName: String
    ) {
        try {
            val intent = Intent(MainActivity.ACTION_NOTIFICATION_RECEIVED).apply {
                setPackage(context.packageName)
                val json = org.json.JSONObject().apply {
                    put("type", type)
                    put("id", "call_${type}_${postTime}_${title.hashCode()}")
                    put("title", title)
                    put("content", content)
                    put("appName", appName)
                    put("packageName", packageName)
                    put("postTime", postTime)
                    put("time", time)
                    put("deviceName", deviceName)
                    put("timestamp", System.currentTimeMillis())
                    for ((k, v) in extra) {
                        put(k, v)
                    }
                }
                putExtra(MainActivity.EXTRA_NOTIFICATION_DATA, json.toString())
            }
            context.sendBroadcast(intent)
        } catch (e: Exception) {
            Log.e(TAG, "发送电话通知广播失败", e)
        }
    }

    private fun sendWithRetry(
        webhookUrl: String,
        payload: String,
        tag: String
    ) {
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
                        Log.d(TAG, "$tag Webhook发送成功 (尝试 ${retryCount + 1})")
                        return
                    } else {
                        val respBody = response.body?.string() ?: ""
                        Log.e(TAG, "$tag Webhook失败: ${response.code} - ${respBody.take(200)} (尝试 ${retryCount + 1})")
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "$tag Webhook发送错误 (尝试 ${retryCount + 1})", e)
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
