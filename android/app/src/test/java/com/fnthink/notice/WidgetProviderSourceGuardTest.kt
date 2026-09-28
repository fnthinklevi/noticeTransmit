package com.fnthink.notice

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * 小部件"不许再回到单看推送开关"的源码守卫。
 *
 * [WidgetLivenessTest] 测的是判定函数本身；这里守的是**接线** —— 一旦有人把
 * `updateWidget` 改回直接读 [PushToggleManager.isPushActive]（或把 CLOSED 的点击
 * 又接回一个后台 startService，那个调用在 Android 8+ 会被系统拒绝并被 try/catch 咽掉），
 * 判定函数再正确也没人用它。这类"逻辑对、接线断"的回归，行为测试看不见。
 */
class WidgetProviderSourceGuardTest {

    private val providerSource: String by lazy { stripComments(File(SRC + "PushToggleWidgetProvider.kt").readText()) }
    private val serviceSource: String by lazy { stripComments(File(SRC + "NotificationMonitorService.kt").readText()) }

    @Test
    fun providerJudgesByLivenessNotByPushSwitch() {
        val block = extractFunction(providerSource, "fun buildRemoteViews(")
        assertTrue(
            "没找到 updateWidget 函数体 —— 守卫本身失效了",
            block.isNotEmpty(),
        )
        assertTrue(
            "渲染路径必须走 WidgetLiveness.resolveState —— 单看 isPushActive 会让被清理后的桌面继续显示绿色「推送中」",
            block.contains("resolveState(context)"),
        )
        assertTrue(
            "updateWidget 必须只是「取尺寸 + 委托」：视图构造只有一处",
            extractFunction(providerSource, "fun updateWidget(").contains("buildRemoteViews(context,"),
        )
        // 判据范围：只禁"渲染路径"里用它。onReceive 里 toggle 之后拿它打日志是合法的
        // （缓存刚被自己写过），全文件一律禁掉会让这条守卫变成谁也过不了的门。
        assertFalse(
            "渲染路径里不许出现 isPushActive()：那是「用户暂停了没有」，不是「进程还在不在」",
            block.contains("isPushActive()"),
        )
    }

    @Test
    fun closedStateTapsIntoAppNotBackgroundServiceStart() {
        val block = extractFunction(providerSource, "fun buildRemoteViews(")
        assertTrue(
            "CLOSED 态点击必须挂 PendingIntent.getActivity（打开应用由既有重绑链路拉起）",
            block.contains("PendingIntent.getActivity"),
        )
        assertTrue(
            "两态的 PendingIntent 必须用不同 requestCode —— 同一个 requestCode 会让两套意图互相覆盖",
            block.contains("REQ_OPEN_APP") && block.contains("REQ_TOGGLE"),
        )
        assertFalse(
            "CLOSED 不许偷偷 startService：广播里后台启动服务会被系统拒（原实现正是静默失败）",
            block.contains("startService"),
        )
    }

    @Test
    fun serviceWritesLivenessAtEveryLifecyclePoint() {
        for (fn in listOf(
            "override fun onDestroy()",
            "override fun onTaskRemoved(",
            "override fun onListenerConnected()",
        )) {
            val block = extractFunction(serviceSource, fn)
            assertTrue(
                "$fn 必须落盘存活证据（写小部件不刷新，用户就只能等下一次推送才知道服务没了）",
                block.contains("writeLiveness") || block.contains("refreshWidgetsQuietly"),
            )
        }
        // onDestroy 里必须**同步**落盘：serviceScope 紧接着就 cancel，异步写会整笔丢
        val destroy = extractFunction(serviceSource, "override fun onDestroy()")
        assertTrue(
            "onDestroy 的存活落盘必须 sync=true（协程已 cancel，异步 commit 可能整笔不落地）",
            Regex("""writeLiveness\(running = false, sync = true\)""").containsMatchIn(destroy),
        )
    }

    @Test
    fun heartbeatIsSeparateFromRecoveryWatermark() {
        // 两枚心跳语义不同：复用同一枚会让"判活"跟着补扫窗口抖，或反过来把补扫改成每分钟写盘
        assertTrue(
            "必须有独立的小部件心跳键，不能复用 notif_last_alive_at（那是补扫水位，通知稀疏时天然陈旧）",
            serviceSource.contains("PREF_HEARTBEAT_AT") && serviceSource.contains("flutter.notif_heartbeat_at"),
        )
        assertTrue(
            "节拍心跳必须走 IO 协程而不是主线程同步写盘（本仓库为热路径上的同步磁盘 IO 付过 ANR 学费）",
            Regex("""writeLiveness\(running = true, sync = false\)""").containsMatchIn(serviceSource),
        )
    }

    /** 兜底闹钟必须自己收口：灰卡片不该每 15 分钟叫醒一次进程却看不出任何变化。 */
    @Test
    fun livenessAlarmIsSelfLimiting() {
        val alarm = extractFunction(providerSource, "internal fun scheduleLivenessRefresh(")
        assertTrue("没找到 scheduleLivenessRefresh", alarm.isNotEmpty())
        assertTrue("活着才排闹钟（setAndAllowWhileIdle）", alarm.contains("setAndAllowWhileIdle"))
        assertTrue(
            "撤销必须用 FLAG_NO_CREATE，不能为了 cancel 凭空造一个 PendingIntent",
            alarm.contains("FLAG_NO_CREATE"),
        )
        assertTrue(
            "不要蹭精确闹钟权限（那是给延迟/聚合推送用的）",
            !alarm.contains("setExactAndAllowWhileIdle"),
        )
        val render = extractFunction(providerSource, "fun buildRemoteViews(")
        assertTrue(
            "渲染路径末尾必须按状态排/撤闹钟，且 CLOSED 传 alive=false",
            render.contains("scheduleLivenessRefresh(context, alive = !closed)"),
        )
    }

    private fun extractFunction(source: String, signature: String): String {
        val start = source.indexOf(signature)
        if (start < 0) return ""
        val bodyStart = source.indexOf('{', start)
        if (bodyStart < 0) return ""
        var depth = 0
        var i = bodyStart
        while (i < source.length) {
            when (source[i]) {
                '{' -> depth++
                '}' -> {
                    depth--
                    if (depth == 0) return source.substring(bodyStart, i + 1)
                }
            }
            i++
        }
        return source.substring(bodyStart)
    }

    /** 注释里出现方法名不算"接了线"：先去注释再去断言。 */
    private fun stripComments(text: String): String =
        text
            .replace(Regex("/\\*\\*?.*?\\*/", RegexOption.DOT_MATCHES_ALL), "")
            .replace(Regex("//[^\n]*"), "")

    private companion object {
        const val SRC = "src/main/kotlin/com/fnthink/notice/"
    }
}
