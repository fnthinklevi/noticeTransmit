package com.fnthink.notice

import android.content.Context
import android.content.Intent
import android.util.Log
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.util.concurrent.TimeUnit

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

    /** 企业微信自建应用 gettoken 专用客户端（与推送重试客户端隔离，独立超时） */
    private val tokenHttpClient: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(10, TimeUnit.SECONDS)
            .build()
    }

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
            // 旧接口只有 URL：id 用 URL 自己兜底（与 ConfigManager 同一条规则）
            ConfigManager.WebhookChannelConfig(
                url = it, id = it, secret = null,
                type = WebhookPayloadBuilder.detectType(it),
            )
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

    /**
     * 仅推送 webhook（不广播记录）。用于延迟推送到点后的补推：
     * 记录已在通知到达时通过 sendBroadcast 立即写入历史。
     *
     * ⚠ 调用方应是 `NotificationMonitorService.dispatchToChannels`（三族扇出的唯一入口）。
     * 本类原先另有一个 `sendNotification`（广播 + 全通道直推）已无调用者并删除 —— 留着
     * 就是"绕过主备路由"的后门：T12 的角色判定、备用标记都只挂在唯一入口上。
     *
     * @param force 强制发送：为 true 时忽略"推送暂停"开关（历史记录"现在推送"手动补推）
     * @param onAllComplete 全部通道发送结束后的汇总回调（含单通道/无通道两种短路情形）。
     *   供聚合推送（[MergePushManager]）把**真实结果**回传给每个成员记录使用——
     *   该链路只有一条聚合 HTTP 结果，无法逐成员映射，必须靠本回调拿到结果，
     *   否则成员记录的送达状态只能写死成功（历史缺陷，见 MergePushManager 头注释 3）。
     * @param configs 主备路由（T12）筛出的本轮目标；为 null 时退回全部已配置通道
     * @param viaBackup 本轮是**降级后走备用通道**（[ChannelRouting] 的决策）。逐通道送达
     *   结果都要带上它：备用模式是设备级判断，但历史记录是逐条的，标记落在结果上才
     *   不会与结果的时序脱节（Activity 被销毁时由 DeliveryResultStore 兜底补传）。
     */
    fun sendWebhooksOnly(
        info: NotificationInfo,
        force: Boolean = false,
        onAllComplete: ((WebhookResponseParser.ParseResult) -> Unit)? = null,
        configs: List<ConfigManager.WebhookChannelConfig>? = null,
        viaBackup: Boolean = false,
    ) {
        // 主备路由（T12）会传入本次该推的那批；不传 = 全部启用的通道都推
        val targets = configs ?: channelConfigs
        if (targets.isEmpty()) {
            onAllComplete?.invoke(noChannelResult())
            return
        }

        // 单通道（最常见）直接透传，不做计数包装
        if (targets.size == 1) {
            sendToSingleUrl(
                targets[0],
                info,
                force,
                viaBackup = viaBackup,
                onResultDone = onAllComplete,
            )
            return
        }

        // 多通道：等全部通道回结果后按「最差优先」汇总（任一失败即失败）——
        // 宁可多报一次失败，也不要让失败被某个成功通道掩盖。
        //
        // 并发约定（勿改）：结果集合与计数**共用同一把锁**（此前用
        // synchronizedList + 独立 lock 两把锁保护同一批状态，虽逻辑正确但易被后人改错）；
        // 且用 AtomicBoolean 保证汇总回调**至多触发一次**——某通道的 onResult 若因异常
        // 路径被调用两次，计数会提前达到 total，导致在结果不全时就汇总（可能选出非最差者）。
        val total = targets.size
        val results = ArrayList<WebhookResponseParser.ParseResult>(total)
        val lock = Any()
        val aggregated = java.util.concurrent.atomic.AtomicBoolean(false)
        for (cfg in targets) {
            sendToSingleUrl(cfg, info, force, viaBackup = viaBackup) { result ->
                // 可用性记账（T12）：只有真实发送结果会进这张表，测试按钮不记账，
                // 否则"手动能通"会掩盖"实际一直在失败"。
                ChannelAvailability.noteResult(
                    context, "webhook", cfg.id,
                    success = result.status == WebhookResponseParser.DeliveryStatus.SUCCESS,
                )
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

    /**
     * 单通道发送。**函数内不再有任何按平台分支**：签名方式、端点改写、content-type、
     * 必填参数与早失败文案、自定义模板是否生效，全部取自 `ChannelRegistry` 描述符
     * （第 4 步把原来 5 个 `if (cfg.type == ...)` 早退分支消成了表里的数据）。
     *
     * 正文优先级（与重构前逐条等价）：
     *   早失败（缺必填参数/secret）
     *   → 实发正文覆写（Server酱表单 / PushPlus 带 token 正文；这两家重构前是早退分支，
     *     自定义模板对它们本来就不生效）
     *   → 平台模板包装（企微/钉钉/飞书的 text/markdown）
     *   → 通用 webhook 的原样模板 body（含该 body 自己声明的 content-type）
     *   → 描述符 notify 默认正文
     */
    private fun sendToSingleUrl(
        cfg: ConfigManager.WebhookChannelConfig,
        info: NotificationInfo,
        force: Boolean = false,
        viaBackup: Boolean = false,
        onResultDone: ((WebhookResponseParser.ParseResult) -> Unit)? = null
    ) {
        val spec = ChannelRegistry.spec(cfg.type)
        val chatId = WebhookPayloadBuilder.extractChatIdFromUrl(cfg.url)
        val urlToken = WebhookPayloadBuilder.extractTokenFromUrl(cfg.url)
        val template = cfg.messageTemplate ?: ""
        val vars = TemplateEngine.Vars(
            appName = info.appName,
            title = info.title,
            content = info.content,
            subText = info.subText,
            time = info.time,
            deviceName = deviceName,
            packageName = info.packageName,
            notifyType = info.type,
            // F3：聚合推送的 %count% / %titles%
            mergeCount = info.mergeCount,
            mergeTitles = info.mergeTitles
        )

        val plan = ChannelDispatch.plan(
            spec,
            OutboundInput(
                url = cfg.url,
                secret = cfg.secret,
                chatId = chatId,
                urlToken = urlToken,
                overrideBody = {
                    spec.transport.bodyOverride?.invoke(
                        BodyInput(
                            title = info.title,
                            content = info.content,
                            time = info.time,
                            deviceName = deviceName,
                            url = cfg.url
                        )
                    )
                },
                platformBody = {
                    TemplateEngine.buildPlatformPayload(
                        type = cfg.type,
                        format = cfg.messageFormat,
                        template = template,
                        vars = vars,
                        chatId = chatId
                    )
                },
                rawTemplateBody = {
                    TemplateEngine.buildGenericBody(
                        format = cfg.messageFormat,
                        template = template,
                        vars = vars
                    )
                },
                defaultBody = {
                    WebhookPayloadBuilder.buildPayload(
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
                }
            )
        )

        // 必填凭据/参数缺失 → 提前失败并给出明确原因（决策来自描述符，不在此按平台分支）
        val missingReason = plan.earlyFailReason
        if (missingReason != null) {
            Log.e(
                TAG,
                "Skip ${'$'}{cfg.type}: required credential/param missing, " +
                    "url=${'$'}{NetworkClient.sanitizeUrlHost(cfg.url)}"
            )
            val earlyFail = WebhookResponseParser.ParseResult(
                WebhookResponseParser.DeliveryStatus.BIZ_FAIL,
                0, missingReason, false
            )
            notifyDeliveryResult(info.id, cfg.type, earlyFail, cfg.url, viaBackup)
            onResultDone?.invoke(earlyFail)
            return
        }

        // 4) 一次发送出口（重构前是 6 处重复的 sendWithRetry 调用）
        NetworkClient.sendWithRetry(
            url = plan.url,
            payload = plan.body,
            tag = "notification",
            webhookType = cfg.type,
            secret = plan.secretForSigner,
            recordId = info.id,
            contentType = plan.contentType,
            force = force,
            onResult = { result ->
                Log.d(
                    TAG,
                    "Delivery(${cfg.type}): ${NetworkClient.sanitizeUrlHost(cfg.url)} " +
                        "\u2192 status=${result.status} msg=${result.message}"
                )
                // 送达结果回传 Flutter 后由 updateDelivery 统一写入 webhook_delivery_log（DB v5）
                notifyDeliveryResult(info.id, cfg.type, result, cfg.url, viaBackup)
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
        channelUrl: String,
        viaBackup: Boolean
    ) {
        DeliveryNotifier.notify(context, notificationId, type, result, channelUrl, viaBackup)
    }
}
