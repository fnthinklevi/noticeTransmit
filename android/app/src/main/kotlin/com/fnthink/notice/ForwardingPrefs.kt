package com.fnthink.notice

import android.content.Context

/**
 * T205：监听总开关与「仅电话/短信」独立开关的**唯一键与读盘作者**。
 *
 * 为什么单独一枚：这两个键在服务、来电链、短信链、桌面小部件四处被读，
 * 各写一份字符串时改键不会报错，只会让某一处永远读到默认值。
 *
 * ⚠ 只读盘、不读任何 `@Volatile` 内存字段：来电/短信广播可以在服务尚未
 * `onCreate` 时冷启动进程，那时静态字段还是默认值 `true`，用它判会把
 * “监听已关”读成“还开着”。
 */
object ForwardingPrefs {
    const val MONITORING_ENABLED = "flutter.monitoring_enabled"
    const val CALL_SMS_FORWARDING = "flutter.call_sms_forwarding"

    private const val PREFS_NAME = "FlutterSharedPreferences"

    fun monitoringEnabled(context: Context): Boolean =
        prefs(context).getBoolean(MONITORING_ENABLED, true)

    /** 缺键取 false：监听关掉时，“不发”必须是默认那一边。 */
    fun callSmsForwarding(context: Context): Boolean =
        prefs(context).getBoolean(CALL_SMS_FORWARDING, false)

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}
