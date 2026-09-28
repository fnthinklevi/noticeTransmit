package com.fnthink.notice

/**
 * 桌面小部件的状态判定（纯逻辑，JVM 可测）。
 *
 * **为什么要单独一个文件**：小部件原先只看 [PushToggleManager.isPushActive]，那是
 * 「用户有没有暂停推送」，与「进程还在不在」是两件事。进程被清理时这个缓存随进程消失，
 * 未初始化还兜底返回 true —— 于是**划掉应用之后小部件仍然显示绿色的「推送中」**，
 * 而它已经不转发了。这类"看起来在工作其实没工作"的假反馈，比报错更伤。
 *
 * **判据的取舍**：
 * - `serviceRunning` 由服务在 `onCreate`/`onDestroy` 里落盘，覆盖"体面地停了"；
 * - 心跳新鲜度覆盖"没来得及写就被强杀"（SIGKILL / ROM 清理时 onDestroy 不跑）；
 *   阈值放得很宽（见 [HEARTBEAT_STALE_MS]），因为心跳只在服务活着时按节拍写，
 *   宁可比真实情况晚几分钟变灰，也不要**误报已关闭**（用户会以为又坏了，而它其实好好的）。
 * - `monitoringEnabled=false` 是用户在应用里主动关掉监听，与"被清理"要分开文案：
 *   前者该去应用里打开，后者该点小部件重新拉起。
 *
 * 不读内存里的 [NotificationMonitorService.isConnected]：小部件可能跑在一个刚被广播
 * 冷启动的进程里，那时静态字段是默认值而不是真值 —— 只有落盘的才是事实。
 */
internal object WidgetLiveness {

    /** 心跳 tick 间隔：服务活着时每 60 秒写一次（见 NotificationMonitorService 的心跳排程）。 */
    const val HEARTBEAT_INTERVAL_MS = 60_000L

    /**
     * 心跳超过此值即认定进程已不在。取 6 倍 tick + 一次性容错：
     * 主线程繁忙、Doze 里闹钟被合并，都不该把"其实活着"判成"已关闭"。
     */
    const val HEARTBEAT_STALE_MS = 6 * HEARTBEAT_INTERVAL_MS

    /** 小部件三态。配色与图标由 UI 层按此枚举决定，不在这里出现视觉词汇。 */
    enum class State {
        /** 转发中：整体绿 */
        PUSHING,

        /** 用户暂停了推送（监听仍在跑）：整体红 */
        PAUSED,

        /** 进程不在 / 监听未开启：整体中性色，并给出"怎么恢复" */
        CLOSED,
    }

    /** 为什么是 CLOSED —— 副文案要能指对方向，不能一律说"已被清理"。 */
    enum class Reason {
        OK,
        PAUSED_BY_USER,

        /** 从没记录过心跳：首次安装或清除数据后还没启动过服务 */
        NEVER_STARTED,

        /** 服务自己报告停了（onDestroy 落盘）或被划掉（onTaskRemoved 落盘） */
        STOPPED,

        /** 标记还是"在跑"但心跳陈旧 ⇒ 没走 onDestroy 就被杀 */
        KILLED,

        /** 用户在应用里关闭了监听 */
        LISTENER_DISABLED,
    }

    data class Verdict(val state: State, val reason: Reason) {
        companion object {
            @JvmStatic
            fun of(state: State, reason: Reason = Reason.OK) = Verdict(state, stateReason(state, reason))

            /** PUSHING/PAUSED 时 reason 只有 OK/PAUSED_BY_USER 两种，别让调用方自己编。 */
            private fun stateReason(state: State, reason: Reason): Reason = when (state) {
                State.CLOSED -> reason
                State.PAUSED -> Reason.PAUSED_BY_USER
                State.PUSHING -> Reason.OK
            }
        }
    }

    /**
     * @param monitoringEnabled 应用内"监听"总开关（`flutter.monitoring_enabled`）
     * @param pushActive 推送暂停开关（prefs `push_toggle_state/push_active`，**读盘不读缓存**）
     * @param serviceRunning 服务落盘的存活标记（`flutter.notif_service_running`）
     * @param heartbeatAt 最后一次心跳（`flutter.notif_heartbeat_at`；0 = 从未写过）
     * @param now 当前时间
     */
    @JvmStatic
    fun resolve(
        monitoringEnabled: Boolean,
        pushActive: Boolean,
        serviceRunning: Boolean,
        heartbeatAt: Long,
        now: Long,
    ): Verdict {
        if (!monitoringEnabled) {
            return Verdict.of(State.CLOSED, Reason.LISTENER_DISABLED)
        }
        if (heartbeatAt <= 0L) {
            return Verdict.of(State.CLOSED, Reason.NEVER_STARTED)
        }
        if (!serviceRunning) {
            return Verdict.of(State.CLOSED, Reason.STOPPED)
        }
        if (now - heartbeatAt > HEARTBEAT_STALE_MS) {
            return Verdict.of(State.CLOSED, Reason.KILLED)
        }
        return if (pushActive) {
            Verdict.of(State.PUSHING, Reason.OK)
        } else {
            Verdict.of(State.PAUSED, Reason.PAUSED_BY_USER)
        }
    }
}
