package com.fnthink.notice

import org.json.JSONObject
import java.net.URLEncoder

object WebhookPayloadBuilder {

    enum class WebhookType {
        GENERIC,
        WECHAT_WORK,
        DINGTALK,
        FEISHU,
        TELEGRAM,
        BARK,
        SERVER_CHAN,
        PUSH_PLUS
    }


    /**
     * 根据 URL 猜测 webhook 平台类型（仅作为兜底，准确类型应由 DB channel_type 字段提供）。
     * 遍历 [PLATFORM_RULES] 做 host 精确匹配，新增平台只需在规则列表中追加一行。
     */
    /** 自动识别通道类型：host 规则集中在 ChannelRegistry 描述符表；无匹配回退 GENERIC */
    fun detectType(url: String): WebhookType {
        val host = ChannelRegistry.extractHost(url) ?: return WebhookType.GENERIC
        return ChannelRegistry.typeByHost(host) ?: WebhookType.GENERIC
    }


    /**
     * 构造通知载荷 —— 分派经 [ChannelRegistry] 描述符表（新增通道只需改表）。
     */
    fun buildPayload(
        type: WebhookType,
        title: String,
        content: String,
        appName: String = "",
        packageName: String = "",
        time: String = "",
        deviceName: String = "",
        notifyType: String = "",
        chatId: String = "",
        extras: Map<String, String> = emptyMap()
    ): String {
        return ChannelRegistry.spec(type).notify(
            NotifyInput(
                title = title, content = content, appName = appName,
                packageName = packageName, time = time, deviceName = deviceName,
                notifyType = notifyType, chatId = chatId, extras = extras,
            )
        )
    }

    /** 构造测试发送载荷（文案取自 I18n，分派经描述符表） */
    fun buildTestPayload(type: WebhookType, deviceName: String, chatId: String = ""): String {
        return ChannelRegistry.spec(type).test(
            TestInput(
                title = I18n.testTitle(), content = I18n.testContent(),
                deviceLabel = I18n.testDeviceLabel(), sep = I18n.labelSeparator(),
                deviceName = deviceName, chatId = chatId,
            )
        )
    }

    internal fun buildGeneric(
        title: String,
        content: String,
        appName: String,
        packageName: String,
        time: String,
        deviceName: String,
        notifyType: String,
        extras: Map<String, String>
    ): String {
        return JSONObject().apply {
            put("title", title)
            put("content", content)
            put("appName", appName)
            put("packageName", packageName)
            put("time", time)
            put("deviceName", deviceName)
            put("type", notifyType)
            put("timestamp", System.currentTimeMillis())
            for ((k, v) in extras) {
                put(k, v)
            }
        }.toString()
    }

    /**
     * 构造文本型推送正文（企微/钉钉/飞书通用），所有标签从 I18n 取，支持中英双语
     */
    internal fun buildTextBody(
        title: String,
        content: String,
        appName: String,
        time: String,
        deviceName: String,
        notifyType: String = "",
        state: String? = null,
        phoneNumber: String? = null,
        sender: String? = null,
        message: String? = null,
        durationStr: String? = null,
        simFooter: String? = null
    ): String {
        val sep = I18n.labelSeparator()
        val sb = StringBuilder()

        // 头部标签
        val headLabel = when {
            sender != null && message != null -> I18n.newSmsLabel()
            phoneNumber != null && state != null -> when (state) {
                "ringing" -> I18n.incomingCallLabel()
                "answered" -> I18n.inCallLabel()
                "ended" -> I18n.callEndedLabel()
                else -> I18n.notificationLabel(appName)
            }
            else -> I18n.notificationLabel(appName)
        }
        sb.append("$headLabel\n")

        // SMS 字段
        if (sender != null && message != null) {
            sb.append("${I18n.senderLabel()}$sep$sender\n")
            sb.append("${I18n.messageLabel()}$sep$message\n")
        } else {
            // 通用通知 / 通话字段
            if (phoneNumber != null && state != null) {
                sb.append("${I18n.callerLabel()}$sep$phoneNumber\n")
            } else {
                if (title.isNotEmpty()) sb.append("${I18n.titleLabel()}$sep$title\n")
                if (content.isNotEmpty()) sb.append("${I18n.contentLabel()}$sep$content\n")
            }
            if (durationStr != null && durationStr.isNotEmpty()) {
                sb.append("${I18n.durationLabel()}$sep$durationStr\n")
            }
        }
        if (time.isNotEmpty()) sb.append("${I18n.timeLabel()}$sep$time\n")
        if (deviceName.isNotEmpty()) sb.append("${I18n.deviceLabel()}$sep$deviceName")
        // 底部 SIM 信息行（"卡1，运营商：中国移动"），通知兜底链路无 SIM 信息时不加
        if (simFooter != null) sb.append("\n$simFooter")

        return sb.toString()
    }

    internal fun buildWeChatWork(
        title: String,
        content: String,
        appName: String,
        time: String,
        deviceName: String,
        notifyType: String
    ): String {
        val text = buildTextBody(
            title = title, content = content, appName = appName,
            time = time, deviceName = deviceName, notifyType = notifyType
        )
        return JSONObject().apply {
            put("msgtype", "text")
            put("text", JSONObject().apply { put("content", text) })
        }.toString()
    }

    internal fun buildDingTalk(
        title: String,
        content: String,
        appName: String,
        time: String,
        deviceName: String,
        notifyType: String = ""
    ): String {
        val text = buildTextBody(
            title = title, content = content, appName = appName,
            time = time, deviceName = deviceName, notifyType = notifyType
        )
        return JSONObject().apply {
            put("msgtype", "text")
            put("text", JSONObject().apply { put("content", text) })
        }.toString()
    }

    internal fun buildFeishu(
        title: String,
        content: String,
        appName: String,
        time: String,
        deviceName: String,
        notifyType: String = ""
    ): String {
        val text = buildTextBody(
            title = title, content = content, appName = appName,
            time = time, deviceName = deviceName, notifyType = notifyType
        )
        return JSONObject().apply {
            put("msg_type", "text")
            put("content", JSONObject().apply { put("text", text) })
        }.toString()
    }

    internal fun buildTelegram(
        title: String,
        content: String,
        appName: String,
        time: String,
        deviceName: String,
        notifyType: String = "",
        chatId: String = ""
    ): String {
        val text = buildTextBody(
            title = title, content = content, appName = appName,
            time = time, deviceName = deviceName, notifyType = notifyType
        )
        return buildTelegramMessage(text, chatId)
    }

    /**
     * Telegram sendMessage payload：
     * - 文本截断至 4096 字符（超长会返回 400 并被记为送达失败），不截断代理项对
     * - 注入 chat_id（由 [extractChatIdFromUrl] 从 URL query 提取，缺省时由 URL 承担）
     * - 禁用网页自动预览
     */
    fun buildTelegramMessage(text: String, chatId: String = ""): String {
        val truncated = if (text.length > 4096) {
            var end = 4096
            if (end > 0 && Character.isHighSurrogate(text[end - 1])) end--
            text.substring(0, end)
        } else {
            text
        }
        return JSONObject().apply {
            put("text", truncated)
            if (chatId.isNotEmpty()) put("chat_id", chatId)
            put("disable_web_page_preview", true)
        }.toString()
    }

    /**
     * 从 Telegram webhook URL 的 query 中提取 chat_id（缺失时返回空串）。
     * 例："https://api.telegram.org/bot<token>/sendMessage?chat_id=-100123" → "-100123"
     */
    fun extractChatIdFromUrl(url: String): String {
        val queryStart = url.indexOf('?')
        if (queryStart < 0) return ""
        return url.substring(queryStart + 1)
            .split('&')
            .firstOrNull { it.startsWith("chat_id=") && it.length > "chat_id=".length }
            ?.substringAfter('=') ?: ""
    }

    internal fun buildBark(
        title: String,
        content: String,
        appName: String,
        time: String,
        deviceName: String,
        notifyType: String = ""
    ): String {
        val body = buildTextBody(
            title = "", content = content, appName = appName,
            time = time, deviceName = deviceName, notifyType = notifyType
        )
        return JSONObject().apply {
            put("title", title)
            put("body", body)
        }.toString()
    }

    /** 构造短信载荷（标题按既有规则预构造，分派经描述符表） */
    fun buildSmsPayload(
        type: WebhookType,
        sender: String,
        message: String,
        time: String,
        deviceName: String,
        simInfo: String? = null,
        simFooter: String? = null,
        chatId: String = "",
        titleTag: String = ""
    ): String {
        val simSuffix = I18n.simSuffix(simInfo)
        // SMS 标题（用于通用类型 JSON）；titleTag 为白名单等命中来源备注前缀
        val title = "$titleTag${I18n.smsNotifyTitle(sender, null)}"
        return ChannelRegistry.spec(type).sms(
            SmsInput(
                title = title, sender = sender, message = message, time = time,
                deviceName = deviceName, simInfo = simInfo, simFooter = simFooter,
                chatId = chatId,
            )
        )
    }

    /** 构造通话载荷（分派经描述符表） */
    fun buildCallPayload(
        type: WebhookType,
        state: String,
        phoneNumber: String,
        time: String,
        durationStr: String = "",
        deviceName: String,
        simInfo: String? = null,
        simFooter: String? = null,
        chatId: String = ""
    ): String {
        return ChannelRegistry.spec(type).call(
            CallInput(
                state = state, phoneNumber = phoneNumber, time = time,
                durationStr = durationStr, deviceName = deviceName,
                simInfo = simInfo, simFooter = simFooter, chatId = chatId,
            )
        )
    }

    fun buildServerChanFormBody(
        title: String,
        content: String,
        deviceName: String,
        time: String = ""
    ): String {
        val desp = buildTextBody(
            title = title, content = content, appName = "",
            time = time, deviceName = deviceName
        )
        return "title=${urlEncode(title)}&desp=${urlEncode(desp)}"
    }

    /**
     * 从 URL query 中提取 token（PushPlus 使用），缺失时返回空串。
     * 例："https://www.pushplus.plus/send?token=abc123" → "abc123"
     */
    fun extractTokenFromUrl(url: String): String {
        val queryStart = url.indexOf('?')
        if (queryStart < 0) return ""
        return url.substring(queryStart + 1)
            .split('&')
            .firstOrNull { it.startsWith("token=") && it.length > "token=".length }
            ?.substringAfter('=') ?: ""
    }

    /**
     * PushPlus payload：POST JSON，token 由 [extractTokenFromUrl] 从 URL query 提取。
     * 接口：https://www.pushplus.plus/send
     * 响应：{"code":200,"msg":"发送成功"}（code==200 成功）
     */
    fun buildPushPlusPayload(
        title: String,
        content: String,
        deviceName: String,
        time: String,
        token: String
    ): String {
        val body = buildTextBody(
            title = title, content = content, appName = "",
            time = time, deviceName = deviceName
        )
        return JSONObject().apply {
            put("token", token)
            put("title", title)
            put("content", body)
            put("template", "txt")
            put("channel", "wechat")
        }.toString()
    }

    private fun urlEncode(value: String): String = URLEncoder.encode(value, "UTF-8")
}
