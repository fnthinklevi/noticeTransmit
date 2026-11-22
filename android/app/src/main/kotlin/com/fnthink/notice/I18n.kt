package com.fnthink.notice

import android.content.Context
import android.util.Log

/**
 * Webhook 推送文案国际化
 *
 * 解决问题：WebhookPayloadBuilder 与 SmsReceiver/PhoneCallReceiver 中所有标签硬编码中文，
 * 英文模式下推送仍为中文。
 *
 * 工作机制：
 * - 维护全局 locale（"zh" / "en"），默认 "zh"
 * - 服务启动时 [init] 从 SharedPreferences 读取 flutter.locale
 * - 用户切换语言时由 MainActivity.setLocaleLabel 调用 [setLocale]
 * - 所有 buildXxx 方法通过本对象取文案
 */
object I18n {
    private const val TAG = "I18n"
    private const val KEY_LOCALE = "flutter.locale"

    @Volatile
    private var locale: String = "zh"

    fun init(context: Context) {
        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            locale = prefs.getString(KEY_LOCALE, "zh") ?: "zh"
            Log.i(TAG, "I18n initialized: locale=$locale")
        } catch (e: Exception) {
            Log.e(TAG, "init failed", e)
        }
    }

    fun setLocale(localeCode: String) {
        locale = if (localeCode == "en") "en" else "zh"
        Log.i(TAG, "Locale set to: $locale")
    }

    fun getLocale(): String = locale

    private val isEn: Boolean get() = locale == "en"

    // ========== 通用标签 ==========
    fun bracket(text: String): String = if (isEn) "[$text]" else "【$text】"
    fun labelSeparator(): String = if (isEn) ": " else "："

    // ========== 通知类型标签 ==========
    fun newSmsLabel(): String = bracket(if (isEn) "New SMS" else "新短信")
    fun incomingCallLabel(): String = bracket(if (isEn) "Incoming Call" else "来电提醒")
    fun inCallLabel(): String = bracket(if (isEn) "In Call" else "通话中")
    fun callEndedLabel(): String = bracket(if (isEn) "Call Ended" else "通话结束")
    fun chargingLabel(): String = bracket(if (isEn) "Charging" else "充电提醒")
    fun batteryFullLabel(): String = bracket(if (isEn) "Battery Full" else "电量充满")
    fun lowBatteryLabel(): String = bracket(if (isEn) "Low Battery" else "低电量提醒")
    fun notificationLabel(appName: String): String =
        if (appName.isNotEmpty()) bracket(appName)
        else bracket(if (isEn) "Notification" else "通知提醒")

    /**
     * 锁屏脱敏正文的替换提示（面向用户的文案，唯一作者）。
     *
     * 锁屏时系统把验证码等正文显示成 `******`，原样转发没有价值；这里换成一句
     * "解锁后查看"。英文用户也必须看到英文 —— 这条曾经是 NotificationProcessor 里的
     * 硬编码中文。
     */
    fun notificationContentMasked(masked: String): String =
        if (isEn) "Verification code hidden on lock screen (shown as $masked). Unlock to view"
        else "验证码内容被锁屏隐藏（显示为 $masked），请解锁后查看"

    // ========== 字段标签 ==========
    fun titleLabel(): String = if (isEn) "Title" else "标题"
    fun contentLabel(): String = if (isEn) "Content" else "内容"
    fun timeLabel(): String = if (isEn) "Time" else "时间"
    fun deviceLabel(): String = if (isEn) "Device" else "设备"
    fun senderLabel(): String = if (isEn) "Sender" else "发送号码"
    fun messageLabel(): String = if (isEn) "Message" else "短信内容"
    fun receivedTimeLabel(): String = if (isEn) "Received" else "接收时间"
    fun callerLabel(): String = if (isEn) "Caller" else "来电号码"
    fun durationLabel(): String = if (isEn) "Duration" else "通话时长"
    fun simCardLabel(): String = if (isEn) "SIM" else "SIM卡"

    // ========== 应用名 ==========
    fun smsAppName(): String = if (isEn) "SMS" else "短信"
    fun callAppName(): String = if (isEn) "Phone" else "电话"
    fun appName(): String = if (isEn) "NoticeTransmit" else "通知推送助手"

    // ========== SIM 标签（用于标题中追加） ==========
    fun simSuffix(simInfo: String?): String =
        if (simInfo.isNullOrEmpty()) "" else " [${if (isEn) "SIM" else "SIM卡"}: $simInfo]"
    fun simSuffixShort(simInfo: String?): String =
        if (simInfo.isNullOrEmpty()) "" else " [$simInfo]"

    // ========== SIM 槽位标签（SimInfoHelper 使用，中英双语） ==========
    fun simSlotLabel(slot: Int): String = if (isEn) "SIM$slot" else "卡$slot"

    /**
     * 推送正文底部 SIM 信息行（短信/通话链路，中英双语）
     * 中文："卡1，运营商：中国移动" / 英文："SIM 1, Carrier: China Mobile"
     */
    fun simFooterLine(slot: Int, carrier: String): String =
        if (isEn) "SIM $slot, Carrier: $carrier" else "卡$slot，运营商：$carrier"

    // ========== 电量规则文案（BatteryMonitor 使用，中英双语） ==========
    fun batteryRuleTitle(type: String, threshold: Int): String = when (type) {
        "charging" -> if (isEn) "Charging started" else "开始充电"
        "discharging" -> if (isEn) "Charging disconnected" else "断开充电"
        "level_above" -> if (isEn) "Battery reached $threshold%" else "电量达到$threshold%"
        "level_below" -> if (isEn) "Battery below $threshold%" else "电量低于$threshold%"
        "level_equals" -> if (isEn) "Battery equals $threshold%" else "电量等于$threshold%"
        else -> if (isEn) "Battery Alert" else "电量提醒"
    }
    fun batteryLevelText(level: Int, isCharging: Boolean): String =
        if (isEn) "Current battery: $level%${if (isCharging) " (charging)" else ""}"
        else "当前电量: $level%${if (isCharging) " (充电中)" else ""}"

    // ========== 未知发件人（SmsReceiver 使用，中英双语） ==========
    fun unknownSender(): String = if (isEn) "Unknown number" else "未知号码"

    // ========== 过滤决策文案（FilterResult 使用，中英双语） ==========
    fun filterBlacklistReason(keyword: String): String {
        val kw = if (keyword.isNotEmpty()) {
            if (isEn) " (keyword: $keyword)" else "（命中: $keyword）"
        } else ""
        return if (isEn) "Blocked by blacklist$kw" else "黑名单$kw"
    }

    fun filterAppBlockReason(): String =
        if (isEn) "Blocked by app filter" else "应用过滤"

    fun whitelistTag(): String = if (isEn) "[Whitelist]" else "[白名单]"

    /**
     * 规则判定「仅记录，不推送」那一条的理由（T150 片2）。
     *
     * 这一格与 [filterAppBlockReason] 走同一个伪通道，所以措辞要答同一个问题：
     * 「这条怎么没出去」。写成"已记录"那种中性说法会盖住事实——它**没投递**，
     * 而历史那一格必须与「发送中」区分开（旧写法这里静默返回，那一排通道就永远停在初值）。
     */
    fun ruleRecordOnlyReason(): String =
        if (isEn) "Recorded only by rule · not sent" else "按规则仅记录，未推送"

    // ========== 更新包签名校验（P0 安全加固，中英双语） ==========
    fun updateSigFileMissing(): String =
        if (isEn) "Update package not found" else "安装包不存在"

    fun updateSigReadCurrentFail(): String =
        if (isEn) "Failed to read current app signature"
        else "无法读取当前应用签名"

    fun updateSigParseFail(): String =
        if (isEn)
            "Failed to parse update package signature (corrupted or tampered?)"
        else "无法解析安装包签名（可能已损坏或被篡改）"

    fun updateSigMismatch(): String =
        if (isEn)
            "Signature mismatch with the installed app. The package may be tampered. Installation blocked."
        else "安装包签名与当前应用不一致，可能被篡改，已阻止安装"

    fun updateSigUnverifiable(): String =
        if (isEn)
            "Cannot resolve downloaded file for signature verification. Installation blocked."
        else "无法获取下载文件以校验签名，已阻止安装"

    fun updateSigDowngradeBlocked(): String =
        if (isEn)
            "The update package is older than the installed version. Downgrade blocked."
        else "安装包版本低于当前版本，已阻止降级安装"

    fun updateInstallPermissionNeeded(): String =
        if (isEn)
            "Install permission is required. Please enable it in system settings."
        else "缺少安装权限，请到系统设置中开启"

    fun updateDownloadNotReady(): String =
        if (isEn) "Download is not finished or no longer available"
        else "下载未完成或已失效，无法安装"

    fun updateInstallFailed(): String =
        if (isEn) "Failed to start installation of the update package"
        else "更新包安装失败"

    // ========== 通话状态 → 标题/内容 ==========
    fun callStateTitle(state: String, simInfo: String?): String {
        val label = when (state) {
            "ringing" -> incomingCallLabel()
            "answered" -> inCallLabel()
            "ended" -> callEndedLabel()
            else -> bracket(if (isEn) "Phone" else "电话")
        }
        return label
    }

    fun callStateContent(state: String, phoneNumber: String, simInfo: String?): String {
        val simSuffix = simSuffix(simInfo)
        return when (state) {
            "ringing" -> if (isEn) "Incoming call$simSuffix: $phoneNumber"
            else "来电$simSuffix: $phoneNumber"
            "answered" -> if (isEn) "Answered$simSuffix: $phoneNumber"
            else "已接听$simSuffix: $phoneNumber"
            "ended" -> if (isEn) "Call ended$simSuffix: $phoneNumber"
            else "通话结束$simSuffix: $phoneNumber"
            else -> if (isEn) "Phone$simSuffix: $phoneNumber"
            else "电话$simSuffix: $phoneNumber"
        }
    }

    /**
     * PhoneCallReceiver 内 notifyFlutter 构造的标题（含号码）。
     */
    fun callNotifyTitle(state: String, phoneNumber: String, simInfo: String?): String {
        val simSuf = simSuffixShort(simInfo)
        val stateLabel = when (state) {
            "ringing" -> if (isEn) "Incoming Call" else "来电"
            "answered" -> if (isEn) "In Call" else "通话中"
            "ended" -> if (isEn) "Call Ended" else "通话结束"
            else -> if (isEn) "Phone" else "电话"
        }
        return "$stateLabel$simSuf - $phoneNumber"
    }

    // ========== SmsReceiver 标题 ==========
    fun smsNotifyTitle(sender: String, simInfo: String?): String {
        val simSuf = simSuffixShort(simInfo)
        val label = if (isEn) "SMS" else "短信"
        return "$label$simSuf - $sender"
    }

    // ========== 通话时长格式化 ==========
    fun formatDuration(durationSec: Long): String {
        if (durationSec <= 0) return ""
        val m = durationSec / 60
        val s = durationSec % 60
        return if (isEn) "${m}m ${s}s"
        else "${m}分${s}秒"
    }

    // ========== 测试推送文案 ==========
    fun testTitle(): String = if (isEn) "Test Notification" else "测试通知"
    fun testContent(): String = if (isEn)
        "This is a test message. Webhook configured successfully!"
    else "这是一条测试消息，Webhook 配置成功！"
    fun testDeviceLabel(): String = if (isEn) "Device" else "设备"

    // ========== 渠道名（送达详情 / 测试结果显示用） ==========
    // ⚠ 这里的 `else` 是**故意的**：当前枚举已穷尽，Kotlin 会报「exhaustive so else is
    // redundant」；但留着它，新增通道没补文案时退回枚举名而不是编译失败（见下面那条注释）。
    // 某天补上新枚举成员，when 不再穷尽，warning 会自己消失。
    @Suppress("REDUNDANT_ELSE_IN_WHEN")
    fun channelName(type: WebhookPayloadBuilder.WebhookType): String = when (type) {
        WebhookPayloadBuilder.WebhookType.WECHAT_WORK -> if (isEn) "WeCom" else "企业微信"
        WebhookPayloadBuilder.WebhookType.DINGTALK -> if (isEn) "DingTalk" else "钉钉"
        WebhookPayloadBuilder.WebhookType.FEISHU -> if (isEn) "Feishu" else "飞书"
        WebhookPayloadBuilder.WebhookType.TELEGRAM -> "Telegram"
        WebhookPayloadBuilder.WebhookType.BARK -> "Bark"
        WebhookPayloadBuilder.WebhookType.SERVER_CHAN -> if (isEn) "ServerChan" else "Server酱"
        WebhookPayloadBuilder.WebhookType.PUSH_PLUS -> "PushPlus"
        WebhookPayloadBuilder.WebhookType.NTFY -> "ntfy"
        WebhookPayloadBuilder.WebhookType.GOTIFY -> "Gotify"
        WebhookPayloadBuilder.WebhookType.SLACK -> "Slack"
        WebhookPayloadBuilder.WebhookType.DISCORD -> "Discord"
        WebhookPayloadBuilder.WebhookType.GENERIC -> if (isEn) "Generic" else "通用"
        // else 分支（第 4 步）：新增通道还没补文案时显示枚举名，而不是编译失败——
        // 本函数与 MainActivity 的 typeLabel 曾是"加一个通道必须改两处中文"的强制点。
        else -> type.name.lowercase()
    }
    fun pushPlusTokenMissing(): String =
        if (isEn) "PushPlus URL is missing the token parameter" else "PushPlus 链接缺少 token 参数"
    fun pushException(e: String?): String =
        if (isEn) "Push exception: ${e ?: ""}" else "推送异常: ${e ?: ""}"

    // ========== 前台服务通知 ==========
    fun serviceTitle(): String = if (isEn) "NoticeTransmit" else "通知推送助手"
    fun serviceListening(count: Int): String =
        if (isEn) "Listening · $count pushed today"
        else "正在监听通知 · 当日已推送 $count 条"
    fun servicePushPaused(count: Int): String =
        if (isEn) "Push paused · $count pushed today"
        else "推送已暂停 · 当日已推送 $count 条"

    // 幻念收件与通知监听共用同一条常驻通知（见 NotificationMonitorService.foregroundWanted）：
    // 只开收件时监听那几句都不成立，得有自己的文案；两个都开时说清两件事都在跑。
    fun serviceFnthinkReceiving(): String =
        if (isEn) "Fnthink inbox receiving" else "幻念收件运行中"
    fun serviceListeningWithFnthink(count: Int): String =
        if (isEn) "Listening · Fnthink inbox receiving · $count pushed today"
        else "正在监听通知 · 幻念收件运行中 · 当日已推送 $count 条"
    fun servicePushPausedWithFnthink(count: Int): String =
        if (isEn) "Push paused · Fnthink inbox receiving · $count pushed today"
        else "推送已暂停 · 幻念收件运行中 · 当日已推送 $count 条"

    // ========== 幻念推送 · 收件通知渠道（T48 前置）==========
    // 渠道名要能一眼看出"这是别人推给我的消息"，与前台服务那条常驻通知（"通知推送助手"）分开：
    // 用户在系统设置里是按渠道关通知的，名字混了就关错那一个。
    fun fnthinkInboxChannelName(): String =
        if (isEn) "Fnthink messages" else "幻念推送 · 收件"
    fun fnthinkInboxChannelDescription(): String =
        if (isEn) "Messages pushed to this device by paired devices and endpoints"
        else "由已配对设备与接入端点推给本机的消息"
    // T173：通知自检发出的那一条测试通知（不走收件表、不产生未读）。
    fun fnthinkInboxTestTitle(): String =
        if (isEn) "Fnthink inbox test" else "幻念推送 · 收件测试"
    fun fnthinkInboxTestText(): String =
        if (isEn) "If you can see this on the lock screen, with sound and vibration, the inbox channel is healthy."
        else "能在锁屏看到这一条、并且响铃/震动，说明收件渠道配置正常。"
    // ── 远程「让这台响一条」（T124 片B 的 alert:ring）──
    // 与收件那条通知**同一条渠道**（见 FnthinkAlertDisplay 的类注释：另开一条等于
    // 把用户关掉的声音偷偷打开），文案上分得开这两类事。
    fun fnthinkAlertTitle(): String =
        if (isEn) "A paired device is calling your attention" else "有一台已配对的设备在找你"
    fun fnthinkAlertText(): String =
        if (isEn) "That device asked this one to ring. Open the app for details."
        else "对面让你注意一下，所以响起了这一条。打开应用可以看到来源。"
    // ⚠ 与收件那一条**分开**（片3c-5）：关掉收件通知时不该连撤销机会一起关掉，
    //   否则界面上是"远程执行开着、却找不到能取消它的入口"。
    fun fnthinkRemoteExecChannelName(): String =
        if (isEn) "Fnthink remote commands" else "幻念推送 · 远程指令"
    fun fnthinkRemoteExecChannelDescription(): String =
        if (isEn) "Someone asks this device to do something; it runs after a short delay unless you cancel"
        else "别人让这台设备做事；延时窗口内不撤销就自动执行"
    /** 通知上那枚动作按钮的标题（动作按钮**不吃** l10n 资源，必须带真实文案）。 */
    fun remoteExecCancelLabel(): String = if (isEn) "Cancel" else "撤销"
    // ========== v1.59 温度维度（自建应用通道体系的电池域扩展） ==========

/** 温度维度显示名（电池/设备/屏幕） */
    fun temperatureDimLabel(type: String): String = when (type) {
        "battery_temp_above" -> if (isEn) "Battery" else "电池"
        "screen_temp_above" -> if (isEn) "Screen" else "屏幕"
        else -> if (isEn) "Device" else "设备"
    }

/** 温度规则默认标题：{维度}温度已达{阈值}℃ */
    fun temperatureRuleTitle(dimLabel: String, threshold: Int): String =
        if (isEn) "$dimLabel temperature reached $threshold°C"
        else "${dimLabel}温度已达$threshold℃"

/** 温度推送正文：当前{维度}温度 */
    fun temperatureContent(dimLabel: String, currentC: Double): String =
        if (isEn) "Current ${dimLabel.lowercase()} temperature: ${
            String.format(java.util.Locale.US, "%.1f", currentC)
        }°C"
        else "当前${dimLabel}温度：${String.format(java.util.Locale.US, "%.1f", currentC)}℃"

    /**
     * T24：亮度与网络触发源的文案。
     *
     * 网络类型标签必须在这里有一份**给人看的**名字：`DeviceSnapshot` 那侧的
     * `wifi/cellular/vpn/...` 是协议值（跨端比较、存库都用它），把它们直接写进推送正文
     * 等于让用户读英文小写黑话。两边的一致性由 Kotlin 侧这条 when 的 `else` 兜底 ——
     * 出现没登记的新类型时显示原值，不猜、不吞。
     */
    fun brightnessBelowTitle(threshold: Int): String =
        if (isEn) "Screen brightness below $threshold%" else "屏幕亮度低于$threshold%"

    fun brightnessAboveTitle(threshold: Int): String =
        if (isEn) "Screen brightness above $threshold%" else "屏幕亮度高于$threshold%"

    fun brightnessContent(percent: Int): String =
        if (isEn) "Current brightness: $percent%" else "当前亮度：$percent%"

    fun networkLostTitle(): String =
        if (isEn) "Network disconnected" else "设备已断网"

    fun networkRestoredTitle(): String =
        if (isEn) "Network restored" else "网络已恢复"

    fun networkLostContent(): String =
        if (isEn) "The device is offline" else "当前无可用网络"

    fun networkRestoredContent(networkType: String): String =
        if (isEn) "Back online via ${networkTypeLabel(networkType)}"
        else "已重新联网：${networkTypeLabel(networkType)}"

    fun networkTypeLabel(networkType: String): String = when (networkType) {
        "wifi" -> if (isEn) "Wi-Fi" else "Wi-Fi"
        "cellular" -> if (isEn) "mobile data" else "移动数据"
        "ethernet" -> if (isEn) "ethernet" else "有线网络"
        "vpn" -> if (isEn) "VPN" else "VPN"
        "none" -> if (isEn) "no network" else "无网络"
        "other" -> if (isEn) "other" else "其它网络"
        else -> if (networkType.isEmpty()) "—" else networkType
    }

    // ========== T186 片1：设备态翻转触发的规则推送 ==========
    /** 状态触发推送的标题：不假装它是某一条应用通知，也不猜命中的是充电还是网络条件。 */
    fun deviceStateChangedTitle(): String =
        if (isEn) "Device state changed" else "设备状态变化"

    /** 充电状态标签：三档原值 → 给人看的话；读不到写「未知」，不冒充某一档。 */
    fun chargingStateLabel(state: String): String = when (state) {
        "charging" -> if (isEn) "charging" else "充电中"
        "full" -> if (isEn) "full" else "已充满"
        "not_charging" -> if (isEn) "not charging" else "未充电"
        else -> if (isEn) "unknown" else "未知"
    }

    /**
     * 状态触发推送的正文：两枚原值（充电档、网络档）＋可读到的电量。
     *
     * ⚠ 文案只陈述**当前读数**，不写"已开始充电/已断网"：这条规则可能只按充电条件
     * 或只按网络条件匹配，猜一个方向就会和规则实际命中的那一半对不上。
     */
    fun deviceStateRuleContent(
        chargingState: String,
        networkType: String,
        batteryPercent: Int?,
    ): String {
        val charging = chargingStateLabel(chargingState)
        val network = networkTypeLabel(networkType)
        val battery = batteryPercent?.let {
            if (isEn) " · Battery: $it%" else " · 电量：$it%"
        } ?: ""
        return if (isEn) {
            "Charging: $charging · Network: $network$battery"
        } else {
            "充电状态：$charging · 网络：$network$battery"
        }
    }

    fun serviceListenerDisconnected(): String = if (isEn)
        "Notification read permission not granted · listening paused. Enable Notification Access to resume"
    else "未授予通知读取权限，通知监听已暂停"
    fun actionPausePush(): String = if (isEn) "Pause push" else "暂停推送"
    fun actionResumePush(): String = if (isEn) "Resume push" else "恢复推送"

    // ========== 聚合推送（P2 merge 动作） ==========
    /** 聚合通知标题：{appName} 合并推送 (N 条) */
    fun mergePushTitle(appName: String, count: Int): String =
        if (isEn) "$appName merged push ($count)"
        else "$appName 合并推送 ($count 条)"

    /** 成员记录送达补标文案（MERGE 伪通道，success） */
    fun mergeDeliveredLabel(): String = if (isEn) "Delivered as merged push" else "已合并推送"

    /**
     * 成员被摘出聚合组时的送达文案（MERGE 伪通道，failed）。
     *
     * 为什么是 failed 而不是 intercepted：摘出这一条不是"规则决定这条不发"，
     * 而是**这一组装不下了**——通知已经进了历史、内容还在，用户手动「现在推送」应当推得动；
     * intercepted 会把它划进"不该重推"那一族（`RepushScope` 按状态筛），等于替用户把门关上。
     */
    fun mergeMemberDroppedReason(): String =
        if (isEn) "Not pushed: it was dropped from the merged group (group full)"
        else "未随聚合发出：这一组成员已达上限，这条被摘出该组"

    /**
     * 幻念待发队列满了，最旧的那几条没转发出去（T147③）。
     *
     * 与 [mergeMemberDroppedReason] 同一条语义：报 failed 而不是 intercepted ——
     * 这不是"规则决定不发"，用户仍该能手动补这一条。
     */
    fun fnthinkFanoutQueueDroppedReason(count: Int): String =
        if (isEn) "Not forwarded: the fan-out queue was full; the $count oldest entr(ies) were dropped"
        else "未转发：待发队列已满，最旧的 $count 条被丢弃"

    /**
     * 通知处理失败时的降级历史（提取/过滤/分发任一步抛异常）。
     * 此前只写 logcat，release 下用户完全无感 —— 该通知既不入历史也不推送，内容静默消失。
     * 正文刻意不含通知内容与异常堆栈（隐私：日志脱敏同样适用于历史）。
     */
    fun processFailedTitle(): String =
        if (isEn) "Notification processing failed" else "通知处理失败"

    fun processFailedBody(): String =
        if (isEn) {
            "This notification could not be processed or pushed. " +
                "Check the app logs for details."
        } else {
            "这条通知处理失败，未推送。详细信息见应用日志。"
        }

    /** 前台通知聚合预览：摘要行 */
    fun mergePendingSummary(count: Int): String =
        if (isEn) "Merging $count notification(s)…" else "正在合并 $count 条通知…"

    /** 前台通知聚合预览：每组一行的尾注（剩余秒数） */
    fun mergeEta(seconds: Long): String =
        if (isEn) "push in ${seconds}s" else "${seconds}s 后推送"

    // ========== 桌面小部件 ==========
    // ⚠ 这一族的文案长度是**版式定的**，不是风格：2×2 卡片去掉内边距只剩 78dp 宽，
    // 24sp 粗体英文一个字母约 19dp（⇒ 大字 ≤4 个字母），12sp 小字约 6dp（⇒ ≤13 个字母 / 6 个汉字）。
    // 中文按这个写正好，英文一写成就溢出被省略号截掉 —— 而且只有渲染出来才看得见。
    // 所以这几条字符串的宽度由 WidgetRenderSnapshotTest（zh + en × 2 主题 × 2 规格 × 3 态）逐张核对，
    // 改文案前后请重跑它，别只看中文。
    // ⚠ 2026-11-01 真机（2410DPN6CC / Android 17 / 393dp）把上界收窄到 **11 个字母**：
    // 「Tap to resume」13 个字母被省略号截掉 2 个，而同字宽的「Tap to pause」正好一行。
    // 所以「恢复」这一格用 11 个字母的「Tap to start」，不是随手换词。
    fun widgetActiveText(): String = if (isEn) "Live" else "推送中"
    fun widgetPausedText(): String = if (isEn) "Idle" else "已暂停"
    fun widgetTapPause(): String = if (isEn) "Tap to pause" else "点击暂停推送"
    fun widgetTapResume(): String = if (isEn) "Tap to start" else "点击恢复推送"
    fun widgetDailyPushed(): String = if (isEn) "Sent today" else "当日已推送"
    // 「已关闭」的副文案按**四种成因**分叉：一律写"已被清理"就有几条是错的
    // （STOPPED 是自己停的、KILLED 是被系统杀的、LISTENER_DISABLED 是在应用里关的、
    // NEVER_STARTED 是还没跑过）。四种处境对应的下一步不同，所以这一行说的是"为什么"
    // 而不是"怎么办" —— 大字已经说了"已关闭"，桌面上唯一取不到的信息就是原因；
    // 而"点小部件能重开"由另外两态的「点击…」教会用户（4×2 与 2×2 同为两格高，塞不下第四行）。
    // 每句都必须短到一行放得下：加长一个字就会被省略号截断，
    // 渲染取证 WidgetRenderSnapshotTest 的 collectClipped 正是钉这一点的。
    fun widgetClosedText(): String = if (isEn) "Off" else "已关闭"
    fun widgetCallSmsOnlyText(): String = if (isEn) "Calls & SMS" else "仅电话短信"
    fun widgetCallSmsOnlyHint(): String = if (isEn) "Notifications off" else "通知转发已停止"
    fun widgetClosedKilled(): String = if (isEn) "App closed" else "应用已被清理"
    fun widgetClosedStopped(): String = if (isEn) "Service off" else "服务已停止"
    fun widgetClosedListenerOff(): String = if (isEn) "Listener off" else "监听未开启"
    fun widgetClosedNeverStarted(): String = if (isEn) "Not started" else "尚未启动过"
    fun widgetAddTitle(): String = if (isEn) "Add widget" else "添加桌面小部件"
    fun widgetAddDesc(): String = if (isEn)
        "Tap below, then confirm in the system dialog to place the 2×2 push toggle widget on your home screen."
    else "点击下方按钮后，在系统弹窗中确认即可将 2×2 推送开关小部件添加到桌面。"
    fun widgetAddAction(): String = if (isEn) "Add 2×2 widget" else "一键添加 2×2 小部件"
    fun widgetAddSuccess(): String = if (isEn)
        "Added. You can now place the widget on the home screen."
    else "已发起添加，请在桌面放置小部件。"
    fun widgetAddUnsupported(): String = if (isEn)
        "This launcher does not support quick-add. Please add it manually by long-pressing the home screen."
    else "当前桌面不支持一键添加，请长按桌面空白处手动添加。"
    fun widgetAddLowApi(): String = if (isEn)
        "Quick-add requires Android 8.0+. Please add it manually by long-pressing the home screen."
    else "一键添加需要 Android 8.0 及以上，请长按桌面空白处手动添加。"

    // ========== 消息目录：面向用户的动态/错误文案 ==========
    // 为什么有这一层：错误原因、邮件正文、Toast 这类文案数量多、参数多，每条都写一个
    // 具名函数会把 I18n 撑成一堵墙。键值目录让"文案唯一作者"仍然在 I18n.kt，调用点
    // 只出现 ASCII 键 —— Kotlin CJK 棘轮守卫据此判断"新增用户文案有没有进 I18n"。
    // 占位符用 `{0}`/`{1}`（不用 `%s`：邮件模板里本身就有 `%appName%` 这类百分号）。
    private val MESSAGES_ZH: Map<String, String> = mapOf(
        // 邮件
        "email.sent" to "邮件发送成功",
        "email.sentRetry" to "邮件发送成功（重试后）",
        "email.testSubject" to "🧪 通知推送助手 — 邮件通道测试",
        "email.testBody" to "这是一封测试邮件。\n发送时间：{0}\nSMTP 服务器：{1}\n发件人：{2}\n收件人：{3}",
        "email.testSent" to "测试邮件发送成功",
        "email.probeOk" to "SMTP 握手与认证通过（未发送邮件）",
        "email.authFailed" to "认证失败，请检查账号和授权码是否正确",
        "email.sslFailed" to "SSL 连接失败，请检查端口号或关闭 SSL 后重试",
        "email.connectFailed" to "无法连接 SMTP 服务器，请检查地址和端口",
        "email.timeout" to "连接超时，请检查网络或防火墙设置",
        "email.dnsFailed" to "无法解析 SMTP 服务器地址，请检查域名是否正确",
        "email.rejected" to "邮件发送被拒: {0}",
        "email.smtp530" to "SMTP 认证失败(530)，请检查账号和授权码",
        "email.smtp535" to "SMTP 认证失败，请检查账号和授权码是否正确",
        "email.smtp550" to "收件人地址被拒绝(550)，请检查收件邮箱地址",
        "email.smtp553" to "发件人地址被拒绝(553)，请检查发件邮箱",
        "email.smtp554" to "邮件被服务端拒绝(554)，可能触发反垃圾策略",
        "email.smtp421" to "SMTP 服务暂时不可用(421)，请稍后重试",
        "email.smtp450" to "收件人邮箱不存在或已停用(450)",
        "email.smtp504" to "SMTP 认证方式不支持(504)，请检查 SSL 开关设置",
        "email.connRefused" to "连接被拒绝，请检查 SMTP 地址和端口",
        "email.sendFailed" to "邮件发送失败：{0}",
        "email.sendFailedShort" to "发送失败: {0}",
        "email.bodyDefault" to
            "【通知转发】\n\n应用：%appName%\n标题：%title%\n内容：%content%\n%subTextLine\n包名：%packageName%\n时间：%time%\n设备：%deviceName%\n\n--- 由 NoticeTransmit 自动发送 ---",
        "email.subTextLine" to "副标题：{0}",
        // 内置应用名（系统/厂商推送的兜底显示名）
        "app.wechat" to "微信",
        "app.qq" to "QQ",
        "app.sms" to "短信",
        "app.phone" to "电话",
        "app.settings" to "设置",
        "app.systemui" to "系统界面",
        "app.xiaomiPush" to "小米推送",
        "app.huaweiPush" to "华为推送",
        "app.vivoPush" to "vivo推送",
        "app.meizuPush" to "魅族推送",
        "app.oppoPush" to "OPPO推送",
        "app.googleServices" to "Google服务",
        "app.alipay" to "支付宝",
        "app.dingtalk" to "钉钉",
        // 通道/投递失败原因
        "err.bizFailCode" to "业务失败 code={0}: {1}",
        "err.bizFailErrcode" to "业务失败 errcode={0}: {1}",
        "err.bizFailCodeStatus" to "业务失败 code={0} StatusCode={1}: {2}",
        "err.rateLimitErrcode" to "限流 errcode={0}: {1}",
        "err.rateLimitCode" to "限流 code={0}: {1}",
        "err.telegramChatIdMissing" to "Telegram 链接缺少 chat_id 参数",
        "err.pushplusTokenMissing" to "PushPlus 链接缺少 token 参数",
        "err.gotifySecretMissing" to "Gotify 缺少应用 Token（secret 字段）",
        "err.barkBizFail" to "Bark 业务失败 code={0}: {1}",
        "err.serverChanBizFail" to "Server酱业务失败 code={0}: {1}",
        "err.pushplusBizFail" to "PushPlus 业务失败 code={0}: {1}",
        "err.genericFail" to "失败",
        "err.unknownAppChannel" to "未知应用通道类型",
        "err.invalidAddress" to "地址无效",
        "err.payloadBuild" to "载荷构造失败",
        "err.tokenFetch" to "获取 token 失败",
        "err.tokenQueued" to "获取 token 失败已转入自动重试队列，解锁/联网后自动补发 · {0}",
        "err.tokenNetwork" to "获取 token 失败（网络原因）：{0}",
        "err.queuedRetry" to "发送失败已转入自动重试队列，解锁/联网后自动补发 · {0}",
        "err.wecomMissing" to "企业微信自建应用缺少 corpid 或 corpsecret",
        "err.agentidInvalid" to "agentid 无效（须为正整数）",
        "err.feishuMissing" to "飞书自建应用缺少 app_id 或 app_secret",
        "err.receiveIdEmpty" to "receive_id 不能为空",
        "err.gettokenNonJson" to "gettoken 响应非 JSON（网关/代理错误页？）: {0}",
        "err.gettokenFail" to "gettoken 失败 errcode={0}: {1}",
        "err.tokenMissing" to "gettoken 响应缺少 access_token",
        "err.tenantNonJson" to "tenant_access_token 响应非 JSON（网关/代理错误页？）: {0}",
        "err.tenantFail" to "tenant_access_token 获取失败 code={0}: {1}",
        "err.tenantMissing" to "响应缺少 tenant_access_token",
        "err.emptyToken" to "token 端点返回空 access_token",
        "err.httpPrefix" to "API 地址必须以 http(s):// 开头",
        "err.httpServer" to "服务器错误 HTTP {0}: {1}",
        "err.httpRate" to "限流 HTTP 429: {0}",
        "err.httpClient" to "客户端错误 HTTP {0}: {1}",
        "err.nonJson" to "响应非 JSON，无法确认送达：{0}",
        "err.noWebhook" to "未配置 Webhook 通道",
        "err.emailQueueRemoved" to "自动补发失败：邮件通道已删除或停用",
        "err.emailResent" to "邮件发送成功（自动补发）",
        "err.pushException" to "推送异常: {0}",
        "err.testEmailException" to "测试邮件异常: {0}",
        // 通知/前台服务
        "notif.channelName" to "后台服务",
        "notif.channelDesc" to "通知监听与幻念收件的前台服务",
        "notif.noTitle" to "(无标题)",
        "merge.listSep" to "、",
        "merge.listMore" to "{0} 等",
        // 自建应用测试
        "test.appChannelMessage" to "这是一条测试消息，自建应用通道配置成功！",
        "test.deviceLine" to "设备：{0}",
        "test.signedLabel" to " [已签名]",
        "test.exception" to "测试异常: {0}",
        // 导出/归档/下载失败原因
        "export.success" to "导出成功",
        "export.writeFailed" to "写入失败: {0}",
        "export.canceled" to "已取消",
        "export.noArchiveDir" to "未设置自定义归档目录",
        "export.createFileFailed" to "创建文件失败",
        "export.openStreamFailed" to "无法打开输出流",
        "download.unknown" to "未知错误",
        "download.fileError" to "文件错误",
        "download.httpStatus" to "服务器返回异常状态码（HTTP 错误）",
        "download.dataError" to "网络数据错误",
        "download.redirects" to "重定向过多",
        "download.space" to "存储空间不足",
        "download.deviceNotFound" to "设备未找到",
        "download.cannotResume" to "无法断点续传",
        "download.exists" to "文件已存在",
        "download.blocked" to "下载被阻止",
        "download.cannotOverwrite" to "无法覆盖文件",
        "download.notFound" to "文件不存在（服务器 404）",
        // 幻念/文件通道的错误原因
        "fn.err.identityUnavailable" to "身份密钥不可用",
        "fn.err.canonicalEmpty" to "canonicalBase64 不能为空",
        "fn.err.signFailed" to "签名失败",
        "fn.err.secondsPositive" to "seconds 必须为正整数",
        "file.err.hash" to "哈希计算失败",
        "identity.noPrivateKey" to "KeyStore 里没有身份私钥（{0}）",
        "identity.publicKeyLost" to "私钥在、公钥缓存丢了且证书读不回来：要用户显式重置身份，不能悄悄换一把",
        "identity.signatureUntrusted" to "原生签名未通过独立实现验签：本机 Ed25519 不可信",
        "identity.wrappedKeyMissing" to "包裹私钥文件缺失而公钥仍在：需要用户显式重置身份",
    )

    private val MESSAGES_EN: Map<String, String> = mapOf(
        "email.sent" to "Email sent",
        "email.sentRetry" to "Email sent (after retry)",
        "email.testSubject" to "🧪 NoticeTransmit — Email channel test",
        "email.testBody" to "This is a test email.\nSent at: {0}\nSMTP server: {1}\nFrom: {2}\nTo: {3}",
        "email.testSent" to "Test email sent",
        "email.probeOk" to "SMTP handshake and authentication succeeded (no email sent)",
        "email.authFailed" to "Authentication failed. Check the account and authorization code",
        "email.sslFailed" to "SSL connection failed. Check the port or disable SSL and retry",
        "email.connectFailed" to "Cannot connect to the SMTP server. Check the address and port",
        "email.timeout" to "Connection timed out. Check the network or firewall settings",
        "email.dnsFailed" to "Cannot resolve the SMTP server address. Check the domain",
        "email.rejected" to "Email rejected: {0}",
        "email.smtp530" to "SMTP authentication failed (530). Check the account and authorization code",
        "email.smtp535" to "SMTP authentication failed. Check the account and authorization code",
        "email.smtp550" to "Recipient rejected (550). Check the recipient address",
        "email.smtp553" to "Sender rejected (553). Check the sender address",
        "email.smtp554" to "Rejected by the server (554); an anti-spam policy may have triggered",
        "email.smtp421" to "SMTP service temporarily unavailable (421). Try again later",
        "email.smtp450" to "Recipient mailbox does not exist or is disabled (450)",
        "email.smtp504" to "SMTP authentication method unsupported (504). Check the SSL setting",
        "email.connRefused" to "Connection refused. Check the SMTP address and port",
        "email.sendFailed" to "Email send failed: {0}",
        "email.sendFailedShort" to "Send failed: {0}",
        "email.bodyDefault" to
            "[Notification Forward]\n\nApp: %appName%\nTitle: %title%\nContent: %content%\n%subTextLine\nPackage: %packageName%\nTime: %time%\nDevice: %deviceName%\n\n--- Sent automatically by NoticeTransmit ---",
        "email.subTextLine" to "Sub-text: {0}",
        "app.wechat" to "WeChat",
        "app.qq" to "QQ",
        "app.sms" to "SMS",
        "app.phone" to "Phone",
        "app.settings" to "Settings",
        "app.systemui" to "System UI",
        "app.xiaomiPush" to "Xiaomi Push",
        "app.huaweiPush" to "Huawei Push",
        "app.vivoPush" to "vivo Push",
        "app.meizuPush" to "Meizu Push",
        "app.oppoPush" to "OPPO Push",
        "app.googleServices" to "Google Services",
        "app.alipay" to "Alipay",
        "app.dingtalk" to "DingTalk",
        "err.bizFailCode" to "Business failure code={0}: {1}",
        "err.bizFailErrcode" to "Business failure errcode={0}: {1}",
        "err.bizFailCodeStatus" to "Business failure code={0} StatusCode={1}: {2}",
        "err.rateLimitErrcode" to "Rate limited errcode={0}: {1}",
        "err.rateLimitCode" to "Rate limited code={0}: {1}",
        "err.telegramChatIdMissing" to "Telegram URL is missing the chat_id parameter",
        "err.pushplusTokenMissing" to "PushPlus URL is missing the token parameter",
        "err.gotifySecretMissing" to "Gotify is missing the app token (secret field)",
        "err.barkBizFail" to "Bark business failure code={0}: {1}",
        "err.serverChanBizFail" to "ServerChan business failure code={0}: {1}",
        "err.pushplusBizFail" to "PushPlus business failure code={0}: {1}",
        "err.genericFail" to "Failed",
        "err.unknownAppChannel" to "Unknown app channel type",
        "err.invalidAddress" to "Invalid address",
        "err.payloadBuild" to "Failed to build payload",
        "err.tokenFetch" to "Failed to fetch token",
        "err.tokenQueued" to "Token fetch failed and was queued for automatic retry; it will be resent after unlock/network recovery · {0}",
        "err.tokenNetwork" to "Token fetch failed (network): {0}",
        "err.queuedRetry" to "Send failed and was queued for automatic retry; it will be resent after unlock/network recovery · {0}",
        "err.wecomMissing" to "WeCom app is missing corpid or corpsecret",
        "err.agentidInvalid" to "agentid is invalid (must be a positive integer)",
        "err.feishuMissing" to "Feishu app is missing app_id or app_secret",
        "err.receiveIdEmpty" to "receive_id must not be empty",
        "err.gettokenNonJson" to "gettoken response is not JSON (gateway/proxy error page?): {0}",
        "err.gettokenFail" to "gettoken failed errcode={0}: {1}",
        "err.tokenMissing" to "gettoken response is missing access_token",
        "err.tenantNonJson" to "tenant_access_token response is not JSON (gateway/proxy error page?): {0}",
        "err.tenantFail" to "tenant_access_token fetch failed code={0}: {1}",
        "err.tenantMissing" to "Response is missing tenant_access_token",
        "err.emptyToken" to "Token endpoint returned an empty access_token",
        "err.httpPrefix" to "API URL must start with http(s)://",
        "err.httpServer" to "Server error HTTP {0}: {1}",
        "err.httpRate" to "Rate limited HTTP 429: {0}",
        "err.httpClient" to "Client error HTTP {0}: {1}",
        "err.nonJson" to "Response is not JSON; delivery cannot be confirmed: {0}",
        "err.noWebhook" to "No Webhook channel configured",
        "err.emailQueueRemoved" to "Automatic resend failed: the email channel was removed or disabled",
        "err.emailResent" to "Email sent (automatic resend)",
        "err.pushException" to "Push error: {0}",
        "err.testEmailException" to "Test email error: {0}",
        "notif.channelName" to "Background service",
        "notif.channelDesc" to "Foreground service for notification listening and Fnthink receiving",
        "notif.noTitle" to "(No title)",
        "merge.listSep" to ", ",
        "merge.listMore" to "{0} and more",
        "test.appChannelMessage" to "This is a test message — the self-built app channel is configured correctly!",
        "test.deviceLine" to "Device: {0}",
        "test.signedLabel" to " [signed]",
        "test.exception" to "Test error: {0}",
        "export.success" to "Exported",
        "export.writeFailed" to "Write failed: {0}",
        "export.canceled" to "Canceled",
        "export.noArchiveDir" to "No custom archive directory configured",
        "export.createFileFailed" to "Failed to create file",
        "export.openStreamFailed" to "Failed to open output stream",
        "download.unknown" to "Unknown error",
        "download.fileError" to "File error",
        "download.httpStatus" to "Server returned an error status (HTTP error)",
        "download.dataError" to "Network data error",
        "download.redirects" to "Too many redirects",
        "download.space" to "Insufficient storage",
        "download.deviceNotFound" to "Device not found",
        "download.cannotResume" to "Cannot resume download",
        "download.exists" to "File already exists",
        "download.blocked" to "Download blocked",
        "download.cannotOverwrite" to "Cannot overwrite file",
        "download.notFound" to "File not found (server 404)",
        "fn.err.identityUnavailable" to "Identity key unavailable",
        "fn.err.canonicalEmpty" to "canonicalBase64 must not be empty",
        "fn.err.signFailed" to "Signing failed",
        "fn.err.secondsPositive" to "seconds must be a positive integer",
        "file.err.hash" to "Hash calculation failed",
        "identity.noPrivateKey" to "No identity private key in KeyStore ({0})",
        "identity.publicKeyLost" to "Private key exists but the public key cache and certificate are unreadable; the user must reset the identity explicitly, never swap keys silently",
        "identity.signatureUntrusted" to "Native signature failed independent verification: local Ed25519 is untrusted",
        "identity.wrappedKeyMissing" to "Wrapped private key file is missing while the public key remains; the user must reset the identity explicitly",
    )

    /** 取一条消息（键不存在时回键本身：宁可露出键名，也不静默变空串）。 */
    fun msg(key: String): String =
        (if (isEn) MESSAGES_EN else MESSAGES_ZH)[key] ?: key

    /** 带 `{0}`/`{1}` 占位符的消息。 */
    fun msgf(key: String, vararg args: Any?): String {
        var out = msg(key)
        args.forEachIndexed { i, arg ->
            out = out.replace("{$i}", arg?.toString() ?: "")
        }
        return out
    }
}
