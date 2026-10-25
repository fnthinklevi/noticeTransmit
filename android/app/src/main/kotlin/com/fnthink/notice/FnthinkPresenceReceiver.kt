package com.fnthink.notice

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager

/**
 * 闹钟到点之后只做两件事：**把这一轮交给执行器**、**把下一轮排上**（T33 第二片 / §4-9）。
 *
 * 为什么不在这儿直接收货：receiver 的 `onReceive` 只有几秒生命周期，而起后台引擎、
 * 签名、取货、落库是几十秒量级的事 —— 在这儿做等于"每次都做到一半被系统掐掉"。
 * 为什么交给 [FnthinkPresenceWorker] 而不是自己起引擎：WorkManager 自己管进程死亡后的重启、
 * 约束与退避，那正是"被 ROM 杀掉"这一片要的那点兜底；闹钟只负责"到点"这件事。
 *
 * ⚠ 这里**续排下一轮**用的是 Dart 上一次交下来的那个数（[FnthinkPresenceAlarm] 的
 * `next_round_at` 与 cadence 都由 Dart 写），不是 Kotlin 自己算节奏：
 * 数值与决定权仍在 Dart（契约 `presence.*`），本类只是"链条别在这儿断掉"。
 * 不这样做的后果很具体：engine 起不来 / 原生不肯签 / 那一轮根本没跑起来时，
 * 链条从那一刻起就没人续，而界面上看着"闹钟是开着的" —— 那是"沉默的收不到"的又一个形状。
 */
class FnthinkPresenceReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != FnthinkPresenceAlarm.ACTION_ROUND_DUE) return
        FnthinkDiag.markAlarmFired(context)
        val alarm = FnthinkPresenceAlarm(context)
        val cadence = alarm.cadenceSeconds()
        Log.d(TAG, "幻念收货闹钟到点，cadence=$cadence")
        try {
            WorkManager.getInstance(context).enqueueUniqueWork(
                FnthinkPresenceWorker.UNIQUE_WORK,
                // T181 A：这里必须是 KEEP，不能是 REPLACE。
                // 闹钟按 cadence（默认 20s）续排，而 worker 一轮的预算是 90s；
                // REPLACE 会在下一颗闹钟到点时把**还在跑或还在排队**的那一轮取消 ——
                // 冷启动超过 20s 的设备会永远凑不齐一轮（表现为闹钟一直响、没有 roundDone）。
                // KEEP 让已有的一轮跑完；下一颗闹钟到点若它已结束，就自然排上新的一轮。
                ExistingWorkPolicy.KEEP,
                OneTimeWorkRequestBuilder<FnthinkPresenceWorker>().build(),
            )
        } catch (e: Exception) {
            // WorkManager 起不来（少见，通常是数据库不可用）：这一轮确实丢了，必须留话。
            Log.e(TAG, "交付执行器失败，这一轮跳过", e)
        }
        if (cadence > 0L) alarm.schedule(cadence)
    }

    private companion object {
        const val TAG = "FnthinkPresenceReceiver"
    }
}
