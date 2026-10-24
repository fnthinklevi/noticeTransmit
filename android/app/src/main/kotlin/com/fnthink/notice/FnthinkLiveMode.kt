package com.fnthink.notice

import android.content.Context
import android.os.PowerManager
import android.util.Log

/**
 * T181 B：常驻前台服务里的高频轮询档。
 *
 * 只做两件事：
 *  1. 把「后台常驻轮询是否开启 / 几秒一轮」写进 FlutterSharedPreferences —— 服务重建时
 *     [restore] 按它恢复持锁，界面经 `fnthinkPresenceStatus` 读它；
 *  2. 持一把 PARTIAL_WAKE_LOCK，避免长锁屏后 CPU 休眠把 Dart 的 5 秒 Timer 一起冻住。
 *
 * ⚠ 这把锁由**已有的** NotificationMonitorService 持有，不另起服务、不另发通知。
 *   每轮 Dart 都会重新调一次 `startFnthinkLive`，这里的 acquire 同时充当续期；
 *   用户关掉接收、或服务销毁时 release —— 不留一把永不过期的锁。
 */
object FnthinkLiveMode {
    private const val TAG = "FnthinkLiveMode"
    private const val PREFS = "FlutterSharedPreferences"
    private const val KEY_ENABLED = "flutter.fnthink_live_enabled"
    private const val KEY_SECONDS = "flutter.fnthink_live_seconds"
    private const val WAKE_TAG = "fnthink:live-poll"

    /** 续期窗口：远大于 5 秒一轮；Dart 每轮都会续，所以正常时不会过期。 */
    private const val WAKE_TIMEOUT_MS = 30 * 60 * 1000L

    private var wakeLock: PowerManager.WakeLock? = null

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun isEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_ENABLED, false)

    fun seconds(context: Context): Int =
        prefs(context).getInt(KEY_SECONDS, 0)

    fun isHolding(): Boolean = wakeLock?.isHeld == true

    fun setEnabled(context: Context, enabled: Boolean, seconds: Int) {
        val wanted = if (enabled) seconds else 0
        val p = prefs(context)
        // Dart 每轮都会续一次：值没变就不写盘，别把 5 秒一轮变成 5 秒一次落盘。
        if (p.getBoolean(KEY_ENABLED, false) != enabled || p.getInt(KEY_SECONDS, 0) != wanted) {
            p.edit()
                .putBoolean(KEY_ENABLED, enabled)
                .putInt(KEY_SECONDS, wanted)
                .apply()
        }
        if (enabled) acquire(context) else release()
    }

    /** 服务重启（START_STICKY / 开机）时按落盘的那一档恢复。 */
    fun restore(context: Context) {
        if (isEnabled(context)) acquire(context)
    }

    private fun acquire(context: Context) {
        try {
            // 已经是持锁状态时这一发只续期；日志不再每 5 秒刷一行。
            val alreadyHeld = wakeLock?.isHeld == true
            val lock = wakeLock ?: run {
                val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
                    ?: run {
                        Log.w(TAG, "没有 PowerManager，后台轮询不持锁")
                        return
                    }
                pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_TAG).apply {
                    setReferenceCounted(false)
                }.also { wakeLock = it }
            }
            // 重复 acquire 只续期，不增加引用计数（上面 setReferenceCounted(false)）。
            lock.acquire(WAKE_TIMEOUT_MS)
            if (!alreadyHeld) Log.d(TAG, "后台轮询持锁（${seconds(context)} 秒一轮）")
        } catch (e: Exception) {
            Log.e(TAG, "后台轮询持锁失败", e)
        }
    }

    fun release() {
        try {
            wakeLock?.let {
                if (it.isHeld) it.release()
            }
        } catch (e: Exception) {
            Log.w(TAG, "后台轮询放锁失败", e)
        } finally {
            wakeLock = null
        }
    }
}
