package com.fnthink.notice

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * T197 片1：解锁/亮屏/网络恢复触发器的接线守卫。
 *
 * 这一族的失败同样是静默的：服务没注册监听 ⇒ 解锁后没人补收，界面一切正常；
 * 触发器绕过 [FnthinkPresenceWake] 自己 enqueue ⇒ 开关与 5 秒节流失效，
 * 亮屏+USER_PRESENT+网络恢复会连着起好几颗引擎。
 */
class FnthinkWakeTriggerGuardTest {

    private val service: String by lazy {
        stripComments(
            File(SRC + "NotificationMonitorService.kt").readText(Charsets.UTF_8),
        )
    }
    private val wake: String by lazy {
        stripComments(File(SRC + "FnthinkPresenceWake.kt").readText(Charsets.UTF_8))
    }
    private val settings: String by lazy {
        stripComments(repoFile("lib/services/fnthink_settings.dart").readText(Charsets.UTF_8))
    }

    @Test
    fun serviceRegistersScreenAndNetworkTriggersAndUnregistersThem() {
        for (needle in listOf(
            "Intent.ACTION_SCREEN_ON",
            "Intent.ACTION_USER_PRESENT",
            "registerDefaultNetworkCallback",
            "FnthinkPresenceWake.enqueueRound",
        )) {
            assertTrue("服务没有注册 $needle", service.contains(needle))
        }
        val destroy = service.substringAfter("override fun onDestroy()")
        assertTrue(
            "onDestroy 必须撤掉触发监听：注册不注销 = 系统持有 Service 引用",
            destroy.contains("stopFnthinkWakeTriggers()"),
        )
        assertTrue(
            "触发监听必须由 startFnthinkWakeTriggers 一处注册（别在 onCreate 里再抄一遍）",
            service.contains("startFnthinkWakeTriggers()"),
        )
    }

    @Test
    fun wakeUsesTheSameSwitchAndKeepPolicy() {
        assertTrue(
            "触发开关必须与 Dart keyReceiveEnabled 成对（原生带 flutter. 前缀）",
            wake.contains("KEY_RECEIVE_ENABLED = \"flutter.fnthink.receive_enabled\""),
        )
        assertTrue(
            "Dart 侧那把开关名变了会静默读 false",
            settings.contains("keyReceiveEnabled = 'fnthink.receive_enabled'"),
        )
        assertTrue(
            "已有的一轮还在跑时用 KEEP；REPLACE 会把它取消",
            wake.contains("ExistingWorkPolicy.KEEP"),
        )
        assertTrue(
            "触发必须交给收货那一轮的唯一工作名",
            wake.contains("FnthinkPresenceWorker.UNIQUE_WORK"),
        )
        assertTrue(
            "节流窗口必须是 5 秒一处常量",
            wake.contains("THROTTLE_MS = 5_000L"),
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
