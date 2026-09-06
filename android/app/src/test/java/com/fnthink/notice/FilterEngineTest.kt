package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * FilterEngine.normalize / matchKeyword 单元测试。
 *
 * normalize 是 Flutter 端 FilterService.normalizeForMatch 的对齐基准，
 * 对齐用例同时存在于 test/services/filter_service_golden_test.dart，两端必须一致。
 */
class FilterEngineTest {

    @Test
    fun normalize_fullwidthAscii() {
        assertEquals("abc123", FilterEngine.normalize("ＡＢＣ１２３"))
    }

    @Test
    fun normalize_fullwidthSpace() {
        assertEquals("abc def", FilterEngine.normalize("ＡＢＣ　ＤＥＦ"))
    }

    @Test
    fun normalize_fullwidthPunctuation() {
        assertEquals("hello!", FilterEngine.normalize("Ｈｅｌｌｏ！"))
    }

    @Test
    fun normalize_collapseWhitespace() {
        assertEquals("a b c", FilterEngine.normalize("  a \t b　　c  "))
    }

    @Test
    fun normalize_lowercase() {
        assertEquals("server error", FilterEngine.normalize("Server ERROR"))
    }

    @Test
    fun normalize_empty() {
        assertEquals("", FilterEngine.normalize(""))
    }

    @Test
    fun matchKeyword_plainContains() {
        assertTrue(FilterEngine.matchKeyword("xxx abc yyy", "abc"))
        assertFalse(FilterEngine.matchKeyword("xxx abc yyy", "xyz"))
    }

    @Test
    fun matchKeyword_emptyKeywordNeverMatches() {
        assertFalse(FilterEngine.matchKeyword("anything", "  "))
    }

    @Test
    fun matchKeyword_regexPrefix() {
        assertTrue(FilterEngine.matchKeyword("code 1234 ok", "re:\\d{4}"))
        assertFalse(FilterEngine.matchKeyword("no digits", "re:\\d{4}"))
    }

    @Test
    fun matchKeyword_regexTooLongRejected() {
        assertFalse(FilterEngine.matchKeyword("aaaa", "re:${"a".repeat(201)}"))
    }

    @Test
    fun matchKeyword_invalidRegexRejected() {
        assertFalse(FilterEngine.matchKeyword("anything", "re:["))
    }

    // ===== 过滤决策语义（产品确认的规则基线，修改决策顺序前先同步本组用例）=====
    //
    // 优先级：关键词黑名单 > 关键词白名单 > 应用过滤 > 默认放行。
    // 应用维度是「一个选择列表 + allow/block 模式开关」，同一应用不存在同时在
    // 两个名单的情况；白名单应用命中关键词黑名单仍拦截，黑名单应用命中
    // 关键词白名单仍放行。

    private fun filter(
        packageName: String,
        content: String,
        enabledPackages: Set<String>,
        whitelistKeywords: List<String> = emptyList(),
        blacklistKeywords: List<String> = emptyList(),
        filterMode: String = "allow"
    ) = FilterEngine.filter(
        packageName = packageName,
        title = "标题",
        content = content,
        subText = "",
        whitelistKeywords = whitelistKeywords,
        enabledPackages = enabledPackages,
        blacklistKeywords = blacklistKeywords,
        filterMode = filterMode
    )

    @Test
    fun filter_whitelistAppWithBlacklistKeyword_blocked() {
        // 白名单应用 + 内容命中关键词黑名单 → 不推送（关键词黑名单优先级最高）
        val result = filter(
            packageName = "com.example.app",
            content = "限时优惠 验证码 123456",
            enabledPackages = setOf("com.example.app"),
            blacklistKeywords = listOf("验证码")
        )
        assertFalse(result.allowed)
        assertEquals(FilterSource.BLACKLIST, result.source)
        assertEquals("验证码", result.keyword)
    }

    @Test
    fun filter_blacklistAppWithWhitelistKeyword_allowed() {
        // 黑名单应用（block 模式选中）+ 内容命中关键词白名单 → 正常推送
        val result = filter(
            packageName = "com.example.bank",
            content = "您的账户变动提醒",
            enabledPackages = setOf("com.example.bank"),
            whitelistKeywords = listOf("账户变动"),
            filterMode = "block"
        )
        assertTrue(result.allowed)
        assertEquals(FilterSource.WHITELIST, result.source)
    }

    @Test
    fun filter_allowModeSelectedApp_allowed() {
        // 白名单模式：选中的应用正常推送
        val result = filter(
            packageName = "com.example.app",
            content = "普通消息",
            enabledPackages = setOf("com.example.app")
        )
        assertTrue(result.allowed)
        assertEquals(FilterSource.DEFAULT, result.source)
    }

    @Test
    fun filter_allowModeUnselectedApp_blocked() {
        // 白名单模式：未选中的应用被应用过滤拦截
        val result = filter(
            packageName = "com.example.other",
            content = "普通消息",
            enabledPackages = setOf("com.example.app")
        )
        assertFalse(result.allowed)
        assertEquals(FilterSource.APP_FILTER, result.source)
    }

    @Test
    fun filter_blockModeSelectedApp_blocked() {
        // 黑名单模式：选中的应用被拦截
        val result = filter(
            packageName = "com.example.game",
            content = "普通消息",
            enabledPackages = setOf("com.example.game"),
            filterMode = "block"
        )
        assertFalse(result.allowed)
        assertEquals(FilterSource.APP_FILTER, result.source)
    }

    @Test
    fun filter_bothKeywordListsHit_blacklistWins() {
        // 关键词黑/白名单同时命中 → 拦截（黑名单关键词优先于白名单关键词）
        val result = filter(
            packageName = "com.example.app",
            content = "广告推送 优惠活动",
            enabledPackages = setOf("com.example.app"),
            whitelistKeywords = listOf("优惠"),
            blacklistKeywords = listOf("广告")
        )
        assertFalse(result.allowed)
        assertEquals(FilterSource.BLACKLIST, result.source)
    }
}
