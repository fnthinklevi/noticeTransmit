package com.fnthink.notice

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * T197 片2：服务侧锁屏持锁的接线守卫。
 *
 * 失败形态与片1同族：锁没接上 ⇒ 长锁屏下 CPU 仍会睡，看门狗不跑，
 * 而界面、日志、单元测试都可以是绿的；开关没接到原生 ⇒ 用户翻完要等 5 分钟才生效。
 */
class FnthinkScreenLockGuardTest {

    private val lock: String by lazy {
        stripComments(
            File(SRC + "FnthinkScreenLock.kt").readText(Charsets.UTF_8),
        )
    }
    private val service: String by lazy {
        stripComments(
            File(SRC + "NotificationMonitorService.kt").readText(Charsets.UTF_8),
        )
    }
    private val handler: String by lazy {
        stripComments(
            File(SRC + "channels/FnthinkChannelHandler.kt").readText(Charsets.UTF_8),
        )
    }
    private val page: String by lazy {
        stripComments(repoFile("lib/pages/fnthink_receive_page.dart").readText(Charsets.UTF_8))
    }
    private val settings: String by lazy {
        stripComments(repoFile("lib/services/fnthink_settings.dart").readText(Charsets.UTF_8))
    }

    @Test
    fun serviceOwnsTheScreenOffLockAndRenewsIt() {
        for (needle in listOf(
            "PowerManager.PARTIAL_WAKE_LOCK",
            "lock.acquire(WAKE_TIMEOUT_MS)",
            "scheduleRenew(context)",
            "fun refresh(context: Context)",
            "fun release()",
        )) {
            assertTrue("FnthinkScreenLock 缺 $needle", lock.contains(needle))
        }
        assertTrue(
            "判据必须只有 FnthinkScreenLockPolicy 一个作者",
            lock.contains("FnthinkScreenLockPolicy.shouldHold"),
        )
        assertTrue(
            "续期必须按当前屏幕/开关对账，不能盲目 acquire",
            lock.contains("refresh(context)"),
        )
    }

    @Test
    fun serviceWiresStartScreenEventsAndDestroy() {
        for (needle in listOf(
            "FnthinkScreenLock.refresh(this)",
            "FnthinkScreenLock.onScreenOff",
            "FnthinkScreenLock.onScreenOn",
            "Intent.ACTION_SCREEN_OFF",
            "FnthinkScreenLock.release()",
        )) {
            assertTrue("NotificationMonitorService 缺 $needle", service.contains(needle))
        }
    }

    @Test
    fun channelAndPageCanAskForAnImmediateRefresh() {
        assertTrue(
            "原生 handler 缺 refreshFnthinkScreenLock",
            handler.contains("\"refreshFnthinkScreenLock\"") &&
                handler.contains("FnthinkScreenLock.refresh(context)"),
        )
        assertTrue(
            "页面缺锁屏开关控件",
            page.contains("fnthink-screen-keepalive-switch"),
        )
        assertTrue(
            "开关写完必须立刻叫原生对账",
            page.contains("setScreenKeepalive") && page.contains("refreshScreenLock"),
        )
        assertTrue(
            "总开关也必须触发同一次对账",
            page.contains("setReceiveEnabled") && page.contains("refreshScreenLock"),
        )
        assertTrue(
            "诊断行必须把开关与真实持锁分开说",
            page.contains("screenKeepalive") &&
                page.contains("screenLockHeld") &&
                page.contains("fnthinkDiagScreenLock"),
        )
    }

    @Test
    fun dartAndNativeReadTheSamePreferenceKey() {
        assertTrue(
            "Dart 侧键名变了会静默失效",
            settings.contains("keyScreenKeepalive = 'fnthink.screen_keepalive'"),
        )
        assertTrue(
            "原生侧必须读带 flutter. 前缀的那一份",
            lock.contains("KEY_SCREEN_KEEPALIVE = \"flutter.fnthink.screen_keepalive\""),
        )
    }

    private fun repoFile(rel: String): File {
        val candidates = listOf(File("../.."), File("."), File(".."))
        for (root in candidates) {
            val f = File(root, rel)
            if (f.exists()) return f
        }
        return File("../../$rel")
    }

    private companion object {
        const val SRC = "src/main/kotlin/com/fnthink/notice/"
    }
}
