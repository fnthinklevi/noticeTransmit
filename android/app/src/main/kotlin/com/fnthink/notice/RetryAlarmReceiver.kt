package com.fnthink.notice

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * T239 重放闹钟到点接收器（manifest 注册：进程死了队列还在，闹钟必须能把它拉起来）。
 *
 * 到点只做一件事：走 [RetryQueueWake.wake] 的同一条重放路（webhook 队列 + 邮件队列），
 * 深睡门控（T240）在 replay 入口。真正的排程逻辑在 [RetryReplayAlarm]。
 */
class RetryAlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != RetryReplayAlarm.ACTION_RETRY_DUE) return
        RetryQueueWake.wake("alarm")
    }
}

/**
 * T239：失败队列重放的**闹钟排程器**。
 *
 * 为什么用 AllowWhileIdle 闹钟（2026-11-07 MEIZU 21 真机修正）：原设计把解锁/亮屏
 * 接进触发面，但真机实证这台 Flyme 对运行时注册的 SCREEN_ON/USER_PRESENT 接收器
 * **不投递**（服务内注册与 applicationContext 注册都收不到；T197 的屏触发验证是在
 * MIUI 设备上做的）。而 AllowWhileIdle 闹钟是官方 Doze 清单点名的正解
 * （"Set critical alarms with setAndAllowWhileIdle() and setExactAndAllowWhileIdle()"），
 * 且本仓 DelayedPushManager 已有同型先例（排程/降级/SecurityException 兜底全套）。
 * 屏上事件钩子保留——在 MIUI 等正常投递的 ROM 上它比闹钟更即时。
 *
 * 排程点：enqueue 成功 / 重放取出（冷却重排）/ 门控延后（T240，见 [scheduleAfter]）。
 * 到点经 [RetryAlarmReceiver] 唤醒 drain；drain 若发现仍有更晚到期的条目会再排下一轮。
 */
object RetryReplayAlarm {
    private const val TAG = "RetryReplayAlarm"
    const val ACTION_RETRY_DUE = "com.fnthink.notice.RETRY_DUE"
    private const val REQUEST_CODE = 4201

    /** T240 门控延后后的重试间隔：15 分钟（与重放冷却同量级，AllowWhileIdle 限频 7 次/小时 内） */
    const val DEFER_RETRY_MS = 15 * 60 * 1000L

    /** 读取两条队列的最早到期时间并排程。无待重放条目时是空操作。 */
    fun schedule(context: Context) {
        val now = System.currentTimeMillis()
        val retryEarliest = RetryQueue.earliestDueAt(now)
        val emailEarliest = EmailRetryQueue.earliestDueAt(now)
        val candidates = listOf(retryEarliest, emailEarliest).filter { it > 0 }
        if (candidates.isEmpty()) return
        scheduleAt(context, candidates.min())
    }

    /** T240 门控延后后的兜底重排：delay 后再试一轮（队列此刻必有到期条目，只是不可用窗口）。 */
    fun scheduleAfter(context: Context, delayMs: Long) {
        scheduleAt(context, System.currentTimeMillis() + delayMs)
    }

    private fun scheduleAt(context: Context, fireAt: Long) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        try {
            // ⚠ 必须显式组件寻址：RetryAlarmReceiver 在 manifest 里**没有 intent-filter**
            // （只收本包闹钟），action+package 的隐式形态匹配不到它——闹钟到点会被系统
            // 静默丢弃（2026-11-07 真机实证：排程成功、到点无任何投递）。显式组件不受此限。
            val intent = Intent(context, RetryAlarmReceiver::class.java).apply {
                action = ACTION_RETRY_DUE
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            val pi = PendingIntent.getBroadcast(context, REQUEST_CODE, intent, flags)
            // 与 DelayedPushManager 同一条降级纪律：已授权 → setExactAndAllowWhileIdle；
            // 未授权 → setAndAllowWhileIdle；授权在排程一刻被收回的 SecurityException 兜底降级。
            if (ExactAlarmPolicy.allowed(context)) {
                try {
                    am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAt, pi)
                    Log.i(TAG, "重放精确闹钟已排程 fireAt=$fireAt")
                    return
                } catch (e: SecurityException) {
                    Log.w(TAG, "精确闹钟未授权，降级非精确闹钟", e)
                }
            }
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAt, pi)
            Log.i(TAG, "重放闹钟已排程 fireAt=$fireAt")
        } catch (e: Exception) {
            // 排不上只留日志：条目已落盘，其余触发源（网络回调 / 服务重启 / 屏事件）仍在
            Log.e(TAG, "重放闹钟排程失败", e)
        }
    }
}
