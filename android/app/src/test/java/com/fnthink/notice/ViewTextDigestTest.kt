package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * P2-3：RemoteViews 布局文本的整理判据。
 *
 * 取数（inflate + 遍历）只能在真机/仪器测试里发生；这里钉的是"哪些文本留下、
 * 重复的怎么并、超长截哪头"—— 这几条若写错，提取到的内容仍会被污染或截掉正文。
 */
class ViewTextDigestTest {
    @Test
    fun `多段文本按布局顺序换行拼接`() {
        val out = ViewTextDigest.format(listOf("正在播放", "晴天 - 周杰伦", "00:42 / 04:29"))
        assertEquals("正在播放\n晴天 - 周杰伦\n00:42 / 04:29", out)
    }

    @Test
    fun `空文本不占行`() {
        val out = ViewTextDigest.format(listOf("", "  ", "正文"))
        assertEquals("正文", out)
    }

    @Test
    fun `布局里重复出现的同一句只留一次`() {
        val out = ViewTextDigest.format(listOf("标题", "正文", "标题"))
        assertEquals("标题\n正文", out)
    }

    @Test
    fun `超长保留开头并补省略号`() {
        val line = "开头" + "x".repeat(300)
        val out = ViewTextDigest.format(listOf(line), maxChars = 20)
        assertEquals(20, out.length)
        assertTrue("应保留开头：$out", out.startsWith("开头"))
        assertTrue("应补省略号：$out", out.endsWith("…"))
    }

    @Test
    fun `上限为 1 时只输出省略号`() {
        assertEquals("…", ViewTextDigest.format(listOf("任意文本"), maxChars = 1))
    }

    @Test
    fun `全部为空时返回空串`() {
        assertEquals("", ViewTextDigest.format(listOf("", "   ")))
    }
}
