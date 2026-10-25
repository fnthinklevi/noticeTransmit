package com.fnthink.notice

import android.content.Context
import android.os.PowerManager
import android.os.Process
import android.os.SystemClock
import android.util.Log

/**
 * T196：后台收货的只读诊断快照。
 *
 * 这一层只回答"最后一层到底走到哪一步"，不改任何行为：
 *  - 闹钟真的响过没有（[markAlarmFired]）；
 *  - 后台那一轮真的开始/结束没有、结果是什么（[markWorkerStarted] / [markWorkerFinished]）；
 *  - 最近一次 poll / SSE 字节是什么时候（Dart 写进 FlutterSharedPreferences，这里只读）；
 *  - 服务/进程何时起来的，以及 Doze/电池优化/省电/精确闹钟此刻是什么状态。
 *
 * ⚠ 只落时间、状态与原因；不落标题、正文、地址码、签名。这是自检读数，不是第二本账。
 * ⚠ 写入失败一律吞掉并留一行日志：诊断读数坏了不许反过来影响收货。
 */
object FnthinkDiag {
    private const val TAG = "FnthinkDiag"
    private const val PREFS = "fnthink_diag"
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"

    const val KEY_LAST_ALARM_FIRED_AT = "last_alarm_fired_at"
    const val KEY_LAST_WORKER_STARTED_AT = "last_worker_started_at"
    const val KEY_LAST_WORKER_FINISHED_AT = "last_worker_finished_at"
    const val KEY_LAST_WORKER_RESULT = "last_worker_result"
    const val KEY_SERVICE_STARTED_AT = "service_started_at"
    const val KEY_PROCESS_STARTED_AT = "process_started_at"

    // Dart 侧写 FlutterSharedPreferences 时由 shared_preferences 自动加 `flutter.` 前缀。
    // ⚠ 这三对字符串由 `test/architecture/fnthink_presence_guard_test.dart` 与
    //   `FnthinkPresenceSourceGuardTest` 共同钉住；改一边不改另一边会静默读 0。
    const val DART_KEY_LAST_POLL_AT = "flutter.fnthink_diag_last_poll_at"
    const val DART_KEY_LAST_POLL_STATUS = "flutter.fnthink_diag_last_poll_status"
    const val DART_KEY_LAST_STREAM_BYTE_AT = "flutter.fnthink_diag_last_stream_byte_at"

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun flutterPrefs(context: Context) =
        context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)

    fun markAlarmFired(context: Context) {
        val now = System.currentTimeMillis()
        write(context, "alarm-fired") {
            it.putLong(KEY_LAST_ALARM_FIRED_AT, now)
        }
        Log.d(TAG, "alarm-fired at=$now")
    }

    fun markWorkerStarted(context: Context) {
        val now = System.currentTimeMillis()
        write(context, "worker-started") {
            it.putLong(KEY_LAST_WORKER_STARTED_AT, now)
                .putString(KEY_LAST_WORKER_RESULT, "running")
        }
        Log.d(TAG, "worker-started at=$now")
    }

    fun markWorkerFinished(context: Context, result: String) {
        val now = System.currentTimeMillis()
        write(context, "worker-finished") {
            it.putLong(KEY_LAST_WORKER_FINISHED_AT, now)
                .putString(KEY_LAST_WORKER_RESULT, result)
        }
        Log.d(TAG, "worker-finished at=$now result=$result")
    }

    /**
     * 服务起来时记两枚时刻：服务启动 = 现在；进程启动按 `Process.getStartElapsedRealtime()`
     * 反推（没有自定义 Application，服务重启与进程重启必须分得开）。
     */
    fun markServiceStarted(context: Context) {
        val now = System.currentTimeMillis()
        val processStartedAt = try {
            val elapsed = SystemClock.elapsedRealtime()
            val processElapsed = Process.getStartElapsedRealtime()
            now - (elapsed - processElapsed)
        } catch (e: Exception) {
            now
        }
        write(context, "service-started") {
            it.putLong(KEY_SERVICE_STARTED_AT, now)
                .putLong(KEY_PROCESS_STARTED_AT, processStartedAt)
        }
        Log.d(TAG, "service-started at=$now processStartedAt=$processStartedAt")
    }

    /** 只读快照；所有读数失败一律降级成 0 / false，不抛。 */
    fun snapshot(context: Context): Map<String, Any?> {
        val p = prefs(context)
        val fp = flutterPrefs(context)
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        var deviceIdle = false
        var batteryIgnored = false
        var powerSave = false
        try {
            if (pm != null) {
                deviceIdle = pm.isDeviceIdleMode
                batteryIgnored = pm.isIgnoringBatteryOptimizations(context.packageName)
                powerSave = pm.isPowerSaveMode
            }
        } catch (e: Exception) {
            Log.w(TAG, "power-state-read-failed", e)
        }
        return mapOf(
            "lastAlarmFiredAt" to p.getLong(KEY_LAST_ALARM_FIRED_AT, 0L),
            "lastWorkerStartedAt" to p.getLong(KEY_LAST_WORKER_STARTED_AT, 0L),
            "lastWorkerFinishedAt" to p.getLong(KEY_LAST_WORKER_FINISHED_AT, 0L),
            "lastWorkerResult" to (p.getString(KEY_LAST_WORKER_RESULT, "") ?: ""),
            "lastPollAt" to fp.getLong(DART_KEY_LAST_POLL_AT, 0L),
            "lastPollStatus" to (fp.getString(DART_KEY_LAST_POLL_STATUS, "") ?: ""),
            "lastStreamByteAt" to fp.getLong(DART_KEY_LAST_STREAM_BYTE_AT, 0L),
            "serviceStartedAt" to p.getLong(KEY_SERVICE_STARTED_AT, 0L),
            "processStartedAt" to p.getLong(KEY_PROCESS_STARTED_AT, 0L),
            "deviceIdle" to deviceIdle,
            "batteryOptimizationIgnored" to batteryIgnored,
            "powerSaveMode" to powerSave,
            "exactAlarmAllowed" to ExactAlarmPolicy.allowed(context),
            // T197 片2：屏幕亮着没有 / 高可靠开关开着没有 / 服务此刻是否真的持着锁。
            // 第三格与服务侧 FnthinkScreenLock 同一个作者，页面不再自己猜。
            "screenInteractive" to (pm?.isInteractive ?: true),
            "screenKeepalive" to FnthinkScreenLock.keepaliveEnabled(context),
            "screenLockHeld" to FnthinkScreenLock.isHolding(),
        )
    }

    private fun write(context: Context, label: String, block: (android.content.SharedPreferences.Editor) -> Unit) {
        try {
            val editor = prefs(context).edit()
            block(editor)
            editor.apply()
        } catch (e: Exception) {
            Log.w(TAG, "write-failed:$label", e)
        }
    }
}
