package com.fnthink.notice

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.telephony.TelephonyManager
import android.util.Log
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class PhoneCallReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "PhoneCallReceiver"
        @Volatile private var lastState = TelephonyManager.CALL_STATE_IDLE
        @Volatile private var lastIncomingNumber: String = ""
        @Volatile private var callStartTime: Long = 0
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        context ?: return
        intent ?: return

        if (intent.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) return

        try {
            val configManager = ConfigManager(context)
            val webhookUrls = configManager.getWebhookUrls()
            val deviceName = configManager.getDeviceName().ifEmpty { android.os.Build.MODEL }

            if (webhookUrls.isEmpty()) return

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
                        for (url in webhookUrls) {
                            sendIncomingCallWebhook(
                                context = context,
                                phoneNumber = incomingNumber,
                                webhookUrl = url,
                                deviceName = deviceName
                            )
                        }
                    }
                }
                TelephonyManager.CALL_STATE_OFFHOOK -> {
                    if (lastState == TelephonyManager.CALL_STATE_RINGING) {
                        if (lastIncomingNumber.isNotEmpty()) {
                            for (url in webhookUrls) {
                                sendCallAnsweredWebhook(
                                    context = context,
                                    phoneNumber = lastIncomingNumber,
                                    webhookUrl = url,
                                    deviceName = deviceName
                                )
                            }
                        }
                    }
                }
                TelephonyManager.CALL_STATE_IDLE -> {
                    if (lastState == TelephonyManager.CALL_STATE_RINGING || lastState == TelephonyManager.CALL_STATE_OFFHOOK) {
                        if (lastIncomingNumber.isNotEmpty()) {
                            val duration = if (callStartTime > 0) {
                                System.currentTimeMillis() - callStartTime
                            } else 0L
                            for (url in webhookUrls) {
                                sendCallEndedWebhook(
                                    context = context,
                                    phoneNumber = lastIncomingNumber,
                                    duration = duration,
                                    webhookUrl = url,
                                    deviceName = deviceName
                                )
                            }
                        }
                        callStartTime = 0
                        lastIncomingNumber = ""
                    }
                }
            }

            lastState = state
        } catch (e: Exception) {
            Log.e(TAG, "处理电话状态失败", e)
        }
    }

    private fun sendCallWebhook(
        context: Context,
        phoneNumber: String,
        webhookUrl: String,
        deviceName: String,
        callState: String,
        duration: Long = 0L
    ) {
        val now = System.currentTimeMillis()
        val timeStr = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
            .format(Date(now))
        val durationSec = duration / 1000
        val durationStr = if (duration > 0) "${durationSec / 60}分${durationSec % 60}秒" else ""

        val notifyType = when (callState) {
            "ringing" -> "call_incoming"
            "answered" -> "call_answered"
            "ended" -> "call_ended"
            else -> "call_unknown"
        }

        val title = when (callState) {
            "ringing" -> "来电 - $phoneNumber"
            "answered" -> "通话中 - $phoneNumber"
            "ended" -> "通话结束 - $phoneNumber"
            else -> "电话 - $phoneNumber"
        }

        val content = when (callState) {
            "ringing" -> "来电: $phoneNumber"
            "answered" -> "已接听: $phoneNumber"
            "ended" -> "通话结束: $phoneNumber, 时长: $durationStr"
            else -> "电话: $phoneNumber"
        }

        val extra = mutableMapOf<String, Any>(
            "phoneNumber" to phoneNumber,
            "callState" to callState
        ).apply {
            if (duration > 0) {
                put("duration", duration)
                put("durationStr", durationStr)
            }
        }

        notifyFlutter(
            context = context,
            type = notifyType,
            title = title,
            content = content,
            appName = "电话",
            packageName = "com.android.dialer",
            postTime = now,
            time = timeStr,
            extra = extra,
            deviceName = deviceName
        )

        val webhookType = WebhookPayloadBuilder.detectType(webhookUrl)
        val payload = WebhookPayloadBuilder.buildCallPayload(
            type = webhookType,
            state = callState,
            phoneNumber = phoneNumber,
            time = timeStr,
            durationStr = durationStr,
            deviceName = deviceName
        )

        val tag = when (callState) {
            "ringing" -> "来电通知"
            "answered" -> "接听通知"
            "ended" -> "挂断通知"
            else -> "电话通知"
        }

        NetworkClient.sendWithRetry(webhookUrl, payload, tag)
    }

    private fun sendIncomingCallWebhook(
        context: Context,
        phoneNumber: String,
        webhookUrl: String,
        deviceName: String
    ) {
        sendCallWebhook(context, phoneNumber, webhookUrl, deviceName, "ringing")
    }

    private fun sendCallAnsweredWebhook(
        context: Context,
        phoneNumber: String,
        webhookUrl: String,
        deviceName: String
    ) {
        sendCallWebhook(context, phoneNumber, webhookUrl, deviceName, "answered")
    }

    private fun sendCallEndedWebhook(
        context: Context,
        phoneNumber: String,
        duration: Long,
        webhookUrl: String,
        deviceName: String
    ) {
        sendCallWebhook(context, phoneNumber, webhookUrl, deviceName, "ended", duration)
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
}
