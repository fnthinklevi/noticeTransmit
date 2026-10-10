package com.fnthink.notice

import android.content.Context
import android.util.Log
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 「当日已推送」这一句话的**唯一作者**（T131）。
 *
 * 为什么需要这一个文件：改之前同一条句子上住着三个作者 ——
 * 1. 服务里的内存计数 `pushCount`：每次调四族扇出就 +1，**不看暂停那道闸**（闸住在
 *    [NetworkClient] / 幻念 / 邮件各自的 `!force && !PushToggleManager.isPushActive()`）；
 * 2. `WidgetDailyCounter`：每次**写历史**就 +1，连被规则过滤、"仅记录不推送"的都算；
 * 3. Flutter 启动/恢复时把 DB 的「今日记录数」灌回 `pushCount`（`syncDailyPushCount`，
 *    同一天还取 `maxOf`）。
 * 三者口径互不相同，而常驻通知与桌面小部件写的是同一句「当日已推送 X 条」——
 * 「暂停转发之后那个数还在涨」不是偶发，是这三份口径的必然交集。
 *
 * 现在的口径只有一句：**这一发真的被推出去了才算**。判据是纯函数 [countsAsPush]（可 JVM 测），
 * 累加点只有 [record] 一处。落 SharedPreferences 而不是进程内存：内存计数会随进程死亡归零，
 * 而「当日」这件事本来就该活过一次重启（旧实现靠上面第 3 个作者把它补回来，那正是串台的入口）。
 */
object DailyPushCounter {
    private const val TAG = "DailyPushCounter"
    private const val PREFS_NAME = "daily_push_counter"
    private const val KEY_DATE = "date"
    private const val KEY_COUNT = "count"

    /**
     * 这一轮扇出算不算「推了一发」（纯函数，不含任何 Android 依赖）。
     *
     * 三条判据各挡一种"数字与屏幕上那句话不符"：
     * - [targets] 为 0：一个目标都没有（没配通道，或被主备路由全部剔掉）——发无可发，计入就是虚报。
     * - [pushActive] 为 false 且不是手动补推：用户按了「暂停转发」，这一发根本没出门。
     *   这正是 T131 报的那条缺陷的原形。
     * - [force]（历史页「现在推送」）是例外：那是用户明确点的一下，暂停态下也会真发，所以算。
     *
     * ⚠ 这里判的是「推没推」，不是「通不通」：主通道 500、备通道成功，仍然是一发推出去了。
     * 逐通道的成败由送达记录（`chan:<slug>` 那份状态）负责，两套数不许互相替。
     */
    fun countsAsPush(pushActive: Boolean, force: Boolean, targets: Int): Boolean {
        if (targets <= 0) return false
        return pushActive || force
    }

    fun todayString(): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())

    /** 唯一 +1 口：跨天先归零再累加。 */
    fun record(context: Context) {
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val today = todayString()
            val savedDate = prefs.getString(KEY_DATE, "")
            val base = if (today == savedDate) prefs.getInt(KEY_COUNT, 0) else 0
            prefs.edit().putString(KEY_DATE, today).putInt(KEY_COUNT, base + 1).apply()
            // 数字变了就刷新小部件（仅在已添加小部件时广播，无小部件时零开销）
            PushToggleWidgetProvider.updateAllWidgetsIfExists(context)
        } catch (e: Exception) {
            Log.e(TAG, "record failed", e)
        }
    }

    /** 当日计数（跨天读回 0，不写盘）。 */
    fun todayCount(context: Context): Int {
        return try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val today = todayString()
            if (prefs.getString(KEY_DATE, "") != today) 0 else prefs.getInt(KEY_COUNT, 0)
        } catch (e: Exception) {
            Log.e(TAG, "todayCount failed", e)
            0
        }
    }
}
