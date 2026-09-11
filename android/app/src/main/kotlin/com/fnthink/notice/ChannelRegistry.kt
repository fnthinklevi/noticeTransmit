package com.fnthink.notice

import org.json.JSONObject

/**
 * 通道描述符表（**新增通道的唯一改动点**）。
 *
 * 背景：此前「加一个通道」需要改 6 处散落的 `when`（host 识别 / 通知载荷 / 测试载荷 /
 * 短信载荷 / 电话载荷 / 模板平台 JSON / 响应判定），漏改一处即静默失效
 * （典型表现：能推送但状态永远"发送中"、或测试按钮失败）。现全部收敛到本表：
 * **新增通道 = 加一个枚举值 + 在本表加一行（表内以 lambda 提供各载荷与判定）**。
 *
 * 完整性由守卫测试锁定：`ChannelRegistryTest` 断言「每个枚举值都有表项、
 * 表项四类载荷齐全、host 规则不重复」——漏登记会直接测试失败。
 *
 * ⚠ 行为等价性由 `ChannelBehaviorGoldenTest` 的逐字节快照锁定（32 条载荷 + 26 条解析）。
 * 表内 lambda 体为既有分支代码的**原文搬迁**（开头解构参数以避免改名引入漂移），
 * 修改任何一条都会触发快照对比失败——这是有意设计：通道行为变更必须显式更新快照。
 */
internal class NotifyInput(
    val title: String,
    val content: String,
    val appName: String,
    val packageName: String,
    val time: String,
    val deviceName: String,
    val notifyType: String,
    val chatId: String,
    val extras: Map<String, String>,
)

internal class TestInput(
    val title: String,
    val content: String,
    val deviceLabel: String,
    val sep: String,
    val deviceName: String,
    val chatId: String,
)

internal class SmsInput(
    val title: String,
    val sender: String,
    val message: String,
    val time: String,
    val deviceName: String,
    val simInfo: String?,
    val simFooter: String?,
    val chatId: String,
)

internal class CallInput(
    val state: String,
    val phoneNumber: String,
    val time: String,
    val durationStr: String,
    val deviceName: String,
    val simInfo: String?,
    val simFooter: String?,
    val chatId: String,
)

/**
 * 单个通道的完整描述：host 识别 + 四类载荷构造 + 响应判定 + 模板平台 JSON。
 * [notify]/[test]/[sms]/[call] 为必填；[parse]/[platformJson] 允许 null（走通用兜底）。
 */
internal class ChannelSpec(
    val type: WebhookPayloadBuilder.WebhookType,
    val hosts: List<String>,
    val notify: (NotifyInput) -> String,
    val test: (TestInput) -> String,
    val sms: (SmsInput) -> String,
    val call: (CallInput) -> String,
    /**
     * 响应成功判定（httpCode、已解析 JSON、原始 body）。
     * 调用方仅在 body 可解析为 JSON 时调用（`json` 因此非空，实现内以 `!!` 解构）；
     * body 非 JSON 的兜底判定由 `WebhookResponseParser` 外层统一处理。
     */
    val parse: ((Int, JSONObject?, String) -> WebhookResponseParser.ParseResult)? = null,
    /**
     * 平台模板包装（自定义模板 + 平台 msgtype 格式时走此分支）。
     * 入参：vars 变量、rendered 模板渲染结果、format 消息格式、chatId（Telegram 用）。
     * 返回该通道的最终请求体；null = 该通道不支持平台模板包装（走文本/独立发送路径）。
     */
    val platformPayload: ((TemplateEngine.Vars, String, String, String) -> String?)? = null,
)

internal object ChannelRegistry {
    /** 全部通道（顺序即 host 匹配优先级） */
    val CHANNELS: List<ChannelSpec> = listOf(
    ChannelSpec(
        type = WebhookPayloadBuilder.WebhookType.GENERIC,
        hosts = emptyList(),
        notify = { p ->
            val title = p.title; val content = p.content; val appName = p.appName
            val packageName = p.packageName; val time = p.time; val deviceName = p.deviceName
            val notifyType = p.notifyType; val chatId = p.chatId; val extras = p.extras
         WebhookPayloadBuilder.buildGeneric(
                        title = title,
                        content = content,
                        appName = appName,
                        packageName = packageName,
                        time = time,
                        deviceName = deviceName,
                        notifyType = notifyType,
                        extras = extras
                    )
        },
        test = { p ->
            val title = p.title; val content = p.content; val deviceLabel = p.deviceLabel
            val sep = p.sep; val deviceName = p.deviceName; val chatId = p.chatId
         JSONObject().apply {
                        put("type", "test")
                        put("title", title)
                        put("content", content)
                        put("deviceName", deviceName)
                        put("timestamp", System.currentTimeMillis())
                    }.toString()
        },
        sms = { p ->
            val title = p.title; val sender = p.sender; val message = p.message
            val time = p.time; val deviceName = p.deviceName
            val simInfo = p.simInfo; val simFooter = p.simFooter; val chatId = p.chatId
         JSONObject().apply {
                        put("type", "sms")
                        put("sender", sender)
                        put("message", message)
                        put("time", time)
                        put("deviceName", deviceName)
                        put("timestamp", System.currentTimeMillis())
                        if (simInfo != null) put("simInfo", simInfo)
                    }.toString()
        },
        call = { p ->
            val state = p.state; val phoneNumber = p.phoneNumber; val time = p.time
            val durationStr = p.durationStr; val deviceName = p.deviceName
            val simInfo = p.simInfo; val simFooter = p.simFooter; val chatId = p.chatId
         JSONObject().apply {
                        put("type", "call_$state")
                        put("phoneNumber", phoneNumber)
                        put("callState", state)
                        put("time", time)
                        if (durationStr.isNotEmpty()) put("duration", durationStr)
                        put("deviceName", deviceName)
                        put("timestamp", System.currentTimeMillis())
                        if (simInfo != null) put("simInfo", simInfo)
                    }.toString()
        },
        parse = { httpCode, jsonOrNull, rawBody ->
            val json = jsonOrNull!!
                // 通用 webhook：尝试解析 code 字段，0 为成功；否则视为 HTTP 成功
                val code = json.optInt("code", -1)
                val message = json.optString("message", json.optString("msg", ""))
                if (json.has("code") && code != 0) {
                    WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.BIZ_FAIL, httpCode,
                        "业务失败 code=$code: $message", false
                    )
                } else {
                    WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.SUCCESS, httpCode,
                        if (message.isNotEmpty()) message else "OK", false
                    )
                }
        },
    ),
    ChannelSpec(
        type = WebhookPayloadBuilder.WebhookType.WECHAT_WORK,
        hosts = listOf("qyapi.weixin.qq.com"),
        notify = { p ->
            val title = p.title; val content = p.content; val appName = p.appName
            val packageName = p.packageName; val time = p.time; val deviceName = p.deviceName
            val notifyType = p.notifyType; val chatId = p.chatId; val extras = p.extras
         WebhookPayloadBuilder.buildWeChatWork(
                        title = title,
                        content = content,
                        appName = appName,
                        time = time,
                        deviceName = deviceName,
                        notifyType = notifyType
                    )
        },
        test = { p ->
            val title = p.title; val content = p.content; val deviceLabel = p.deviceLabel
            val sep = p.sep; val deviceName = p.deviceName; val chatId = p.chatId
         JSONObject().apply {
                        put("msgtype", "text")
                        put("text", JSONObject().apply {
                            put("content", "${I18n.bracket(title)}\n$content\n\n$deviceLabel$sep$deviceName")
                        })
                    }.toString()
        },
        sms = { p ->
            val title = p.title; val sender = p.sender; val message = p.message
            val time = p.time; val deviceName = p.deviceName
            val simInfo = p.simInfo; val simFooter = p.simFooter; val chatId = p.chatId
         JSONObject().apply {
                        put("msgtype", "text")
                        put("text", JSONObject().apply {
                            put("content", WebhookPayloadBuilder.buildTextBody(
                                title = title, content = "", appName = "",
                                time = time, deviceName = deviceName,
                                sender = sender, message = message, simFooter = simFooter
                            ))
                        })
                    }.toString()
        },
        call = { p ->
            val state = p.state; val phoneNumber = p.phoneNumber; val time = p.time
            val durationStr = p.durationStr; val deviceName = p.deviceName
            val simInfo = p.simInfo; val simFooter = p.simFooter; val chatId = p.chatId
         JSONObject().apply {
                        put("msgtype", "text")
                        put("text", JSONObject().apply {
                            put("content", WebhookPayloadBuilder.buildTextBody(
                                title = "", content = "", appName = "",
                                time = time, deviceName = deviceName,
                                state = state, phoneNumber = phoneNumber,
                                durationStr = durationStr, simFooter = simFooter
                            ))
                        })
                    }.toString()
        },
        platformPayload = { vars, rendered, format, chatId ->
 JSONObject().apply {
                put("msgtype", format) // text / markdown
                if (format == "markdown") {
                    put("markdown", JSONObject().apply { put("content", rendered) })
                } else {
                    put("text", JSONObject().apply { put("content", rendered) })
                }
            }.toString()
        },
        parse = { httpCode, jsonOrNull, rawBody ->
            val json = jsonOrNull!!
                // errcode == 0 为成功
                val errcode = json.optInt("errcode", -1)
                val errmsg = json.optString("errmsg", "")
                when {
                    errcode == 0 -> WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.SUCCESS, httpCode,
                        if (errmsg.isNotEmpty()) errmsg else "OK", false
                    )
                    errcode == 45009 -> WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.RATE_LIMITED, httpCode,
                        "限流 errcode=$errcode: $errmsg", true
                    )
                    errcode == 130101 -> WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.RATE_LIMITED, httpCode,
                        "限流 errcode=$errcode: $errmsg", true
                    )
                    else -> WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.BIZ_FAIL, httpCode,
                        "业务失败 errcode=$errcode: $errmsg", false
                    )
                }
        },
    ),
    ChannelSpec(
        type = WebhookPayloadBuilder.WebhookType.DINGTALK,
        hosts = listOf("oapi.dingtalk.com"),
        notify = { p ->
            val title = p.title; val content = p.content; val appName = p.appName
            val packageName = p.packageName; val time = p.time; val deviceName = p.deviceName
            val notifyType = p.notifyType; val chatId = p.chatId; val extras = p.extras
         WebhookPayloadBuilder.buildDingTalk(
                        title = title,
                        content = content,
                        appName = appName,
                        time = time,
                        deviceName = deviceName,
                        notifyType = notifyType
                    )
        },
        test = { p ->
            val title = p.title; val content = p.content; val deviceLabel = p.deviceLabel
            val sep = p.sep; val deviceName = p.deviceName; val chatId = p.chatId
         JSONObject().apply {
                        put("msgtype", "text")
                        put("text", JSONObject().apply {
                            put("content", "${I18n.bracket(title)}\n$content\n\n$deviceLabel$sep$deviceName")
                        })
                    }.toString()
        },
        sms = { p ->
            val title = p.title; val sender = p.sender; val message = p.message
            val time = p.time; val deviceName = p.deviceName
            val simInfo = p.simInfo; val simFooter = p.simFooter; val chatId = p.chatId
         JSONObject().apply {
                        put("msgtype", "text")
                        put("text", JSONObject().apply {
                            put("content", WebhookPayloadBuilder.buildTextBody(
                                title = title, content = "", appName = "",
                                time = time, deviceName = deviceName,
                                sender = sender, message = message, simFooter = simFooter
                            ))
                        })
                    }.toString()
        },
        call = { p ->
            val state = p.state; val phoneNumber = p.phoneNumber; val time = p.time
            val durationStr = p.durationStr; val deviceName = p.deviceName
            val simInfo = p.simInfo; val simFooter = p.simFooter; val chatId = p.chatId
         JSONObject().apply {
                        put("msgtype", "text")
                        put("text", JSONObject().apply {
                            put("content", WebhookPayloadBuilder.buildTextBody(
                                title = "", content = "", appName = "",
                                time = time, deviceName = deviceName,
                                state = state, phoneNumber = phoneNumber,
                                durationStr = durationStr, simFooter = simFooter
                            ))
                        })
                    }.toString()
        },
        platformPayload = { vars, rendered, format, chatId ->
 JSONObject().apply {
                put("msgtype", format)
                if (format == "markdown") {
                    put("markdown", JSONObject().apply {
                        put("title", vars.title)
                        put("text", rendered)
                    })
                } else {
                    put("text", JSONObject().apply { put("content", rendered) })
                }
            }.toString()

            // 飞书自定义机器人不支持 markdown msg_type（仅 text/post/image/interactive），
            // markdown 格式降级为 text 发送渲染后的文本，保证送达。
        },
        parse = { httpCode, jsonOrNull, rawBody ->
            val json = jsonOrNull!!
                // errcode == 0 为成功
                val errcode = json.optInt("errcode", -1)
                val errmsg = json.optString("errmsg", "")
                when {
                    errcode == 0 -> WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.SUCCESS, httpCode,
                        if (errmsg.isNotEmpty()) errmsg else "OK", false
                    )
                    errcode == 45009 -> WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.RATE_LIMITED, httpCode,
                        "限流 errcode=$errcode: $errmsg", true
                    )
                    errcode == 130101 -> WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.RATE_LIMITED, httpCode,
                        "限流 errcode=$errcode: $errmsg", true
                    )
                    else -> WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.BIZ_FAIL, httpCode,
                        "业务失败 errcode=$errcode: $errmsg", false
                    )
                }
        },
    ),
    ChannelSpec(
        type = WebhookPayloadBuilder.WebhookType.FEISHU,
        hosts = listOf("open.feishu.cn", "open.larksuite.com"),
        notify = { p ->
            val title = p.title; val content = p.content; val appName = p.appName
            val packageName = p.packageName; val time = p.time; val deviceName = p.deviceName
            val notifyType = p.notifyType; val chatId = p.chatId; val extras = p.extras
         WebhookPayloadBuilder.buildFeishu(
                        title = title,
                        content = content,
                        appName = appName,
                        time = time,
                        deviceName = deviceName,
                        notifyType = notifyType
                    )
        },
        test = { p ->
            val title = p.title; val content = p.content; val deviceLabel = p.deviceLabel
            val sep = p.sep; val deviceName = p.deviceName; val chatId = p.chatId
         JSONObject().apply {
                        put("msg_type", "text")
                        put("content", JSONObject().apply {
                            put("text", "${I18n.bracket(title)}\n$content\n\n$deviceLabel$sep$deviceName")
                        })
                    }.toString()
        },
        sms = { p ->
            val title = p.title; val sender = p.sender; val message = p.message
            val time = p.time; val deviceName = p.deviceName
            val simInfo = p.simInfo; val simFooter = p.simFooter; val chatId = p.chatId
         JSONObject().apply {
                        put("msg_type", "text")
                        put("content", JSONObject().apply {
                            put("text", WebhookPayloadBuilder.buildTextBody(
                                title = title, content = "", appName = "",
                                time = time, deviceName = deviceName,
                                sender = sender, message = message, simFooter = simFooter
                            ))
                        })
                    }.toString()
        },
        call = { p ->
            val state = p.state; val phoneNumber = p.phoneNumber; val time = p.time
            val durationStr = p.durationStr; val deviceName = p.deviceName
            val simInfo = p.simInfo; val simFooter = p.simFooter; val chatId = p.chatId
         JSONObject().apply {
                        put("msg_type", "text")
                        put("content", JSONObject().apply {
                            put("text", WebhookPayloadBuilder.buildTextBody(
                                title = "", content = "", appName = "",
                                time = time, deviceName = deviceName,
                                state = state, phoneNumber = phoneNumber,
                                durationStr = durationStr, simFooter = simFooter
                            ))
                        })
                    }.toString()
        },
        platformPayload = { vars, rendered, format, chatId ->
 JSONObject().apply {
                put("msg_type", "text")
                put("content", JSONObject().apply { put("text", rendered) })
            }.toString()
        },
        parse = { httpCode, jsonOrNull, rawBody ->
            val json = jsonOrNull!!
                // 飞书 code == 0 / StatusCode == 0 / FalconCode == 0 为成功
                val code = json.optInt("code", -1)
                val statusCode = json.optInt("StatusCode", -1)
                val falconCode = json.optInt("FalconCode", -1)
                val msg = json.optString("msg", "")
                when {
                    code == 0 || statusCode == 0 || falconCode == 0 -> WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.SUCCESS, httpCode,
                        if (msg.isNotEmpty()) msg else "OK", false
                    )
                    code == 99991663 || code == 99991664 -> WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.RATE_LIMITED, httpCode,
                        "限流 code=$code: $msg", true
                    )
                    else -> WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.BIZ_FAIL, httpCode,
                        "业务失败 code=$code StatusCode=$statusCode: $msg", false
                    )
                }
        },
    ),
    ChannelSpec(
        type = WebhookPayloadBuilder.WebhookType.TELEGRAM,
        hosts = listOf("api.telegram.org"),
        notify = { p ->
            val title = p.title; val content = p.content; val appName = p.appName
            val packageName = p.packageName; val time = p.time; val deviceName = p.deviceName
            val notifyType = p.notifyType; val chatId = p.chatId; val extras = p.extras
         WebhookPayloadBuilder.buildTelegram(
                        title = title,
                        content = content,
                        appName = appName,
                        time = time,
                        deviceName = deviceName,
                        notifyType = notifyType,
                        chatId = chatId
                    )
        },
        test = { p ->
            val title = p.title; val content = p.content; val deviceLabel = p.deviceLabel
            val sep = p.sep; val deviceName = p.deviceName; val chatId = p.chatId
         WebhookPayloadBuilder.buildTelegramMessage(
                        "${I18n.bracket(title)}\n$content\n\n$deviceLabel$sep$deviceName",
                        chatId
                    )
        },
        sms = { p ->
            val title = p.title; val sender = p.sender; val message = p.message
            val time = p.time; val deviceName = p.deviceName
            val simInfo = p.simInfo; val simFooter = p.simFooter; val chatId = p.chatId
         WebhookPayloadBuilder.buildTelegramMessage(
                        WebhookPayloadBuilder.buildTextBody(
                            title = title, content = "", appName = "",
                            time = time, deviceName = deviceName,
                            sender = sender, message = message, simFooter = simFooter
                        ),
                        chatId
                    )
        },
        call = { p ->
            val state = p.state; val phoneNumber = p.phoneNumber; val time = p.time
            val durationStr = p.durationStr; val deviceName = p.deviceName
            val simInfo = p.simInfo; val simFooter = p.simFooter; val chatId = p.chatId
         WebhookPayloadBuilder.buildTelegramMessage(
                        WebhookPayloadBuilder.buildTextBody(
                            title = "", content = "", appName = "",
                            time = time, deviceName = deviceName,
                            state = state, phoneNumber = phoneNumber,
                            durationStr = durationStr, simFooter = simFooter
                        ),
                        chatId
                    )
        },
        platformPayload = { vars, rendered, format, chatId ->

                WebhookPayloadBuilder.buildTelegramMessage(rendered, chatId)
        },
        parse = { httpCode, jsonOrNull, rawBody ->
            val json = jsonOrNull!!
                // Telegram: {"ok": true/false, "description": "..."}
                // （Bark 已独立判定——Bark 响应无 ok 字段，共用会导致业务失败被判成功）
                val ok = json.optBoolean("ok", true)
                val description = json.optString("description", json.optString("message", ""))
                if (ok) {
                    WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.SUCCESS, httpCode,
                        if (description.isNotEmpty()) description else "OK", false
                    )
                } else {
                    WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.BIZ_FAIL, httpCode,
                        if (description.isNotEmpty()) description else "失败", false
                    )
                }
        },
    ),
    ChannelSpec(
        type = WebhookPayloadBuilder.WebhookType.BARK,
        hosts = listOf("api.day.app", "bark.gugu.ovh"),
        notify = { p ->
            val title = p.title; val content = p.content; val appName = p.appName
            val packageName = p.packageName; val time = p.time; val deviceName = p.deviceName
            val notifyType = p.notifyType; val chatId = p.chatId; val extras = p.extras
         WebhookPayloadBuilder.buildBark(
                        title = title,
                        content = content,
                        appName = appName,
                        time = time,
                        deviceName = deviceName,
                        notifyType = notifyType
                    )
                    // Server酱 / PushPlus 在 WebhookSender 中走独立发送路径（GET / token 注入），
                    // 此处返回文本 body 作为兜底，保证 when 穷尽。
        },
        test = { p ->
            val title = p.title; val content = p.content; val deviceLabel = p.deviceLabel
            val sep = p.sep; val deviceName = p.deviceName; val chatId = p.chatId
         JSONObject().apply {
                        put("title", title)
                        put("body", "$content\n\n$deviceLabel$sep$deviceName")
                    }.toString()
        },
        sms = { p ->
            val title = p.title; val sender = p.sender; val message = p.message
            val time = p.time; val deviceName = p.deviceName
            val simInfo = p.simInfo; val simFooter = p.simFooter; val chatId = p.chatId
         JSONObject().apply {
                        put("title", title)
                        put("body", WebhookPayloadBuilder.buildTextBody(
                            title = "", content = "", appName = "",
                            time = time, deviceName = deviceName,
                            sender = sender, message = message, simFooter = simFooter
                        ))
                    }.toString()
        },
        call = { p ->
            val state = p.state; val phoneNumber = p.phoneNumber; val time = p.time
            val durationStr = p.durationStr; val deviceName = p.deviceName
            val simInfo = p.simInfo; val simFooter = p.simFooter; val chatId = p.chatId
         JSONObject().apply {
                        put("title", I18n.callNotifyTitle(state, phoneNumber, simInfo))
                        put("body", WebhookPayloadBuilder.buildTextBody(
                            title = "", content = "", appName = "",
                            time = time, deviceName = deviceName,
                            state = state, phoneNumber = phoneNumber,
                            durationStr = durationStr, simFooter = simFooter
                        ))
                    }.toString()
        },
        platformPayload = { vars, rendered, format, chatId ->
 JSONObject().apply {
                put("title", vars.title)
                put("body", rendered)
            }.toString()

            // Server酱 / PushPlus 无平台模板包装（走 WebhookSender 独立发送路径）
        },
        parse = { httpCode, jsonOrNull, rawBody ->
            val json = jsonOrNull!!
                // Bark：{"code":200,"message":"..."} —— code 为业务状态码（200 成功）
                // ⚠ 修复（原与 Telegram 共用判定导致静默成功）：Bark 响应**没有 ok 字段**，
                // 原先 `optBoolean("ok", true)` 恒取默认 true → 400（参数错）/404（路径错）/
                // 500（服务端错）等业务失败全被判「推送成功」，历史页显示成功但实际未送达。
                // 现按 code 语义独立判定；code 缺失（-1）同样保守判失败——宁可让用户看到
                // 失败，也不要静默把失败标成成功（与 v1.5.68 聚合失败回传同一原则）。
                val code = json.optInt("code", -1)
                val message = json.optString("message", "")
                when {
                    code == 200 -> WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.SUCCESS, httpCode,
                        if (message.isNotEmpty()) message else "OK", false
                    )
                    code == 429 -> WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.RATE_LIMITED, httpCode,
                        "限流 code=$code: $message", true
                    )
                    else -> WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.BIZ_FAIL, httpCode,
                        "Bark 业务失败 code=$code: $message", false
                    )
                }
        },
    ),
    ChannelSpec(
        type = WebhookPayloadBuilder.WebhookType.SERVER_CHAN,
        hosts = listOf("sctapi.ftqq.com"),
        notify = { p ->
            val title = p.title; val content = p.content; val appName = p.appName
            val packageName = p.packageName; val time = p.time; val deviceName = p.deviceName
            val notifyType = p.notifyType; val chatId = p.chatId; val extras = p.extras
         WebhookPayloadBuilder.buildTextBody(
                        title = title,
                        content = content,
                        appName = appName,
                        time = time,
                        deviceName = deviceName,
                        notifyType = notifyType
                    )
        },
        test = { p ->
            val title = p.title; val content = p.content; val deviceLabel = p.deviceLabel
            val sep = p.sep; val deviceName = p.deviceName; val chatId = p.chatId
         JSONObject().apply {
                        put("title", title)
                        put("content", "$content\n\n$deviceLabel$sep$deviceName")
                        put("deviceName", deviceName)
                    }.toString()
        },
        sms = { p ->
            val title = p.title; val sender = p.sender; val message = p.message
            val time = p.time; val deviceName = p.deviceName
            val simInfo = p.simInfo; val simFooter = p.simFooter; val chatId = p.chatId
         JSONObject().apply {
                        put("title", title)
                        put("content", WebhookPayloadBuilder.buildTextBody(
                            title = "", content = "", appName = "",
                            time = time, deviceName = deviceName,
                            sender = sender, message = message, simFooter = simFooter
                        ))
                    }.toString()
        },
        call = { p ->
            val state = p.state; val phoneNumber = p.phoneNumber; val time = p.time
            val durationStr = p.durationStr; val deviceName = p.deviceName
            val simInfo = p.simInfo; val simFooter = p.simFooter; val chatId = p.chatId
         JSONObject().apply {
                        put("title", I18n.callNotifyTitle(state, phoneNumber, simInfo))
                        put("content", WebhookPayloadBuilder.buildTextBody(
                            title = "", content = "", appName = "",
                            time = time, deviceName = deviceName,
                            state = state, phoneNumber = phoneNumber,
                            durationStr = durationStr, simFooter = simFooter
                        ))
                    }.toString()
        
            /**
             * Server酱（Server酱³ / Turbo）：POST form（application/x-www-form-urlencoded），
             * title + desp 作为表单体提交，内容不进入 URL，避免被中间代理/访问日志留存。
             * 接口：https://sctapi.ftqq.com/{SendKey}.send  body: title=xxx&desp=xxx
             */
        },
        parse = { httpCode, jsonOrNull, rawBody ->
            val json = jsonOrNull!!
                // Server酱：{"code":0,"message":"发送成功","data":{...}} — code==0 成功
                val code = json.optInt("code", -1)
                val message = json.optString("message", json.optString("msg", ""))
                if (code == 0) {
                    WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.SUCCESS, httpCode,
                        if (message.isNotEmpty()) message else "OK", false
                    )
                } else {
                    WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.BIZ_FAIL, httpCode,
                        "Server酱业务失败 code=$code: $message", false
                    )
                }
        },
    ),
    ChannelSpec(
        type = WebhookPayloadBuilder.WebhookType.PUSH_PLUS,
        hosts = listOf("www.pushplus.plus", "pushplus.plus"),
        notify = { p ->
            val title = p.title; val content = p.content; val appName = p.appName
            val packageName = p.packageName; val time = p.time; val deviceName = p.deviceName
            val notifyType = p.notifyType; val chatId = p.chatId; val extras = p.extras
         WebhookPayloadBuilder.buildTextBody(
                        title = title,
                        content = content,
                        appName = appName,
                        time = time,
                        deviceName = deviceName,
                        notifyType = notifyType
                    )
        },
        test = { p ->
            val title = p.title; val content = p.content; val deviceLabel = p.deviceLabel
            val sep = p.sep; val deviceName = p.deviceName; val chatId = p.chatId
         JSONObject().apply {
                        put("title", title)
                        put("content", "$content\n\n$deviceLabel$sep$deviceName")
                        put("deviceName", deviceName)
                    }.toString()
        },
        sms = { p ->
            val title = p.title; val sender = p.sender; val message = p.message
            val time = p.time; val deviceName = p.deviceName
            val simInfo = p.simInfo; val simFooter = p.simFooter; val chatId = p.chatId
         JSONObject().apply {
                        put("title", title)
                        put("content", WebhookPayloadBuilder.buildTextBody(
                            title = "", content = "", appName = "",
                            time = time, deviceName = deviceName,
                            sender = sender, message = message, simFooter = simFooter
                        ))
                    }.toString()
        },
        call = { p ->
            val state = p.state; val phoneNumber = p.phoneNumber; val time = p.time
            val durationStr = p.durationStr; val deviceName = p.deviceName
            val simInfo = p.simInfo; val simFooter = p.simFooter; val chatId = p.chatId
         JSONObject().apply {
                        put("title", I18n.callNotifyTitle(state, phoneNumber, simInfo))
                        put("content", WebhookPayloadBuilder.buildTextBody(
                            title = "", content = "", appName = "",
                            time = time, deviceName = deviceName,
                            state = state, phoneNumber = phoneNumber,
                            durationStr = durationStr, simFooter = simFooter
                        ))
                    }.toString()
        
            /**
             * Server酱（Server酱³ / Turbo）：POST form（application/x-www-form-urlencoded），
             * title + desp 作为表单体提交，内容不进入 URL，避免被中间代理/访问日志留存。
             * 接口：https://sctapi.ftqq.com/{SendKey}.send  body: title=xxx&desp=xxx
             */
        },
        parse = { httpCode, jsonOrNull, rawBody ->
            val json = jsonOrNull!!
                // PushPlus：{"code":200,"msg":"发送成功","data":"..."} — code==200 成功
                val code = json.optInt("code", -1)
                val message = json.optString("msg", json.optString("message", ""))
                if (code == 200) {
                    WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.SUCCESS, httpCode,
                        if (message.isNotEmpty()) message else "OK", false
                    )
                } else {
                    WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.BIZ_FAIL, httpCode,
                        "PushPlus 业务失败 code=$code: $message", false
                    )
                }
        },
    ),
    )

    private val byType: Map<WebhookPayloadBuilder.WebhookType, ChannelSpec> =
        CHANNELS.associateBy { it.type }

    /** 取通道描述（未登记时退化为 GENERIC，保证运行时不崩；漏登记由守卫测试拦截） */
    fun spec(type: WebhookPayloadBuilder.WebhookType): ChannelSpec =
        byType[type] ?: byType.getValue(WebhookPayloadBuilder.WebhookType.GENERIC)

    /** 按 host 自动识别通道；无匹配返回 null（调用方回退 GENERIC） */
    fun typeByHost(host: String): WebhookPayloadBuilder.WebhookType? {
        val h = host.lowercase()
        for (spec in CHANNELS) {
            if (h in spec.hosts) return spec.type
        }
        return null
    }

    /**
     * 从 URL 中提取 host（小写），失败返回 null。
     * 示例：
     *   "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxx" → "qyapi.weixin.qq.com"
     *   "qyapi.weixin.qq.com/cgi-bin/webhook/send" → "qyapi.weixin.qq.com"
     *   "not a url" → null
     * ⚠ 与 Dart 端 `WebhookChannel._extractHost` 保持一致（自动识别两端口径必须相同）。
     */
    fun extractHost(url: String): String? {
        val lower = url.trim().lowercase()
        if (lower.isEmpty()) return null
        val noProto = when {
            lower.startsWith("https://") -> lower.substring(8)
            lower.startsWith("http://") -> lower.substring(7)
            else -> lower
        }
        val endIdx = noProto.indexOfAny(charArrayOf('/', '?', '#'))
        val hostPort = if (endIdx >= 0) noProto.substring(0, endIdx) else noProto
        if (hostPort.isEmpty()) return null
        val atIdx = hostPort.lastIndexOf('@')
        val hostWithOptionalPort = if (atIdx >= 0) hostPort.substring(atIdx + 1) else hostPort
        val host = hostWithOptionalPort.substringBeforeLast(':')
        return host.takeIf { it.isNotEmpty() }
    }
}
