package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * 桌面小部件状态判定测试（WidgetLiveness）。
 *
 * 这一组用例的存在理由只有一条：**被清理之后小部件仍然显示绿色「推送中」**。
 * 原实现读的是 `PushToggleManager.isPushActive()` —— 那是"用户暂停了没有"，
 * 未初始化还兜底 true，进程被杀后它就是"永远推送中"。所以下面每一条 CLOSED
 * 都是对那个假反馈的一次钉死，而不是装饰性的分支覆盖。
 */
class WidgetLivenessTest {

    private val now = 1_700_000_000_000L
    private val fresh = now - 10_000L
    private val stale = now - WidgetLiveness.HEARTBEAT_STALE_MS - 1_000L

    private fun resolve(
        monitoring: Boolean = true,
        push: Boolean = true,
        running: Boolean = true,
        heartbeat: Long = fresh,
    ) = WidgetLiveness.resolve(
        monitoringEnabled = monitoring,
        pushActive = push,
        serviceRunning = running,
        heartbeatAt = heartbeat,
        now = now,
    )

    @Test
    fun aliveAndPushing_isGreenPushing() {
        val v = resolve()
        assertEquals(WidgetLiveness.State.PUSHING, v.state)
        assertEquals(WidgetLiveness.Reason.OK, v.reason)
    }

    @Test
    fun aliveButPaused_isRedPaused() {
        val v = resolve(push = false)
        assertEquals(WidgetLiveness.State.PAUSED, v.state)
        assertEquals(WidgetLiveness.Reason.PAUSED_BY_USER, v.reason)
    }

    /** ⚠ 本文件的"那一条"用例：服务停了、推送开关却还是 true（被杀前的常态），必须判 CLOSED。 */
    @Test
    fun killedProcess_neverReportsPushing_evenThoughPushSwitchSaysActive() {
        val v = resolve(push = true, running = false)
        assertEquals(WidgetLiveness.State.CLOSED, v.state)
        assertEquals(WidgetLiveness.Reason.STOPPED, v.reason)
    }

    @Test
    fun noHeartbeatAtAll_isNeverStarted_notKilled() {
        // 首次安装/清数据：说"应用已被清理"是指责错了，文案要指"打开应用启动它"
        val v = resolve(running = false, heartbeat = 0L)
        assertEquals(WidgetLiveness.State.CLOSED, v.state)
        assertEquals(WidgetLiveness.Reason.NEVER_STARTED, v.reason)
    }

    @Test
    fun staleHeartbeatWithRunningFlag_isKilled() {
        // 强杀不走 onDestroy：标记还说"在跑"，但心跳停了 → 只能信心跳
        val v = resolve(running = true, heartbeat = stale)
        assertEquals(WidgetLiveness.State.CLOSED, v.state)
        assertEquals(WidgetLiveness.Reason.KILLED, v.reason)
    }

    @Test
    fun listenerDisabled_winsOverEverything() {
        // 用户在应用里关掉监听：即便其余都是"活着"的样子，也不能显示"推送中"
        val v = resolve(monitoring = false, push = true, running = true, heartbeat = fresh)
        assertEquals(WidgetLiveness.State.CLOSED, v.state)
        assertEquals(WidgetLiveness.Reason.LISTENER_DISABLED, v.reason)
    }

    @Test
    fun heartbeatExactlyAtThreshold_stillAlive() {
        // 边界取"闭区间"：阈值判定用 > 而不是 >=，避免每 6 分钟在灰/绿之间抖一次
        val v = resolve(heartbeat = now - WidgetLiveness.HEARTBEAT_STALE_MS)
        assertEquals(WidgetLiveness.State.PUSHING, v.state)
    }

    /** Doze 里心跳被合并延后几分钟：不该判死。取 6 倍 tick 就是给这个留的余量。 */
    @Test
    fun heartbeatFourMinutesAgo_stillAlive() {
        val v = resolve(heartbeat = now - 4 * WidgetLiveness.HEARTBEAT_INTERVAL_MS)
        assertEquals(WidgetLiveness.State.PUSHING, v.state)
    }

    @Test
    fun staleAndPaused_reportsClosedNotPaused() {
        // 顺序：先判活，再判暂停 —— 一个"死了且用户也暂停过"的设备显示红色「已暂停」
        // 会让人以为"是我关的"，而它其实是被清理的
        val v = resolve(push = false, running = false)
        assertEquals(WidgetLiveness.State.CLOSED, v.state)
    }
}
