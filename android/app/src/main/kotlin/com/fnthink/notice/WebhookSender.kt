package com.fnthink.notice

import android.content.Context
import android.content.Intent
import android.util.Log
import org.json.JSONObject

class WebhookSender(private val context: Context) {
    companion object {
        private const val TAG = "WebhookSender"
    }

    // 持有完整通道配置（url + secret + type），用于签名与送达校验
    private var channelConfigs: List<ConfigManager.WebhookChannelConfig> = emptyList()
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

        if (channelConfigs.isEmpty()) return

        for (cfg in channelConfigs) {
            sendToSingleUrl(cfg, info)
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
                put("timestamp", System.currentTimeMillis())
            }
            // 同步写入离线缓存：即使 MainActivity 被销毁，Flutter 重启后也能从缓存拉取
            HistoryCache.append(context, json)

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
        info: NotificationInfo
    ) {
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
            vars = vars
        )

        if (platformPayload != null) {
            // 企微/钉钉/飞书：平台原生支持 text/markdown，按平台 payload 发送
            NetworkClient.sendWithRetry(
                url = cfg.url,
                payload = platformPayload,
                tag = "notification",
                webhookType = cfg.type,
                secret = cfg.secret,
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
            notifyType = info.type
        )
        // 通过 NetworkClient 发送（含签名 + 送达校验）
        NetworkClient.sendWithRetry(
            url = cfg.url,
            payload = payload,
            tag = "notification",
            webhookType = cfg.type,
            secret = cfg.secret,
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
