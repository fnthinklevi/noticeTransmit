package com.fnthink.notice

import org.json.JSONObject

object WebhookPayloadBuilder {

    enum class WebhookType {
        GENERIC,
        WECHAT_WORK,
        DINGTALK,
        FEISHU
    }

    /**
     * 根据 URL 猜测 webhook 平台类型（仅作为兜底，准确类型应由 DB channel_type 字段提供）。
     *
     * 精确匹配规则（避免误判）：
     * - 企业微信群机器人：host == qyapi.weixin.qq.com
     * - 钉钉群机器人：host == oapi.dingtalk.com
     * - 飞书群机器人：host 后缀 == open.feishu.cn / open.larksuite.com
     *
     * 已修正的历史误判：
     * - 旧逻辑 `url.contains("weixin.qq.com")` 会误匹配任意微信相关域名
     * - 旧逻辑 `url.contains("dingtalk")` 会误匹配自定义域名中的 dingtalk 字样
     * - 旧逻辑 `url.contains("feishu.cn")` 会误匹配 feishu.cn 子域
     */
    fun detectType(url: String): WebhookType {
        val host = extractHost(url) ?: return WebhookType.GENERIC
        return when {
            host == "qyapi.weixin.qq.com" -> WebhookType.WECHAT_WORK
            host == "oapi.dingtalk.com" -> WebhookType.DINGTALK
            host == "open.feishu.cn" || host == "open.larksuite.com" -> WebhookType.FEISHU
            else -> WebhookType.GENERIC
        }
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
        // 去掉端口（不区分 IPv6，webhook URL 实际不会用到 IPv6 字面量 host）
        val host = hostPort.substringBeforeLast(':')
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
                deviceName = deviceName
            )
            WebhookType.FEISHU -> buildFeishu(
                title = title,
                content = content,
                appName = appName,
                time = time,
                deviceName = deviceName
            )
        }
    }

    fun buildTestPayload(type: WebhookType, deviceName: String): String {
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
            notifyType == "battery_charging" -> I18n.chargingLabel()
            notifyType == "battery_full" -> I18n.batteryFullLabel()
            notifyType == "battery_low_30" || notifyType == "battery_low_20" -> I18n.lowBatteryLabel()
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
        deviceName: String
    ): String {
        val text = buildTextBody(
            title = title, content = content, appName = appName,
            time = time, deviceName = deviceName
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
        deviceName: String
    ): String {
        val text = buildTextBody(
            title = title, content = content, appName = appName,
            time = time, deviceName = deviceName
        )
        return JSONObject().apply {
            put("msg_type", "text")
            put("content", JSONObject().apply { put("text", text) })
        }.toString()
    }

    fun buildSmsPayload(
        type: WebhookType,
        sender: String,
        message: String,
        time: String,
        deviceName: String,
        simInfo: String? = null
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
        }
    }

    fun buildCallPayload(
        type: WebhookType,
        state: String,
        phoneNumber: String,
        time: String,
        durationStr: String = "",
        deviceName: String,
        simInfo: String? = null
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
        }
    }
}
