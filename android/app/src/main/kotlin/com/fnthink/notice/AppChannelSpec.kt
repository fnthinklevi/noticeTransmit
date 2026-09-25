package com.fnthink.notice

import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject

/**
 * 应用通道模板（自建应用体系）。
 *
 * 与 webhook 通道（URL 即端点）不同，自建应用是「凭据换 token → 调用消息端点」的
 * 两阶段 API 模型。本文件定义各应用通道的**模板**：凭据读取、token 获取、载荷构造、
 * 发送端点与内容截断，由 [AppChannelRegistry] 统一登记，`AppChannelSender` 按模板
 * 执行发送。新增自建应用通道 = 在 SPECS 加一个 spec 实现。
 *
 * 响应判定：发送端点均为对应平台的开放 API 域名，`NetworkClient` 按 URL host
 * 解析响应（企微 errcode / 飞书 code），与既有判定同构。
 */
object AppChannelTypes {
    const val WECOM_APP = "wecom_app"
    const val FEISHU_APP = "feishu_app"

    const val WECOM_OFFICIAL_BASE = "https://qyapi.weixin.qq.com"
    const val FEISHU_OFFICIAL_BASE = "https://open.feishu.cn"
}

/** 应用通道运行时配置（来自 app_channels 表 / 原生加密存储） */
data class AppChannelConfig(
    val id: String,
    val name: String,
    val type: String,
    val baseUrl: String,
    val secret: String, // corpsecret / app_secret（加密存储）
    val config: JSONObject, // 扩展参数（corpid/agentid/touser 或 app_id/receive_id_type/receive_id）
    val messageFormat: String,
    val enabled: Boolean,
    /** T12 主备角色。`NONE` 的通道由 `ConfigManager.getAppChannelConfigs()` 挡掉，
     *  但 `getAppChannelConfigById()`（「测试」按钮走它）**看得到** —— 不参与推送
     *  不该连"手动测一下"都不让做。 */
    val role: ChannelRole = ChannelRole.PRIMARY,
)

/**
 * 单个应用通道模板：
 * - [fetchToken]：两阶段第一步，凭据换 token（同步 HTTP，调用方保证 IO 线程）
 * - [sendTarget]：两阶段第二步的端点与鉴权头（企微 token 走 query、飞书走 Bearer header）
 * - [buildPayload]：消息载荷（content 已截断；markdown 由模板决定是否支持）
 * - [truncate]：正文截断（各平台上限不同）
 */
class AppChannelSpec(
    val type: String,
    val officialBase: String,
    val fetchToken: (AppChannelConfig, String, OkHttpClient) -> Pair<String, Int>,
    val sendTarget: (AppChannelConfig, String, String) -> Pair<String, Map<String, String>>,
    val buildPayload: (AppChannelConfig, String, Boolean) -> String,
    val truncate: (String) -> String,
    val configSchema: List<ConfigField>,
    /** Dart ARB 资源名（通道类型标签）。译文只在 ARB。 */
    val labelKey: String,
    /** Dart 图标表 key */
    val iconKey: String,
    /** 该平台的 markdown 消息是否真被支持（飞书统一降级为 text） */
    val supportsMarkdown: Boolean,
) {
    /** 能力位：与 webhook 侧同一套名字，Dart 只读名字不猜平台 */
    fun capabilities(): List<String> = buildList {
        add(Capability.SECRET_USED) // secret = corpsecret / app_secret，必填凭据
        if (supportsMarkdown) add(Capability.MARKDOWN)
    }

    /** `getChannelDescriptors` 的载荷（应用通道族） */
    fun descriptor(): Map<String, Any?> = mapOf(
        "family" to "app",
        "key" to type,
        "nativeType" to type,
        "labelKey" to labelKey,
        "iconKey" to iconKey,
        "officialBase" to officialBase,
        "hosts" to listOf(officialBase.removePrefix("https://")),
        "capabilities" to capabilities(),
        "fields" to configSchema.map { it.toMap() },
    )
}

/**
 * 扩展参数字段描述。第 5 步起直接复用 webhook 侧的 [FieldSpec]：
 * 原来的 `ConfigField` 另存中英双份 label/hint 字面量（与 ARB 已漂移），
 * 且 `configSchema` 在生产代码里**零消费者**。保留别名是为了测试与调用点可读。
 */
typealias ConfigField = FieldSpec

object AppChannelRegistry {

    /**
     * 字节上限截断 / 字符上限截断。
     *
     * 实现已并入 `ChannelDefaults`（第 4 步）：此前 webhook 侧的 Telegram/Discord 与
     * 应用通道侧各写了一份同样的「超长就回退一位、不拆代理项对」逻辑，
     * 三份实现在边界（末位是代理项、恰好等于上限）上只要有一处改动就会分叉。
     * 这里保留同名入口，行为逐字节不变。
     */
    fun truncateByBytes(text: String, maxBytes: Int): String =
        ChannelDefaults.truncateBytes(text, maxBytes)

    fun truncateByChars(text: String, maxChars: Int): String =
        ChannelDefaults.truncateChars(text, maxChars)

    /** 企业微信自建应用 */
    private val wecomAppSpec = AppChannelSpec(
        type = AppChannelTypes.WECOM_APP,
        officialBase = AppChannelTypes.WECOM_OFFICIAL_BASE,
        fetchToken = { config, base, client ->
            val corpid = config.config.optString("corpid", "").trim()
            require(corpid.isNotEmpty() && config.secret.isNotEmpty()) {
                "企业微信自建应用缺少 corpid 或 corpsecret"
            }
            val url = base.trimEnd('/') + "/cgi-bin/gettoken?corpid=" +
                AppChannelTokenHelper.urlEncode(corpid) +
                "&corpsecret=" + AppChannelTokenHelper.urlEncode(config.secret)
            val request = Request.Builder().url(url).build()
            client.newCall(request).execute().use { response ->
                AppChannelsTokenParsers.parseWecomToken(response.body?.string() ?: "")
            }
        },
        sendTarget = { config, base, token ->
            val url = base.trimEnd('/') + "/cgi-bin/message/send?access_token=" +
                AppChannelTokenHelper.urlEncode(token)
            Pair(url, emptyMap())
        },
        buildPayload = { config, content, markdown ->
            val agentid = config.config.optString("agentid", "0").trim().toLongOrNull() ?: 0L
            require(agentid > 0) { "agentid 无效（须为正整数）" }
            val touser = config.config.optString("touser", "").ifEmpty { "@all" }
            val json = JSONObject()
            if (markdown) {
                json.put("msgtype", "markdown")
                json.put("markdown", JSONObject().put("content", content))
            } else {
                json.put("msgtype", "text")
                json.put("text", JSONObject().put("content", content))
            }
            json.put("agentid", agentid)
            json.put("touser", touser)
            json.toString()
        },
        truncate = { text -> truncateByBytes(text, ChannelLimits.WECOM_APP_BYTES) },
        labelKey = "channelTypeWecomApp",
        iconKey = AppChannelTypes.WECOM_APP,
        supportsMarkdown = true,
        configSchema = listOf(
            ConfigField("corpid", "appChannelCorpidLabel", required = true),
            ConfigField(
                "agentid", "appChannelAgentidLabel",
                kind = FieldKind.NUMBER, required = true, defaultValue = "0",
            ),
            ConfigField("touser", "appChannelTouserLabel", defaultValue = "@all"),
        ),
    )

    /** 飞书自建应用 */
    private val feishuAppSpec = AppChannelSpec(
        type = AppChannelTypes.FEISHU_APP,
        officialBase = AppChannelTypes.FEISHU_OFFICIAL_BASE,
        fetchToken = { config, base, client ->
            val appId = config.config.optString("app_id", "").trim()
            require(appId.isNotEmpty() && config.secret.isNotEmpty()) {
                "飞书自建应用缺少 app_id 或 app_secret"
            }
            val url = base.trimEnd('/') + "/open-apis/auth/v3/tenant_access_token/internal"
            val body = JSONObject()
                .put("app_id", appId)
                .put("app_secret", config.secret)
                .toString()
                .toRequestBody("application/json; charset=utf-8".toMediaType())
            val request = Request.Builder().url(url).post(body).build()
            client.newCall(request).execute().use { response ->
                AppChannelsTokenParsers.parseFeishuToken(response.body?.string() ?: "")
            }
        },
        sendTarget = { config, base, token ->
            val receiveIdType = config.config.optString("receive_id_type", "chat_id")
            val url = base.trimEnd('/') + "/open-apis/im/v1/messages?receive_id_type=" +
                AppChannelTokenHelper.urlEncode(receiveIdType)
            Pair(url, mapOf("Authorization" to "Bearer $token"))
        },
        buildPayload = { config, content, markdown ->
            // 飞书自建应用 IM 消息：text 原生支持；markdown 需 post/interactive 卡片，
            // 通知转发场景统一降级为 text（换行保留），保证送达
            val receiveId = config.config.optString("receive_id", "").trim()
            require(receiveId.isNotEmpty()) { "receive_id 不能为空" }
            val contentJson = JSONObject().put("text", content).toString()
            JSONObject()
                .put("receive_id", receiveId)
                .put("msg_type", "text")
                .put("content", contentJson)
                .toString()
        },
        truncate = { text -> truncateByChars(text, ChannelLimits.FEISHU_APP_CHARS) },
        labelKey = "channelTypeFeishuApp",
        iconKey = AppChannelTypes.FEISHU_APP,
        supportsMarkdown = false,
        configSchema = listOf(
            ConfigField("app_id", "appChannelAppidLabel", required = true),
            ConfigField(
                "receive_id_type", "appChannelReceiveIdTypeLabel",
                defaultValue = "chat_id",
            ),
            ConfigField("receive_id", "appChannelReceiveIdLabel", required = true),
        ),
    )

    val SPECS = listOf(wecomAppSpec, feishuAppSpec)

    private val byType = SPECS.associateBy { it.type }

    fun spec(type: String): AppChannelSpec? = byType[type]

    fun exists(type: String): Boolean = byType.containsKey(type)

    /** 全部应用通道描述符（顺序即 Dart「新增通道」弹层的展示顺序） */
    fun descriptors(): List<Map<String, Any?>> = SPECS.map { it.descriptor() }
}

/** 各平台 token 响应解析（含错误码语义） */
object AppChannelsTokenParsers {

    /** 企业微信：{"errcode":0,"access_token":"...","expires_in":7200} */
    fun parseWecomToken(body: String): Pair<String, Int> {
        // 网关/代理错误页、空响应或非 JSON 错误结构都会让 JSONObject 构造函数抛异常。
        // 必须在此收敛为 TokenFetchException（调用链的失败约定），否则 JSONException
        // 会绕过 AppChannelSender 的 catch 冒泡，导致进程崩溃或通道静默失效。
        val json = try {
            JSONObject(body)
        } catch (e: Exception) {
            throw AppChannelTokenManager.TokenFetchException(
                -1, "gettoken 响应非 JSON（网关/代理错误页？）: ${body.take(120)}"
            )
        }
        val errcode = json.optInt("errcode", 0)
        if (errcode != 0) {
            throw AppChannelTokenManager.TokenFetchException(
                errcode, "gettoken 失败 errcode=$errcode: ${json.optString("errmsg")}"
            )
        }
        val token = json.optString("access_token", "")
        if (token.isEmpty()) {
            throw AppChannelTokenManager.TokenFetchException(-1, "gettoken 响应缺少 access_token")
        }
        return token to json.optInt("expires_in", 7200)
    }

    /** 飞书：{"code":0,"tenant_access_token":"t-...","expire":7200} */
    fun parseFeishuToken(body: String): Pair<String, Int> {
        // 同上：非 JSON 响应统一收敛为 TokenFetchException，避免异常冒泡崩溃
        val json = try {
            JSONObject(body)
        } catch (e: Exception) {
            throw AppChannelTokenManager.TokenFetchException(
                -1, "tenant_access_token 响应非 JSON（网关/代理错误页？）: ${body.take(120)}"
            )
        }
        val code = json.optInt("code", 0)
        if (code != 0) {
            throw AppChannelTokenManager.TokenFetchException(
                code, "tenant_access_token 获取失败 code=$code: ${json.optString("msg")}"
            )
        }
        val token = json.optString("tenant_access_token", "")
        if (token.isEmpty()) {
            throw AppChannelTokenManager.TokenFetchException(-1, "响应缺少 tenant_access_token")
        }
        return token to json.optInt("expire", 7200)
    }
}
