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
     * @param onAllComplete 全部通道发送结束后的汇总回调（含单通道/无通道两种短路情形）。
     *   供聚合推送（[MergePushManager]）把**真实结果**回传给每个成员记录使用——
     *   该链路只有一条聚合 HTTP 结果，无法逐成员映射，必须靠本回调拿到结果，
     *   否则成员记录的送达状态只能写死成功（历史缺陷，见 MergePushManager 头注释 3）。
     */
    fun sendWebhooksOnly(
        info: NotificationInfo,
        force: Boolean = false,
        onAllComplete: ((WebhookResponseParser.ParseResult) -> Unit)? = null
    ) {
        if (channelConfigs.isEmpty()) {
            onAllComplete?.invoke(noChannelResult())
            return
        }

        // 单通道（最常见）直接透传，不做计数包装
        if (channelConfigs.size == 1) {
            sendToSingleUrl(channelConfigs[0], info, force, onAllComplete)
            return
        }

        // 多通道：等全部通道回结果后按「最差优先」汇总（任一失败即失败）——
        // 宁可多报一次失败，也不要让失败被某个成功通道掩盖。
        //
        // 并发约定（勿改）：结果集合与计数**共用同一把锁**（此前用
        // synchronizedList + 独立 lock 两把锁保护同一批状态，虽逻辑正确但易被后人改错）；
        // 且用 AtomicBoolean 保证汇总回调**至多触发一次**——某通道的 onResult 若因异常
        // 路径被调用两次，计数会提前达到 total，导致在结果不全时就汇总（可能选出非最差者）。
        val total = channelConfigs.size
        val results = ArrayList<WebhookResponseParser.ParseResult>(total)
        val lock = Any()
        val aggregated = java.util.concurrent.atomic.AtomicBoolean(false)
        for (cfg in channelConfigs) {
            sendToSingleUrl(cfg, info, force) { result ->
                val done = synchronized(lock) {
                    results.add(result)
                    // 多调用防御：同一通道重复回结果时，计数不超过 total，避免提前汇总
                    results.size >= total
                }
                if (done && aggregated.compareAndSet(false, true)) {
                    // 锁内只做判定与收集，汇总回调在锁外执行，避免回调里再进网络层造成死锁
                    val worst = synchronized(lock) {
                        results.maxByOrNull { severity(it.status) }
                    } ?: noChannelResult()
                    onAllComplete?.invoke(worst)
                }
            }
        }
    }

    /** 无可用通道时的结果（不是成功，避免误标"已送达"） */
    private fun noChannelResult() = WebhookResponseParser.ParseResult(
        WebhookResponseParser.DeliveryStatus.BIZ_FAIL,
        0,
        "未配置 Webhook 通道",
        false
    )

    /**
     * 结果严重度排序：数值越大越严重，「最差优先」汇总时取最大者。
     *
     * ⚠ `PAUSED` 的位置（=1）是**刻意**的，勿随意调整：
     * - `PAUSED` 表示「用户主动暂停推送」，是**用户预期行为**，不是错误——它的
     *   严重度必须低于一切真实失败（BIZ_FAIL 及以上），否则多通道汇总时会被
     *   失败掩盖，历史里显示成「推送失败」，误导用户以为系统出了问题。
     * - 这也是 Dart 侧能把 `PAUSED` 单独归一为 `paused`（而非 failed）并对
     *   **不落送达日志**（`normalized != 'paused'` 才写 webhook_delivery_log）的前提：
     *   一旦 PAUSED 被提升为「最差」，就会把「用户暂停」写进失败日志。
     * - 注意 `PAUSED` 由 `NetworkClient` 在**每个通道**上一致返回（`!force && !isPushActive()`
     *   是全局开关），正常不存在「部分通道 PAUSED、部分通道失败」的混合场景；
     *   保留低严重度是为了在该混合场景下**优先显示真实失败**而非暂停。
     *
     * 断言：`PAUSED < BIZ_FAIL < HTTP_FAIL < RATE_LIMITED < NETWORK_FAIL`
     * （由 `MergeDeliveryResultTest` 的 `pausedIsLessSevereThanEveryRealFailure` /
     *  `pausedMixedWithFailureAggregatesToFailure` 锁定）
     */
    private fun severity(status: WebhookResponseParser.DeliveryStatus): Int =
        when (status) {
            WebhookResponseParser.DeliveryStatus.SUCCESS -> 0
            WebhookResponseParser.DeliveryStatus.PAUSED -> 1
            WebhookResponseParser.DeliveryStatus.BIZ_FAIL -> 2
            WebhookResponseParser.DeliveryStatus.HTTP_FAIL -> 3
            WebhookResponseParser.DeliveryStatus.RATE_LIMITED -> 4
            WebhookResponseParser.DeliveryStatus.NETWORK_FAIL -> 5
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
        force: Boolean = false,
        onResultDone: ((WebhookResponseParser.ParseResult) -> Unit)? = null
    ) {
        // Telegram 必须携带 chat_id（一般来自 URL query）。缺失时提前失败并给出明确原因，
        // 避免发出必然 400 的请求再被记为送达失败。
        val chatId = WebhookPayloadBuilder.extractChatIdFromUrl(cfg.url)
        if (cfg.type == WebhookPayloadBuilder.WebhookType.TELEGRAM && chatId.isEmpty()) {
            Log.e(TAG, "Telegram URL missing chat_id, skip: ${NetworkClient.sanitizeUrlHost(cfg.url)}")
            val earlyFail = WebhookResponseParser.ParseResult(
                WebhookResponseParser.DeliveryStatus.BIZ_FAIL,
                0, "Telegram 链接缺少 chat_id 参数", false
            )
            notifyDeliveryResult(info.id, cfg.type, earlyFail, cfg.url)
            onResultDone?.invoke(earlyFail)
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
                recordId = info.id,
                contentType = "application/x-www-form-urlencoded; charset=utf-8",
                force = force,
                onResult = { result ->
                    Log.d(TAG, "Delivery(ServerChan): ${NetworkClient.sanitizeUrlHost(cfg.url)} → status=${result.status} msg=${result.message}")
                    notifyDeliveryResult(info.id, cfg.type, result, cfg.url)
                    onResultDone?.invoke(result)
                }
            )
            return
        }

        // PushPlus：token 从 URL query 提取注入 body（缺失时提前失败）
        val pushPlusToken = WebhookPayloadBuilder.extractTokenFromUrl(cfg.url)
        if (cfg.type == WebhookPayloadBuilder.WebhookType.PUSH_PLUS && pushPlusToken.isEmpty()) {
            Log.e(TAG, "PushPlus URL missing token, skip: ${NetworkClient.sanitizeUrlHost(cfg.url)}")
            val earlyFail = WebhookResponseParser.ParseResult(
                WebhookResponseParser.DeliveryStatus.BIZ_FAIL,
                0, "PushPlus 链接缺少 token 参数", false
            )
            notifyDeliveryResult(info.id, cfg.type, earlyFail, cfg.url)
            onResultDone?.invoke(earlyFail)
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
                recordId = info.id,
                force = force,
                onResult = { result ->
                    Log.d(TAG, "Delivery(PushPlus): ${NetworkClient.sanitizeUrlHost(cfg.url)} → status=${result.status} msg=${result.message}")
                    notifyDeliveryResult(info.id, cfg.type, result, cfg.url)
                    onResultDone?.invoke(result)
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
                recordId = info.id,
                force = force,
                onResult = { result ->
                    Log.d(TAG, "Delivery: ${NetworkClient.sanitizeUrlHost(cfg.url)} → status=${result.status} msg=${result.message}")
                    notifyDeliveryResult(info.id, cfg.type, result, cfg.url)
                    onResultDone?.invoke(result)
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
                recordId = info.id,
                contentType = contentType,
                force = force,
                onResult = { result ->
                    Log.d(TAG, "Delivery: ${NetworkClient.sanitizeUrlHost(cfg.url)} → status=${result.status} msg=${result.message}")
                    notifyDeliveryResult(info.id, cfg.type, result, cfg.url)
                    onResultDone?.invoke(result)
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
            recordId = info.id,
            onResult = { result ->
                Log.d(TAG, "Delivery: ${NetworkClient.sanitizeUrlHost(cfg.url)} → status=${result.status} msg=${result.message}")
                // 送达结果回传 Flutter 后由 updateDelivery 统一写入 webhook_delivery_log（DB v5）
                notifyDeliveryResult(info.id, cfg.type, result, cfg.url)
                    onResultDone?.invoke(result)
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
        result: WebhookResponseParser.ParseResult,
        channelUrl: String
    ) {
        DeliveryNotifier.notify(context, notificationId, type, result, channelUrl)
    }
}
