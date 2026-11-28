package com.fnthink.notice

import android.content.Context
import android.os.Build
import android.service.notification.StatusBarNotification
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Collections
import java.util.Date
import java.util.Locale

class NotificationProcessor(private val context: Context) {
    companion object {
        private const val TAG = "NotificationProcessor"
        private const val MAX_NOTIFIED_KEYS = 200
    }

    private val notifiedKeys = Collections.synchronizedSet(LinkedHashSet<String>())

    // N9：短信兜底分发的作用域。原实现每条短信通知都新建
    // `CoroutineScope(Dispatchers.IO)`（无人管理、不受服务生命周期约束，
    // 进程被回收即丢）——收敛为类级作用域（随 NotificationProcessor 实例存在）。
    private val smsFallbackScope = kotlinx.coroutines.CoroutineScope(
        kotlinx.coroutines.Dispatchers.IO + kotlinx.coroutines.SupervisorJob()
    )

    fun processNotification(sbn: StatusBarNotification): NotificationInfo? {
        val notification = sbn.notification ?: return null
        val packageName = sbn.packageName
        val notificationId = sbn.id

        if (packageName == context.packageName) return null

        // P2-4：识别短信/电话应用不再按"包名里含 sms/dialer"猜（那会把
        // com.example.smsbackup / com.acme.dialer 这类普通应用整包吞掉）。
        // 判据只在 [NotificationSourceClassifier] 一处：系统默认短信/拨号器 + 已知
        // 系统组件前缀，并要求通知类别与用途一致（短信包发的"备份完成"照常转发）。
        val category = notification.category
        when (
            NotificationSourceClassifier.classify(
                packageName = packageName,
                category = category,
                defaultSmsPackage = platformDefaultSmsPackage(),
                defaultDialerPackage = platformDefaultDialerPackage(),
            )
        ) {
            // 电话应用由 PhoneCallReceiver 独占处理（携带 SIM 卡信息），通知栏监听跳过，
            // 避免同一事件产生两条记录（一条有 SIM、一条无 SIM）。
            NotificationSourceClassifier.Kind.CALL -> return null
            NotificationSourceClassifier.Kind.SMS -> {
                // 短信应用通知：第三兜底链路（source=notification）。
                // 系统「验证码安全保护」（MIUI/HyperOS 等默认开启）会拦截 SMS_RECEIVED 广播、
                // 并对第三方应用隐藏短信库内容，使 SmsReceiver / SmsObserver 双链路同时失效；
                // 通知栏不受影响（输入法读验证码同款方案）。统一走 SmsDispatcher 指纹去重：
                // 双链路已处理则丢弃，未处理（保护开启）则补推，不产生重复记录。
                if (dispatchSmsFromNotification(sbn)) return null
                // P2-4：内容不足（无发送者/无正文/锁屏掩码）时**不再静默丢弃**，
                // 落到普通通知路径：至少留下历史与诊断，用户能看到"有一条短信来了"。
                Log.d(TAG, "短信通知内容不足，回落到普通通知路径：$packageName")
            }
            NotificationSourceClassifier.Kind.OTHER -> Unit
        }

        val isOngoing = (notification.flags and android.app.Notification.FLAG_ONGOING_EVENT) != 0
        val tag = sbn.tag
        // 去重键必须包含 tag：同一应用可能用相同通知 id + 不同 tag 发多条常驻通知，
        // 仅用 包名:id 会把第二条误判为重复而漏读。
        val dedupKey = if (tag.isNullOrEmpty()) {
            "$packageName:$notificationId"
        } else {
            "$packageName:$tag:$notificationId"
        }

        if (isOngoing && notifiedKeys.contains(dedupKey)) {
            return null
        }

        val extras = notification.extras
        val title = extras.getCharSequence(android.app.Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(android.app.Notification.EXTRA_TEXT)?.toString() ?: ""
        val bigText = extras.getCharSequence(android.app.Notification.EXTRA_BIG_TEXT)?.toString() ?: ""
        val subText = extras.getCharSequence(android.app.Notification.EXTRA_SUB_TEXT)?.toString() ?: ""
        // P2-3：group summary 的正文常常只写在 EXTRA_SUMMARY_TEXT（"3 条新消息"），
        // 旧兜底链没有它 ⇒ 这类通知落到"标题+正文都空"被丢弃。
        val summaryText =
            extras.getCharSequence(android.app.Notification.EXTRA_SUMMARY_TEXT)?.toString() ?: ""
        val messagingContent = extractMessagingContent(extras)
        val textLines = extras.getCharSequenceArray(android.app.Notification.EXTRA_TEXT_LINES)
            ?.filterNotNull()
            ?.joinToString("\n") ?: ""
        val ticker = notification.tickerText?.toString() ?: ""
        val postTime = sbn.postTime

        // 内容兜底链：大文本 → 正文 → MessagingStyle 消息 → 多行文本 → group summary
        // → ticker → 副标题 → RemoteViews 的 TextView 文本（有限提取，最后一道）。
        // 会话类通知（微信/QQ/Telegram 等）正文可能只存在于 MessagingStyle.messages 中，
        // 仅读 EXTRA_TEXT 会导致"标题和正文都为空被跳过"的漏通知。
        var content = bigText
            .ifEmpty { text }
            .ifEmpty { messagingContent }
            .ifEmpty { textLines }
            .ifEmpty { summaryText }
            .ifEmpty { ticker }
            .ifEmpty { subText }
            .ifEmpty { extractRemoteViewsText(notification) }
        // B3 星号兜底：锁屏脱敏时正文显示为 ******，直接转发无价值，
        // 改为发送提示（验证码等敏感内容需解锁后查看）
        if (isMaskedContent(content)) {
            // 文案唯一作者在 I18n：英文系统下不能弹出一句中文（P0：原生国际化缺口）。
            content = I18n.notificationContentMasked(content.trim())
            Log.d(TAG, "Notification content masked, replaced with hint: $packageName")
        }
        if (title.isEmpty() && content.isEmpty()) {
            // P2-3：走到这里说明连 RemoteViews 都没提取到文本。留一条**不含正文**的
            // 诊断（只报包名与候选来源是否在场），否则用户只看到"这条没转发"，
            // 没有任何地方能回答"它到底有没有内容、卡在哪一步"。
            Log.d(
                TAG,
                "无可用文本，按空内容跳过：$packageName " +
                    "(summary=${summaryText.isNotEmpty()}, " +
                    "lines=${textLines.isNotEmpty()}, " +
                    "views=${hasRemoteViews(notification)})",
            )
            return null
        }

        // P0：去重键必须在**确认这条真的要转发**之后才记。
        // 旧顺序是先记 key 再抽正文：首条纯进度条 / 纯 Custom RemoteViews（标题与正文都空）
        // 会在这里 return null，却把 key 永久留在 notifiedKeys 里 —— 同一个 key 的后续更新
        // 全被当重复拦掉，直到通知被移除或进程重启。这就是"常驻通知只来第一条"的锁死。
        if (isOngoing) {
            notifiedKeys.remove(dedupKey)
            notifiedKeys.add(dedupKey)
            if (notifiedKeys.size > MAX_NOTIFIED_KEYS) {
                synchronized(notifiedKeys) {
                    val toRemove = notifiedKeys.size - MAX_NOTIFIED_KEYS + 50
                    val list = ArrayList(notifiedKeys)
                    for (i in 0 until toRemove) {
                        notifiedKeys.remove(list[i])
                    }
                }
            }
        }

        val baseAppName = getAppNameByPackage(packageName)
        val isPushService = isVendorPushService(packageName)
        val resolvedAppName = if (isPushService) {
            resolveRealAppName(sbn, baseAppName, title, subText)
        } else {
            baseAppName
        }
        val appName = resolvedAppName
        val notifyType = detectNotificationType(packageName, appName, title, content)
        val timeStr = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
            .format(Date(postTime))

        return NotificationInfo(
            // 记录 id = dedupKey + postTime。⚠ 只用 dedupKey（包名+tag+通知id）不唯一：
            // 微信等会话应用连发消息会**复用同一个 StatusBarNotification**（同 tag + sbn.id，
            // 每条消息是一次 repost），dedupKey 完全相同 → ① DB 主键 ConflictAlgorithm.replace
            // 静默覆盖，历史只剩最后一条；② 聚合推送的成员逐条回传（DeliveryNotifier）按 id
            // 找记录时只能命中一条，其余成员永远停留「发送中」。
            // postTime 在每次 repost 时由系统更新，拼上它即可让每条消息独立成行。
            id = "$dedupKey:$postTime",
            title = title,
            content = content,
            subText = subText,
            packageName = packageName,
            appName = appName,
            postTime = postTime,
            time = timeStr,
            type = notifyType,
            deviceName = "",
            priority = extractPriority(notification),
            // T186 片1：设备态条件按"到达那一刻"的读数求值。两枚读数**各自容错**：
            // 读不到就留空串 ⇒ 那一型条件不匹配，而不是把未知伪装成某一档；
            // 也不许让一次 sticky／Connectivity 异常把整条通知的转发链路带崩
            // （这条函数跑在通知监听的 IO 协程里，抛出去就是这一发通知整个丢掉）。
            chargingState = try {
                DeviceSnapshot.readChargingState(context)
            } catch (e: Exception) {
                ""
            },
            networkType = try {
                DeviceSnapshot.readNetworkType(context) ?: ""
            } catch (e: Exception) {
                ""
            },
            // T186 片1：模板变量 %battery% 的读数，与上面两枚同一时刻取；
            // 读不到 = null ⇒ 渲染空串（不伪装成 0%）。
            batteryPercent = try {
                DeviceSnapshot.readBatteryPercent(context)
            } catch (e: Exception) {
                null
            }
        )
    }

    /**
     * B3 星号兜底：检测正文是否被锁屏脱敏（如验证码显示为 ******）。
     * 判定：长度 ≥ 4 且全部由掩码字符（* · ● • ﹡ × ○）+ 空格组成，不含数字/字母。
     */
    private fun isMaskedContent(content: String): Boolean {
        val trimmed = content.trim()
        if (trimmed.length < 4) return false
        val maskedChars = setOf('*', '·', '●', '•', '﹡', '×', '○')
        for (c in trimmed) {
            if (c != ' ' && c !in maskedChars) return false
        }
        return true
    }

    /**
     * 短信应用通知 → SmsDispatcher 兜底分发。
     *
     * 通知格式：标题=发送方（可能是联系人名而非号码），正文=短信内容（BIG_TEXT 为展开全文）。
     * 正文优先取 BIG_TEXT（缩略 TEXT 可能截断），其次 MessagingStyle 聚合内容。
     *
     * 延迟 2 秒再入队：广播（SmsReceiver）与短信库观察（SmsObserver）链路几乎同时触发，
     * 让它们先把「发送方+正文」指纹写入 SmsDispatcher，本链路到达时即可被判重丢弃；
     * 仅当双链路被系统保护切断时，本链路才实际补推。
     *
     * 锁屏脱敏（正文全为掩码字符）时跳过：完整内容应由广播/观察链路提供，
     * 掩码版本只会产生一条无验证码价值的重复记录。
     *
     * 注意：本链路无 SIM 卡信息（simInfo=null），记录 id 基于通知 postTime，
     * 与广播链路的 SMSC 时间戳不同源——跨链路去重依赖 SmsDispatcher 的正文指纹。
     *
     * @return true＝已交给 SmsDispatcher（2 秒后入队去重）；false＝内容不足或掩码，
     *   调用方应回落到普通通知路径（P2-4：此前这里是静默 return，短信包里那条
     *   无正文的通知既不入历史也不转发）。
     */
    private fun dispatchSmsFromNotification(sbn: StatusBarNotification): Boolean {
        try {
            val extras = sbn.notification?.extras ?: return false
            val sender = extras.getCharSequence(android.app.Notification.EXTRA_TITLE)
                ?.toString()?.trim().orEmpty()
            val text = extras.getCharSequence(android.app.Notification.EXTRA_TEXT)
                ?.toString()?.trim().orEmpty()
            val bigText = extras.getCharSequence(android.app.Notification.EXTRA_BIG_TEXT)
                ?.toString()?.trim().orEmpty()
            val messaging = extractMessagingContent(extras).trim()
            val body = when {
                bigText.isNotEmpty() -> bigText
                messaging.isNotEmpty() -> messaging
                else -> text
            }
            if (sender.isEmpty() || body.isEmpty()) return false
            if (isMaskedContent(body)) {
                Log.d(TAG, "短信通知正文为锁屏掩码，回落到普通通知路径: $sender")
                return false
            }
            val postTime = sbn.postTime
            smsFallbackScope.launch {
                delay(2_000L)
                SmsDispatcher.handle(
                    context = context,
                    sender = sender,
                    message = body,
                    timestamp = postTime,
                    simInfo = null,
                    source = "notification"
                )
            }
            return true
        } catch (e: Exception) {
            Log.w(TAG, "短信通知栏兜底分发失败: ${e.message}")
            return false
        }
    }

    /**
     * 优先级分级：0=低 1=中 2=高。
     * Android O+ 上系统会按渠道重要性维护 notification.priority 字段
     * （IMPORTANCE_HIGH→MAX、DEFAULT→DEFAULT、LOW→LOW、MIN→MIN），因此直接读取即可，
     * 无需再自行查询渠道重要性。
     */
    // 读「收到的通知」的 priority 没有替代 API：渠道重要性只对**自己发的**通知生效，
    // 这里量的是别人发的。API 26 把它标弃用，但没有等价读法 ⇒ 保留并 suppress。
    @Suppress("DEPRECATION")
    private fun extractPriority(notification: android.app.Notification): Int {
        val p = notification.priority
        return when {
            p >= android.app.Notification.PRIORITY_HIGH -> 2
            p <= android.app.Notification.PRIORITY_LOW -> 0
            else -> 1
        }
    }

    fun removeNotification(sbn: StatusBarNotification) {
        val tag = sbn.tag
        val dedupKey = if (tag.isNullOrEmpty()) {
            "${sbn.packageName}:${sbn.id}"
        } else {
            "${sbn.packageName}:$tag:${sbn.id}"
        }
        notifiedKeys.remove(dedupKey)
    }

    /**
     * 提取会话类通知（MessagingStyle）的正文。
     *
     * 微信/QQ/Telegram 等聊天应用的通知正文可能只写在 MessagingStyle.messages 中，
     * EXTRA_TEXT / EXTRA_BIG_TEXT 可能为空。**P2-2 起取全量而非只取最新一条**：
     * 合并通知里前面几条同样是被用户看见的内容，只取最后一条等于把前面几条丢掉
     * （审计 2026-11-27「内容级遗漏」）。拼接/去重/截断的唯一作者是 [MessagingDigest]。
     *
     * 部分 ROM 对 MessagingStyle 的序列化不兼容，读取失败时静默忽略走其他兜底。
     */
    @Suppress("DEPRECATION")
    private fun extractMessagingContent(extras: android.os.Bundle): String {
        return try {
            val entries = ArrayList<MessagingDigest.Entry>()
            val style = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                // EXTRA_MESSAGING_STYLE 为隐藏 API，编译期不可引用，用字符串常量
                extras.getParcelable(
                    "android.messagingStyle",
                    android.app.Notification.MessagingStyle::class.java
                )
            } else {
                extras.getParcelable("android.messagingStyle")
            }
            if (style != null) {
                for (message in style.messages) {
                    entries.add(
                        MessagingDigest.Entry(
                            sender = messagingSender(message),
                            text = message.text?.toString().orEmpty(),
                        ),
                    )
                }
            }
            // 兜底：EXTRA_MESSAGES 数组（部分 ROM 只写该字段，或 style 里是空的）。
            if (entries.none { it.text.isNotBlank() }) {
                val messageList = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    extras.getParcelableArrayList(
                        android.app.Notification.EXTRA_MESSAGES,
                        android.app.Notification.MessagingStyle.Message::class.java
                    )
                } else {
                    extras.getParcelableArrayList<android.os.Parcelable>(
                        android.app.Notification.EXTRA_MESSAGES
                    )
                }
                entries.clear()
                if (messageList != null) {
                    for (item in messageList) {
                        val msg = item as? android.app.Notification.MessagingStyle.Message
                            ?: continue
                        entries.add(
                            MessagingDigest.Entry(
                                sender = messagingSender(msg),
                                text = msg.text?.toString().orEmpty(),
                            ),
                        )
                    }
                }
            }
            if (entries.isEmpty()) return ""
            MessagingDigest.format(entries) { count ->
                I18n.msgf("notif.messagingOmitted", count)
            }
        } catch (e: Exception) {
            ""
        }
    }

    /**
     * MessagingStyle 消息的发送者名。API 28 起以 [Person] 形式保存（`senderPerson`），
     * 旧的 `sender` 仍可读但已弃用；两个都读不到就留空串，由拼接侧只输出正文。
     */
    @Suppress("DEPRECATION")
    private fun messagingSender(
        message: android.app.Notification.MessagingStyle.Message
    ): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            message.senderPerson?.name?.toString()?.let { if (it.isNotBlank()) return it }
        }
        return message.sender?.toString().orEmpty()
    }

    /** 这条通知有没有可尝试提取的 RemoteViews（只看存在性，不改内容）。 */
    @Suppress("DEPRECATION")
    private fun hasRemoteViews(notification: android.app.Notification): Boolean =
        notification.bigContentView != null || notification.contentView != null

    /**
     * 从 `bigContentView`/`contentView` 里**有限**提取文本（P2-3 的最后一道兜底）。
     *
     * 只做两件事：inflate 出视图树、读 `TextView` 的文本。不点按钮、不跑 PendingIntent、
     * 不读其它属性 —— 第三方布局里可能有我们进程不认识的标签或动作，抛异常就按
     * "这条视图没有文本"处理，继续试下一个候选，最后返回空串（由调用方留诊断）。
     *
     * 先试 `bigContentView`（展开态文本更全），再试 `contentView`（折叠态）。
     */
    @Suppress("DEPRECATION")
    private fun extractRemoteViewsText(notification: android.app.Notification): String {
        for (views in listOf(notification.bigContentView, notification.contentView)) {
            if (views == null) continue
            try {
                // parent 传 null：只求把布局建出来读文本，不挂到任何窗口上。
                val root = views.apply(context, null) ?: continue
                val texts = ArrayList<String>()
                collectTextViewTexts(root, texts)
                val text = ViewTextDigest.format(texts)
                if (text.isNotEmpty()) return text
            } catch (e: Exception) {
                // 只报异常类型，不报布局内容（与日志脱敏同规）。
                Log.d(TAG, "RemoteViews 文本提取失败（按无文本继续）：${e.javaClass.simpleName}")
            }
        }
        return ""
    }

    /** 深度优先收集 `TextView` 的文本；`ViewGroup` 只递归子节点，别的类型一律忽略。 */
    private fun collectTextViewTexts(view: View, out: MutableList<String>) {
        when (view) {
            is TextView -> view.text?.toString()?.let { out.add(it) }
            is ViewGroup -> for (index in 0 until view.childCount) {
                collectTextViewTexts(view.getChildAt(index), out)
            }
        }
    }

    /** 带过滤原因版：返回 FilterResult，供服务端完成「拦截入历史 / 白名单标注」 */
    fun filter(
        packageName: String,
        title: String,
        content: String,
        subText: String,
        whitelistKeywords: List<String>,
        enabledPackages: Set<String>,
        blacklistKeywords: List<String>,
        filterMode: String = "allow",
        sourceType: String = "notification",
    ): FilterResult {
        // 委托给统一过滤引擎，与 SMS / Call 链路共用同一套规则
        // 修复点：黑名单优先级最高（原代码白名单命中后短路 return true，会跳过黑名单检查）
        return FilterEngine.filter(
            packageName = packageName,
            title = title,
            content = content,
            subText = subText,
            whitelistKeywords = whitelistKeywords,
            enabledPackages = enabledPackages,
            blacklistKeywords = blacklistKeywords,
            filterMode = filterMode,
            sourceType = sourceType,
        )
    }

    fun shouldNotify(
        packageName: String,
        title: String,
        content: String,
        subText: String,
        whitelistKeywords: List<String>,
        enabledPackages: Set<String>,
        blacklistKeywords: List<String>,
        filterMode: String = "allow"
    ): Boolean = filter(
        packageName, title, content, subText,
        whitelistKeywords, enabledPackages, blacklistKeywords, filterMode
    ).allowed

    private fun getAppNameByPackage(packageName: String): String {
        return try {
            val pm = context.packageManager
            val appInfo = pm.getApplicationInfo(packageName, 0)
            val label = pm.getApplicationLabel(appInfo).toString()
            val friendlyName = AppNameResolution.friendlyAppName(packageName)

            val isLabelSuspicious = label.isEmpty() ||
                label == packageName ||
                label.length > 12 ||
                label.contains("推送") ||
                label.contains("服务") ||
                label.contains("system", ignoreCase = true) ||
                label.contains("push", ignoreCase = true)

            if (isLabelSuspicious && friendlyName != packageName && friendlyName.isNotEmpty()) {
                friendlyName
            } else if (label.isNotEmpty() && label != packageName) {
                label
            } else {
                friendlyName
            }
        } catch (e: Exception) {
            AppNameResolution.friendlyAppName(packageName)
        }
    }

    /**
     * 系统当前默认短信应用（P2-4 的**首选信号**）。
     *
     * 每次现读而不是缓存：用户随时可能在系统设置里换默认短信应用，而本服务是常驻的；
     * 一次 binder 查询对通知到达频率来说可以忽略。读不到就回空串 —— 此时只有
     * [NotificationSourceClassifier] 的已知组件前缀还能认人，不会退回"包名含 sms"
     * 的旧启发式（那会把普通应用整包吞掉）。
     */
    private fun platformDefaultSmsPackage(): String {
        return try {
            android.provider.Telephony.Sms.getDefaultSmsPackage(context).orEmpty()
        } catch (e: Exception) {
            Log.d(TAG, "读默认短信应用失败（按未设置处理）：${e.javaClass.simpleName}")
            ""
        }
    }

    /** 系统当前默认拨号器（P2-4）；读不到回空串，理由同上。 */
    private fun platformDefaultDialerPackage(): String {
        return try {
            val telecom = context.getSystemService(Context.TELECOM_SERVICE) as? android.telecom.TelecomManager
            telecom?.defaultDialerPackage.orEmpty()
        } catch (e: Exception) {
            Log.d(TAG, "读默认拨号器失败（按未设置处理）：${e.javaClass.simpleName}")
            ""
        }
    }

    private fun isVendorPushService(packageName: String): Boolean {
        val pkg = packageName.lowercase()
        return when {
            pkg.startsWith("com.xiaomi.xmsf") -> true
            pkg.startsWith("com.xiaomi.push") -> true
            pkg.startsWith("com.miui.push") -> true
            pkg.startsWith("com.huawei.android.push") -> true
            pkg.startsWith("com.huawei.hms.push") -> true
            pkg.startsWith("com.vivo.push") -> true
            pkg.startsWith("com.vivo.notification") -> true
            pkg.startsWith("com.coloros.push") -> true
            pkg.startsWith("com.oppo.push") -> true
            pkg.startsWith("com.heytap.push") -> true
            pkg.startsWith("com.meizu.cloud") -> true
            pkg.startsWith("com.meizu.push") -> true
            pkg.startsWith("com.flyme.push") -> true
            pkg.startsWith("com.samsung.android.push") -> true
            pkg.startsWith("com.google.android.gms") && pkg.contains("push") -> true
            else -> false
        }
    }

    private fun resolveRealAppName(
        sbn: StatusBarNotification,
        baseName: String,
        title: String,
        subText: String
    ): String {
        val extras = sbn.notification?.extras ?: return baseName
        val pkg = sbn.packageName.lowercase()

        val vendorExtraKeys = listOf(
            "miui_android_notification_channel_id",
            "miui_primary_key",
            "miui_notification_id",
            "hw_push_id",
            "hw_from",
            "vivo_push_id",
            "oppo_push_id",
            "meizu_push_id",
            "flyme_push_id",
            "heytap_push_id",
            "push_app_name",
            "target_package",
            "src_package",
            "original_package",
            "ext_org_package",
            "ext_org_app_name"
        )
        for (key in vendorExtraKeys) {
            // `Bundle.get(String)` 从 API 33 起弃用，这里是按 key 取任意类型的厂商字段；
            // 用类型化 getter 读出 CharSequence（String 也实现 CharSequence），语义不变。
            val value: CharSequence? = extras.getCharSequence(key)
            if (value != null && value.isNotEmpty()) {
                val str = value.toString()
                if (str.isNotEmpty() && str.length <= 12 && !str.contains("push", true) && !str.contains("service", true)) {
                    return str
                }
            }
            if (value is String && value.isNotEmpty() && value.contains(".")) {
                val candidateAppName = getAppNameByPackage(value)
                if (candidateAppName != value && candidateAppName.isNotEmpty()) {
                    return candidateAppName
                }
            }
        }

        if (subText.isNotEmpty() && subText.length in 1..12) {
            val isAppName = !subText.contains("push", true) &&
                !subText.contains("service", true) &&
                !subText.contains("notification", true) &&
                !subText.contains("条消息", true) &&
                !subText.contains("新消息", true) &&
                !subText.contains("通知", true)
            if (isAppName) {
                return subText
            }
        }

        // Notification.getChannelId() 自 API 26 起（minSdk 24）：低版本裸调用抛
        // NoSuchMethodError，而它是 Error、不被本文件随处可见的 catch (Exception) 兜住。
        val channelId = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            sbn.notification?.channelId
        } else {
            null
        }
        if (!channelId.isNullOrEmpty()) {
            // ⚠ 候选包名必须保留渠道 ID 里的原始大小写：PackageManager 按包名精确匹配，
            // 先 lowercase() 再查会让 com.eg.android.AlipayGphone 查不到 ⇒ 回落成包名
            // （2026-11-08 魅族推送支付宝通知实测）。
            for (origPkg in AppNameResolution.channelPackageCandidates(channelId)) {
                val candidate = getAppNameByPackage(origPkg)
                if (candidate != origPkg && candidate.isNotEmpty()) {
                    return candidate
                }
            }
        }

        if (title.isNotEmpty()) {
            val bracketMatch = Regex("【([^】]+)】").find(title)
            if (bracketMatch != null) {
                val extracted = bracketMatch.groupValues[1]
                if (extracted.length in 1..12) {
                    return extracted
                }
            }
            val colonMatch = title.indexOf("：")
            if (colonMatch in 1..12) {
                val extracted = title.substring(0, colonMatch)
                if (extracted.isNotEmpty() && extracted.length <= 12) {
                    return extracted
                }
            }
        }

        val lowerBase = baseName.lowercase()
        if (lowerBase.contains("推送") || lowerBase.contains("push") || lowerBase.contains("服务") || lowerBase.contains("魅族")) {
            val firstWord = title.take(10)
            if (firstWord.isNotEmpty() && firstWord.length >= 2) {
                return firstWord
            }
        }

        return baseName
    }

    private fun detectNotificationType(packageName: String, appName: String, title: String, content: String): String {
        val pkg = packageName.lowercase()
        val appLower = appName.lowercase()
        val fullText = "$appName $title $content".lowercase()

        return when {
            pkg.contains("tencent.mm") || appLower.contains("微信") || appLower.contains("wechat") -> "wechat"
            pkg.contains("tencent.mobileqq") || appLower.contains("qq") -> "qq"
            pkg.contains("mms") || pkg.contains("sms") || appLower.contains("短信") -> "sms"
            pkg.contains("dialer") || pkg.contains("phone") || pkg.contains("incallui") || appLower.contains("电话") -> "call"
            pkg.contains("alipay") || appLower.contains("支付宝") -> "alipay"
            pkg.contains("taobao") || pkg.contains("tmall") || appLower.contains("淘宝") || appLower.contains("天猫") -> "taobao"
            pkg.contains("jd") || appLower.contains("京东") -> "jd"
            pkg.contains("weibo") || appLower.contains("微博") -> "weibo"
            pkg.contains("douyin") || appLower.contains("抖音") -> "douyin"
            pkg.contains("bilibili") || appLower.contains("哔哩哔哩") || appLower.contains("b站") -> "bilibili"
            pkg.contains("netease.cloudmusic") || pkg.contains("qqmusic") -> "music"
            pkg.contains("baidu.netdisk") || appLower.contains("百度网盘") -> "netdisk"
            pkg.contains("xingin") || pkg.contains("xhs") || appLower.contains("小红书") -> "xiaohongshu"
            pkg.contains("zhihu") || appLower.contains("知乎") -> "zhihu"
            pkg.contains("meituan") || pkg.contains("dianping") || pkg.contains("sankuai") ||
                appLower.contains("美团") || appLower.contains("大众点评") -> "meituan"
            pkg.contains("ele") || appLower.contains("饿了么") -> "eleme"
            pkg.contains("pinduoduo") || appLower.contains("拼多多") -> "pinduoduo"
            pkg.contains("kuaishou") || appLower.contains("快手") -> "kuaishou"
            pkg.contains("android.systemui") -> "system"
            pkg.contains("miui") && (pkg.contains("home") || pkg.contains("security") || pkg.contains("settings")) -> "system"
            pkg.contains("com.android.settings") -> "system"
            pkg.contains("com.android.systemui") -> "system"
            pkg.contains("xiaomi") && pkg.contains("xmsf") -> "system"
            pkg.contains("huawei.android.push") -> "system"
            pkg.contains("vivo") && pkg.contains("push") -> "system"
            pkg.contains("fcm") || pkg.contains("google.android.gms") -> "system"
            else -> "other"
        }
    }
}
