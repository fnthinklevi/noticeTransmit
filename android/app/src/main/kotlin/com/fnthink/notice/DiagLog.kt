package com.fnthink.notice

import android.content.Context
import android.util.Log

/**
 * 开发者诊断日志开关（N7 诊断模式产品化）。
 *
 * 取代 v1.5.68 的编译期 `BuildConfig.DIAG_MERGE_LOGS`：改为**运行时开关**，
 * 正式包默认关闭，排查问题无需重新发包。
 *
 * - 开关入口：「更多」页连点版本号 7 次（经 `setDiagLogEnabled` 通道下发）；
 * - 状态持久化于 SharedPreferences（键 = flutter.developer_diag_enabled，
 *   Dart 侧 SharedPreferences 同文件可读）；App / Service 启动时经 [init] 恢复；
 * - 主进程单实例（MainActivity 与 NotificationMonitorService 同进程），
 *   `@Volatile` 保证切换对服务侧日志即时生效；
 * - ⚠ 红线：诊断内容不含通知标题/正文（仅规则名/包名/计数等轻量信息）。
 *
 * 非惰性说明：[w] 的 message 在调用点即完成字符串构建（仅输出受开关控制）。
 * 现有调用点均为轻量插值（规则名/包名/计数），关闭态开销可忽略。
 */
object DiagLog {
    private const val TAG = "DiagLog"
    private const val PREFS_NAME = "FlutterSharedPreferences"
    private const val KEY = "flutter.developer_diag_enabled"

    @Volatile
    var enabled: Boolean = false
        private set

    /** App / Service 启动时恢复持久化的开关状态 */
    fun init(context: Context) {
        enabled = try {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getBoolean(KEY, false)
        } catch (_: Exception) {
            false
        }
    }

    /** 切换开关并持久化；返回切换后的状态 */
    fun setEnabled(context: Context, value: Boolean): Boolean {
        enabled = value
        try {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY, value)
                .apply()
        } catch (_: Exception) {}
        Log.i(TAG, "developer diag log -> $value")
        return value
    }

    /** 翻转开关（「更多」页连点版本号 7 次触发）；返回切换后的状态 */
    fun toggle(context: Context): Boolean = setEnabled(context, !enabled)

    /** 诊断日志：仅开关开启时输出（Log.w 级别，release 不会被 R8 剔除） */
    fun w(tag: String, message: String) {
        if (enabled) Log.w(tag, "[diag] $message")
    }
}
