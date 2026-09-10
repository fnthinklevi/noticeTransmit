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
    fun channelName(type: WebhookPayloadBuilder.WebhookType): String = when (type) {
        WebhookPayloadBuilder.WebhookType.WECHAT_WORK -> if (isEn) "WeCom" else "企业微信"
        WebhookPayloadBuilder.WebhookType.DINGTALK -> if (isEn) "DingTalk" else "钉钉"
        WebhookPayloadBuilder.WebhookType.FEISHU -> if (isEn) "Feishu" else "飞书"
        WebhookPayloadBuilder.WebhookType.TELEGRAM -> "Telegram"
        WebhookPayloadBuilder.WebhookType.BARK -> "Bark"
        WebhookPayloadBuilder.WebhookType.SERVER_CHAN -> if (isEn) "ServerChan" else "Server酱"
        WebhookPayloadBuilder.WebhookType.PUSH_PLUS -> "PushPlus"
        WebhookPayloadBuilder.WebhookType.GENERIC -> if (isEn) "Generic" else "通用"
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
    fun serviceListenerDisconnected(): String = if (isEn)
        "Listener disconnected · notifications may be missed, please check Notification Access"
        else "监听已断开 · 可能漏读通知，请检查通知使用权"
    fun actionPausePush(): String = if (isEn) "Pause push" else "暂停推送"
    fun actionResumePush(): String = if (isEn) "Resume push" else "恢复推送"

    // ========== 聚合推送（P2 merge 动作） ==========
    /** 聚合通知标题：{appName} 合并推送 (N 条) */
    fun mergePushTitle(appName: String, count: Int): String =
        if (isEn) "$appName merged push ($count)"
        else "$appName 合并推送 ($count 条)"

    /** 成员记录送达补标文案（MERGE 伪通道，success） */
    fun mergeDeliveredLabel(): String = if (isEn) "Delivered as merged push" else "已合并推送"

    /** 前台通知聚合预览：摘要行 */
    fun mergePendingSummary(count: Int): String =
        if (isEn) "Merging $count notification(s)…" else "正在合并 $count 条通知…"

    /** 前台通知聚合预览：每组一行的尾注（剩余秒数） */
    fun mergeEta(seconds: Long): String =
        if (isEn) "push in ${seconds}s" else "${seconds}s 后推送"

    // ========== 桌面小部件 ==========
    fun widgetActiveText(): String = if (isEn) "PUSHING" else "推送中"
    fun widgetPausedText(): String = if (isEn) "PAUSED" else "已暂停"
    fun widgetTapPause(): String = if (isEn) "Tap to pause push" else "点击暂停推送"
    fun widgetTapResume(): String = if (isEn) "Tap to resume push" else "点击恢复推送"
    fun widgetDailyPushed(): String = if (isEn) "Pushed today" else "当日已推送"
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
}
