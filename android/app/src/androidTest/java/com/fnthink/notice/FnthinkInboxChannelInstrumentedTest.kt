package com.fnthink.notice

import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * T55 的设备侧断言：收件通知那一枚渠道**建出来之后**在系统眼里到底是什么形状。
 *
 * 为什么必须跑在设备上：JVM 单测只能读源文件断言"那几行写了没有"，而 T55 要验的是
 * **Android 真的按那样建了渠道 / 真的那样发了通知**。
 *
 * ⚠ 这一支**顺带发一条真通知**（`FnthinkInboxDisplay.show`），所以设备通知栏会多出那一条
 * （`autoCancel`，点掉即消）。维护者要人眼确认的正是它：**横幅有没有弹、锁屏能不能看见正文、
 * 桌面图标上有没有那个数字**。
 *
 * ⚠⚠ **一条设备侧实测到的 ROM 边界（2026-10-05 真机 23046RP50C / MIUI / SDK 35）**：
 * 渠道那一层的 `lockscreenVisibility` 我们写的是 `PUBLIC`，而设备**读回来是 -1000
 * （UNKNOWN）** —— MIUI 不保存/不回读这一层。
 * 真正决定"这一条在锁屏上显不显示正文"的是**通知那一层**的 `setVisibility`，
 * 那一层在同一台设备上实测是 `vis=PUBLIC`（见 dumpsys notification 的 NotificationRecord）。
 * 所以这里把渠道层那一条降成"PUBLIC 或 UNKNOWN 都算过"，**并把边界写在这里**：
 * 降的不是"该不该写 PUBLIC"（JVM 单测钉着那行还在），是"设备能不能把这一层读回来"。
 */
@RunWith(AndroidJUnit4::class)
class FnthinkInboxChannelInstrumentedTest {

    private fun context(): Context =
        InstrumentationRegistry.getInstrumentation().targetContext

    /** 读回来没记这一层时系统给的值。它不是公开常量（Notification 里没有这一枚），所以按字面量比。 */
    private val LOCKSCREEN_UNKNOWN = -1000

    private fun manager(): NotificationManager =
        context().getSystemService(NotificationManager::class.java)

    @Test
    fun inboxChannelIsHighImportanceAndBadgeEnabled() {
        // 先发一条：渠道是懒创建的（ensureChannel 在 show 里面），不发就没有那枚渠道。
        // ⚠ 没给 POST_NOTIFICATIONS 权限时 show() 会回 false（这是**正确**行为），
        //   所以第一条断言是"显示出来了"，不是"渠道存在" —— 否则后面验的是空气。
        val shown = FnthinkInboxDisplay.show(
            context(),
            FnthinkInboxDisplay.specFor(
                messageId = "t55_instrumented_1",
                sender = "endpoint:t55_probe",
                title = "T55 设备侧取证",
                body = "这一条用来验渠道形状：上岛 / 锁屏可见正文 / 角标数。",
                unreadCount = 3,
            ),
        )
        assertTrue(
            "通知没显示出来（多半是 POST_NOTIFICATIONS 没给）⇒ 后面的渠道断言验的是空气",
            shown,
        )

        val channel = manager().getNotificationChannel(FnthinkInboxDisplay.CHANNEL_ID)
        assertNotNull("渠道没建出来：id=${FnthinkInboxDisplay.CHANNEL_ID}", channel)
        channel!!
        assertEquals(
            "importance 必须是 HIGH(4)：DEFAULT(3) 进通知栏但不弹 heads-up（T55 ①）",
            NotificationManager.IMPORTANCE_HIGH,
            channel.importance,
        )
        assertTrue(
            "角标被渠道层关掉了 ⇒ 桌面图标上永远不出现那个数（T55 ③）",
            channel.canShowBadge(),
        )
        // ⚠ 见类注释那段 MIUI 边界：这一层设备不一定回读得出来。
        val lockscreen = channel.lockscreenVisibility
        assertTrue(
            "渠道层锁屏可见性读回 $lockscreen；" +
                "只接受 PUBLIC(1)（我们写了它）或 UNKNOWN(-1000)（MIUI 不保存这一层）。" +
                "真正管这一条通知的是通知层的 setVisibility，另有 dumpsys 可证。",
            lockscreen == Notification.VISIBILITY_PUBLIC || lockscreen == LOCKSCREEN_UNKNOWN,
        )
        assertEquals(
            "旧渠道那一枚不许被读成新的（换 id 是为了 importance 能重建，不是重命名）",
            "fnthink_inbox",
            FnthinkInboxDisplay.LEGACY_CHANNEL_ID,
        )
    }
}
