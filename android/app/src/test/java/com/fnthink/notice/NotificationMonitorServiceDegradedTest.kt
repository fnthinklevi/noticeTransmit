package com.fnthink.notice

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * P2-5：提取阶段异常必须**降级分发原文**，不能只写一条「处理失败」占位。
 *
 * 为什么是源码守卫：`StatusBarNotification` / `NotificationMonitorService` 是 Android
 * 组件，JVM 单测起不来实例；但这条判据的核心是"异常分支里先走哪条路、原文从哪来、
 * 前缀从哪来"，全部是装配事实，源码可断言。
 */
class NotificationMonitorServiceDegradedTest {
    private val serviceSource = stripComments(
        File("src/main/kotlin/com/fnthink/notice/NotificationMonitorService.kt").readText(),
    )
    private val i18nSource = stripComments(
        File("src/main/kotlin/com/fnthink/notice/I18n.kt").readText(),
    )

    @Test
    fun `提取异常先降级分发而不是只写占位`() {
        val block = serviceSource.substring(
            serviceSource.indexOf("val rawInfo = try {"),
            serviceSource.indexOf("if (rawInfo != null)"),
        )
        assertTrue("没有 catch 提取异常", block.contains("catch (e: Exception)"))
        assertTrue("没有走降级分发", block.contains("dispatchDegradedFallback(sbn)"))
        assertTrue("降级后没有结束本条处理", block.contains("return@launch"))
        // 占位历史这一步必须留在**下游**外层 catch，不许在提取分支里先写占位。
        assertFalse("提取分支里先写了占位", block.contains("recordFailurePlaceholder"))
    }

    @Test
    fun `降级信息标题带 I18n 前缀且原文优先`() {
        assertTrue(serviceSource.contains("I18n.processDegradedPrefix()"))
        assertTrue(serviceSource.contains("rawTitle.ifEmpty"))
        assertTrue(serviceSource.contains("rawBody.ifEmpty"))
        assertTrue(serviceSource.contains("I18n.processDegradedNoContent()"))
        // 前缀不许硬编码在服务里（中英双语唯一作者是 I18n）。
        assertFalse(serviceSource.contains("【降级】"))
        assertFalse(serviceSource.contains("[Degraded]"))
    }

    @Test
    fun `原文不可读时占位历史写明原因`() {
        val block = serviceSource.substring(
            serviceSource.indexOf("private fun recordFailurePlaceholder("),
            serviceSource.indexOf("private fun formatNotificationTime("),
        )
        assertTrue("占位历史没有写送达原因", block.contains("DeliveryNotifier.notify("))
        assertTrue("原因没有传进 ParseResult", block.contains("reason,"))
    }

    @Test
    fun `降级前缀与无原文文案中英都有`() {
        assertTrue(i18nSource.contains("【降级】"))
        assertTrue(i18nSource.contains("[Degraded] "))
        assertTrue(i18nSource.contains("解析出错，未取到原文正文"))
        assertTrue(i18nSource.contains("Parsing failed; the original body is unavailable"))
    }
}
