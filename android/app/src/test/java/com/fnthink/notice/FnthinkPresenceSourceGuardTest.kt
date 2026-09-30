package com.fnthink.notice

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * 幻念推送"被杀之后还有人去问一轮"的源码守卫（T33 第二片 / §4-9 片1a）。
 *
 * 这一族的判据全是"两处都以为对方会做"那一类：JVM 行为测试看不见，因为
 * 真正的失败要等一次进程被杀、一次引擎起不来才现形，而那在 CI 里复现不出来（必须真机）。
 * 所以这里钉的是**结构与分工**：
 *
 *  - ①闹钟 requestCode 不许复用既有的那几个 —— 同码不同 action 会互相覆盖，
 *    被覆盖的那一类从此不再响，而没有任何一行日志说"你的闹钟被谁顶掉了"；
 *  - ②receiver 只做"交付执行器 + 续排"，不起引擎（起引擎是几十秒的事，receiver 只有几秒寿命）；
 *  - ③worker 必须把幻念那条通道装到它自己起的引擎上 —— 漏了这一行，后台那一轮
 *    一调签名就 `MissingPluginException`，而那是**沉默的收不到**（片0 就是为了这一行能写出来）；
 *  - ④节奏只有一个读者：Kotlin 侧不写死间隔、worker 不 retry() 续排
 *    （否则 Dart 的契约间隔与 Kotlin 的退避会互相追）；
 *  - ⑤Manifest 里那条 receiver 的 action 必须与 Kotlin 常量逐字相同（跨文件同源，
 *    错一个字母的表现是"闹钟响了，但没人收到广播"，而闹钟看起来一切正常）。
 */
class FnthinkPresenceSourceGuardTest {

    private val alarm: String by lazy { stripComments(File(SRC + "FnthinkPresenceAlarm.kt").readText()) }
    private val receiver: String by lazy {
        stripComments(
            File(SRC + "FnthinkPresenceReceiver.kt").readText(),
        )
    }
    private val worker: String by lazy {
        stripComments(
            File(SRC + "FnthinkPresenceWorker.kt").readText(),
        )
    }
    private val manifest: String by lazy { File(MANIFEST).readText() }

    @Test
    fun alarmUsesAFreshRequestCodeAndKeepsTheExistingOnesAlone() {
        assertTrue(
            "闹钟必须用自己的新 requestCode（本文件里没有既有的那五个码）",
            alarm.contains("REQUEST_CODE = 3201"),
        )
        for (taken in listOf("2001", "3001", "3002", "3101")) {
            assertFalse(
                "幻念这条闹钟里出现了已被占用的 requestCode $taken：同码会互相覆盖，" +
                    "被顶掉的那一类从此不再响",
                alarm.contains("= $taken") || alarm.contains("REQUEST_CODE = $taken"),
            )
        }
    }

    @Test
    fun receiverOnlyHandsOffAndReArmsItDoesNotRunAnEngine() {
        assertTrue(
            "到点必须交给 WorkManager（receiver 的 onReceive 只有几秒寿命）",
            receiver.contains("enqueueUniqueWork(") && receiver.contains("ExistingWorkPolicy.REPLACE"),
        )
        assertFalse(
            "receiver 里不许起引擎：那是 worker 的事，混在这儿等于每次都在半路被系统掐掉",
            receiver.contains("FlutterEngine"),
        )
    }

    @Test
    fun workerAttachesTheFnthinkChannelToItsOwnEngine() {
        assertTrue(
            "后台引擎必须自己把幻念那条通道装上（签名与身份都在它上面）——" +
                "MainActivity 那份只属于 UI 引擎，漏了这一行就是 MissingPluginException",
            worker.contains("FnthinkChannelHandler("),
        )
        assertTrue(
            "Dart 那一轮的完成回报口必须在 worker 里注册，否则只能等到超时",
            worker.contains("PRESENCE_CHANNEL"),
        )
        assertFalse(
            "worker 不许依赖 MainActivity：后台引擎没有 Activity 可拿",
            worker.contains("MainActivity"),
        )
    }

    @Test
    fun cadenceHasExactlyOneOwner() {
        assertFalse(
            "worker 不许用 retry() 续排：下一轮由 receiver 按 Dart 交下来的 cadence 排，" +
                "两处都排就是两套节奏互相追",
            worker.contains("Result.retry()"),
        )
        assertFalse(
            "receiver 不许自己算间隔（只能读 Dart 写下来的那个数）",
            receiver.contains("pollInterval") || receiver.contains("Duration"),
        )
        assertTrue(
            "cadence 必须由闹钟这一层持久化，receiver 只是读回来",
            alarm.contains("fun cadenceSeconds()") && receiver.contains("cadenceSeconds()"),
        )
    }

    @Test
    fun manifestRegistersTheReceiverWithTheSameActionAsTheConstant() {
        assertTrue(
            "Manifest 里必须有这条 receiver",
            manifest.contains("android:name=\".FnthinkPresenceReceiver\""),
        )
        assertTrue(
            "action 必须与 Kotlin 常量逐字相同：差一个字母的表现是闹钟响了而没人收到广播",
            manifest.contains(
                "<action android:name=\"com.fnthink.notice.FNTHINK_ROUND_DUE\" />",
            ),
        )
        assertTrue(
            "exported=false：不给外部一个催这台设备醒来的入口（唤醒成本落在用户的电上）",
            Regex("FnthinkPresenceReceiver\"[^>]*android:exported=\"false\"").containsMatchIn(manifest),
        )
    }

    private companion object {
        const val SRC = "src/main/kotlin/com/fnthink/notice/"
        const val MANIFEST = "src/main/AndroidManifest.xml"
    }
}
