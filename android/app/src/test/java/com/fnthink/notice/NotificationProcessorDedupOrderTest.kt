package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * P0：常驻通知的**去重键**必须在"确认这条真的要转发"之后才写入。
 *
 * 旧顺序（2026-11-27 审计）：先 `notifiedKeys.add(dedupKey)`，再抽正文、判空。
 * 首条纯进度条 / 纯 Custom RemoteViews（标题与正文都空）会 `return null` 丢掉，
 * 但 key 已经留在表里 —— 同一个 key 的后续更新全被当重复拦掉，直到通知被移除
 * 或进程重启。表现是"常驻通知只来第一条"，且历史里一条都没有（连丢弃记录都不写）。
 *
 * 这是源码顺序守卫而非行为用例：`NotificationProcessor` 依赖 StatusBarNotification /
 * Bundle 等 Android 类，JVM 单测拿不到；而这条缺陷的判据就是两行的相对顺序。
 */
class NotificationProcessorDedupOrderTest {
    private val source = stripComments(
        File("src/main/kotlin/com/fnthink/notice/NotificationProcessor.kt").readText(),
    )

    @Test
    fun `空内容丢弃的判断在去重键写入之前`() {
        val emptyAt = source.indexOf(
            "if (title.isEmpty() && content.isEmpty()) return null",
        )
        val addAt = source.indexOf("notifiedKeys.add(dedupKey)")
        assertTrue("空内容判断消失", emptyAt >= 0)
        assertTrue("去重键写入消失", addAt >= 0)
        assertTrue(
            "先写 key 再判空 ⇒ 首条空内容会把 key 锁死，后续更新全被当重复",
            addAt > emptyAt,
        )
    }

    @Test
    fun `去重键只写一处`() {
        val count = Regex(Regex.escape("notifiedKeys.add(dedupKey)"))
            .findAll(source)
            .count()
        assertEquals("去重键出现多处 ⇒ 顺序守卫只看得到第一处", 1, count)
    }
}
