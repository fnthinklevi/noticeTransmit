package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 「按关键词搜本机通讯录」（T124 片C-4 的 `contacts:search`）里**能在 JVM 上断的那一半**：
 * 转义与选择串的形状。与 [CallLogSearchTest] / [SmsSearchTest] 同一套判据
 * （同一族的三条路，格式一处漂了就这里红）。
 *
 * 为什么这两条要紧：LIKE 的通配符不转义时，`50%` 会变成"50 开头的任意串"、`a_b` 会变成
 * "aXb" —— 那是**静默多带**（通讯录比短信更宽，带出去的每一条都是隐私面，
 * 而读的人以为匹配是字面的）。真机上"搜出来的是不是那几条"只有真机+真实通讯录能证，
 * 这里钉的是"拼出去的那个串字面对不对"。
 */
class ContactSearchTest {

    @Test
    fun `转义百分号与下划线，且先转反斜杠本身`() {
        assertEquals("50\\%", ContactSearch.escapeLike("50%"))
        assertEquals("a\\_b", ContactSearch.escapeLike("a_b"))
        // ⚠ 顺序：先转 `\` 再转 `%` / `_`。反过来的话 `\%` 会被二次转义成 `\\%`，
        //   那匹配的是"反斜杠开头的串"——一个看起来对、实际搜错东西的形状。
        assertEquals(
            "\\\\\\%",
            ContactSearch.escapeLike("\\%"),
        )
        assertEquals("10086", ContactSearch.escapeLike("10086"))
    }

    @Test
    fun `选择串：姓名与号码两个 LIKE、都用 ESCAPE、参数两侧带通配`() {
        val (selection, args) = ContactSearch.selectionFor("50%")
        assertTrue(
            "姓名那一列要有 LIKE",
            selection.contains("display_name LIKE ?"),
        )
        assertTrue(
            "号码那一列也要有 LIKE（对面可能只有号码）",
            selection.contains("data1 LIKE ?"),
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
        assertTrue("一次带回去的条数要有上限", ContactSearch.LIMIT > 0)
        // 与 SmsSearch / CallLogSearch 同一条：不把 "LIMIT n" 写进 sortOrder
        // （各家 ROM 支持不一），条数上限在游标那一层收（见 search 里那句注释）。
        val source = appFile("src/main/kotlin/com/fnthink/notice/ContactSearch.kt").readText()
        assertTrue(
            "sortOrder 不许带 LIMIT（那是 SQL 方言，各家 ROM 不一）",
            !source.contains("ASC LIMIT"),
        )
        assertTrue(
            "没权限要回 null 而不是空表（空表 = 搜了没有，两件事不一样）",
            source.contains("PERMISSION_GRANTED") &&
                source.contains("if (!granted) return null"),
        )
        assertTrue(
            "只读两列（姓名/号码），多带的每个字段都是一次新的对外披露面",
            source.contains("Phone.DISPLAY_NAME") &&
                source.contains("Phone.NUMBER"),
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
