package com.fnthink.notice

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * 常驻通知（前台服务通知）显隐状态机契约守卫（v1.59）。
 *
 * 背景：通知栏常驻通知的显示与消失横跨 5 个场景（开始监听 / 停止监听 /
 * 进程终止 / 自启动保活 / 权限缺失），各场景的实现点分散在
 * `NotificationMonitorService`（onDestroy / stopForegroundCompat /
 * refreshForegroundVisibility / startForegroundService /
 * updateForegroundNotification / onTaskRemoved）与 `I18n`（断开文案）——
 * 任何一处被"顺手清理"都会导致通知残留或英文/错误文案回归。
 *
 * 本守卫把关键实现点固化为静态源码断言（**注释已剥离**），
 * 覆盖 base.md v1.59 ⑪ 的状态机：
 *
 * | 场景 | 期望 | 关键实现 |
 * |---|---|---|
 * | 开始监听 | 显示（内容随状态） | applyMonitoringState → startForegroundService |
 * | 停止监听 | 立即消失 | stopForegroundCompat（REMOVE + cancel 双保险） |
 * | 进程终止 | 不得残留 | onDestroy 显式 stopForegroundCompat + cancel |
 * | 自启动保活（划任务被杀） | 保持/1s 内恢复且内容一致 | onTaskRemoved 重启排程 + stopWithTask=false |
 * | 权限缺失（使用权✗/通知权限✗） | 显示暂停文案 / 直接隐藏 | refreshForegroundVisibility + areNotificationsEnabled 守卫 |
 */
class ForegroundNotificationContractTest {

    private val serviceSource: String by lazy {
        stripComments(
            File(
                "src/main/kotlin/com/fnthink/notice/NotificationMonitorService.kt",
            ).readText(),
        )
    }

    private val i18nSource: String by lazy {
        stripComments(
            File("src/main/kotlin/com/fnthink/notice/I18n.kt").readText(),
        )
    }

    private val manifestSource: String by lazy {
        stripComments(
            File("src/main/AndroidManifest.xml").readText(),
        )
    }

    @Test
    fun `onDestroy 显式清理常驻通知（进程终止不得残留）`() {
        val onDestroyBlock = extractFunction(serviceSource, "override fun onDestroy()")
        assertTrue(
            "onDestroy 缺少 stopForegroundCompat —— 常驻通知可能残留",
            onDestroyBlock.contains("stopForegroundCompat()"),
        )
        assertTrue(
            "onDestroy 缺少 notificationManager.cancel(FOREGROUND_ID) 双保险",
            onDestroyBlock.contains("notificationManager.cancel(FOREGROUND_ID)"),
        )
    }

    @Test
    fun `stopForegroundCompat 含 cancel 双保险（停止监听立即消失）`() {
        val block = extractFunction(serviceSource, "private fun stopForegroundCompat()")
        assertTrue(
            "stopForegroundCompat 应使用 STOP_FOREGROUND_REMOVE（立即移除通知）",
            block.contains("STOP_FOREGROUND_REMOVE"),
        )
        assertTrue(
            "stopForegroundCompat 缺少 notificationManager.cancel(FOREGROUND_ID) 双保险",
            block.contains("notificationManager.cancel(FOREGROUND_ID)"),
        )
    }

    @Test
    fun `refreshForegroundVisibility 统一显隐入口且含通知权限守卫`() {
        val block = extractFunction(serviceSource, "private fun refreshForegroundVisibility()")
        assertTrue(
            "refreshForegroundVisibility 缺少 areNotificationsEnabled 守卫（场景 5b）",
            block.contains("areNotificationsEnabled()"),
        )
        assertTrue(
            "通知权限缺失时应 cancel 常驻通知（直接隐藏）",
            block.contains("notificationManager.cancel(FOREGROUND_ID)"),
        )
        assertTrue(
            "refreshForegroundVisibility 应按 monitoringEnabled 决定显隐",
            block.contains("monitoringEnabled"),
        )
    }

    @Test
    fun `通知权限缺失时 start 与 update 均有守卫（防残留）`() {
        val startBlock = extractFunction(serviceSource, "private fun startForegroundService()")
        assertTrue(
            "startForegroundService 缺少通知权限守卫（cancel 防残留）",
            startBlock.contains("areNotificationsEnabled()") &&
                startBlock.contains("notificationManager.cancel(FOREGROUND_ID)"),
        )
        val updateBlock = extractFunction(serviceSource, "private fun updateForegroundNotification()")
        assertTrue(
            "updateForegroundNotification 缺少通知权限守卫",
            updateBlock.contains("areNotificationsEnabled()") &&
                updateBlock.contains("notificationManager.cancel(FOREGROUND_ID)"),
        )
    }

    @Test
    fun `监听断开文案对齐 v1_59 措辞（场景 5a）`() {
        assertTrue(
            "serviceListenerDisconnected 文案应为「未授予通知读取权限，通知监听已暂停」",
            i18nSource.contains("未授予通知读取权限，通知监听已暂停"),
        )
        assertTrue(
            "英文文案应同步（listening paused）",
            i18nSource.contains("listening paused"),
        )
    }

    @Test
    fun `onTaskRemoved 保留保活重启排程（自启动场景 4）`() {
        val block = extractFunction(serviceSource, "override fun onTaskRemoved(")
        assertTrue(
            "onTaskRemoved 缺少重启排程（AlarmManager 1s 拉起，保活恢复链）",
            block.contains("AlarmManager") && block.contains("PendingIntent"),
        )
    }

    @Test
    fun `Manifest 声明 stopWithTask=false（划任务不随任务停止，保活基础）`() {
        assertTrue(
            "NotificationMonitorService 应声明 android:stopWithTask=\"false\"",
            manifestSource.contains("android:stopWithTask=\"false\""),
        )
    }

    private fun extractFunction(source: String, signature: String): String {
        val start = source.indexOf(signature)
        assertTrue("未找到函数：$signature", start >= 0)
        val bodyStart = source.indexOf('{', start)
        var depth = 0
        var i = bodyStart
        while (i < source.length) {
            when (source[i]) {
                '{' -> depth++
                '}' -> {
                    depth--
                    if (depth == 0) return source.substring(start, i + 1)
                }
            }
            i++
        }
        return source.substring(start)
    }
}
