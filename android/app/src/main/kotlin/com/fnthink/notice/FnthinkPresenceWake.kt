package com.fnthink.notice

import android.content.Context
import android.util.Log
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager

/**
 * T197 片1：解锁 / 亮屏 / 网络恢复时补一轮收货。
 *
 * 触发源只决定"现在可以问一次"，真正取货仍是 [FnthinkPresenceWorker] 那一条路：
 * 服务活着时它起一颗只活一轮的引擎；进程不在时 WorkManager 也能把它拉起来。
 * 不在这里另拼 poll —— 那就等于给同一个协议找第二个作者。
 *
 * 止损：同一进程 5 秒内只排一次（亮屏 + USER_PRESENT + 网络恢复经常连着来）。
 * 接收开关读不到一律按关处理：这个开关的语义是"用户同意过走中转"，兜底成开会替用户同意。
 */
object FnthinkPresenceWake {
    private const val TAG = "FnthinkPresenceWake"
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"

    /** 与 `FnthinkPresenceAlarm.receiveEnabled()` / Dart `FnthinkSettings.keyReceiveEnabled` 同一把开关。 */
    const val KEY_RECEIVE_ENABLED = "flutter.fnthink.receive_enabled"

    @Volatile
    private var lastEnqueueAt: Long = 0L

    fun receiveEnabled(context: Context): Boolean = try {
        context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_RECEIVE_ENABLED, false)
    } catch (e: Exception) {
        false
    }

    /** 只给测试与日志用：这一发该不该排。 */
    internal fun shouldWake(
        receiveEnabled: Boolean,
        lastEnqueueAtMs: Long,
        nowMs: Long,
    ): Boolean = FnthinkPresenceWakePolicy.shouldWake(
        receiveEnabled = receiveEnabled,
        lastEnqueueAtMs = lastEnqueueAtMs,
        nowMs = nowMs,
    )

    /** 返回 true = 真的交给 WorkManager 了；false = 开关关着或在 5 秒窗口内。 */
    fun enqueueRound(context: Context, reason: String): Boolean {
        val now = System.currentTimeMillis()
        if (!shouldWake(receiveEnabled(context), lastEnqueueAt, now)) {
            Log.d(TAG, "skip trigger=$reason (switch off or within 5s)")
            return false
        }
        return try {
            WorkManager.getInstance(context).enqueueUniqueWork(
                FnthinkPresenceWorker.UNIQUE_WORK,
                ExistingWorkPolicy.KEEP,
                OneTimeWorkRequestBuilder<FnthinkPresenceWorker>().build(),
            )
            lastEnqueueAt = now
            Log.d(TAG, "enqueue trigger=$reason")
            true
        } catch (e: Exception) {
            // 排不上必须留话；下一颗闹钟仍会到点，不能把这一发报成成功。
            Log.e(TAG, "enqueue failed trigger=$reason", e)
            false
        }
    }
}

/** 纯判据：开关 + 5 秒节流。JVM 可测，不碰 WorkManager。 */
internal object FnthinkPresenceWakePolicy {
    const val THROTTLE_MS = 5_000L

    fun shouldWake(
        receiveEnabled: Boolean,
        lastEnqueueAtMs: Long,
        nowMs: Long,
    ): Boolean {
        if (!receiveEnabled) return false
        if (lastEnqueueAtMs <= 0L) return true
        return nowMs - lastEnqueueAtMs >= THROTTLE_MS
    }
}
