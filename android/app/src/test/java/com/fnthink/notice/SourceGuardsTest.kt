package com.fnthink.notice

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * [stripComments] 的行为守卫。
 *
 * 本包所有静态源码断言都依赖它。若它退化成「按行内首个 // 截断」，
 * 含 `"https://host"` 的字符串会被从中间切断，被守卫的集合**静默少项**——
 * 守卫照样变绿，保护却没了。这里把这种退化直接钉成失败。
 */
class SourceGuardsTest {

    @Test
    fun `URL 字符串不被截断且行注释仍被剥离`() {
        val out = stripComments(
            """val u = "https://oapi.example.com/robot/send" // 真注释""",
        )
        assertTrue(
            "URL 必须完整保留，实际得到：$out",
            out.contains("https://oapi.example.com/robot/send"),
        )
        assertFalse("行注释必须剥掉", out.contains("真注释"))
    }

    @Test
    fun `转义引号不提前闭合字符串`() {
        val out = stripComments("""val s = "x\"//y" // cut""")
        assertTrue("转义引号后的 // 仍属字符串：$out", out.contains("""x\"//y"""))
        assertFalse("行注释应被剥离", out.contains("cut"))
    }

    @Test
    fun `块注释整体剥离（含跨行）`() {
        val out = stripComments("a /* 块\n注释 */ b\n// 尾行\n")
        assertTrue(out.contains("b"))
        assertFalse("块注释内容应剥净", out.contains("块"))
        assertFalse("尾行注释应剥净", out.contains("尾行"))
    }
}
