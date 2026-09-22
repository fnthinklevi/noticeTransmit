package com.fnthink.notice

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 应用通道 token 缓存管理测试（JVM 直测，fake fetcher 不出网）。
 *
 * 守住核心契约：**多个自建应用（不同凭据）的 token 分 key 缓存、互不驱逐、互不串用**；
 * invalidate 定向清除；提前刷新窗口；token 失效错误码识别。
 * ⚠ 全部使用假凭据字面量（测试专用，非真实凭据）。
 */
class AppChannelTokenManagerTest {

    /** 计数 fake：按凭据标记调用（fetcher 无入参，构造时绑定凭据），返回确定性 token */
    private class CountingFetcher(private val tag: String) : AppChannelTokenManager.TokenFetcher {
        var calls = 0
        override suspend fun fetch(): Pair<String, Int> {
            calls++
            return "token-$tag-$calls" to 7200
        }
    }

    private fun reset(vararg keys: String) {
        for (k in keys) AppChannelTokenManager.invalidate(k)
    }

    @Test
    fun multiChannel_tokensCachedPerCredential_noCrossEviction() = runBlocking {
        reset(
            AppChannelTokenManager.cacheKey("wecom_app", "corp-a+s-a"),
            AppChannelTokenManager.cacheKey("feishu_app", "app-b+s-b"),
        )
        val fa = CountingFetcher("a")
        val fb = CountingFetcher("b")

        val t1 = AppChannelTokenManager.getToken("wecom_app", "corp-a+s-a", fa)
        val t1Again = AppChannelTokenManager.getToken("wecom_app", "corp-a+s-a", fa)
        val t2 = AppChannelTokenManager.getToken("feishu_app", "app-b+s-b", fb)
        val t1Third = AppChannelTokenManager.getToken("wecom_app", "corp-a+s-a", fa)

        assertEquals("token-a-1", t1)
        assertEquals("token-a-1", t1Again) // 命中缓存
        assertEquals("token-b-1", t2)
        assertEquals("token-a-1", t1Third) // 另一凭据未驱逐本条
        assertEquals(1, fa.calls) // A 仅 fetch 一次
        assertEquals(1, fb.calls) // B 仅 fetch 一次
    }

    @Test
    fun invalidate_onlyClearsTargetedCredential() = runBlocking {
        reset(
            AppChannelTokenManager.cacheKey("wecom_app", "c-c"),
            AppChannelTokenManager.cacheKey("feishu_app", "c-d"),
        )
        val fc = CountingFetcher("c")
        val fd = CountingFetcher("d")

        AppChannelTokenManager.getToken("wecom_app", "c-c", fc)
        AppChannelTokenManager.getToken("feishu_app", "c-d", fd)

        // 模拟 message/send 对 wecom 返回 40014 → 定向失效
        AppChannelTokenManager.invalidate(AppChannelTokenManager.cacheKey("wecom_app", "c-c"))

        AppChannelTokenManager.getToken("wecom_app", "c-c", fc) // 重新 fetch
        AppChannelTokenManager.getToken("feishu_app", "c-d", fd) // 仍命中缓存

        assertEquals(2, fc.calls) // 仅 wecom 重取一次
        assertEquals(1, fd.calls) // 飞书仍命中缓存
    }

    @Test
    fun getToken_refetchesAfterExpiryBeyondEarlyRefreshWindow() = runBlocking {
        val key = AppChannelTokenManager.cacheKey("wecom_app", "c-e")
        reset(key)
        val f = CountingFetcher("e")
        val now = 1_000_000_000_000L

        val t1 = AppChannelTokenManager.getToken("wecom_app", "c-e", f, now)
        assertEquals("token-e-1", t1)
        // 有效期内（距过期 > 5 分钟）→ 命中
        AppChannelTokenManager.getToken("wecom_app", "c-e", f, now + 60_000L)
        // 距过期不足 5 分钟 → 提前刷新
        val t2 = AppChannelTokenManager.getToken(
            "wecom_app", "c-e", f, now + (7200L - 60L) * 1000L
        )
        assertEquals("token-e-2", t2)
        assertEquals(2, f.calls)
    }

    @Test
    fun isTokenErrorMessage_matchesKnownTokenErrorCodes() {
        assertTrue(AppChannelTokenManager.isTokenErrorMessage("业务失败 errcode=40014: invalid token"))
        assertTrue(AppChannelTokenManager.isTokenErrorMessage("业务失败 errcode=42001: token expired"))
        assertTrue(AppChannelTokenManager.isTokenErrorMessage("业务失败 errcode=99991661: feishu token"))
        assertFalse(AppChannelTokenManager.isTokenErrorMessage("业务失败 errcode=81013: invalid user"))
        assertFalse(AppChannelTokenManager.isTokenErrorMessage("OK"))
    }
}
