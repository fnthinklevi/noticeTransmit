package com.fnthink.notice

import android.util.Log

/**
 * T239 重放触发面的纯判据：5 秒节流。
 *
 * 与 [FnthinkPresenceWakePolicy] 同一条纪律：解锁 + 亮屏经常连着来，
 * 不节流就是同一进程里几秒内跑三轮重放。JVM 可测，不碰 BroadcastReceiver。
 */
internal object RetryQueueWakePolicy {
    const val THROTTLE_MS = 5_000L

    fun shouldWake(lastWakeAtMs: Long, nowMs: Long): Boolean =
        nowMs - lastWakeAtMs >= THROTTLE_MS
}

/**
 * T239：解锁 / 亮屏时补一轮失败队列重放。
 *
 * 为什么要有这一处（E2 真机实证，2026-11-07）：`RetryQueue` 的重放触发面原本只有
 * 「服务 onCreate」与「网络回调 onAvailable」。长锁屏期间系统网络一直连通（Doze 挂起的
 * 是**按应用的**网络，不是系统级连通性变化）⇒ `onAvailable` 不触发；解锁/亮屏更没接进来
 * ⇒ 排队的推送一直躺着，用户解锁后看到的仍是「推送失败」。
 *
 * **触发源复用服务的既有屏上事件接收器**（`startFnthinkWakeTriggers` 注册的那一条，
 * T197 起）——本机真机验证过它能收到 SCREEN_ON/USER_PRESENT；单独再注册一份接收器
 * 在部分 ROM 上收不到投递（2026-11-07 MEIZU 21 实测：独立注册的 SCREEN_ON 无回调），
 * 且同一份系统监听服务两个消费方，注册/注销生命周期只算一本账。
 * 真正重放仍是 [RetryQueue.replayIfEligible] / [EmailRetryQueue.replayIfEligible]，
 * 不另拼第二条路；深睡门控在 replay 入口（T240），这里不重复判。
 *
 * 止损：同一进程 5 秒内只跑一次（亮屏 + USER_PRESENT 经常连着来）。
 */
object RetryQueueWake {
    private const val TAG = "RetryQueueWake"

    @Volatile
    private var lastWakeAt: Long = 0L

    /** 只给测试与日志用：这一发该不该排。 */
    internal fun shouldWake(lastWakeAtMs: Long, nowMs: Long): Boolean =
        RetryQueueWakePolicy.shouldWake(lastWakeAtMs, nowMs)

    /** 返回 true = 真的调了重放；false = 在节流窗口内。 */
    fun wake(reason: String): Boolean {
        val now = System.currentTimeMillis()
        if (!shouldWake(lastWakeAt, now)) {
            Log.d(TAG, "skip trigger=$reason (within ${RetryQueueWakePolicy.THROTTLE_MS}ms)")
            return false
        }
        lastWakeAt = now
        Log.i(TAG, "wake replay trigger=$reason")
        RetryQueue.replayIfEligible()
        EmailRetryQueue.replayIfEligible()
        return true
    }
}
