package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 「按关键词搜本机通话记录」（T124 片C 的 `calls:search`）里**能在 JVM 上断的那一半**：
 * 转义与选择串的形状。与 [SmsSearchTest] 同一套判据（同一族的两条路，格式一处漂了就这里红）。
 *
 * 为什么这两条要紧：LIKE 的通配符不转义时，`50%` 会变成"50 开头的任意串"、`a_b` 会变成
 * "aXb" —— 那是**静默多带**（带出去的每一条都是隐私面，而读的人以为匹配是字面的）。
 * 真机上"搜出来的是不是那几条"只有真机+真通话记录能证，这里钉的是"拼出去的那个串字面对不对"。
 */
class CallLogSearchTest {

    @Test
    fun `转义百分号与下划线，且先转反斜杠本身`() {
        assertEquals("50\\%", CallLogSearch.escapeLike("50%"))
        assertEquals("a\\_b", CallLogSearch.escapeLike("a_b"))
        // ⚠ 顺序：先转 `\` 再转 `%` / `_`。反过来的话 `\%` 会被二次转义成 `\\%`，
        //   那匹配的是"反斜杠开头的串"——一个看起来对、实际搜错东西的形状。
        assertEquals(
            "\\\\\\%",
            CallLogSearch.escapeLike("\\%"),
        )
        assertEquals("10086", CallLogSearch.escapeLike("10086"))
    }

    @Test
    fun `选择串：号码与姓名两个 LIKE、都用 ESCAPE、参数两侧带通配`() {
        val (selection, args) = CallLogSearch.selectionFor("50%")
        assertTrue(
            "号码那一列要有 LIKE",
            selection.contains("number LIKE ?"),
        )
        assertTrue(
            "本机缓存的姓名那一列也要有 LIKE（对面可能只有名字）",
            selection.contains("name LIKE ?"),
        )
        assertTrue(
            "没有 ESCAPE 子句时，字面量里的反斜杠就是个普通字符 ⇒ 转义等于没写",
            selection.contains("ESCAPE '\\'"),
        )
        assertEquals("两个 LIKE 各吃一个参数", 2, args.size)
        assertEquals("%50\\%%", args[0])
        assertEquals("%50\\%%", args[1])
    }

    @Test
    fun `上限是个正数且不依赖 SQL 的 LIMIT 方言`() {
        assertTrue("一次带回去的条数要有上限", CallLogSearch.LIMIT > 0)
        // 与 SmsSearch 同一条：不把 "LIMIT n" 写进 sortOrder（各家 ROM 支持不一），
        // 条数上限在游标那一层收（见 CallLogSearch.search 里那句注释）。
        val source = appFile("src/main/kotlin/com/fnthink/notice/CallLogSearch.kt").readText()
        assertTrue(
            "sortOrder 不许带 LIMIT（那是 SQL 方言，各家 ROM 不一）",
            !source.contains("DESC LIMIT"),
        )
        assertTrue(
            "没权限要回 null 而不是空表（空表 = 搜了没有，两件事不一样）",
            source.contains("PERMISSION_GRANTED") &&
                source.contains("if (!granted) return null"),
        )
        assertTrue(
            "只读四列（号码/姓名/类型/时长），多带的每个字段都是一次新的对外披露面",
            source.contains("CallLog.Calls.NUMBER") &&
                source.contains("CallLog.Calls.CACHED_NAME") &&
                source.contains("CallLog.Calls.TYPE") &&
                source.contains("CallLog.Calls.DURATION"),
        )
    }

    private fun appFile(rel: String): java.io.File {
        var dir = java.io.File("").absoluteFile
        while (true) {
            val f = java.io.File(dir, "android/app/$rel")
            if (f.exists()) return f
            dir = dir.parentFile ?: break
        }
        throw AssertionError("找不到 $rel")
    }
}
