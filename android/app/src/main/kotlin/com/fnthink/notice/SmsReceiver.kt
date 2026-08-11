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
            val channelConfigs = configManager.getWebhookChannelConfigs()
            val deviceName = configManager.getDeviceName().ifEmpty { android.os.Build.MODEL }

            if (channelConfigs.isEmpty()) return

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
                    sender = smsMessage.originatingAddress ?: I18n.unknownSender()
                    timestamp = smsMessage.timestampMillis
                }
                message += smsMessage.messageBody ?: ""
            }

            // 统一通过 SimInfoHelper.getSimInfoFromIntent 入口识别 SIM 卡
            // 兼容多 key（subscription / EXTRA_SUBSCRIPTION_ID）+ 多策略降级（subId→单卡→slotId→占位）
            val simInfo = SimInfoHelper.getSimInfoFromIntent(context, intent)?.displayLabel
            val simLabel = if (simInfo != null) " [$simInfo]" else ""

            if (message.isNotEmpty()) {
                Log.d(TAG, "收到短信: 来自 $sender$simLabel")

                val timeStr = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
                    .format(Date(timestamp))

                // 接入统一过滤引擎：短信链路与通知链路共用同一套黑白名单
                // 注意：sms 不走应用过滤（无 packageName 概念），仅按关键词过滤
                val allowed = FilterEngine.shouldNotify(
                    packageName = "com.android.mms",
                    title = I18n.smsNotifyTitle(sender, simInfo),
                    content = message,
                    subText = "",
                    whitelistKeywords = configManager.getWhitelistKeywords(),
                    enabledPackages = emptySet(),
                    blacklistKeywords = configManager.getBlacklistKeywords(),
                    filterMode = "allow",
                    sourceType = "sms"
                )
                if (!allowed) {
                    Log.d(TAG, "短信被过滤拦截: 来自 $sender")
                    return
                }

                for (cfg in channelConfigs) {
                    sendWebhook(
                        context = context,
                        sender = sender,
                        message = message,
                        timestamp = timestamp,
                        timeStr = timeStr,
                        channelConfig = cfg,
                        deviceName = deviceName,
                        simInfo = simInfo
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
        channelConfig: ConfigManager.WebhookChannelConfig,
        deviceName: String,
        simInfo: String?
    ) {
        val simLabel = if (simInfo != null) " [$simInfo]" else ""
        try {
            val json = org.json.JSONObject().apply {
                put("type", "sms")
                put("id", "sms_${timestamp}_${sender.hashCode()}")
                put("title", I18n.smsNotifyTitle(sender, simInfo))
                put("sender", sender)
                put("content", message)
                put("message", message)
                put("packageName", "com.android.mms")
                put("appName", I18n.smsAppName())
                put("postTime", timestamp)
                put("time", timeStr)
                put("deviceName", deviceName)
                put("timestamp", System.currentTimeMillis())
                if (simInfo != null) put("simInfo", simInfo)
            }
            // 同步写入离线缓存，避免 Flutter 引擎未就绪时丢失
            HistoryCache.append(context, json)

            val intent = Intent(MainActivity.ACTION_NOTIFICATION_RECEIVED).apply {
                setPackage(context.packageName)
                putExtra(MainActivity.EXTRA_NOTIFICATION_DATA, json.toString())
            }
            context.sendBroadcast(intent)
        } catch (e: Exception) {
            Log.e(TAG, "发送短信广播失败", e)
        }

        val payload = WebhookPayloadBuilder.buildSmsPayload(
            type = channelConfig.type,
            sender = sender,
            message = message,
            time = timeStr,
            deviceName = deviceName,
            simInfo = simInfo
        )

        // 通过 NetworkClient 发送（含签名 + 送达校验）
        NetworkClient.sendWithRetry(
            url = channelConfig.url,
            payload = payload,
            tag = "sms",
            webhookType = channelConfig.type,
            secret = channelConfig.secret,
            onResult = { result ->
                Log.d(TAG, "SMS delivery: ${channelConfig.url.take(40)} → status=${result.status}")
            }
        )
    }
}
