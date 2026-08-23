package com.fnthink.notice

import android.content.Context
import android.content.Intent
import android.util.Log
import org.json.JSONObject

class WebhookSender(private val context: Context) {
    companion object {
        private const val TAG = "WebhookSender"
    }

    // 持有完整通道配置（url + secret + type），用于签名与送达校验。
    // @Volatile + 不可变 List：配置线程写入、IO 线程读取，copy-on-write 保证可见性（E2）
    @Volatile
    private var channelConfigs: List<ConfigManager.WebhookChannelConfig> = emptyList()
    @Volatile
    private var deviceName: String = ""

    fun destroy() {
        NetworkClient.destroy()
        Log.d(TAG, "WebhookSender destroyed")
    }

    fun activate() {
        NetworkClient.activate()
    }

    fun setDeviceName(name: String) {
        deviceName = name
    }

    /**
     * 兼容旧接口：仅更新 URL 列表（无 secret / type，将退化为无签名推送）
     */
    fun updateUrls(urls: List<String>) {
        channelConfigs = urls.filter { it.isNotEmpty() }.map {
            ConfigManager.WebhookChannelConfig(it, null, WebhookPayloadBuilder.detectType(it))
        }
        Log.d(TAG, "Webhook URLs updated: ${channelConfigs.size} URLs (legacy mode, no signing)")
    }

    /**
     * 更新完整通道配置（含 secret 与 type，启用签名与送达校验）
     */
    fun updateChannelConfigs(configs: List<ConfigManager.WebhookChannelConfig>) {
        channelConfigs = configs.filter { it.url.isNotEmpty() }
        Log.d(TAG, "Webhook channels updated: ${channelConfigs.size} channels (with signing)")
    }

    fun sendNotification(info: NotificationInfo) {
        sendBroadcast(info)

        sendWebhooksOnly(info)
    }

    /**
     * 仅推送 webhook（不广播记录）。用于延迟推送到点后的补推：
     * 记录已在通知到达时通过 sendBroadcast 立即写入历史。
     *
     * @param force 强制发送：为 true 时忽略"推送暂停"开关（历史记录"现在推送"手动补推）
     */
    fun sendWebhooksOnly(info: NotificationInfo, force: Boolean = false) {
        if (channelConfigs.isEmpty()) return

        for (cfg in channelConfigs) {
            sendToSingleUrl(cfg, info, force)
        }
    }

    fun sendBroadcast(info: NotificationInfo) {
        try {
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
                put("priority", info.priority)
                put("timestamp", System.currentTimeMillis())
            }
            // 同步写入离线缓存：即使 MainActivity 被销毁，Flutter 重启后也能从缓存拉取
            HistoryCache.append(context, json)

            // 当日推送计数（桌面小部件 4×2 规格数据源，跨天自动重置）
            WidgetDailyCounter.increment(context)
            // 推送数量变化后刷新小部件（仅在已添加小部件时广播，无小部件时零开销）
            PushToggleWidgetProvider.updateAllWidgetsIfExists(context)

            val intent = Intent(MainActivity.ACTION_NOTIFICATION_RECEIVED).apply {
                setPackage(context.packageName)
                putExtra(MainActivity.EXTRA_NOTIFICATION_DATA, json.toString())
            }
            context.sendBroadcast(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send broadcast", e)
        }
    }

    private fun sendToSingleUrl(
        cfg: ConfigManager.WebhookChannelConfig,
        info: NotificationInfo,
        force: Boolean = false
    ) {
        // Telegram 必须携带 chat_id（一般来自 URL query）。缺失时提前失败并给出明确原因，
        // 避免发出必然 400 的请求再被记为送达失败。
        val chatId = WebhookPayloadBuilder.extractChatIdFromUrl(cfg.url)
        if (cfg.type == WebhookPayloadBuilder.WebhookType.TELEGRAM && chatId.isEmpty()) {
            Log.e(TAG, "Telegram URL missing chat_id, skip: ${cfg.url.take(60)}")
            notifyDeliveryResult(
                info.id,
                cfg.type,
                WebhookResponseParser.ParseResult(
                    WebhookResponseParser.DeliveryStatus.BIZ_FAIL,
                    0, "Telegram 链接缺少 chat_id 参数", false
                )
            )
            return
        }

        // Server酱：POST form（application/x-www-form-urlencoded），内容不进 URL，避免被代理/日志留存
        if (cfg.type == WebhookPayloadBuilder.WebhookType.SERVER_CHAN) {
            val formBody = WebhookPayloadBuilder.buildServerChanFormBody(
                title = info.title,
                content = info.content,
                deviceName = deviceName,
                time = info.time
            )
            NetworkClient.sendWithRetry(
                url = cfg.url,
                payload = formBody,
                tag = "notification",
                webhookType = cfg.type,
                secret = cfg.secret,
                contentType = "application/x-www-form-urlencoded; charset=utf-8",
                force = force,
                onResult = { result ->
                    Log.d(TAG, "Delivery(ServerChan): ${cfg.url.take(40)} → status=${result.status} msg=${result.message}")
                    notifyDeliveryResult(info.id, cfg.type, result)
                }
            )
            return
        }

        // PushPlus：token 从 URL query 提取注入 body（缺失时提前失败）
        val pushPlusToken = WebhookPayloadBuilder.extractTokenFromUrl(cfg.url)
        if (cfg.type == WebhookPayloadBuilder.WebhookType.PUSH_PLUS && pushPlusToken.isEmpty()) {
            Log.e(TAG, "PushPlus URL missing token, skip: ${cfg.url.take(60)}")
            notifyDeliveryResult(
                info.id,
                cfg.type,
                WebhookResponseParser.ParseResult(
                    WebhookResponseParser.DeliveryStatus.BIZ_FAIL,
                    0, "PushPlus 链接缺少 token 参数", false
                )
            )
            return
        }
        if (cfg.type == WebhookPayloadBuilder.WebhookType.PUSH_PLUS) {
            val pushPlusPayload = WebhookPayloadBuilder.buildPushPlusPayload(
                title = info.title,
                content = info.content,
                deviceName = deviceName,
                time = info.time,
                token = pushPlusToken
            )
            NetworkClient.sendWithRetry(
                url = cfg.url,
                payload = pushPlusPayload,
                tag = "notification",
                webhookType = cfg.type,
                secret = cfg.secret,
                force = force,
                onResult = { result ->
                    Log.d(TAG, "Delivery(PushPlus): ${cfg.url.take(40)} → status=${result.status} msg=${result.message}")
                    notifyDeliveryResult(info.id, cfg.type, result)
                }
            )
            return
        }

        // 优先使用自定义模板（仅当 messageFormat != default 且非空时）
        val vars = TemplateEngine.Vars(
            appName = info.appName,
            title = info.title,
            content = info.content,
            subText = info.subText,
            time = info.time,
            deviceName = deviceName,
            packageName = info.packageName,
            notifyType = info.type
        )

        val platformPayload = TemplateEngine.buildPlatformPayload(
            type = cfg.type,
            format = cfg.messageFormat,
            template = cfg.messageTemplate ?: "",
            vars = vars,
            chatId = chatId
        )

        if (platformPayload != null) {
            // 企微/钉钉/飞书：平台原生支持 text/markdown，按平台 payload 发送
            NetworkClient.sendWithRetry(
                url = cfg.url,
                payload = platformPayload,
                tag = "notification",
                webhookType = cfg.type,
                secret = cfg.secret,
                force = force,
                onResult = { result ->
                    Log.d(TAG, "Delivery: ${cfg.url.take(40)} → status=${result.status} msg=${result.message}")
                    notifyDeliveryResult(info.id, cfg.type, result)
                }
            )
            return
        }

        val genericBody = TemplateEngine.buildGenericBody(
            format = cfg.messageFormat,
            template = cfg.messageTemplate ?: "",
            vars = vars
        )

        if (genericBody != null && cfg.type == WebhookPayloadBuilder.WebhookType.GENERIC) {
            // 通用 webhook + 自定义模板（text/markdown/json/xml）：直接发送渲染后 body
            val (body, contentType) = genericBody
            NetworkClient.sendWithRetry(
                url = cfg.url,
                payload = body,
                tag = "notification",
                webhookType = cfg.type,
                secret = cfg.secret,
                contentType = contentType,
                force = force,
                onResult = { result ->
                    Log.d(TAG, "Delivery: ${cfg.url.take(40)} → status=${result.status} msg=${result.message}")
                    notifyDeliveryResult(info.id, cfg.type, result)
                }
            )
            return
        }

        // 默认：走平台默认 payload
        val payload = WebhookPayloadBuilder.buildPayload(
            type = cfg.type,
            title = info.title,
            content = info.content,
            appName = info.appName,
            packageName = info.packageName,
            time = info.time,
            deviceName = deviceName,
            notifyType = info.type,
            chatId = chatId
        )
        // 通过 NetworkClient 发送（含签名 + 送达校验）
        NetworkClient.sendWithRetry(
            url = cfg.url,
            payload = payload,
            tag = "notification",
            webhookType = cfg.type,
            secret = cfg.secret,
            force = force,
            onResult = { result ->
                Log.d(TAG, "Delivery: ${cfg.url.take(40)} → status=${result.status} msg=${result.message}")
                notifyDeliveryResult(info.id, cfg.type, result)
                // TODO: 可选写入 webhook_delivery_log 表（DB v5），当前先记录日志
            }
        )
    }

    /**
     * 把单条通道的送达结果异步回传 Flutter（用于历史记录逐条显示推送成功状态）。
     * 链路：ACTION_DELIVERY_RESULT 广播 → MainActivity.deliveryReceiver → onDeliveryResult MethodChannel
     */
    private fun notifyDeliveryResult(
        notificationId: String,
        type: WebhookPayloadBuilder.WebhookType,
        result: WebhookResponseParser.ParseResult
    ) {
        DeliveryNotifier.notify(context, notificationId, type, result)
    }
}
