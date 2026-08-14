package com.fnthink.notice

import org.json.JSONObject

object WebhookPayloadBuilder {

    enum class WebhookType {
        GENERIC,
        WECHAT_WORK,
        DINGTALK,
        FEISHU,
        TELEGRAM,
        BARK
    }

    /** 平台 host 匹配规则（新增平台只需追加一行） */
    data class PlatformRule(val type: WebhookType, val hosts: List<String>)

    val PLATFORM_RULES = listOf(
        PlatformRule(WebhookType.WECHAT_WORK, listOf("qyapi.weixin.qq.com")),
        PlatformRule(WebhookType.DINGTALK, listOf("oapi.dingtalk.com")),
        PlatformRule(WebhookType.FEISHU, listOf("open.feishu.cn", "open.larksuite.com")),
        PlatformRule(WebhookType.TELEGRAM, listOf("api.telegram.org")),
        PlatformRule(WebhookType.BARK, listOf("api.day.app", "bark.gugu.ovh")),
    )

    /**
     * 根据 URL 猜测 webhook 平台类型（仅作为兜底，准确类型应由 DB channel_type 字段提供）。
     * 遍历 [PLATFORM_RULES] 做 host 精确匹配，新增平台只需在规则列表中追加一行。
     */
    fun detectType(url: String): WebhookType {
        val host = extractHost(url) ?: return WebhookType.GENERIC
        for (rule in PLATFORM_RULES) {
            if (host in rule.hosts) return rule.type
        }
        return WebhookType.GENERIC
    }

    /**
     * 从 URL 中提取 host（小写），失败返回 null。
     * 示例：
     *   "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxx" → "qyapi.weixin.qq.com"
     *   "qyapi.weixin.qq.com/cgi-bin/webhook/send" → "qyapi.weixin.qq.com"
     *   "not a url" → null
     */
    private fun extractHost(url: String): String? {
        val lower = url.trim().lowercase()
        if (lower.isEmpty()) return null
        // 去掉协议
        val noProto = when {
            lower.startsWith("https://") -> lower.substring(8)
            lower.startsWith("http://") -> lower.substring(7)
            else -> lower
        }
        // 去掉 path / query / port
        val endIdx = noProto.indexOfAny(charArrayOf('/', '?', '#'))
        val hostPort = if (endIdx >= 0) noProto.substring(0, endIdx) else noProto
        if (hostPort.isEmpty()) return null
        // 去掉 credentials（user:pass@host）中的 userinfo 部分，与 Dart 端 _extractHost 保持一致
        val atIdx = hostPort.lastIndexOf('@')
        val hostWithOptionalPort = if (atIdx >= 0) hostPort.substring(atIdx + 1) else hostPort
        // 去掉端口（不区分 IPv6，webhook URL 实际不会用到 IPv6 字面量 host）
        val host = hostWithOptionalPort.substringBeforeLast(':')
        return host.takeIf { it.isNotEmpty() }
    }

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
        return when (type) {
            WebhookType.GENERIC -> buildGeneric(
                title = title,
                content = content,
                appName = appName,
                packageName = packageName,
                time = time,
                deviceName = deviceName,
                notifyType = notifyType,
                extras = extras
            )
            WebhookType.WECHAT_WORK -> buildWeChatWork(
                title = title,
                content = content,
                appName = appName,
                time = time,
                deviceName = deviceName,
                notifyType = notifyType
            )
            WebhookType.DINGTALK -> buildDingTalk(
                title = title,
                content = content,
                appName = appName,
                time = time,
                deviceName = deviceName,
                notifyType = notifyType
            )
            WebhookType.FEISHU -> buildFeishu(
                title = title,
                content = content,
                appName = appName,
                time = time,
                deviceName = deviceName,
                notifyType = notifyType
            )
            WebhookType.TELEGRAM -> buildTelegram(
                title = title,
                content = content,
                appName = appName,
                time = time,
                deviceName = deviceName,
                notifyType = notifyType,
                chatId = chatId
            )
            WebhookType.BARK -> buildBark(
                title = title,
                content = content,
                appName = appName,
                time = time,
                deviceName = deviceName,
                notifyType = notifyType
            )
        }
    }

    fun buildTestPayload(type: WebhookType, deviceName: String, chatId: String = ""): String {
        val title = I18n.testTitle()
        val content = I18n.testContent()
        val deviceLabel = I18n.testDeviceLabel()
        val sep = I18n.labelSeparator()

        return when (type) {
            WebhookType.GENERIC -> JSONObject().apply {
                put("type", "test")
                put("title", title)
                put("content", content)
                put("deviceName", deviceName)
                put("timestamp", System.currentTimeMillis())
            }.toString()

            WebhookType.WECHAT_WORK -> JSONObject().apply {
                put("msgtype", "text")
                put("text", JSONObject().apply {
                    put("content", "${I18n.bracket(title)}\n$content\n\n$deviceLabel$sep$deviceName")
                })
            }.toString()

            WebhookType.DINGTALK -> JSONObject().apply {
                put("msgtype", "text")
                put("text", JSONObject().apply {
                    put("content", "${I18n.bracket(title)}\n$content\n\n$deviceLabel$sep$deviceName")
                })
            }.toString()

            WebhookType.FEISHU -> JSONObject().apply {
                put("msg_type", "text")
                put("content", JSONObject().apply {
                    put("text", "${I18n.bracket(title)}\n$content\n\n$deviceLabel$sep$deviceName")
                })
            }.toString()

            WebhookType.TELEGRAM -> buildTelegramMessage(
                "${I18n.bracket(title)}\n$content\n\n$deviceLabel$sep$deviceName",
                chatId
            )

            WebhookType.BARK -> JSONObject().apply {
                put("title", title)
                put("body", "$content\n\n$deviceLabel$sep$deviceName")
            }.toString()
        }
    }

    private fun buildGeneric(
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
    private fun buildTextBody(
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
        simInfo: String? = null
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
        if (simInfo != null) sb.append("\n${I18n.simCardLabel()}$sep$simInfo")

        return sb.toString()
    }

    private fun buildWeChatWork(
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

    private fun buildDingTalk(
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

    private fun buildFeishu(
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

    private fun buildTelegram(
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

    private fun buildBark(
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

    fun buildSmsPayload(
        type: WebhookType,
        sender: String,
        message: String,
        time: String,
        deviceName: String,
        simInfo: String? = null,
        chatId: String = ""
    ): String {
        val simSuffix = I18n.simSuffix(simInfo)
        // SMS 标题（用于通用类型 JSON）
        val title = I18n.smsNotifyTitle(sender, null)

        return when (type) {
            WebhookType.GENERIC -> JSONObject().apply {
                put("type", "sms")
                put("sender", sender)
                put("message", message)
                put("time", time)
                put("deviceName", deviceName)
                put("timestamp", System.currentTimeMillis())
                if (simInfo != null) put("simInfo", simInfo)
            }.toString()

            WebhookType.WECHAT_WORK -> JSONObject().apply {
                put("msgtype", "text")
                put("text", JSONObject().apply {
                    put("content", buildTextBody(
                        title = title, content = "", appName = "",
                        time = time, deviceName = deviceName,
                        sender = sender, message = message, simInfo = simInfo
                    ))
                })
            }.toString()

            WebhookType.DINGTALK -> JSONObject().apply {
                put("msgtype", "text")
                put("text", JSONObject().apply {
                    put("content", buildTextBody(
                        title = title, content = "", appName = "",
                        time = time, deviceName = deviceName,
                        sender = sender, message = message, simInfo = simInfo
                    ))
                })
            }.toString()

            WebhookType.FEISHU -> JSONObject().apply {
                put("msg_type", "text")
                put("content", JSONObject().apply {
                    put("text", buildTextBody(
                        title = title, content = "", appName = "",
                        time = time, deviceName = deviceName,
                        sender = sender, message = message, simInfo = simInfo
                    ))
                })
            }.toString()

            WebhookType.TELEGRAM -> buildTelegramMessage(
                buildTextBody(
                    title = title, content = "", appName = "",
                    time = time, deviceName = deviceName,
                    sender = sender, message = message, simInfo = simInfo
                ),
                chatId
            )

            WebhookType.BARK -> JSONObject().apply {
                put("title", title)
                put("body", buildTextBody(
                    title = "", content = "", appName = "",
                    time = time, deviceName = deviceName,
                    sender = sender, message = message, simInfo = simInfo
                ))
            }.toString()
        }
    }

    fun buildCallPayload(
        type: WebhookType,
        state: String,
        phoneNumber: String,
        time: String,
        durationStr: String = "",
        deviceName: String,
        simInfo: String? = null,
        chatId: String = ""
    ): String {
        return when (type) {
            WebhookType.GENERIC -> JSONObject().apply {
                put("type", "call_$state")
                put("phoneNumber", phoneNumber)
                put("callState", state)
                put("time", time)
                if (durationStr.isNotEmpty()) put("duration", durationStr)
                put("deviceName", deviceName)
                put("timestamp", System.currentTimeMillis())
                if (simInfo != null) put("simInfo", simInfo)
            }.toString()

            WebhookType.WECHAT_WORK -> JSONObject().apply {
                put("msgtype", "text")
                put("text", JSONObject().apply {
                    put("content", buildTextBody(
                        title = "", content = "", appName = "",
                        time = time, deviceName = deviceName,
                        state = state, phoneNumber = phoneNumber,
                        durationStr = durationStr, simInfo = simInfo
                    ))
                })
            }.toString()

            WebhookType.DINGTALK -> JSONObject().apply {
                put("msgtype", "text")
                put("text", JSONObject().apply {
                    put("content", buildTextBody(
                        title = "", content = "", appName = "",
                        time = time, deviceName = deviceName,
                        state = state, phoneNumber = phoneNumber,
                        durationStr = durationStr, simInfo = simInfo
                    ))
                })
            }.toString()

            WebhookType.FEISHU -> JSONObject().apply {
                put("msg_type", "text")
                put("content", JSONObject().apply {
                    put("text", buildTextBody(
                        title = "", content = "", appName = "",
                        time = time, deviceName = deviceName,
                        state = state, phoneNumber = phoneNumber,
                        durationStr = durationStr, simInfo = simInfo
                    ))
                })
            }.toString()

            WebhookType.TELEGRAM -> buildTelegramMessage(
                buildTextBody(
                    title = "", content = "", appName = "",
                    time = time, deviceName = deviceName,
                    state = state, phoneNumber = phoneNumber,
                    durationStr = durationStr, simInfo = simInfo
                ),
                chatId
            )

            WebhookType.BARK -> JSONObject().apply {
                put("title", I18n.callNotifyTitle(state, phoneNumber, simInfo))
                put("body", buildTextBody(
                    title = "", content = "", appName = "",
                    time = time, deviceName = deviceName,
                    state = state, phoneNumber = phoneNumber,
                    durationStr = durationStr, simInfo = simInfo
                ))
            }.toString()
        }
    }
}
