package com.fnthink.notice

/**
 * 发送计划的**纯决策**部分：给定一个通道描述符 + 本次发送的原料，决定
 * 「请求打到哪个 URL、发什么正文、用什么 content-type、secret 交不交给签名层、要不要提前失败」。
 *
 * 为什么单独成文件（第 4 步）：这些判断原来全部写在 `WebhookSender.sendToSingleUrl` 里，
 * 以 `if (cfg.type == X)` 的形式存在 —— 于是"新增一个通道要不要改核心"这件事
 * **没法脱离 Android 上下文测试**。搬到这里后：
 * - 决策只依赖 [ChannelSpec]（表里的数据），不查全局注册表、不碰网络、不读 Context；
 * - `WebhookSender` 退化成"取原料 → 调 [ChannelDispatch.plan] → 交给 NetworkClient"；
 * - 新通道是否被正确对待，可以用一个**没注册进全局表的合成描述符**直接测
 *   （见 `ChannelDescriptorContractTest.aBrandNewChannel_needsNothingButADescriptor`）。
 *
 * 优先级（与重构前逐条等价）：
 *   早失败（缺必填参数/secret）
 *   → 实发正文覆写（Server酱表单 / PushPlus 带 token 正文）
 *   → 平台模板包装 → 通用 webhook 的原样模板 body → 描述符 notify 默认正文
 */
internal class OutboundInput(
    val url: String,
    val secret: String?,
    /** 从 [url] 的 query 里取到的 chat_id（无则空串） */
    val chatId: String,
    /** 从 [url] 的 query 里取到的 token（无则空串） */
    val urlToken: String,
    /** [ChannelTransport.bodyOverride] 的产物；无覆写时 null。传 lambda 是为了不被选中时不构造 */
    val overrideBody: () -> String?,
    /** 平台模板包装（企微/钉钉/飞书的 text/markdown）；未命中时 null */
    val platformBody: () -> String?,
    /** 通用 webhook 的原样模板渲染结果（正文 + 该格式自己的 content-type） */
    val rawTemplateBody: () -> Pair<String, String>?,
    /** 描述符 notify 产出的默认正文 */
    val defaultBody: () -> String,
)

internal class OutboundPlan(
    val url: String,
    val body: String,
    val contentType: String,
    /** 交给 `WebhookSigner` 的密钥；null 表示签名层不参与 */
    val secretForSigner: String?,
    /** 非 null = 不发送，直接按该原因记一次业务失败送达结果 */
    val earlyFailReason: String?,
)

internal object ChannelDispatch {
    /** JSON 默认 content-type，与 `NetworkClient.sendWithRetry` 的参数默认值一致 */
    const val JSON_CONTENT_TYPE = "application/json; charset=utf-8"

    fun plan(spec: ChannelSpec, input: OutboundInput): OutboundPlan {
        val transport = spec.transport
        val secret = input.secret?.trim().orEmpty()

        val missingReason = when {
            transport.requiredUrlParam == UrlParam.CHAT_ID && input.chatId.isEmpty() ->
                transport.missingParamReason
            transport.requiredUrlParam == UrlParam.TOKEN && input.urlToken.isEmpty() ->
                transport.missingParamReason
            transport.secretRequired && secret.isEmpty() -> transport.missingParamReason
            else -> null
        }

        val targetUrl = if (transport.pathSuffix != null) {
            input.url.trimEnd('/') + transport.pathSuffix +
                "?token=" + java.net.URLEncoder.encode(secret, "UTF-8")
        } else {
            input.url
        }

        var body: String? = transport.bodyOverride?.let { override ->
            input.overrideBody()
        }
        var contentType = transport.contentType ?: JSON_CONTENT_TYPE

        if (body == null && transport.templateSupport != TemplateSupport.DISABLED) {
            body = input.platformBody()
        }
        if (body == null && transport.templateSupport == TemplateSupport.RAW_BODY) {
            input.rawTemplateBody()?.let {
                body = it.first
                contentType = it.second
            }
        }
        if (body == null) {
            body = input.defaultBody()
        }

        return OutboundPlan(
            url = targetUrl,
            body = body,
            contentType = contentType,
            // token 已进 URL 的平台不得再把 secret 交给签名层（会二次签名 / 覆盖凭据）
            secretForSigner = if (transport.secretAsQueryToken) null else input.secret,
            earlyFailReason = missingReason,
        )
    }
}
