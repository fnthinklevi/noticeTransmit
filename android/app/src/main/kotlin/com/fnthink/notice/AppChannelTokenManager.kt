package com.fnthink.notice

import java.net.URLEncoder

/**
 * 应用通道 access_token 缓存管理（自建应用体系通用）。
 *
 * 自建应用通道（企业微信自建应用 / 飞书自建应用…）均为两阶段模型：
 * 先以凭据换取 access_token，再携带 token 调用消息发送端点。
 * 本管理器按「通道类型 + 凭据摘要」**分 key 缓存** token，
 * 多通道、多凭据互不驱逐；过期前 5 分钟提前刷新；失效定向清除。
 *
 * token 的实际获取经 [AppChannelTokenFetcher] 注入（各通道 Spec 提供实现，
 * 生产走 OkHttp，测试注入 fake——不出网、不写真实凭据）。
 */
object AppChannelTokenManager {

    /** 消息发送端点返回这些业务码时，调用方应 [invalidate] 对应凭据后重试一次 */
    const val ERR_INVALID_TOKEN = 40014 // 企业微信：invalid access_token
    const val ERR_TOKEN_EXPIRED = 42001 // 企业微信：access_token expired
    const val ERR_INVALID_CREDENTIAL = 40001 // 企业微信：invalid credential
    const val ERR_FEISHU_TOKEN_INVALID = 99991661 // 飞书：invalid access token
    val TOKEN_ERROR_CODES = setOf(
        ERR_INVALID_TOKEN, ERR_TOKEN_EXPIRED, ERR_INVALID_CREDENTIAL, ERR_FEISHU_TOKEN_INVALID,
    )

    fun isTokenError(errcode: Int): Boolean = errcode in TOKEN_ERROR_CODES

    /**
     * 从 WebhookResponseParser 的 message（形如 "业务失败 errcode=42001: ..." 或
     * "业务失败 code=99991661: ..."）识别 token 失效。
     *
     * ⚠ 必须同时认两种参数名：企微用 errcode，飞书用 code。原实现只匹配 errcode=，
     *   于是飞书 token 过期时这条判定永远为 false ⇒ 不清缓存、不重试一次，此后持续失败。
     */
    private val TOKEN_ERROR_PARAM = Regex("(?:errcode|code)=(\\d+)")

    fun isTokenErrorMessage(message: String): Boolean {
        val m = TOKEN_ERROR_PARAM.find(message) ?: return false
        return isTokenError(m.groupValues[1].toIntOrNull() ?: -1)
    }

    /** 提前刷新窗口：距过期不足 5 分钟即重新获取（避免边界期 token 失效） */
    const val EARLY_REFRESH_MS = 5 * 60 * 1000L

    /** token 获取异常（token 端点返回业务错误 / 非 JSON / 网络失败） */
    class TokenFetchException(val errcode: Int, message: String) : Exception(message)

    data class CachedToken(val cacheKey: String, val token: String, val expiresAt: Long)

    /** token 获取器抽象（测试注入 fake；各通道 Spec 提供生产实现） */
    fun interface TokenFetcher {
        /** @return (access_token, expiresInSeconds) */
        suspend fun fetch(): Pair<String, Int>
    }

    /** 缓存：key = type + 凭据摘要；value = token 与过期时间。仅存内存不落盘。 */
    private val cache = LinkedHashMap<String, CachedToken>()
    private val lock = Any()

    fun cacheKey(type: String, credential: String): String =
        "$type:${Integer.toHexString(credential.hashCode())}"

    fun cachedToken(key: String): CachedToken? = synchronized(lock) { cache[key] }

    /** 是否需要刷新：无缓存 / 已过期 / 距过期不足提前刷新窗口 */
    fun needsRefresh(cached: CachedToken?, now: Long): Boolean =
        cached == null || now >= cached.expiresAt - EARLY_REFRESH_MS

    /**
     * 获取 token（按 type+凭据 分 key 缓存）。
     * 命中判定在锁内；token 网络请求在锁外执行（不阻塞其他凭据的命中路径）。
     * 同 key 并发极端下会重复 fetch 一次——各平台对有效期内重复换取返回
     * 同一 token，无害。fetch 失败抛 [TokenFetchException]，不缓存任何结果。
     */
    suspend fun getToken(
        type: String,
        credential: String,
        fetcher: TokenFetcher,
        now: Long = System.currentTimeMillis(),
    ): String {
        val key = cacheKey(type, credential)
        synchronized(lock) {
            val cached = cache[key]
            if (cached != null && !needsRefresh(cached, now)) {
                return cached.token
            }
        }
        val (token, expiresIn) = fetcher.fetch()
        if (token.isEmpty()) {
            throw TokenFetchException(-1, "token 端点返回空 access_token")
        }
        synchronized(lock) {
            cache[key] = CachedToken(key, token, now + expiresIn * 1000L)
        }
        return token
    }

    /** 消息发送返回 token 失效业务码后调用：**仅清除该凭据**的缓存，其他通道不受影响 */
    fun invalidate(key: String) {
        synchronized(lock) { cache.remove(key) }
    }
}

/**
 * 应用通道 token 获取的通用帮助（URL 编码 / 响应解析）。
 * 各通道的端点与响应结构差异由对应 Spec 实现。
 */
object AppChannelTokenHelper {

    fun urlEncode(value: String): String = URLEncoder.encode(value, "UTF-8")

    fun normalizeBase(raw: String, fallback: String): String {
        val base = raw.trim().trimEnd('/')
        val candidate = base.ifEmpty { fallback }
        require(candidate.startsWith("https://") || candidate.startsWith("http://")) {
            "API 地址必须以 http(s):// 开头"
        }
        return candidate
    }
}
