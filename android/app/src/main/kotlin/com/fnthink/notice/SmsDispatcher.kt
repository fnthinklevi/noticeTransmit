package com.fnthink.notice

import android.content.Context
import android.content.Intent
import android.util.Log
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Collections
import java.util.Date
import java.util.LinkedHashMap
import java.util.Locale

/**
 * 短信统一处理入口。
 *
 * 两条链路共用本类，保证过滤、去重、历史缓存与 Webhook 推送行为完全一致：
 *  · SmsReceiver —— SMS_RECEIVED 广播（主链路）
 *  · SmsObserver —— 短信库 ContentObserver（广播丢失时的兜底链路）
 *
 * 去重：广播与 ContentObserver 会对同一条短信各触发一次，按
 * 「发送方 + 正文 + 秒级时间戳」指纹在 DEDUP_WINDOW_MS 内去重，避免重复推送。
 */
object SmsDispatcher {
    private const val TAG = "SmsDispatcher"
    private const val DEDUP_WINDOW_MS = 120_000L
    private const val MAX_DEDUP_KEYS = 200

    private val dedupKeys = Collections.synchronizedMap(
        object : LinkedHashMap<String, Long>(64, 0.75f, true) {
            override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Long>?): Boolean =
                size > MAX_DEDUP_KEYS
        }
    )

    private const val VERIFY_KW =
        "(?:验证码|校验码|动态码|确认码|登录码|安全码|code|verification|otp|passcode)"

    // 主模式：关键词 + 任意非数字间隔 + 4~6 位纯数字。
    // 间隔用 [^0-9]（而非 [^0-9a-zA-Z]）才能跨过 "is" 这类填充词，
    // 命中 "Your verification code is 123456"；只取纯数字可避免把单词 code 当验证码。
    // 右侧 (?!\d) 保证不会从手机号/订单号里截出一段。
    private val codeDigitsAfter =
        Regex("(?i)$VERIFY_KW[^0-9]{0,16}(\\d{4,6})(?!\\d)")
    // 数字在关键词之前：123456 是您的验证码
    private val codeDigitsBefore =
        Regex("(?i)(\\d{4,6})(?!\\d)[^0-9]{0,16}$VERIFY_KW")
    // 次级：紧邻关键词的字母数字混合码（含至少一位数字），如 验证码 aB3d
    private val codeAlnumAfter =
        Regex("(?i)$VERIFY_KW[^0-9a-zA-Z]{0,8}(?=[0-9a-zA-Z]*\\d)([0-9a-zA-Z]{4,8})(?![0-9a-zA-Z])")

    /**
     * 提取验证码。仅在正文出现验证码语义词时提取，且码后不得紧跟字母数字，
     * 避免把手机号、订单号误判为验证码。提取不到返回 null。
     */
    fun extractCode(message: String): String? {
        if (message.isBlank()) return null
        codeDigitsAfter.find(message)?.let { return it.groupValues[1] }
        codeDigitsBefore.find(message)?.let { return it.groupValues[1] }
        codeAlnumAfter.find(message)?.let { return it.groupValues[1] }
        return null
    }

    private fun dedupKey(sender: String, message: String, timestamp: Long): String =
        "$sender|$message|${timestamp / 1000}"

    /**
     * 处理一条短信。
     * @param source 链路标识（broadcast / observer），仅用于日志区分
     * @return true 表示已推送，false 表示被去重、过滤或未配置通道
     */
    fun handle(
        context: Context,
        sender: String,
        message: String,
        timestamp: Long,
        simInfo: String?,
        source: String
    ): Boolean {
        if (message.isBlank()) {
            Log.w(TAG, "[$source] 短信正文为空，丢弃 sender=$sender")
            return false
        }

        val now = System.currentTimeMillis()
        val key = dedupKey(sender, message, timestamp)
        synchronized(dedupKeys) {
            val last = dedupKeys[key]
            if (last != null && now - last < DEDUP_WINDOW_MS) {
                Log.d(TAG, "[$source] 短信重复，已去重 sender=$sender")
                return false
            }
            // 不用 removeIf（要求 API 24+），手动迭代清理过期指纹
            val it = dedupKeys.entries.iterator()
            while (it.hasNext()) {
                if (now - it.next().value >= DEDUP_WINDOW_MS) it.remove()
            }
            dedupKeys[key] = now
        }

        return try {
            // 服务 onDestroy 会把 NetworkClient 置为 inactive，而短信广播仍会唤醒本进程。
            // 兜底激活，避免短信被静默丢弃（"NetworkClient inactive"）。
            NetworkClient.activate()

            val configManager = ConfigManager(context)
            val channelConfigs = configManager.getWebhookChannelConfigs()
            val deviceName = configManager.getDeviceName().ifEmpty { android.os.Build.MODEL }

            if (channelConfigs.isEmpty()) {
                Log.d(TAG, "[$source] 未配置 Webhook 通道，跳过")
                return false
            }

            Log.d(TAG, "[$source] 收到短信: 来自 $sender")

            val timeStr = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
                .format(Date(timestamp))

            // 短信不走应用过滤（无 packageName 概念），仅按关键词过滤
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
                Log.d(TAG, "[$source] 短信被过滤拦截: 来自 $sender")
                return false
            }

            val code = extractCode(message)
            if (code != null) Log.d(TAG, "[$source] 提取到验证码: $code")

            for (cfg in channelConfigs) {
                sendWebhook(
                    context = context,
                    sender = sender,
                    message = message,
                    timestamp = timestamp,
                    timeStr = timeStr,
                    channelConfig = cfg,
                    deviceName = deviceName,
                    simInfo = simInfo,
                    verificationCode = code
                )
            }
            true
        } catch (e: Exception) {
            Log.e(TAG, "[$source] 处理短信失败", e)
            false
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
        simInfo: String?,
        verificationCode: String?
    ) {
        // 与 notifyFlutter 中的记录 id 保持一致，供送达结果回传按 id 定位记录
        val notificationId = "sms_${timestamp}_${sender.hashCode()}"
        try {
            val json = JSONObject().apply {
                put("type", "sms")
                put("id", notificationId)
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
                if (verificationCode != null) {
                    put("verificationCode", verificationCode)
                    put("code", verificationCode)
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
            Log.e(TAG, "发送短信广播失败", e)
        }

        val payload = WebhookPayloadBuilder.buildSmsPayload(
            type = channelConfig.type,
            sender = sender,
            message = message,
            time = timeStr,
            deviceName = deviceName,
            simInfo = simInfo,
            chatId = WebhookPayloadBuilder.extractChatIdFromUrl(channelConfig.url)
        )

        // 通过 NetworkClient 发送（含签名 + 送达校验），结果回传 Flutter 逐条显示送达状态
        NetworkClient.sendWithRetry(
            url = channelConfig.url,
            payload = payload,
            tag = "sms",
            webhookType = channelConfig.type,
            secret = channelConfig.secret,
            onResult = { result ->
                Log.d(TAG, "SMS delivery: ${channelConfig.url.take(40)} → status=${result.status}")
                DeliveryNotifier.notify(context, notificationId, channelConfig.type, result)
            }
        )
    }
}
