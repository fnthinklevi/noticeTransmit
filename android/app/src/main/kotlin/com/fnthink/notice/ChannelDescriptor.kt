package com.fnthink.notice

/**
 * 通道描述符的**声明位**（第 4 步引入）。
 *
 * 这些类型不承载行为，只把过去散落在 `when (type)` 里的**事实**变成表里的数据：
 * - [SignatureScheme]：原 `WebhookSigner.sign` 的 12 臂 `when`（漏一臂就编译不过 = 强制改动点）
 * - [ChannelTransport]：原 `WebhookSender.sendToSingleUrl` 里 5 个 `if (cfg.type == ...)` 早退分支
 * - `legacyTokens`：原 `ConfigManager.parseWebhookType` 的字符串 + 数字 `"0".."11"` 映射表
 * - 正文上限：原散在 `buildTelegramMessage` / `truncateForDiscord` 里的魔数
 *
 * 判据（守卫测试 [ChannelDescriptorContractTest] 逐条锁）：**新增一个通道时，
 * 除 `WebhookType` 枚举与本表外，不得再有需要动的生产代码**。
 * `WebhookType` 保留是因为它是跨进程身份（`RetryQueue` 持久化 `.name`、
 * `DeliveryNotifier` 广播 `.name`、送达日志键 `parse:<idx>:<TYPE>:<code>`），
 * 换成字符串键属于独立的破坏性变更，不在本步范围。
 *
 * ⚠ 中文原因串（[ChannelTransport.missingParamReason] 等）暂存在本表：
 * 它们原本是 `WebhookSender` 里的字面量，搬进表里只是把"第二处真相"合并到"唯一一处"。
 * 第 5 步连同 `MainActivity` 的 typeLabel 一起改走资源 id / ARB。
 */

/** 签名方案：`WebhookSigner` 按此声明分派，不再按平台名分支。 */
internal enum class SignatureScheme {
    /** 不签名（Telegram/Bark/Server酱/PushPlus/Slack/Discord：凭据在 URL 或 body 里） */
    NONE,

    /**
     * URL 追加 `&timestamp=<ts>&sign=<urlencoded base64>`；
     * HMAC 的 key = secret、data = `"<ts>\n<secret>"`。企微与钉钉**只差时间戳单位**
     * （企微秒、钉钉毫秒），所以拆成两个值而不是加参数——避免出现"半个枚举值"。
     */
    URL_TIMESTAMP_SECONDS,
    URL_TIMESTAMP_MILLIS,

    /**
     * 飞书：在 JSON 顶层注入 `timestamp` + `sign`；
     * HMAC 的 key = `"<ts>\n<secret>"`、data = 空字节串（与钉钉/企微**正好相反**，
     * 用错算法平台返回 code 19021 Sign match fail）。
     */
    FEISHU_PAYLOAD_JSON,

    /** 通用 webhook：HTTP 头 `X-Signature: sha256=<hex(HMAC(body, secret))>` + `X-Timestamp` */
    HEADER_HEX_BODY,

    /** ntfy：secret 是访问令牌，以 `Authorization: Bearer <secret>` 传递（不参与签名） */
    BEARER_HEADER,
}

/** 凭据/参数从哪儿取、缺失时怎么办。 */
internal enum class UrlParam { NONE, CHAT_ID, TOKEN }

/**
 * 自定义模板（`message_format` + `message_template`）对该通道是否生效。
 *
 * 重构前这件事是靠 `sendToSingleUrl` 里的**早退顺序**偶然形成的：
 * NTFY/GOTIFY/SERVER_CHAN/PUSH_PLUS 在模板代码之前就 return 了，所以用户在界面上
 * 选的格式与模板对它们**静默不生效**。改成显式声明，行为保持不变，但事实可见。
 */
internal enum class TemplateSupport {
    /** 走平台模板包装（企微/钉钉/飞书 text/markdown 等；无 platformPayload 的等于无包装） */
    STANDARD,

    /** 通用 webhook：渲染结果原样作为请求体，并采用该格式自己的 content-type */
    RAW_BODY,

    /** 模板一律不生效（正文形状由平台强约束，或正文由 [ChannelTransport.bodyOverride] 决定） */
    DISABLED,
}

/** [ChannelTransport.bodyOverride] 的入参（实发正文只用到这几个字段，故不复用 NotifyInput） */
internal class BodyInput(
    val title: String,
    val content: String,
    val time: String,
    val deviceName: String,
    val url: String,
)

/**
 * 发送层的通道事实。全部默认值 = "普通 JSON webhook"，因此**大多数通道不需要写这一段**。
 */
internal class ChannelTransport(
    /** null = 用 `NetworkClient` 的默认 JSON content-type */
    val contentType: String? = null,

    /**
     * 请求路径后缀（Gotify 用 `/message`）。
     * 与 [secretAsQueryToken] 配合：真实 URL = `trimEnd('/') + pathSuffix + "?token=<secret>"`。
     */
    val pathSuffix: String? = null,

    /** secret 以 URL query `token=` 传（Gotify）；true 时**不得**再把 secret 交给签名层（会二次签名） */
    val secretAsQueryToken: Boolean = false,

    /** secret 为必填（缺失即早失败，不发请求） */
    val secretRequired: Boolean = false,

    /** 必须能从 URL query 里取到该参数，否则早失败 */
    val requiredUrlParam: UrlParam = UrlParam.NONE,

    /** 早失败时给用户的中文原因（原 WebhookSender 分支里的字面量，逐字保留） */
    val missingParamReason: String? = null,

    /**
     * 实发正文覆写（Server酱 的表单正文、PushPlus 的带 token 正文）。
     *
     * ⚠ 非 null 即表示「该通道**实发正文 ≠ 描述符 notify 产出的 JSON**」——这是既成事实，
     * 不是本步引入的。此前它藏在 `WebhookSender` 的两个 `if (cfg.type == ...)` 里，
     * 于是快照里的 `notify|SERVER_CHAN` 描述的是一条生产上永不发送的正文（**快照虚覆盖了不存在的行为**）。
     * 现在它进声明位，并由快照额外锁 `body|<TYPE>` 两条，覆盖关系才与运行时一致。
     */
    val bodyOverride: ((BodyInput) -> String)? = null,

    /** 自定义模板策略（默认走平台包装）。见 [TemplateSupport]。 */
    val templateSupport: TemplateSupport = TemplateSupport.STANDARD,

    /**
     * 正文上限（**字符**，代理项对安全；Telegram 4096 / Discord 2000）。
     * null = 不截断。数值只在 [ChannelLimits] 里定义一次，载荷 lambda 与本字段共用同一常量。
     */
    val textLimitChars: Int? = null,
)

/**
 * 表单字段类型：Dart 渲染器按它决定控件形态（键盘类型 / 遮罩 / 多行）与落库类型。
 *
 * T08-C 之前只有 TEXT/NUMBER 两值 —— 那是"应用通道只有三个文本框"的形状。邮件族第一次
 * 出现了开关（useSSL）、要遮罩的凭据（SMTP 授权码）、多行正文（bodyTemplate）与
 * 邮箱/主机两种键盘，所以补齐。**每个值都必须有渲染分支**：`kind` 落回 text 的表现是
 * "密码明文显示 / 开关画成输入框"，由 `ChannelFormRenderer` 的用例与
 * `channel_descriptor_export_contract_test` 的"未登记 kind 不得静默降级"一起钉。
 */
enum class FieldKind { TEXT, NUMBER, SWITCH, SECRET, MULTILINE, EMAIL_ADDRESS, HOST }

/**
 * 字段上的一个预置档位（点一下把模板正文填进该字段）。
 *
 * 只存 **ARB 资源名**，不存文案：正文曾经硬编码在 Dart 页面上（11 条中文字面量），
 * 于是英文界面点预置会往用户配置里写中文。现在文本只在 ARB 一处，语言跟着界面走。
 * [valueKey] = null 表示"清空该字段"（= 交回运行时默认，邮件正文的「默认」档位就是这种）。
 */
class FieldPreset(
    val labelKey: String,
    val valueKey: String? = null,
) {
    fun toMap(): Map<String, Any?> = mapOf("labelKey" to labelKey, "valueKey" to valueKey)
}

/**
 * 通道配置字段声明（应用通道的扩展参数、邮件族的连接参数）。
 *
 * ⚠ [labelKey]/[hintKey] 存的是 **Dart ARB 资源名**、不是文案：译文只在 ARB 一处。
 * 这里此前另存 `labelZh/labelEn/hintZh/hintEn` 四份字面量，已与 ARB 漂移
 * （agentid：Kotlin「应用 agentid」vs ARB「应用 agentid（纯数字）」），
 * 而且整份 schema 在生产代码里零消费者 —— Dart 表单是四处硬编码列表（第 5 步收口）。
 */
class FieldSpec(
    val key: String,
    val labelKey: String,
    val kind: FieldKind = FieldKind.TEXT,
    val required: Boolean = false,
    /** 留空时落库的默认值（touser=@all、receive_id_type=chat_id、agentid=0、smtpPort=465） */
    val defaultValue: String? = null,
    /** 输入框提示的 ARB 资源名；null = 不给提示 */
    val hintKey: String? = null,
    /** 预置档位（模板类字段才有）；空列表 = 界面不给档位按钮 */
    val presets: List<FieldPreset> = emptyList(),
) {
    /** MethodChannel 可序列化的 Map（不放 org.json 对象，Dart 侧拿不到） */
    fun toMap(): Map<String, Any?> = mapOf(
        "key" to key,
        "labelKey" to labelKey,
        "kind" to kind.name.lowercase(),
        "required" to required,
        "defaultValue" to defaultValue,
        "hintKey" to hintKey,
        // 空列表也发出去：Dart 侧要能区分"这字段没档位"与"描述符没拉到"
        // （后者不得把已存配置写空）。
        "presets" to presets.map { it.toMap() },
    )
}

/**
 * 能力位名字（导出给 Dart 的是**派生布尔**，不是平台名单）。
 *
 * 派生规则唯一定义在 `ChannelRegistry.capabilitiesOf` / `AppChannelRegistry.capabilitiesOf`。
 * Dart 侧只读这些名字决定表单显隐 —— 此前 `webhook_settings_page._supportsSigning`
 * 自带一份"排除 6 个平台"的黑名单，是原生签名表之外的第二处真相。
 */
object Capability {
    /** secret 字段承载真实凭据（HMAC 密钥 / Bearer 令牌 / App Token）⇒ UI 需要显示它 */
    const val SECRET_USED = "secretUsed"

    /** secret 走 Authorization: Bearer 头（ntfy），不参与签名 */
    const val BEARER_TOKEN = "bearerToken"

    /** secret 以 URL query token 传（Gotify），不再交给签名层 */
    const val SECRET_IN_QUERY = "secretInQuery"

    /** secret 必填，缺失即早失败 */
    const val SECRET_REQUIRED = "secretRequired"

    /** 必须从 URL 取 chat_id（Telegram） */
    const val CHAT_ID_REQUIRED = "chatIdRequired"

    /** 必须从 URL 取 token（PushPlus） */
    const val URL_TOKEN_REQUIRED = "urlTokenRequired"

    /** 自定义消息格式 / 模板对该通道生效 */
    const val CUSTOM_TEMPLATE = "customTemplate"

    /** 渲染结果原样作为请求体（通用 webhook），并采用该格式自己的 content-type */
    const val RAW_TEMPLATE_BODY = "rawTemplateBody"

    /** 响应按业务码判定：2xx + 非 JSON 视为未送达（防反代/认证门户页假成功） */
    const val JSON_CONTRACT = "jsonContract"

    /** 支持 markdown 消息（企业微信自建应用；飞书统一降级为 text） */
    const val MARKDOWN = "markdown"

    /**
     * 凭据字段**留空 = 沿用已存值**（邮件的 SMTP 授权码）。
     *
     * 与 webhook 族正好相反：那边"清空密钥框"是真的清（见 T07-B 的载荷语义），
     * 因为邮件授权码在原生按 id 键控单独存（`EmailManager` 的 passwords 表），
     * 编辑弹层从来读不回明文 ⇒ 空白只能解释为"没改"。这条差异必须在表里可见，
     * 否则 UI 要么把已存授权码洗成空，要么反过来让用户清不掉。
     */
    const val SECRET_KEEPS_PREVIOUS = "secretKeepsPrevious"
}

/** 正文上限常量：唯一定义处（描述符声明与截断实现共用，避免魔数漂移）。 */
internal object ChannelLimits {
    /** Telegram sendMessage 文本上限（超出平台直接回 400） */
    const val TELEGRAM_CHARS = 4096

    /** Discord content 上限（超出回 400） */
    const val DISCORD_CHARS = 2000

    /** 企业微信自建应用 text 正文上限（UTF-8 **字节**，超出回 40058） */
    const val WECOM_APP_BYTES = 2048

    /** 飞书自建应用正文上限（字符） */
    const val FEISHU_APP_CHARS = 3000
}

/**
 * 截断工具（代理项对安全）。
 *
 * 此前 Telegram/Discord 各自内联一份「判断长度→回退一位避免拆开头代理」的逻辑，
 * 字节级截断（企微应用）又是第三种写法；三处同源逻辑只要有一处改动就会漂移。
 */
internal object ChannelDefaults {
    /** 按**字符**截断，不拆开代理项对（与既有 Telegram/Discord 行为逐字节一致） */
    fun truncateChars(text: String, limit: Int): String {
        if (text.length <= limit) return text
        var end = limit
        if (end > 0 && Character.isHighSurrogate(text[end - 1])) end--
        return text.substring(0, end)
    }

    /** 按 **UTF-8 字节**截断（超出即整段回退一位，直到落进上限） */
    fun truncateBytes(text: String, limit: Int): String {
        if (text.toByteArray(Charsets.UTF_8).size <= limit) return text
        var end = text.length
        while (end > 0 && text.substring(0, end).toByteArray(Charsets.UTF_8).size > limit) {
            end--
        }
        return text.substring(0, end)
    }
}
