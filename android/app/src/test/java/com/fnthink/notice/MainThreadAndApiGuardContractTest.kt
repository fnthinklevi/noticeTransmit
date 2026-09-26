package com.fnthink.notice

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * 「编译器与 dart/flutter analyze 都看不见」的两类回归守卫（v1.62 修复轮）。
 *
 * 1. **API 闸门**：注册应用内私有广播有两个叠在一起的约束（依据本地 SDK 的
 *    `data/api-versions.xml`，不是记忆）：
 *    - 三参重载 `registerReceiver(BroadcastReceiver, IntentFilter, int)` **since API 26**，
 *      minSdk 24/25 上裸调用抛 `NoSuchMethodError`——它是 Error，不被本仓库随处可见的
 *      `catch (e: Exception)` 兜住，表现为「打开即闪退」；
 *    - `RECEIVER_NOT_EXPORTED` **since API 33**（常量编译期内联），且 targetSdk 34 起
 *      在 API 33+ 注册非受保护广播必须带导出标志，否则 SecurityException、接收器静默失效。
 *    MainActivity 曾有三处裸调用（已随 1.5.49/1.5.52 发布出去），现收敛到
 *    `registerInternalReceiver` 一处带版本分支的封装。
 *
 * 2. **主线程不得做同步网络**：电量/温度告警有**两条**触发入口——
 *    `BatteryMonitor` 绑主 Looper 的 60s 轮询回调，与 `batteryChangedReceiver.onReceive`
 *    （注册时未传 Handler，同样在主线程）。两处都调用 `AppChannelSender.sendNotification`，
 *    其内部 `runBlocking { getToken }` + 同步 OkHttp 会阻塞调用线程 → ANR。
 *    历史缺陷正是**只修了广播侧、漏了轮询侧**，故本守卫对两条入口分别断言。
 */
class MainThreadAndApiGuardContractTest {

    private val mainActivitySource: String by lazy {
        stripComments(read("src/main/kotlin/com/fnthink/notice/MainActivity.kt"))
    }

    private val serviceSource: String by lazy {
        stripComments(read("src/main/kotlin/com/fnthink/notice/NotificationMonitorService.kt"))
    }

    private fun read(path: String): String = File(path).readText()

    /** 从 [signature] 处起，按花括号配对取出整块（含函数体 / lambda 体 / object 体）。 */
    private fun blockAfter(source: String, from: Int, signature: String): String {
        val start = source.indexOf(signature, from)
        assertTrue("未找到片段：$signature", start >= 0)
        val bodyStart = source.indexOf('{', start)
        assertTrue("$signature 后没有代码块", bodyStart >= 0)
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

    // ———— 1. API 闸门 ————

    @Test
    fun `MainActivity 的三参 registerReceiver 只存在于带 TIRAMISU 判定的私有封装内`() {
        val helper = blockAfter(
            mainActivitySource,
            0,
            "private fun registerInternalReceiver(",
        )
        assertTrue(
            "registerInternalReceiver 缺少 SDK_INT >= TIRAMISU 判定 —— " +
                "33+ 会因缺导出标志抛 SecurityException，24/25 会因三参重载不存在抛 NoSuchMethodError",
            helper.contains("Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU"),
        )
        assertTrue(
            "registerInternalReceiver 应包含带 RECEIVER_NOT_EXPORTED 的三参调用（targetSdk 34+ 必需）",
            helper.contains("Context.RECEIVER_NOT_EXPORTED"),
        )
        assertTrue(
            "registerInternalReceiver 缺少低版本两参兜底分支",
            helper.contains("registerReceiver(receiver, filter)"),
        )
        val outsideHelper = mainActivitySource.replace(helper, "")
        assertTrue(
            "MainActivity 中存在绕过 registerInternalReceiver 的裸三参 registerReceiver 调用",
            !outsideHelper.contains("RECEIVER_NOT_EXPORTED"),
        )
    }

    @Test
    fun `全原生源码每处 RECEIVER 导出标志的使用都在 TIRAMISU 判定之后`() {
        val offenders = mutableListOf<String>()
        File("src/main/kotlin").walkTopDown().filter { it.extension == "kt" }.forEach { file ->
            val src = stripComments(file.readText())
            for (flag in listOf("RECEIVER_NOT_EXPORTED", "RECEIVER_EXPORTED")) {
                var idx = src.indexOf(flag)
                while (idx >= 0) {
                    val guard = src.lastIndexOf("Build.VERSION_CODES.TIRAMISU", idx)
                    if (guard < 0 || guard >= idx || idx - guard > 400) {
                        offenders.add("${file.name} 的 $flag 未紧邻 TIRAMISU 判定")
                    }
                    idx = src.indexOf(flag, idx + flag.length)
                }
            }
        }
        assertTrue(
            "以下注册绕过版本闸门，API 24~32 上会 NoSuchMethodError：$offenders",
            offenders.isEmpty(),
        )
    }

    // ———— 2. 主线程不得做同步网络 ————

    private fun assertSendersInsideLaunch(
        block: String,
        label: String,
        callee: String,
    ) {
        val launch = blockAfter(block, 0, "serviceScope.launch")
        val outsideLaunch = block.replace(launch, "")
        // T12 起三族扇出收进 dispatchToChannels()，所以"发送体在协程内"这条判据
        // 跟着指向收口函数本身（判据强度不变：仍要求 launch 内有、外部无裸调）。
        // T23 起设备态告警再多一层 dispatchDeviceAlert()（要过约束），callee 随之指向
        // 那一个入口 —— 主线程的约束判断本身是纯函数，重活（取 token + HTTP）还在协程里。
        assertTrue(
            "$label：$callee 必须包在 serviceScope.launch 内（onReceive/轮询回调在主线程，" +
                "AppChannelSender 内有 runBlocking + 同步 HTTP，会 ANR）",
            launch.contains(callee),
        )
        assertTrue(
            "$label：$callee 在 serviceScope.launch 之外仍有裸调用（只修一半即为本守卫要拦的形态）",
            !outsideLaunch.contains(callee),
        )
    }

    @Test
    fun `电量轮询回调的发送体在 IO 协程内`() {
        val callback = blockAfter(
            serviceSource,
            0,
            "batteryMonitor.setNotificationCallback",
        )
        assertSendersInsideLaunch(
            callback,
            "BatteryMonitor 轮询回调",
            callee = "dispatchDeviceAlert(",
        )
    }

    @Test
    fun `电量广播 onReceive 的发送体在 IO 协程内`() {
        val decl = serviceSource.indexOf("batteryChangedReceiver = object :")
        assertTrue("未找到 batteryChangedReceiver 声明", decl >= 0)
        // 文件里有三处同名 onReceive 签名，必须从本接收器声明之后向后找
        val receiver = blockAfter(serviceSource, decl, "override fun onReceive(")
        assertSendersInsideLaunch(
            receiver,
            "batteryChangedReceiver.onReceive",
            callee = "dispatchDeviceAlert(",
        )
    }
}
