package com.fnthink.notice

import android.content.Context
import android.util.Log
import kotlinx.coroutines.CoroutineScope

/**
 * 四族通道扇出与主备路由（P1-2）。
 *
 * 从 [NotificationMonitorService] 逐字搬出：暂停分支、`routeChannels` 的主备锁存、
 * `dispatchFnthink` 的 QUEUED/PAUSED、`dispatchEmail` 的重放入队都不改语义。
 * Service 只保留同签名的薄壳 [NotificationMonitorService.dispatchToChannels] 与
 * 7 个调用点，方法频道与行为对外不变。
 */
internal class ChannelFanout(
    private val context: Context,
    private val configManager: ConfigManager,
    private val webhookSender: WebhookSender,
    private val appChannelSender: AppChannelSender,
    private val scope: CoroutineScope,
) {
    private companion object {
        const val TAG = "ChannelFanout"
    }

    /**
     * 四族扇出的**唯一**入口（T12）。原先这段在三处各写一遍、共 7 个调用点，
     * 任何"发送前先做的判断"（推送开关、主备分流）都只能挑几个点加 —— 一旦漏一处，
     * 表现就是"某条路径的通知不受策略约束"。所以先收口，再在收口处加分流。
     *
     * @param alsoBroadcastRecord 是否把这条通知写进历史记录。通知到达的主链路要写；
     *   延迟补推 / 聚合 flush / 手动「现在推送」的记录在到达时已经写过，再播一次就多一条历史。
     * @param force 忽略「推送暂停」开关（只给手动补推用）。
     * @param onlySlugs 手动补推的**族范围**（T133 片4，判据见 [RepushScope]）：null = 全部启用
     *   通道（"刚落库就要发出去"那一条欠的就是全部），非 null = 只发列出来的那几族，
     *   其余通道**这一轮不参与**。⚠ 范围不改变主备裁决的输入 —— 谁被选中仍由
     *   [ChannelRouting] 按全部候选算，范围只在扇出口收窄，否则会写出
     *   「按族筛它 ⇒ 主通道被筛没了就判成降级」这种第二套路由。
     * @param onWebhooksComplete webhook 全部通道结束后的汇总回调，第二个参数是**本轮是否
     *   降级走了备用通道**（聚合推送要用真实结果逐成员回写，见 [MergePushManager] 头注释 3，
     *   备用标记同理 —— 成员记录也得知道自己是通过备用通道补发的）。
     */
    /** Service 侧唯一入口（P1-2）：实现体仍叫 [dispatchToChannels]，守卫的旧锚点不用改。 */
    fun dispatch(
        info: NotificationInfo,
        alsoBroadcastRecord: Boolean = true,
        force: Boolean = false,
        onlySlugs: List<String>? = null,
        onWebhooksComplete: ((WebhookResponseParser.ParseResult, Boolean) -> Unit)? = null,
    ) = dispatchToChannels(info, alsoBroadcastRecord, force, onlySlugs, onWebhooksComplete)

    private fun dispatchToChannels(
        info: NotificationInfo,
        alsoBroadcastRecord: Boolean = true,
        force: Boolean = false,
        onlySlugs: List<String>? = null,
        onWebhooksComplete: ((WebhookResponseParser.ParseResult, Boolean) -> Unit)? = null,
    ) {
        // T178：暂停不是一次"发送失败"，也不该参与主备裁决。
        // 旧顺序是先 routeChannels（其输入含连续失败计数，且可能 applyDecision 锁存
        // backup_engaged）再让每个通道各自回 PAUSED —— 用户暂停几次推送，主备关系就被
        // 永久改了，而界面上只会说"已暂停"。这里先分流：暂停时**不路由**，四族照配置
        // 各回一条 PAUSED，让历史每一格都有终态。
        if (!force && !PushToggleManager.isPushActive()) {
            if (alsoBroadcastRecord) webhookSender.sendBroadcast(info)
            webhookSender.sendWebhooksOnly(
                info,
                force = false,
                onAllComplete = null,
                configs = configManager.getWebhookChannelConfigs(),
                viaBackup = false,
            )
            appChannelSender.sendOnly(
                info,
                force = false,
                configs = configManager.getAppChannelConfigs(),
                viaBackup = false,
            )
            dispatchEmail(
                info,
                force = false,
                configs = EmailManager.getEnabledConfigs(context),
                viaBackup = false,
            )
            dispatchFnthink(
                info,
                force = false,
                configs = configManager.getFnthinkChannelConfigs(),
                viaBackup = false,
            )
            return
        }
        val routed = routeChannels(onlySlugs)
        // 「当日已推送」这一句的**唯一**累加点（T131）。原先它长在五个调用点上，每个都是
        // `dispatchToChannels(info); pushCount++` —— 于是"暂停闸把这一发拦住了"与"这一发
        // 推出去了"在计数上长得一模一样，栏里的数字只能一直涨。
        // ⚠ 判据放在**扇出之前**、按轮记一次：暂停闸住在每个通道里（NetworkClient / 幻念 /
        //   邮件各一处 `!force && !isPushActive()`），等回执再判就要把四族的结果汇总成第三个
        //   口径；而"这一发到底推没推"只由开关与目标数决定，与哪个通道回了什么无关。
        //   聚合组走同一发扇出 ⇒ 按组记一次，不随成员数放大。
        if (DailyPushCounter.countsAsPush(
                PushToggleManager.isPushActive(),
                force,
                routed.webhooks.size + routed.apps.size +
                    routed.emails.size + routed.fnthinks.size,
            )
        ) {
            DailyPushCounter.record(context)
        }
        // 降级标记必须**逐结果**传给三个发送器，不能只在服务里记一笔：
        // 一次扇出的结果会经广播/持久化队列异步落到不同记录（如聚合成员），
        // 事后已经没有「哪一轮」的上下文可对。
        val webhookCallback = onWebhooksComplete?.let { outer ->
            { r: WebhookResponseParser.ParseResult -> outer(r, routed.viaBackup) }
        }

        if (alsoBroadcastRecord) {
            // 只有这一条路知道本轮真正路由到哪些通道；历史快照必须按这一份建，
            // 否则没被选中的备用通道会在历史里永远停在「在途」。
            webhookSender.sendBroadcast(info, routedChannels = routed.deliveryTypes)
        }
        webhookSender.sendWebhooksOnly(
            info,
            force = force,
            onAllComplete = webhookCallback,
            configs = routed.webhooks,
            viaBackup = routed.viaBackup,
        )
        appChannelSender.sendOnly(
            info,
            force = force,
            configs = routed.apps,
            viaBackup = routed.viaBackup,
        )
        dispatchEmail(
            info,
            force = force,
            configs = routed.emails,
            viaBackup = routed.viaBackup,
        )
        dispatchFnthink(
            info,
            force = force,
            configs = routed.fnthinks,
            viaBackup = routed.viaBackup,
        )
    }

    /** 一次扇出对应的四族目标集合（路由后的结果，可能比配置里少） */
    private class RoutedChannels(
        val webhooks: List<ConfigManager.WebhookChannelConfig>,
        val apps: List<AppChannelConfig>,
        val emails: List<EmailSender.EmailConfig>,
        val fnthinks: List<FnthinkChannelConfig>,
        /** 本轮为「降级走备用」：直接取 [ChannelRouting.Decision.engagedBackup]，不自行推断 */
        val viaBackup: Boolean,
    ) {
        /**
         * 本轮真正交给发送器的通道类型。历史广播带这一份，Dart 才不会把没被选中的
         * 备用通道也预置成「在途」。线值与送达回传同源，见 [routedDeliveryTypes]。
         */
        val deliveryTypes: List<String> = routedDeliveryTypes(
            webhooks.map { it.type.name },
            apps.map { it.type },
            emails.isNotEmpty(),
            fnthinks.isNotEmpty(),
        )
    }

    /**
     * 主备路由（T12）：四族候选合成**一次**决策。
     *
     * 分开按族决策会出现「webhook 已经走备用、邮件还在推主通道」的半吊子状态 ——
     * 而「主通道是否全不可用」本来就是设备级判断。
     *
     * 每次现读配置与健康记录（不在进程内缓存）：角色、健康度、锁存都会变，
     * 缓存就得再定一条「谁负责让它失效」的契约，代价大于每次解析几个通道。
     *
     * @param onlySlugs 扇出范围（T133 片4）。**先路由、后收窄**：裁决的输入始终是全部候选，
     *   范围只决定"这一发发给谁"。四族都要过 [RepushScope]，漏一族的表现就是
     *   「重推一条只有邮件失败的记录，却把钉钉又发一遍」—— 与本片要修的那条同一个形状。
     */
    private fun routeChannels(onlySlugs: List<String>? = null): RoutedChannels {
        val webhooks = configManager.getWebhookChannelConfigs()
        val apps = configManager.getAppChannelConfigs()
        val emails = EmailManager.getEnabledConfigs(context)
        val fnthinks = configManager.getFnthinkChannelConfigs()
        val now = System.currentTimeMillis()

        fun read(family: String, id: String): ChannelAvailability.Read =
            ChannelAvailability.observe(context, family, id, now)

        val members = ArrayList<ChannelRouting.Member>()
        webhooks.forEach {
            val r = read("webhook", it.id)
            members.add(ChannelRouting.Member("webhook:" + it.id, it.role, r.available, r.recovery))
        }
        apps.forEach {
            val r = read("app", it.id)
            members.add(ChannelRouting.Member("app:" + it.id, it.role, r.available, r.recovery))
        }
        emails.forEach {
            val r = read("email", it.id)
            members.add(ChannelRouting.Member("email:" + it.id, it.role, r.available, r.recovery))
        }
        // 幻念族（T94 片4）同一次决策，不另判一次：另判就会出现"邮件走备用、幻念还在推主通道"
        // 的半吊子状态。可用性这一档仍**硬编 true**（T132 记的第③条：这一族的探测走 Dart 自己
        // 那条链，原生侧还没有把它接进 available 的判据）；但**切回证据照实取**——T106 片③
        // 之后这一族确实有探测记录（`probeFnthinkChannels` 写同一份健康单点），
        // 攒够的那一份该说得出"这条主通道可以切回去了"。
        fnthinks.forEach {
            val r = read("fnthink", it.id)
            members.add(ChannelRouting.Member("fnthink:" + it.id, it.role, true, r.recovery))
        }

        val engaged = BackupModeStore.isEngaged(context)
        val decision = ChannelRouting.route(
            members,
            engaged,
            autoBackup = BackupModeStore.autoBackupEnabled(context),
            engagedAtMs = BackupModeStore.engagedAt(context),
        )
        // 锁存的写口只有一处，且两条链共用（T135）：降级与自动切回都在那里落盘
        BackupModeStore.applyDecision(context, engaged, decision)

        val want = decision.keys.toHashSet()
        // 扇出范围（片4）：四族各自过一遍。slug 的取法与**送达回传用的那一段**同源 ——
        // webhook 取 [ChannelSpec.slug]（回传是 `type.name`，Dart 侧 lowercase 归一后即这一串），
        // 自建应用取 `cfg.type`（本就是 `wecom_app` 这一形态），邮件/幻念各只有一种 slug
        // （回传侧写的就是 "EMAIL" / "fnthink"，见 dispatchEmail 与 dispatchFnthinkHook）。
        fun inScope(slug: String) = RepushScope.accepts(onlySlugs, slug)
        return RoutedChannels(
            webhooks.filter {
                ("webhook:" + it.id) in want && inScope(ChannelRegistry.spec(it.type).slug)
            },
            apps.filter { ("app:" + it.id) in want && inScope(it.type.lowercase()) },
            emails.filter { ("email:" + it.id) in want && inScope("email") },
            fnthinks.filter { ("fnthink:" + it.id) in want && inScope("fnthink") },
            // T132：标记取 `viaBackup`（本轮不是"只推可用主"），不再取锁存位 `engagedBackup` ——
            // 后者只答"要不要从此以备用为准"，兜底那一档推了全部候选却不该锁存。
            viaBackup = decision.viaBackup,
        )
    }

    /**
     * 幻念族的出站口（T94 片4）。
     *
     * **两种目标走两条路，这是刻意的**：目标是一个 https 地址时，原生这一侧做的就是一条
     * 普通 webhook POST —— 走 [NetworkClient] 才有一整套现成的东西（重试、健康度记账、
     * 送达回执、推送暂停），在 Dart 另写一份只会得到一个"能发出去但什么都不记"的次品。
     * 目标是一台绑定设备时才需要签名私钥（AndroidKeyStore）与载荷/nonce（全在 Dart），
     * 于是那一半只能落进 [FnthinkFanoutQueue]，由 [FnthinkFanoutWorker] 起后台引擎去发。
     *
     * 推送暂停在这里同样生效，但**不回传 paused 结果**：幻念这一族的结果由发送那一侧逐条回执，
     * 这里还没拿到任何送达事实，回传一个"暂停"就是凭空造一条送达记录。
     */
    private fun dispatchFnthink(
        info: NotificationInfo,
        force: Boolean = false,
        configs: List<FnthinkChannelConfig>? = null,
        viaBackup: Boolean = false,
    ) {
        try {
            val selected = configs ?: configManager.getFnthinkChannelConfigs()
            if (selected.isEmpty()) return
            if (!force && !PushToggleManager.isPushActive()) {
                Log.d(TAG, "Fnthink fanout skipped (push paused): ${info.appName}")
                // T138 ①：幻念族也要落一个**可判的档**。旧写法静默 return，那一格永远停在
                // 「推送中」，直到 T112 那道 90 秒上限来收场 —— 界面说的全是假话。
                // "结果由发送侧逐条回执"管的是**送达事实**（成功/失败）；"暂停没发"不是
                // 送达事实，也不写送达日志（Dart 侧 `normalized == paused` 不落 log 的那份
                // 契约）—— 它只让历史那一格说"暂停未发送"这句真话。与邮件同形：
                // paused 分支**不带**备用标记，这条消息根本没投递出去。
                val paused = WebhookResponseParser.ParseResult(
                    WebhookResponseParser.DeliveryStatus.PAUSED,
                    0, "Push paused (skipped)", false
                )
                DeliveryNotifier.notify(context, info.id, "fnthink", paused)
                return
            }
            val hooks = selected.filter { it.isWebhook }
            val devices = selected.filterNot { it.isWebhook }
            hooks.forEach { dispatchFnthinkHook(info, it, force, viaBackup) }
            if (devices.isNotEmpty()) {
                val queue = FnthinkFanoutQueue(context)
                val result = queue.enqueue(info, devices, viaBackup)
                // T175 ①：入队即回 `queued`，不等后台那一轮的回执。旧形状下这一格
                // 要等引擎起起来、跑完发送才有人写；锁屏/被杀时那一轮可能一直不跑，
                // 历史就停在「发送中」。`queued` 说的是本机已经交出去了，球在服务端/队列。
                if (result.dropped.none { it.id == info.id }) {
                    DeliveryNotifier.notify(
                        context,
                        info.id,
                        "fnthink",
                        WebhookResponseParser.ParseResult(
                            WebhookResponseParser.DeliveryStatus.QUEUED,
                            0,
                            "queued: ${devices.size} target(s)",
                            false,
                        ),
                    )
                    DiagLog.w(
                        TAG,
                        "fnthink-queued id=${info.id} channelKey=chan:fnthink " +
                            "targets=${devices.size} queue=${queue.pendingCount()}",
                    )
                }
                // T147③：待发队列丢的是**真丢**（与延迟队列"挤出=补推"不同），
                // 被挤掉那几条的通知已经在历史里，必须逐条回传送达说法，否则永远停在「发送中」。
                for (dropped in result.dropped) {
                    DeliveryNotifier.notify(
                        context,
                        dropped.id,
                        "fnthink",
                        WebhookResponseParser.ParseResult(
                            WebhookResponseParser.DeliveryStatus.BIZ_FAIL,
                            0,
                            I18n.fnthinkFanoutQueueDroppedReason(result.dropped.size),
                            false,
                        ),
                    )
                    DiagLog.w(TAG, "幻念待发队列已满，最旧一条未转发，已回传未送达: ${dropped.appName}")
                }
                // T197 片3：常驻引擎在服务里就直接排空（通知到达即发，不再等 WorkManager
                // 的作业调度/60 秒闹钟）；引擎不可用才退回 WorkManager 那枚 one-shot。
                FnthinkFanoutNow.request(context)
                Log.d(
                    TAG,
                    "Fnthink fanout queued: ${devices.size} device targets, dropped ${result.dropped.size}",
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "幻念分发异常: ${e.message}", e)
        }
    }

    /**
     * 幻念通道的 webhook 目标：一个 https 地址 + 一个不带签名的通用正文。
     *
     * 单通道异常不许影响别的通道（同 [AppChannelSender.sendSafely] 的理由）：
     * 「一个通道有问题 = 全部通道失效」在多通道场景下不可接受。
     */
    private fun dispatchFnthinkHook(
        info: NotificationInfo,
        cfg: FnthinkChannelConfig,
        force: Boolean,
        viaBackup: Boolean,
    ) {
        try {
            // T112 ②：这里原来发的是 `buildTextBody(...)` 的**纯文本多行正文**，而
            // `NetworkClient.sendWithRetry` 的 contentType 默认就是 `application/json; charset=utf-8`
            // ⇒ 服务端 `express.json` 抛 entity.parse.failed，被 bodylimit 按契约回 400 + 空 body `{}`，
            // 界面只能说「HTTP 400：{}」。改法是**换载荷**不是换 content-type：端点只解析 JSON 与 query，
            // 发 text/plain 一条都进不去。载荷构造与通用 webhook 走同一位作者（buildPayload→描述符表），
            // 于是"探测能过、真发不过"这种两半各造一条的形状没了。
            val payload = WebhookPayloadBuilder.buildPayload(
                type = WebhookPayloadBuilder.WebhookType.GENERIC,
                title = info.title,
                content = info.content,
                appName = info.appName,
                time = info.time,
                deviceName = info.deviceName.ifEmpty { PrefsHelper.deviceName },
                notifyType = info.type,
            )
            NetworkClient.sendWithRetry(
                url = cfg.target,
                payload = payload,
                tag = "notification",
                webhookType = WebhookPayloadBuilder.WebhookType.GENERIC,
                secret = null,
                recordId = info.id,
                force = force,
                onResult = { result ->
                    Log.d(TAG, "Delivery(fnthink hook ${cfg.id}) ${NetworkClient.sanitizeUrlHost(cfg.target)} → status=${result.status}")
                    ChannelAvailability.noteResult(
                        context, "fnthink", cfg.id,
                        status = result.status,
                    )
                    // 送达键用族 slug（`chan:fnthink`，T60 已占）：`channelKey` 会在第一个
                    // 冒号处截断，带通道 id 的写法会读成"未知通道"回退成 generic。
                    DeliveryNotifier.notify(context, info.id, "fnthink", result, cfg.target, viaBackup)
                },
            )
        } catch (e: Exception) {
            Log.e(TAG, "幻念 webhook 通道发送异常 id=${cfg.id}", e)
        }
    }

    private fun dispatchEmail(
        info: NotificationInfo,
        force: Boolean = false,
        configs: List<EmailSender.EmailConfig>? = null,
        viaBackup: Boolean = false,
    ) {
        try {
            // 路由后可能为空（本轮不该推邮件）：与「没配邮件通道」走同一条早退路径。
            // 局部量另起名：与同名参数在嵌套作用域里重名会触发 name-shadowed 警告。
            val selected = configs ?: EmailManager.getEnabledConfigs(context)
            if (selected.isEmpty()) return

            // 推送暂停：邮件同样不发送，回传 paused 状态（与 webhook 行为一致）。
            // paused 分支**不带**备用标记：这条消息根本没投递出去，标"走了备用"只会误导。
            if (!force && !PushToggleManager.isPushActive()) {
                val paused = WebhookResponseParser.ParseResult(
                    WebhookResponseParser.DeliveryStatus.PAUSED,
                    0, "Push paused (skipped)", false
                )
                DeliveryNotifier.notify(context, info.id, "EMAIL", paused)
                return
            }

            // T243：回调带渲染成品（subject/body）与 retryable——瞬时类失败入邮件自动
            // 重放队列（配置类失败不入：重放无意义且会拿账号撞厂商认证封禁）；入队成功
            // 回传 QUEUED（非终态，重放成功后翻绿），入队失败回传原失败结果保持诚实。
            EmailSender.sendNotification(selected, info, scope) { config, subject, body, success, msg, retryable ->
                val result = when {
                    success -> WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.SUCCESS, 0, msg, false
                    )
                    else -> {
                        val enqueued = retryable && EmailRetryQueue.enqueue(
                            configId = config.id,
                            subject = subject,
                            body = body,
                            recordId = info.id,
                        )
                        if (enqueued) {
                            WebhookResponseParser.ParseResult(
                                WebhookResponseParser.DeliveryStatus.QUEUED, 0,
                                I18n.msgf("err.queuedRetry", msg), false
                            )
                        } else {
                            WebhookResponseParser.ParseResult(
                                WebhookResponseParser.DeliveryStatus.BIZ_FAIL, 0, msg, false
                            )
                        }
                    }
                }
                DeliveryNotifier.notify(context, info.id, "EMAIL", result, viaBackup = viaBackup)
            }
        } catch (e: Exception) {
            Log.e(TAG, "邮件分发异常: ${e.message}", e)
        }
    }
}
