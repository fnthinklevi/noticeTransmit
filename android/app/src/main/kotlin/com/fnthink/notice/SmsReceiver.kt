package com.fnthink.notice

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.telephony.SmsMessage
import android.util.Log
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class SmsReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "SmsReceiver"
        private const val SMS_RECEIVED = "android.provider.Telephony.SMS_RECEIVED"
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        context ?: return
        intent ?: return

        if (intent.action != SMS_RECEIVED) return

        try {
            val configManager = ConfigManager(context)
            val webhookUrls = configManager.getWebhookUrls()
            val deviceName = configManager.getDeviceName().ifEmpty { android.os.Build.MODEL }

            if (webhookUrls.isEmpty()) return

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

                for (url in webhookUrls) {
                    sendWebhook(
                        context = context,
                        sender = sender,
                        message = message,
                        timestamp = timestamp,
                        timeStr = timeStr,
                        webhookUrl = url,
                        deviceName = deviceName
                    )
                }
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

        NetworkClient.sendWithRetry(webhookUrl, payload, "短信")
    }
}
