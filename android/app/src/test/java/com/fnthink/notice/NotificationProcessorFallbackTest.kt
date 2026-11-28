package com.fnthink.notice

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * P2-3 的取数面：空内容兜底链必须补上 `EXTRA_SUMMARY_TEXT` 与 RemoteViews 的
 * **有限**文本提取，并在确实没有文本时留一条诊断。
 *
 * 为什么是源码守卫：`Notification` / `RemoteViews` / `View` 都是 Android 框架类，
 * JVM 单测拿不到实例。整理判据由 [ViewTextDigestTest] 真跑；这里钉"链上有这一环、
 * 提取只读 TextView、失败有诊断"。
 */
class NotificationProcessorFallbackTest {
    private val source = stripComments(
        File("src/main/kotlin/com/fnthink/notice/NotificationProcessor.kt").readText(),
    )

    @Test
    fun `兜底链补了 EXTRA_SUMMARY_TEXT 且顺序在 ticker 之前`() {
        val summaryAt = source.indexOf("EXTRA_SUMMARY_TEXT")
        val summaryChainAt = source.indexOf(".ifEmpty { summaryText }")
        val tickerChainAt = source.indexOf(".ifEmpty { ticker }")
        assertTrue("EXTRA_SUMMARY_TEXT 没有被读取", summaryAt >= 0)
        assertTrue("summaryText 没有进兜底链", summaryChainAt >= 0)
        assertTrue(
            "summary 排在 ticker 之后 ⇒ group summary 会被 ticker 的空串/弱文本顶掉",
            summaryChainAt < tickerChainAt,
        )
    }

    @Test
    fun `RemoteViews 是最后一道且两个候选都试`() {
        val chainAt = source.indexOf(".ifEmpty { extractRemoteViewsText(notification) }")
        val subTextAt = source.indexOf(".ifEmpty { subText }")
        assertTrue("兜底链没有接 RemoteViews", chainAt >= 0)
        assertTrue("RemoteViews 应排在 subText 之后", chainAt > subTextAt)
        assertTrue("没有试 bigContentView", source.contains("notification.bigContentView"))
        assertTrue("没有试 contentView", source.contains("notification.contentView"))
    }

    @Test
    fun `提取只读 TextView 文本`() {
        assertTrue("遍历入口消失", source.contains("private fun collectTextViewTexts("))
        assertTrue("没有按 TextView 类型判", source.contains("is TextView ->"))
        assertTrue("没有读取 TextView.text", source.contains("view.text?.toString()"))
        // 只读文本：不许在提取路径里点执行动作（PendingIntent / 点击）。
        val start = source.indexOf("private fun extractRemoteViewsText(")
        val end = source.indexOf("private fun collectTextViewTexts(", start)
        assertTrue(end > start)
        val body = source.substring(start, end)
        assertFalse("提取路径里出现了点击/动作执行", body.contains("performClick"))
        assertFalse("提取路径里出现了 PendingIntent", body.contains("send("))
    }

    @Test
    fun `空内容丢弃前留诊断`() {
        val body = source.substring(
            source.indexOf("if (title.isEmpty() && content.isEmpty())"),
            source.indexOf("if (isOngoing)"),
        )
        assertTrue(
            "无可用文本的诊断被删掉了",
            body.contains("No usable text; skipping empty content"),
        )
        // 诊断只报包名与来源在场情况，不许把正文/标题写进日志。
        assertFalse("诊断里出现了正文", body.contains("content="))
        assertFalse("诊断里出现了标题", body.contains("title="))
    }
}
