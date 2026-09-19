package com.fnthink.notice

import org.json.JSONObject
import java.net.URLEncoder

/**
 * 企业微信自建应用 access_token 管理（F4 收尾）。
 *
 * 两阶段请求模型：message/send 前须先 GET /cgi-bin/gettoken 换取 access_token
 * （官方有效期 7200s）。[WecomAppTokenManager] 按 (corpid, corpsecret) 缓存 token，
 * **过期前 5 分钟提前刷新**，获取过程 Mutex 串行化（并发推送只打一次 gettoken）。
 * token 仅存内存不落盘——进程重启重新获取即可，无持久化价值。
 *
 * 测试性：token 实际获取经 [WecomAppTokenManager.TokenFetcher] 注入（生产走 OkHttp，
 * 测试注入 fake）；响应解析与 URL/载荷构造拆为纯函数 [WecomAppTokenLogic]（JVM 直测）。
 */
object WecomAppTokenManager {

    /** message/send 返回这些 errcode 时，调用方应 [invalidate] 后用新 token 重试一次 */
    const val ERR_INVALID_TOKEN = 40014
    const val ERR_TOKEN_EXPIRED = 42001
    const val ERR_INVALID_CREDENTIAL = 40001
    val TOKEN_ERROR_CODES = setOf(ERR_INVALID_TOKEN, ERR_TOKEN_EXPIRED, ERR_INVALID_CREDENTIAL)

    fun isTokenError(errcode: Int): Boolean = errcode in TOKEN_ERROR_CODES

    /** 从 WebhookResponseParser 的 message（形如 "业务失败 errcode=40014: ..."）识别 token 失效 */
    fun isTokenErrorMessage(message: String): Boolean {
        val m = Regex("errcode=(\\d+)").find(message) ?: return false
        return isTokenError(m.groupValues[1].toIntOrNull() ?: -1)
    }

    /** 提前刷新窗口：距过期不足 5 分钟即重新获取（避免边界期 token 失效） */
    const val EARLY_REFRESH_MS = 5 * 60 * 1000L

    /** token 获取异常（gettoken 返回非 0 errcode / 非 JSON / 网络失败） */
    class TokenFetchException(val errcode: Int, message: String) : Exception(message)

    data class CachedToken(val cacheKey: String, val token: String, val expiresAt: Long)

    /** token 获取器抽象（测试注入 fake；生产实现走 OkHttp） */
    fun interface TokenFetcher {
        /** @return (access_token, expiresInSeconds) */
        suspend fun fetch(corpid: String, corpsecret: String): Pair<String, Int>
    }

    /**
     * token 缓存：按 (corpid, corpsecret) 摘要 **分 key 存储**。
     * 用户可配置多个企业微信自建应用通道，单条缓存会让交替推送反复失效重取
     * （gettoken 有频控），Map 分 key 后各凭据互不驱逐。
     */
    private val cache = LinkedHashMap<String, CachedToken>()
    private val lock = Any()

    fun cacheKey(corpid: String, corpsecret: String): String =
        "${corpid}:${Integer.toHexString(corpsecret.hashCode())}"

    fun cachedToken(key: String): CachedToken? = synchronized(lock) { cache[key] }

    /** 是否需要刷新：无缓存 / 已过期 / 距过期不足提前刷新窗口。
     *  Map 按 key 存取不存在串 key；key 参数为防御性保留（与缓存条目一致性断言用）。 */
    fun needsRefresh(cached: CachedToken?, key: String, now: Long): Boolean =
        cached == null || cached.cacheKey != key ||
            now >= cached.expiresAt - EARLY_REFRESH_MS

    /**
     * 获取 token（按凭据分 key 缓存）。
     * 命中判定在锁内；gettoken 网络请求在锁外执行（不阻塞其他凭据的命中路径）。
     * 同 key 并发极端下会重复 fetch 一次——企业微信对有效期内重复 gettoken 返回
     * 同一 token，无害。fetch 失败抛 [TokenFetchException]，不缓存任何结果。
     */
    suspend fun getToken(
        corpid: String,
        corpsecret: String,
        fetcher: TokenFetcher,
        now: Long = System.currentTimeMillis(),
    ): String {
        val key = cacheKey(corpid, corpsecret)
        synchronized(lock) {
            val cached = cache[key]
            if (cached != null && !needsRefresh(cached, key, now)) {
                return cached.token
            }
        }
        val (token, expiresIn) = fetcher.fetch(corpid, corpsecret)
        if (token.isEmpty()) {
            throw TokenFetchException(-1, "gettoken 返回空 access_token")
        }
        synchronized(lock) {
            cache[key] = CachedToken(key, token, now + expiresIn * 1000L)
        }
        return token
    }

    /**
     * message/send 返回 token 失效 errcode（40014/42001）后调用：
     * **仅清除该凭据**的缓存并强制重取，其他通道的 token 不受影响。
     */
    fun invalidate(key: String) {
        synchronized(lock) { cache.remove(key) }
    }
}

/** 纯函数集合（URL/载荷构造与响应解析，JVM 直测） */
object WecomAppTokenLogic {

    /** gettoken 响应解析：errcode != 0 抛 [WecomAppTokenManager.TokenFetchException] */
    fun parseTokenResponse(body: String): Pair<String, Int> {
        val json = try {
            JSONObject(body)
        } catch (e: Exception) {
            throw WecomAppTokenManager.TokenFetchException(
                -1, "gettoken 响应非 JSON: ${body.take(120)}"
            )
        }
        val errcode = json.optInt("errcode", 0)
        if (errcode != 0) {
            throw WecomAppTokenManager.TokenFetchException(
                errcode, "gettoken 失败 errcode=$errcode: ${json.optString("errmsg")}"
            )
        }
        val token = json.optString("access_token", "")
        if (token.isEmpty()) {
            throw WecomAppTokenManager.TokenFetchException(-1, "gettoken 响应缺少 access_token")
        }
        return token to json.optInt("expires_in", 7200)
    }

    /** base 地址规范化：空回退官方地址；仅接受 http/https（拒绝其他 scheme） */
    fun normalizeBase(raw: String): String {
        val base = raw.trim().trimEnd('/')
        val candidate = base.ifEmpty { "https://qyapi.weixin.qq.com" }
        require(candidate.startsWith("https://") || candidate.startsWith("http://")) {
            "企业微信自建应用地址必须以 http(s):// 开头"
        }
        return candidate
    }

    fun tokenUrl(base: String, corpid: String, corpsecret: String): String {
        val enc = { s: String -> URLEncoder.encode(s, "UTF-8") }
        return "${normalizeBase(base)}/cgi-bin/gettoken?corpid=${enc(corpid)}&corpsecret=${enc(corpsecret)}"
    }

    fun sendUrl(base: String, accessToken: String): String =
        "${normalizeBase(base)}/cgi-bin/message/send?access_token=${URLEncoder.encode(accessToken, "UTF-8")}"

    /**
     * message/send 载荷：msgtype text（默认）或 markdown（message_format=markdown 时）。
     * touser 空回退 @all。
     */
    fun buildSendPayload(
        agentid: Long,
        touser: String,
        content: String,
        markdown: Boolean,
    ): String {
        require(agentid > 0) { "agentid 无效（须为正整数）" }
        val json = JSONObject()
        if (markdown) {
            json.put("msgtype", "markdown")
            json.put("markdown", JSONObject().put("content", content))
        } else {
            json.put("msgtype", "text")
            json.put("text", JSONObject().put("content", content))
        }
        json.put("agentid", agentid)
        json.put("touser", touser.ifEmpty { "@all" })
        return json.toString()
    }

    /** extra_config 解析（来自通道配置 JSON 的 extra_config 字段；agentid 兼容数字/字符串存储） */
    fun parseExtraConfig(extra: JSONObject?): Triple<String, Long, String> {
        val corpid = extra?.optString("corpid", "")?.trim() ?: ""
        val agentid = extra?.optString("agentid", "")?.trim()?.toLongOrNull() ?: -1L
        val touser = extra?.optString("touser", "")?.trim() ?: ""
        return Triple(corpid, agentid, touser)
    }
}
