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
}
