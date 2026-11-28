package com.fnthink.notice

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * P2-2 的取数面：`extractMessagingContent` 必须把**整串** `style.messages`
 * 交给 [MessagingDigest]，不许再退回 `last()`。
 *
 * 为什么是源码守卫：`Notification.MessagingStyle` / `StatusBarNotification` 都是
 * Android 框架类，JVM 单测拿不到实例。拼接判据本身由 [MessagingDigestTest] 真跑；
 * 这里只钉「取数层没有把多条偷偷截成一条」—— 两个守卫合起来才闭合审计的验收
 * （构造 3 条 ⇒ 正文含 3 条）。
 */
class NotificationProcessorMessagingTest {
    private val source = stripComments(
        File("src/main/kotlin/com/fnthink/notice/NotificationProcessor.kt").readText(),
    )

    private fun extractBlock(): String {
        val start = source.indexOf("private fun extractMessagingContent(")
        assertTrue("extractMessagingContent 消失（守卫锚点失效）", start >= 0)
        val end = source.indexOf("private fun messagingSender(", start)
        assertTrue("messagingSender 消失（守卫锚点失效）", end > start)
        return source.substring(start, end)
    }

    @Test
    fun `整串 messages 都进拼接而不是只取最后一条`() {
        val body = extractBlock()
        assertTrue("没有遍历 style.messages", body.contains("for (message in style.messages)"))
        assertTrue("没有交给 MessagingDigest", body.contains("MessagingDigest.format(entries)"))
        assertFalse(
            "仍按 last() 只取一条 ⇒ 合并通知里前面的消息继续丢",
            body.contains("messages.last") || body.contains("messages[messages.size - 1]"),
        )
    }

    @Test
    fun `EXTRA_MESSAGES 兜底同样走全量`() {
        val body = extractBlock()
        assertTrue("EXTRA_MESSAGES 兜底被删掉了", body.contains("EXTRA_MESSAGES"))
        assertFalse(
            "兜底里仍取最后一条",
            body.contains("messageList[messageList.size - 1]"),
        )
    }

    @Test
    fun `省略提示走 I18n 而不是硬编码中文`() {
        val body = extractBlock()
        assertTrue(body.contains("I18n.msgf(\"notif.messagingOmitted\""))
    }
}
