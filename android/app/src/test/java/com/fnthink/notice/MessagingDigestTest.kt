package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * P2-2：MessagingStyle 合并通知必须**全量**进转发内容，而不是只取最后一条。
 *
 * 这些用例只看 [MessagingDigest]（纯函数）：Android 框架的
 * `Notification.MessagingStyle.Message` 在 JVM 单测里拿不到实例，而"拼几条、
 * 怎么去重、超长截哪头"这三条判据与框架无关。取数那一层（`extractMessagingContent`）
 * 由源码守卫钉住 —— 它必须把 `style.messages` 整个交给本函数，不许再写 `last()`。
 */
class MessagingDigestTest {
    private fun entry(sender: String, text: String) = MessagingDigest.Entry(sender, text)

    @Test
    fun `三条消息全部进正文并按发送者分行`() {
        val out = MessagingDigest.format(
            listOf(
                entry("妈妈", "晚上回家吃饭吗"),
                entry("我", "回，七点到"),
                entry("妈妈", "好，给你留着"),
            ),
        )
        assertEquals("妈妈: 晚上回家吃饭吗\n我: 回，七点到\n妈妈: 好，给你留着", out)
    }

    @Test
    fun `没有发送者时只输出正文`() {
        val out = MessagingDigest.format(
            listOf(entry("", "无发送者的消息"), entry("  ", "另一条")),
        )
        assertEquals("无发送者的消息\n另一条", out)
    }

    @Test
    fun `空正文不占一行`() {
        val out = MessagingDigest.format(
            listOf(entry("A", "  "), entry("B", "有内容"), entry("C", "")),
        )
        assertEquals("B: 有内容", out)
    }

    @Test
    fun `相邻同文只展开一次`() {
        // 同一应用连续 repost 会把上一条原样再报一次；拼成两行会让用户以为说了两遍。
        val out = MessagingDigest.format(
            listOf(entry("A", "在吗"), entry("A", "在吗"), entry("B", "在")),
        )
        assertEquals("A: 在吗\nB: 在", out)
    }

    @Test
    fun `隔开的同一句话不去重`() {
        val out = MessagingDigest.format(
            listOf(entry("A", "好"), entry("B", "嗯"), entry("A", "好")),
        )
        assertEquals("A: 好\nB: 嗯\nA: 好", out)
    }

    @Test
    fun `超长时保最新并注明省略条数`() {
        val entries = (1..6).map { entry("A", "第${it}条-" + "x".repeat(30)) }
        val out = MessagingDigest.format(entries, maxChars = 120) { "略$it 条" }
        assertTrue("上限没守住：${out.length}", out.length <= 120)
        assertTrue("开头没有省略说明：$out", out.startsWith("略"))
        assertTrue("最新的第 6 条被丢掉了：$out", out.contains("第6条"))
        assertFalse("最早的几条应被省略：$out", out.contains("第1条"))
    }

    @Test
    fun `单条就超长时保留尾部`() {
        val text = "开头" + "y".repeat(300) + "结尾"
        val out = MessagingDigest.format(listOf(entry("", text)), maxChars = 20)
        assertEquals(20, out.length)
        assertTrue("被截断时应留下省略号：$out", out.startsWith("…"))
        assertTrue("应保留最新那句话的结尾：$out", out.endsWith("结尾"))
    }

    @Test
    fun `任何上限下结果都不越界`() {
        val entries = listOf(entry("S", "a".repeat(100)), entry("S", "b".repeat(100)))
        for (max in 1..30) {
            val out = MessagingDigest.format(entries, maxChars = max) { "略$it 条" }
            assertTrue("max=$max 时长度 ${out.length} 越界：$out", out.length <= max)
        }
    }
}
