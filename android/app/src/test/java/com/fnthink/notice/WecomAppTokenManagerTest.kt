package com.fnthink.notice

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * WecomAppTokenManager 多通道缓存行为测试（JVM 直测，fake fetcher 不出网）。
 *
 * 守住核心契约：**多个企业微信自建应用通道（不同 corpid/corpsecret）的 token
 * 互不驱逐、互不串用**；invalidate 仅清除目标凭据。
 * ⚠ 全部使用假凭据字面量（测试专用，非真实凭据）。
 */
class WecomAppTokenManagerTest {

    /** 计数 fake：按 corpid 记录调用次数，返回确定性 token */
    private class CountingFetcher : WecomAppTokenManager.TokenFetcher {
        val calls = mutableListOf<String>()
        override suspend fun fetch(corpid: String, corpsecret: String): Pair<String, Int> {
            calls += corpid
            return "token-$corpid" to 7200
        }
    }

    @Test
    fun multiChannel_tokensCachedPerCredential_noCrossEviction() = runBlocking {
        val f = CountingFetcher()
        // 清理可能的历史残留（全局单例状态）：使用独立凭据 + 先失效
        WecomAppTokenManager.invalidate(WecomAppTokenManager.cacheKey("corp-a", "s-a"))
        WecomAppTokenManager.invalidate(WecomAppTokenManager.cacheKey("corp-b", "s-b"))

        val t1 = WecomAppTokenManager.getToken("corp-a", "s-a", f)
        val t1Again = WecomAppTokenManager.getToken("corp-a", "s-a", f) // 命中缓存
        val t2 = WecomAppTokenManager.getToken("corp-b", "s-b", f)      // 另一凭据
        val t1Third = WecomAppTokenManager.getToken("corp-a", "s-a", f) // A 未被 B 驱逐

        assertEquals("token-corp-a", t1)
        assertEquals("token-corp-a", t1Again)
        assertEquals("token-corp-b", t2)
        assertEquals("token-corp-a", t1Third)
        // 各凭据只 fetch 一次（A 两次取用共用一次 gettoken）
        assertEquals(1, f.calls.count { it == "corp-a" })
        assertEquals(1, f.calls.count { it == "corp-b" })
    }

    @Test
    fun invalidate_onlyClearsTargetedCredential() = runBlocking {
        val f = CountingFetcher()
        WecomAppTokenManager.invalidate(WecomAppTokenManager.cacheKey("corp-c", "s-c"))
        WecomAppTokenManager.invalidate(WecomAppTokenManager.cacheKey("corp-d", "s-d"))

        WecomAppTokenManager.getToken("corp-c", "s-c", f)
        WecomAppTokenManager.getToken("corp-d", "s-d", f)

        // 模拟 message/send 对 corp-c 返回 40014 → 定向失效
        WecomAppTokenManager.invalidate(WecomAppTokenManager.cacheKey("corp-c", "s-c"))

        WecomAppTokenManager.getToken("corp-c", "s-c", f) // 应重新 fetch
        WecomAppTokenManager.getToken("corp-d", "s-d", f) // 应命中缓存

        assertEquals(2, f.calls.count { it == "corp-c" })
        assertEquals(1, f.calls.count { it == "corp-d" })
    }

    @Test
    fun getToken_refetchesAfterExpiryBeyondEarlyRefreshWindow() = runBlocking {
        val f = CountingFetcher()
        val key = WecomAppTokenManager.cacheKey("corp-e", "s-e")
        WecomAppTokenManager.invalidate(key)

        val now = 1_000_000_000_000L
        val t1 = WecomAppTokenManager.getToken("corp-e", "s-e", f, now)
        assertEquals("token-corp-e", t1)
        // 有效期内（距过期 > 5 分钟）→ 命中
        WecomAppTokenManager.getToken("corp-e", "s-e", f, now + 60_000L)
        // 距过期不足 5 分钟 → 提前刷新
        val t2 = WecomAppTokenManager.getToken(
            "corp-e", "s-e", f, now + (7200L - 60L) * 1000L
        )
        assertEquals("token-corp-e", t2)
        assertEquals(2, f.calls.size)
    }

    @Test
    fun isTokenErrorMessage_matchesKnownTokenErrorCodes() {
        assertTrue(WecomAppTokenManager.isTokenErrorMessage("业务失败 errcode=40014: invalid token"))
        assertTrue(WecomAppTokenManager.isTokenErrorMessage("业务失败 errcode=42001: token expired"))
        assertFalse(WecomAppTokenManager.isTokenErrorMessage("业务失败 errcode=81013: invalid user"))
        assertFalse(WecomAppTokenManager.isTokenErrorMessage("OK"))
    }
}
