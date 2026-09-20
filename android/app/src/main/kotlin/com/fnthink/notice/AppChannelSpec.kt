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
    val secret: String,       // corpsecret / app_secret（加密存储）
    val config: JSONObject,   // 扩展参数（corpid/agentid/touser 或 app_id/receive_id_type/receive_id）
    val messageFormat: String,
    val enabled: Boolean,
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
)

/** 扩展参数字段描述（Dart 设置页按此渲染输入框，kinds: text/number） */
data class ConfigField(
    val key: String,
    val labelZh: String,
    val labelEn: String,
    val hintZh: String,
    val hintEn: String,
    val kind: String = "text",
    val required: Boolean = false,
)

object AppChannelRegistry {

    /** 字节上限截断（不截断代理项对） */
    fun truncateByBytes(text: String, maxBytes: Int): String {
        if (text.toByteArray(Charsets.UTF_8).size <= maxBytes) return text
        var end = text.length
        while (end > 0 && text.substring(0, end).toByteArray(Charsets.UTF_8).size > maxBytes) {
            end--
        }
        return text.substring(0, end)
    }

    /** 字符上限截断（不截断代理项对） */
    fun truncateByChars(text: String, maxChars: Int): String {
        if (text.length <= maxChars) return text
        var end = maxChars
        if (end > 0 && Character.isHighSurrogate(text[end - 1])) end--
        return text.substring(0, end)
    }

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
        truncate = { text -> truncateByBytes(text, 2048) },
        configSchema = listOf(
            ConfigField(
                "corpid", "企业 ID（corpid）", "Corp ID (corpid)",
                "企业微信管理后台「我的企业」页可见", "Visible in WeCom admin console", required = true,
            ),
            ConfigField(
                "agentid", "应用 agentid", "App agentid",
                "纯数字，自建应用详情页可见", "Numeric, from the app details page", kind = "number", required = true,
            ),
            ConfigField(
                "touser", "接收人 touser", "Receiver touser",
                "可选，默认 @all；多人用 | 分隔", "Optional, default @all; separate users with |",
            ),
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
        truncate = { text -> truncateByChars(text, 3000) },
        configSchema = listOf(
            ConfigField(
                "app_id", "应用 app_id", "App app_id",
                "飞书开放平台应用凭证页可见", "From the Feishu app credentials page", required = true,
            ),
            ConfigField(
                "receive_id_type", "接收人类型", "Receive ID type",
                "chat_id（群聊）或 open_id（单人）", "chat_id (group) or open_id (user)",
            ),
            ConfigField(
                "receive_id", "接收人 ID receive_id", "Receiver receive_id",
                "群聊 oc_ 开头 / 单人 ou_ 开头", "oc_ for chats, ou_ for users", required = true,
            ),
        ),
    )

    val SPECS = listOf(wecomAppSpec, feishuAppSpec)

    private val byType = SPECS.associateBy { it.type }

    fun spec(type: String): AppChannelSpec? = byType[type]

    fun exists(type: String): Boolean = byType.containsKey(type)
}

/** 各平台 token 响应解析（含错误码语义） */
object AppChannelsTokenParsers {

    /** 企业微信：{"errcode":0,"access_token":"...","expires_in":7200} */
    fun parseWecomToken(body: String): Pair<String, Int> {
        val json = JSONObject(body)
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
        val json = JSONObject(body)
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
