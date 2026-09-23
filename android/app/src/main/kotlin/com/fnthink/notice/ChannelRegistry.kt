package com.fnthink.notice

import org.json.JSONObject

/**
 * 通道描述符表（**通道身份、载荷、判定、签名、发送层事实的唯一改动点**）。
 *
 * 第 4 步之后，新增一个 webhook 平台在原生侧只需要：
 *   ① `WebhookType` 加一个枚举值（跨进程身份：`RetryQueue` 存 `.name`、送达广播存 `.name`）
 *   ② 本表加一行（host 识别 + 四类载荷 + 判定 + 签名方案 + 存储别名 + 发送层事实）
 * 核心管线（`WebhookSender` / `WebhookSigner` / `WebhookResponseParser` / `TemplateEngine` /
 * `NetworkClient` / `ConfigManager`）**零改动**，由 `ChannelDescriptorContractTest` 的
 * 「生产代码不得再按平台分支」源码守卫 + 一个未注册进本表的合成描述符跑通全链路来证明。
 *
 * 还剩两处是"表之外"的（第 5 步收口）：Dart 的 ARB 词条与图标表；以及
 * `MainActivity.testWebhook` 的四条手工构造正文（测试按钮与真实推送不同源）。
 *
 * 完整性由守卫测试锁定：`ChannelRegistryTest`（枚举↔表项 1:1、四类载荷齐全、host 不重复）
 * + `ChannelDescriptorContractTest`（存储别名唯一、`labelKey` 真实存在于 ARB、
 * 响应契约显式声明、上限常量与实现同源）。
 *
 * ⚠ 行为等价性由 `ChannelBehaviorGoldenTest` 的逐字节快照锁定（实测 **50 条载荷 + 36 条解析**；
 *   50 = 12 通道 × 4 类载荷 + Server酱/PushPlus 两条 `body:` 实发正文覆写）。
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
    /**
     * **早期按枚举序号存储的数字**（`"0"`..`"11"`）。
     *
     * 其余合法写法由 [storedTokens] 自动派生（枚举名 / 小写 / 去下划线），
     * 因此 `ConfigManager.parseWebhookType` 那张 12 臂 `when` 已收敛成本表 + 本字段。
     * ⚠ 数字**不是** `WebhookType` 的下标（3=generic、4=telegram），别按枚举顺序推。
     * Dart 侧同名表在 `lib/services/channel_display.dart` 的 `_slugAliases`，
     * 两端一致性由 `test/architecture/channel_identity_contract_test.dart` 跨语言比对。
     */
    val legacyTokens: List<String> = emptyList(),
    /** 签名方案（默认不签名）。见 [SignatureScheme]。 */
    val signature: SignatureScheme = SignatureScheme.NONE,
    /** 发送层事实（默认「普通 JSON webhook」）。见 [ChannelTransport]。 */
    val transport: ChannelTransport = ChannelTransport(),
    /**
     * Dart ARB 资源名（如 `channelTypeDingtalk`）。**只存资源名、不存译文** ——
     * 译文只在 Dart ARB 一处（853 词条 + 漏翻守卫的既有规则）。
     *
     * 默认由枚举名派生；ARB 命名不符合派生规则时在本表显式覆写（目前只有 wechat_work：
     * ARB 里是 `channelTypeWechat`）。每条 labelKey 都必须真实存在于 `app_zh.arb`，
     * 由 `ChannelDescriptorContractTest.labelKeys_existInArb` 跨语言锁住
     * （第 5 步 `getChannelDescriptors` 会把这个名字直接发给 Dart）。
     */
    val labelKey: String =
        "channelType" + type.name.lowercase().split("_").joinToString("") {
            it.replaceFirstChar(Char::uppercase)
        },

    /** Dart 图标表的 key（与 slug 同值；单列出来是为了让"图标按什么取"这件事可见） */
    val iconKey: String = type.name.lowercase(),
    /**
     * 响应契约：2xx + **非 JSON** body 算不算送达成功。
     *
     * 默认 true —— "业务码才算数"是常态：反代 / 认证门户 / 风控网关经常回 200 + HTML，
     * 一律按 HTTP 2xx 判成功就是「假成功 + 静默丢内容」（比报失败危险：失败会提示、还能手动重推）。
     *
     * 此前这条判断写成 `type != GENERIC && spec.parse != null`，藏在解析器里，
     * 等于用"有没有登记 parse"间接推断契约 —— 新通道要么被误判失败、要么被误判成功。
     * 显式声明后，false 的只有 5 家：
     * - GENERIC：自建端点回 200 + "OK" 纯文本完全合法；
     * - ntfy / Gotify / Slack / Discord：语义就是 HTTP 状态码（回 text/plain 或 204 空 body）。
     */
    val requiresJsonContract: Boolean = true,
) {
    /**
     * 存储/跨端可用的全部写法：枚举名、小写、去下划线小写 + 手写的早期数字。
     *
     * ⚠ 必须按**大小写无关**去重：查找侧把输入 lowercase 后再比，所以 "GENERIC" 与 "generic"
     * 是同一个键；不去重的话 `ChannelDescriptorContractTest` 的「存储值全局唯一」会把自己判成歧义。
     */
    val storedTokens: List<String>
        get() = (listOf(type.name, type.name.lowercase(), type.name.lowercase().replace("_", "")) + legacyTokens)
            .distinctBy { it.lowercase() }

    /**
     * 稳定标识（`dingtalk` / `wechat_work`）。
     *
     * Dart 侧 `chan:<slug>` 的 slug、健康缓存 key、图标表 key 都用它 —— 与显示名无关
     * （第 2 步把"显示名当键"的缺陷消掉后，这里就是原生侧的同一身份口径）。
     */
    val slug: String get() = type.name.lowercase()
}

internal object ChannelRegistry {
    /** 全部通道（顺序即 host 匹配优先级） */
    val CHANNELS: List<ChannelSpec> = listOf(
        ChannelSpec(
            type = WebhookPayloadBuilder.WebhookType.GENERIC,
            hosts = emptyList(),
            legacyTokens = listOf("3"),
            signature = SignatureScheme.HEADER_HEX_BODY,
            // 自建端点回 200 + "OK" 纯文本完全合法 ⇒ 不按 JSON 契约判失败
            requiresJsonContract = false,
            transport = ChannelTransport(templateSupport = TemplateSupport.RAW_BODY),
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
                // 通用 webhook：尝试解析 code / errcode 字段，0 为成功；两者都缺才视为 HTTP 成功。
                // ⚠ errcode 分支不是多余的：应用通道（企微/飞书自建应用）复用本管线时传 GENERIC，
                //   官方域名下可由 host 回退拿到真实判定；但**私有化部署/走代理网关**时 host 匹配不上，
                //   原先只看 code 会把企微的 {"errcode":42001} 判成「成功」——历史显示已送达而实际没送达。
                val code = json.optInt("code", -1)
                val errcode = json.optInt("errcode", -1)
                val message = json.optString(
                    "message",
                    json.optString("msg", json.optString("errmsg", ""))
                )
                if (json.has("code") && code != 0) {
                    WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.BIZ_FAIL, httpCode,
                        "业务失败 code=$code: $message", false
                    )
                } else if (json.has("errcode") && errcode != 0) {
                    WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.BIZ_FAIL, httpCode,
                        "业务失败 errcode=$errcode: $message", false
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
            legacyTokens = listOf("0"),
            signature = SignatureScheme.URL_TIMESTAMP_SECONDS,
            // ARB 里的历史命名是 channelTypeWechat（不是派生的 channelTypeWechatWork）
            labelKey = "channelTypeWechat",
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
            legacyTokens = listOf("1"),
            signature = SignatureScheme.URL_TIMESTAMP_MILLIS,
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
            legacyTokens = listOf("2"),
            signature = SignatureScheme.FEISHU_PAYLOAD_JSON,
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
            legacyTokens = listOf("4"),
            transport = ChannelTransport(
                requiredUrlParam = UrlParam.CHAT_ID,
                missingParamReason = "Telegram 链接缺少 chat_id 参数",
                textLimitChars = ChannelLimits.TELEGRAM_CHARS,
            ),
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
            legacyTokens = listOf("5"),
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
            legacyTokens = listOf("6"),
            transport = ChannelTransport(
                contentType = "application/x-www-form-urlencoded; charset=utf-8",
                templateSupport = TemplateSupport.DISABLED,
                bodyOverride = { b ->
                    WebhookPayloadBuilder.buildServerChanFormBody(
                        title = b.title,
                        content = b.content,
                        deviceName = b.deviceName,
                        time = b.time
                    )
                },
            ),
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
            legacyTokens = listOf("7"),
            transport = ChannelTransport(
                requiredUrlParam = UrlParam.TOKEN,
                missingParamReason = "PushPlus 链接缺少 token 参数",
                templateSupport = TemplateSupport.DISABLED,
                bodyOverride = { b ->
                    WebhookPayloadBuilder.buildPushPlusPayload(
                        title = b.title,
                        content = b.content,
                        deviceName = b.deviceName,
                        time = b.time,
                        token = WebhookPayloadBuilder.extractTokenFromUrl(b.url)
                    )
                },
            ),
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
        ChannelSpec(
            type = WebhookPayloadBuilder.WebhookType.NTFY,
            // 官方托管 ntfy.sh 可自动识别；自建服务器 host 不可枚举，
            // 类型由 DB channel_type 字段提供（detectType 兜底 GENERIC）
            hosts = listOf("ntfy.sh"),
            legacyTokens = listOf("8"),
            requiresJsonContract = false,
            signature = SignatureScheme.BEARER_HEADER,
            transport = ChannelTransport(
                contentType = "text/plain; charset=utf-8",
                templateSupport = TemplateSupport.DISABLED,
            ),
            notify = { p ->
                val title = p.title; val content = p.content; val appName = p.appName
                val time = p.time; val deviceName = p.deviceName; val notifyType = p.notifyType
                WebhookPayloadBuilder.buildTextBody(
                    title = title,
                    content = content,
                    appName = appName,
                    time = time,
                    deviceName = deviceName,
                    notifyType = notifyType
                )
                // header 模式：body 即纯文本消息；Title/Authorization 由发送层注入
            },
            test = { p ->
                val content = p.content; val deviceLabel = p.deviceLabel
                val sep = p.sep; val deviceName = p.deviceName
                "$content\n\n$deviceLabel$sep$deviceName"
            },
            sms = { p ->
                val sender = p.sender; val message = p.message
                val time = p.time; val deviceName = p.deviceName
                val simFooter = p.simFooter
                WebhookPayloadBuilder.buildTextBody(
                    title = "", content = "", appName = "",
                    time = time, deviceName = deviceName,
                    sender = sender, message = message, simFooter = simFooter
                )
            },
            call = { p ->
                val state = p.state; val phoneNumber = p.phoneNumber; val time = p.time
                val durationStr = p.durationStr; val deviceName = p.deviceName
                val simFooter = p.simFooter
                WebhookPayloadBuilder.buildTextBody(
                    title = "", content = "", appName = "",
                    time = time, deviceName = deviceName,
                    state = state, phoneNumber = phoneNumber,
                    durationStr = durationStr, simFooter = simFooter
                )
            },
            // parse = null：ntfy 2xx（含 JSON {"id":...}）即成功，走外层兜底
        ),
        ChannelSpec(
            type = WebhookPayloadBuilder.WebhookType.GOTIFY,
            hosts = emptyList(),
            legacyTokens = listOf("9"),
            requiresJsonContract = false,
            transport = ChannelTransport(
                pathSuffix = "/message",
                secretAsQueryToken = true,
                secretRequired = true,
                templateSupport = TemplateSupport.DISABLED,
                missingParamReason = "Gotify 缺少应用 Token（secret 字段）",
            ),
            notify = { p ->
                val title = p.title; val content = p.content; val appName = p.appName
                val time = p.time; val deviceName = p.deviceName; val notifyType = p.notifyType
                JSONObject().apply {
                    put("title", title.ifEmpty { appName })
                    put("message", WebhookPayloadBuilder.buildTextBody(
                        title = "", content = content, appName = "",
                        time = time, deviceName = deviceName,
                        notifyType = notifyType
                    ))
                }.toString()
            },
            test = { p ->
                val title = p.title; val content = p.content; val deviceLabel = p.deviceLabel
                val sep = p.sep; val deviceName = p.deviceName
                JSONObject().apply {
                    put("title", title)
                    put("message", "$content\n\n$deviceLabel$sep$deviceName")
                }.toString()
            },
            sms = { p ->
                val title = p.title; val sender = p.sender; val message = p.message
                val time = p.time; val deviceName = p.deviceName
                val simFooter = p.simFooter
                JSONObject().apply {
                    put("title", title)
                    put("message", WebhookPayloadBuilder.buildTextBody(
                        title = "", content = "", appName = "",
                        time = time, deviceName = deviceName,
                        sender = sender, message = message, simFooter = simFooter
                    ))
                }.toString()
            },
            call = { p ->
                val state = p.state; val phoneNumber = p.phoneNumber; val time = p.time
                val durationStr = p.durationStr; val deviceName = p.deviceName
                val simInfo = p.simInfo; val simFooter = p.simFooter
                JSONObject().apply {
                    put("title", I18n.callNotifyTitle(state, phoneNumber, simInfo))
                    put("message", WebhookPayloadBuilder.buildTextBody(
                        title = "", content = "", appName = "",
                        time = time, deviceName = deviceName,
                        state = state, phoneNumber = phoneNumber,
                        durationStr = durationStr, simFooter = simFooter
                    ))
                }.toString()
            },
            // parse = null：Gotify 2xx（含 JSON {"id":...}）即成功，走外层兜底
        ),
        ChannelSpec(
            type = WebhookPayloadBuilder.WebhookType.SLACK,
            hosts = listOf("hooks.slack.com"),
            legacyTokens = listOf("10"),
            requiresJsonContract = false,
            notify = { p ->
                val title = p.title; val content = p.content; val appName = p.appName
                val time = p.time; val deviceName = p.deviceName; val notifyType = p.notifyType
                JSONObject().apply {
                    put("text", WebhookPayloadBuilder.buildTextBody(
                        title = title, content = content, appName = appName,
                        time = time, deviceName = deviceName,
                        notifyType = notifyType
                    ))
                }.toString()
            },
            test = { p ->
                val title = p.title; val content = p.content; val deviceLabel = p.deviceLabel
                val sep = p.sep; val deviceName = p.deviceName
                JSONObject().apply {
                    put("text", "${I18n.bracket(title)}\n$content\n\n$deviceLabel$sep$deviceName")
                }.toString()
            },
            sms = { p ->
                val sender = p.sender; val message = p.message
                val time = p.time; val deviceName = p.deviceName
                val simFooter = p.simFooter
                JSONObject().apply {
                    put("text", WebhookPayloadBuilder.buildTextBody(
                        title = "", content = "", appName = "",
                        time = time, deviceName = deviceName,
                        sender = sender, message = message, simFooter = simFooter
                    ))
                }.toString()
            },
            call = { p ->
                val state = p.state; val phoneNumber = p.phoneNumber; val time = p.time
                val durationStr = p.durationStr; val deviceName = p.deviceName
                val simFooter = p.simFooter
                JSONObject().apply {
                    put("text", WebhookPayloadBuilder.buildTextBody(
                        title = "", content = "", appName = "",
                        time = time, deviceName = deviceName,
                        state = state, phoneNumber = phoneNumber,
                        durationStr = durationStr, simFooter = simFooter
                    ))
                }.toString()
            },
            // parse = null：Slack 成功响应为文本 "ok"（非 JSON）→ 外层兜底 SUCCESS；失败走 4xx HTTP_FAIL
        ),
        ChannelSpec(
            type = WebhookPayloadBuilder.WebhookType.DISCORD,
            hosts = listOf("discord.com", "discordapp.com"),
            legacyTokens = listOf("11"),
            requiresJsonContract = false,
            transport = ChannelTransport(textLimitChars = ChannelLimits.DISCORD_CHARS),
            notify = { p ->
                val title = p.title; val content = p.content; val appName = p.appName
                val time = p.time; val deviceName = p.deviceName; val notifyType = p.notifyType
                JSONObject().apply {
                    put("content", WebhookPayloadBuilder.truncateForDiscord(
                        WebhookPayloadBuilder.buildTextBody(
                            title = title, content = content, appName = appName,
                            time = time, deviceName = deviceName,
                            notifyType = notifyType
                        )
                    ))
                }.toString()
            },
            test = { p ->
                val content = p.content; val deviceLabel = p.deviceLabel
                val sep = p.sep; val deviceName = p.deviceName
                JSONObject().apply {
                    put("content", "$content\n\n$deviceLabel$sep$deviceName")
                }.toString()
            },
            sms = { p ->
                val sender = p.sender; val message = p.message
                val time = p.time; val deviceName = p.deviceName
                val simFooter = p.simFooter
                JSONObject().apply {
                    put("content", WebhookPayloadBuilder.truncateForDiscord(
                        WebhookPayloadBuilder.buildTextBody(
                            title = "", content = "", appName = "",
                            time = time, deviceName = deviceName,
                            sender = sender, message = message, simFooter = simFooter
                        )
                    ))
                }.toString()
            },
            call = { p ->
                val state = p.state; val phoneNumber = p.phoneNumber; val time = p.time
                val durationStr = p.durationStr; val deviceName = p.deviceName
                val simFooter = p.simFooter
                JSONObject().apply {
                    put("content", WebhookPayloadBuilder.truncateForDiscord(
                        WebhookPayloadBuilder.buildTextBody(
                            title = "", content = "", appName = "",
                            time = time, deviceName = deviceName,
                            state = state, phoneNumber = phoneNumber,
                            durationStr = durationStr, simFooter = simFooter
                        )
                    ))
                }.toString()
            },
            // parse = null：Discord 成功为 HTTP 204（空 body）→ 外层 SUCCESS；429 → 外层 RATE_LIMITED；400 → HTTP_FAIL
        ),
    )

    private val byType: Map<WebhookPayloadBuilder.WebhookType, ChannelSpec> =
        CHANNELS.associateBy { it.type }

    /** 取通道描述（未登记时退化为 GENERIC，保证运行时不崩；漏登记由守卫测试拦截） */
    fun spec(type: WebhookPayloadBuilder.WebhookType): ChannelSpec =
        byType[type] ?: byType.getValue(WebhookPayloadBuilder.WebhookType.GENERIC)

    /**
     * 存储值 → 通道类型。命中口径与旧的 `ConfigManager.parseWebhookType` 一致：
     * 输入先 trim + lowercase，再与本表 [ChannelSpec.storedTokens] 逐条比。
     * 未匹配返回 null，由调用方回退 host 识别（**不要**在这里猜）。
     */
    fun typeByStoredToken(stored: String): WebhookPayloadBuilder.WebhookType? {
        val key = stored.trim().lowercase()
        if (key.isEmpty()) return null
        return CHANNELS.firstOrNull { spec ->
            spec.storedTokens.any { it.lowercase() == key }
        }?.type
    }

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
