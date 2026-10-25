package com.fnthink.notice

import org.junit.Assert.assertEquals
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
 *    错一个字母的表现是"闹钟响了，但没人收到广播"，而闹钟看起来一切正常）；
 *  - ⑥重启之后那颗闹钟**有人补，而且只在能补的那一档补**（片1c）：AlarmManager 的排程不跨重启，
 *    没人补就等于"手机重启一次，这台从此不再自己醒"；而包替换那一档**故意不补**——升级换了 APK
 *    之后 AOT 快照里那个回调 id 会挪位置，拿旧 handle 敲门的最坏结果不是起不了引擎，是进到
 *    另一个 Dart 函数里。补的那一档只许沿用 Dart 交下来的那一档，开关读不到就按关。
 */
class FnthinkPresenceSourceGuardTest {

    private val alarm: String by lazy { stripComments(File(SRC + "FnthinkPresenceAlarm.kt").readText()) }
    private val bootReceiver: String by lazy {
        stripComments(
            File(SRC + "BootReceiver.kt").readText(),
        )
    }
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
    private val handler: String by lazy {
        stripComments(
            File(SRC + "channels/FnthinkChannelHandler.kt").readText(),
        )
    }

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
            receiver.contains("enqueueUniqueWork(") && receiver.contains("ExistingWorkPolicy.KEEP"),
        )
        assertFalse(
            "T181 A：REPLACE 会在下一颗闹钟到点时把还在跑/还在排队的那一轮取消；" +
                "cadence 默认 20s、worker 预算 90s，冷启动必然凑不齐一轮",
            receiver.contains("ExistingWorkPolicy.REPLACE"),
        )
        assertFalse(
            "receiver 里不许起引擎：那是 worker 的事，混在这儿等于每次都在半路被系统掐掉",
            receiver.contains("FlutterEngine"),
        )
    }

    @Test
    fun stoppedRoundIsReportedAsFailureNotAsSuccess() {
        assertTrue(
            "worker 必须把「Dart 交回了 roundDone」与「latch 被放行」分开记：onStopped 也放行同一把 latch",
            worker.contains("AtomicBoolean") && worker.contains("roundReported.set(true)"),
        )
        assertTrue(
            "被系统收走的那一轮必须留可 grep 的行，并按 failure 交回 WorkManager",
            Regex(
                "if\\s*\\(!completed\\)\\s*\\{[^}]*presence-round-stopped[^}]*Result\\.failure\\(\\)",
            ).containsMatchIn(worker),
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
    fun oneOffBackoffIsStoredApartFromTheNormalCadence() {
        assertTrue(
            "退避要有自己的一格：写进 cadence 会让界面把「服务端让我等 700 秒」" +
                "读成「这台常态每 700 秒问一次货」（T180）",
            alarm.contains("KEY_BACKOFF") && alarm.contains("backoffSeconds"),
        )
        assertTrue(
            "正常排程必须把退避格清回 0：留着上一次的值，界面会在退避早就结束后还在说退避",
            alarm.contains("putLong(KEY_BACKOFF, 0L)"),
        )
        assertTrue(
            "Dart 交下来的两个数必须分开传：合成一个参数就等于在原生侧又合并了一次",
            handler.contains("\"backoffSeconds\"") && handler.contains("schedule(seconds, backoff)"),
        )
        assertTrue(
            "状态读口要把退避那格交回给 Dart：界面分两行说靠的就是它",
            handler.contains("\"backoffSeconds\" to alarm.backoffSeconds()"),
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

    @Test
    fun bootReArmsOnlyWhereItIsSafeToReArm() {
        assertTrue(
            "重启后必须有人补那颗闹钟：AlarmManager 的排程不跨重启，没人补就等于手机重启一次" +
                "而这台从此不再自己醒（用户只会读到「很久没到货」，而开关明明写着开着）",
            bootReceiver.contains("alarm.armIfWantedAfterBoot()"),
        )
        assertTrue(
            "包被替换那一档要主动撤而不是补：旧 handle 指向的是上一个包的回调 id，" +
                "AOT 快照换了之后那个 id 会挪位置",
            bootReceiver.contains("Intent.ACTION_MY_PACKAGE_REPLACED ->") &&
                bootReceiver.contains("alarm.cancel()"),
        )
        val reArmBlock = bootReceiver.substringAfter("private fun reArmPresence")
        assertFalse(
            "解锁之前那一支（LOCKED_BOOT_COMPLETED）不许碰闹钟：Dart 写的那两份读数在凭据加密的存储里，" +
                "这时候读到的是空的，拿它当「用户关掉了」会把一次正常重启误判成关掉，还顺手清了节奏",
            reArmBlock.contains("LOCKED_BOOT_COMPLETED ->"),
        )
        assertEquals(
            "补闹钟的调用点只许一处：多处重排就是多处判断，而判断依据（开关与节奏）都在 Dart 那一边",
            count(bootReceiver, "armIfWantedAfterBoot()"),
            1,
        )
    }

    @Test
    fun bootReArmReusesTheCadenceDartLeftAndReadsTheSwitchFailClosed() {
        val block = alarm.substringAfter("fun armIfWantedAfterBoot()")
        assertTrue(
            "补的那一档必须沿用 Dart 上次交下来的那个数：这里既不许读设置页，也不许写死一个间隔",
            block.contains("cadenceSeconds()") && block.contains("schedule(cadence)"),
        )
        assertTrue(
            "开关关着时那份过期的节奏要一起清掉 —— 留着它，下次开机又会重排一颗为「用户已经关掉的」" +
                "功能服务的闹钟，而协调者那一发在通道不通时是会失败的（它不重试），" +
                "所以这份 prefs 完全可能比开关旧：开关才是真值",
            block.contains("cancel()"),
        )
        assertTrue(
            "总开关读不到就按关处理：这个开关的语义是「这台设备从没同意过通知内容经服务器中转」，" +
                "兜底成 true 等于用户没同意过的东西在开机后自己醒",
            alarm.contains("getBoolean(\"flutter.fnthink.receive_enabled\", false)"),
        )
        assertFalse(
            "不许出现兜底成 true 的读法",
            alarm.contains("getBoolean(\"flutter.fnthink.receive_enabled\", true)"),
        )
        assertFalse(
            "闹钟这一层不许拿字面数字当间隔（节奏的唯一作者是 Dart 那边的契约）",
            Regex("schedule\\(\\s*[0-9]").containsMatchIn(alarm),
        )
    }

    @Test
    fun livePollingKeepsItsWakeLockOnlyWhileTheServiceLives() {
        val service = stripComments(File(SRC + "NotificationMonitorService.kt").readText())
        val live = stripComments(File(SRC + "FnthinkLiveMode.kt").readText())
        assertTrue(
            "T181 B：常驻轮询的持锁状态必须由服务重建时恢复 —— 少了这一行，" +
                "START_STICKY 拉起服务之后那把锁没人拿，锁屏久了 CPU 照样睡，Dart 的 5 秒 Timer 被冻住，" +
                "表现与没做这一片逐字节相同（界面上还写着「常驻收取中」）",
            service.contains("FnthinkLiveMode.restore(this)"),
        )
        assertTrue(
            "服务销毁必须放锁：START_STICKY 重建时由 onCreate 的 restore 重新拿，不留一把永不过期的锁",
            service.contains("FnthinkLiveMode.release()"),
        )
        assertTrue(
            "常驻档要挡的是 CPU 休眠（Dart Timer 被冻住），只能是 PARTIAL_WAKE_LOCK",
            live.contains("PARTIAL_WAKE_LOCK"),
        )
        assertTrue(
            "重复 acquire 只许续期、不许叠引用计数，否则每 5 秒一轮就把引用计数堆到永远放不掉",
            live.contains("setReferenceCounted(false)"),
        )
        assertTrue(
            "startFnthinkLive 的分支必须真的把档打开并持锁；只回 true 不落状态时，" +
                "Dart 会以为常驻已开，而原生那边一动不动 —— 界面与事实相反",
            handler.contains("FnthinkLiveMode.setEnabled(context, true") &&
                handler.contains("FnthinkLiveMode.setEnabled(context, false"),
        )
    }

    @Test
    fun taskRemovalAndSystemKillScheduleAFreshRestart() {
        val service = stripComments(File(SRC + "NotificationMonitorService.kt").readText())
        assertTrue(
            "T185 第三步：划掉任务要补一条自愈链 —— `stopWithTask=false` 只保证不主动停，" +
                "国产 ROM 常在划掉后收走进程；缺这一行时表现是「划一下，后台就再也没醒过」",
            service.contains("override fun onTaskRemoved("),
        )
        assertTrue(
            "自愈必须交给 AlarmManager（Android 12+ 不许后台直接起 FGS），" +
                "且 API 26+ 用 getForegroundService 而不是 getService",
            service.contains("PendingIntent.getForegroundService"),
        )
        assertTrue(
            "被系统收走时也要排（onDestroy 里只在 monitoringEnabled 时排：用户关掉监听就别再叫醒它）",
            service.contains("if (monitoringEnabled) scheduleSelfRestart()"),
        )
        assertTrue(
            "请求码必须是新号 3202；复用 3201/2001/3001/3002/3101 会互相覆盖，" +
                "被覆盖的那一类从此不再响而没有任何日志",
            service.contains("SELF_RESTART_REQUEST_CODE = 3202"),
        )
        for (taken in listOf("2001", "3001", "3002", "3101", "3201")) {
            assertFalse(
                "自愈请求码复用了已有码 $taken：同码会互相覆盖",
                service.contains("SELF_RESTART_REQUEST_CODE = $taken"),
            )
        }
    }

    private fun count(src: String, needle: String): Int = src.split(needle).size - 1

    private companion object {
        const val SRC = "src/main/kotlin/com/fnthink/notice/"
        const val MANIFEST = "src/main/AndroidManifest.xml"
    }
}
