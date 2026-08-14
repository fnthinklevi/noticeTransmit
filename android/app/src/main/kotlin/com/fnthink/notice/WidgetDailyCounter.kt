package com.fnthink.notice

import android.content.Context
import android.util.Log
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 当日推送计数（桌面小部件数据源）
 *
 * 解决问题：桌面小部件（4×2 规格）需要显示「当日已推送通知数量」，
 * 而推送历史存储在 Flutter 侧加密数据库（SQLCipher）中，原生侧无法读取。
 *
 * 工作机制：
 * - SharedPreferences 持久化（date + count），跨天自动重置为 0
 * - WebhookSender.sendBroadcast 每次写入历史时递增（与首页「今日记录」口径一致）
 * - 小部件刷新时通过 [getTodayCount] 读取
 */
object WidgetDailyCounter {
    private const val TAG = "WidgetDailyCounter"
    private const val PREFS_NAME = "widget_daily_counter"
    private const val KEY_DATE = "date"
    private const val KEY_COUNT = "count"

    private fun todayString(): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())

    /**
     * 当日推送计数 +1（跨天自动重置）。
     */
    fun increment(context: Context) {
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val today = todayString()
            val savedDate = prefs.getString(KEY_DATE, "")
            val isNewDay = today != savedDate
            val count = if (!isNewDay) prefs.getInt(KEY_COUNT, 0) + 1 else 1
            prefs.edit().putString(KEY_DATE, today).putInt(KEY_COUNT, count).apply()
            Log.i(
                TAG,
                "increment: savedDate=$savedDate today=$today " +
                    "newDay=$isNewDay count=$count"
            )
        } catch (e: Exception) {
            Log.e(TAG, "increment failed", e)
        }
    }

    /**
     * 获取当日推送数量（跨天返回 0）。
     */
    fun getTodayCount(context: Context): Int {
        return try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val today = todayString()
            val savedDate = prefs.getString(KEY_DATE, "")
            val expired = today != savedDate
            val count = if (!expired) prefs.getInt(KEY_COUNT, 0) else 0
            Log.i(
                TAG,
                "getTodayCount: savedDate=$savedDate today=$today " +
                    "expired(跨天重置)=$expired count=$count"
            )
            count
        } catch (e: Exception) {
            Log.e(TAG, "getTodayCount failed", e)
            0
        }
    }
}
