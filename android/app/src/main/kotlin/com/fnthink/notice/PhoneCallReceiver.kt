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
            val channelConfigs = configManager.getWebhookChannelConfigs()
            val deviceName = configManager.getDeviceName().ifEmpty { android.os.Build.MODEL }

            if (channelConfigs.isEmpty()) return

            val stateStr = intent.getStringExtra(TelephonyManager.EXTRA_STATE)
            val incomingNumber = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER) ?: ""

            // 统一通过 SimInfoHelper.getSimInfoFromIntent 入口识别 SIM 卡
            // 兼容多 key（subscription / EXTRA_SUBSCRIPTION_ID）+ 多策略降级（subId→单卡→slotId→占位）
            val simInfo: String? = SimInfoHelper.getSimInfoFromIntent(context, intent)?.displayLabel

            val state = when (stateStr) {
                TelephonyManager.EXTRA_STATE_RINGING -> TelephonyManager.CALL_STATE_RINGING
                TelephonyManager.EXTRA_STATE_OFFHOOK -> TelephonyManager.CALL_STATE_OFFHOOK
                TelephonyManager.EXTRA_STATE_IDLE -> TelephonyManager.CALL_STATE_IDLE
                else -> TelephonyManager.CALL_STATE_IDLE
            }

            if (state == lastState && incomingNumber == lastIncomingNumber) return

            Log.d(TAG, "电话状态变化: $stateStr, 号码: $incomingNumber")

            // 接入统一过滤引擎：来电链路与通知链路共用同一套黑白名单
            // 注意：call 不走应用过滤，仅按关键词过滤；只在响铃阶段过滤，避免多次重复判定
            if (state == TelephonyManager.CALL_STATE_RINGING && incomingNumber.isNotEmpty()) {
                val titleForFilter = I18n.callNotifyTitle("ringing", incomingNumber, simInfo)
                val contentForFilter = I18n.callStateContent("ringing", incomingNumber, simInfo)
                val allowed = FilterEngine.shouldNotify(
                    packageName = "com.android.dialer",
                    title = titleForFilter,
                    content = contentForFilter,
                    subText = "",
                    whitelistKeywords = configManager.getWhitelistKeywords(),
                    enabledPackages = emptySet(),
                    blacklistKeywords = configManager.getBlacklistKeywords(),
                    filterMode = "allow",
                    sourceType = "call"
                )
                if (!allowed) {
                    Log.d(TAG, "来电被过滤拦截: $incomingNumber")
                    // 标记状态防止后续 answered/ended 仍触发推送
                    lastIncomingNumber = ""
                    return
                }
            }

            when (state) {
                TelephonyManager.CALL_STATE_RINGING -> {
                    callStartTime = System.currentTimeMillis()
                    lastIncomingNumber = incomingNumber
                    if (incomingNumber.isNotEmpty()) {
                        for (cfg in channelConfigs) {
                            sendCallWebhook(
                                context = context,
                                phoneNumber = incomingNumber,
                                callState = "ringing",
                                duration = 0L,
                                channelConfig = cfg,
                                deviceName = deviceName,
                                simInfo = simInfo
                            )
                        }
                    }
                }
                TelephonyManager.CALL_STATE_OFFHOOK -> {
                    if (lastState == TelephonyManager.CALL_STATE_RINGING) {
                        if (lastIncomingNumber.isNotEmpty()) {
                            for (cfg in channelConfigs) {
                                sendCallWebhook(
                                    context = context,
                                    phoneNumber = lastIncomingNumber,
                                    callState = "answered",
                                    duration = 0L,
                                    channelConfig = cfg,
                                    deviceName = deviceName,
                                    simInfo = simInfo
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
                            for (cfg in channelConfigs) {
                                sendCallWebhook(
                                    context = context,
                                    phoneNumber = lastIncomingNumber,
                                    callState = "ended",
                                    duration = duration,
                                    channelConfig = cfg,
                                    deviceName = deviceName,
                                    simInfo = simInfo
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
        channelConfig: ConfigManager.WebhookChannelConfig,
        deviceName: String,
        callState: String,
        duration: Long = 0L,
        simInfo: String? = null
    ) {
        val now = System.currentTimeMillis()
        val timeStr = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
            .format(Date(now))
        val durationSec = duration / 1000
        val durationStr = if (duration > 0) I18n.formatDuration(durationSec) else ""

        val notifyType = when (callState) {
            "ringing" -> "call_incoming"
            "answered" -> "call_answered"
            "ended" -> "call_ended"
            else -> "call_unknown"
        }

        val title = I18n.callNotifyTitle(callState, phoneNumber, simInfo)
        val content = I18n.callStateContent(callState, phoneNumber, simInfo) +
                (if (callState == "ended" && durationStr.isNotEmpty())
                    (if (I18n.getLocale() == "en") ", Duration: $durationStr" else ", 时长: $durationStr")
                 else "")

        // 与 notifyFlutter 中的记录 id 保持一致，供送达结果回传按 id 定位记录
        val notificationId = "call_${notifyType}_${now}_${title.hashCode()}"

        val extra = mutableMapOf<String, Any>(
            "phoneNumber" to phoneNumber,
            "callState" to callState
        ).apply {
            if (duration > 0) {
                put("duration", duration)
                put("durationStr", durationStr)
            }
            if (simInfo != null) put("simInfo", simInfo)
        }

        notifyFlutter(
            context = context,
            notificationId = notificationId,
            type = notifyType,
            title = title,
            content = content,
            appName = I18n.callAppName(),
            packageName = "com.android.dialer",
            postTime = now,
            time = timeStr,
            extra = extra,
            deviceName = deviceName
        )

        val payload = WebhookPayloadBuilder.buildCallPayload(
            type = channelConfig.type,
            state = callState,
            phoneNumber = phoneNumber,
            time = timeStr,
            durationStr = durationStr,
            deviceName = deviceName,
            simInfo = simInfo,
            chatId = WebhookPayloadBuilder.extractChatIdFromUrl(channelConfig.url)
        )

        val tag = when (callState) {
            "ringing" -> "来电通知"
            "answered" -> "接听通知"
            "ended" -> "挂断通知"
            else -> "电话通知"
        }

        // 通过 NetworkClient 发送（含签名 + 送达校验），结果回传 Flutter 逐条显示送达状态
        NetworkClient.sendWithRetry(
            url = channelConfig.url,
            payload = payload,
            tag = tag,
            webhookType = channelConfig.type,
            secret = channelConfig.secret,
            onResult = { result ->
                Log.d(TAG, "Call delivery: ${channelConfig.url.take(40)} → status=${result.status}")
                DeliveryNotifier.notify(context, notificationId, channelConfig.type, result)
            }
        )
    }

    private fun notifyFlutter(
        context: Context,
        notificationId: String,
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
            val json = org.json.JSONObject().apply {
                put("type", type)
                put("id", notificationId)
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
            // 同步写入离线缓存，避免 Flutter 引擎未就绪时丢失
            HistoryCache.append(context, json)

            val intent = Intent(MainActivity.ACTION_NOTIFICATION_RECEIVED).apply {
                setPackage(context.packageName)
                putExtra(MainActivity.EXTRA_NOTIFICATION_DATA, json.toString())
            }
            context.sendBroadcast(intent)
        } catch (e: Exception) {
            Log.e(TAG, "发送电话通知广播失败", e)
        }
    }
}
