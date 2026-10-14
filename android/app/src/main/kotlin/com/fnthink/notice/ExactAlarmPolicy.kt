package com.fnthink.notice

import android.app.AlarmManager
import android.content.Context
import android.os.Build

/**
 * 「这台现在能不能排精确闹钟」的**唯一作者**（T140 走 (c)）。
 *
 * 为什么要有这一枚，而不是让三个排闹钟的地方各自判断：
 *  - 此前这一族有**两个**读数被当成一枚用 —— 设置页那枚 App 内开关（一个写在 Flutter
 *    共享偏好里的布尔，默认关）与系统授权（`AlarmManager.canScheduleExactAlarms()`）。
 *    开关关掉 ⇒ 系统给了也走非精确；界面那一行画的却是系统授权 ⇒ 用户看到"已授权"，
 *    实际到点晚几分钟，而契约承诺的是常态收取 5–60 秒。两句话各自都不算假，合起来是一句假话。
 *  - 维护者裁定：**只留系统授权这一枚真值**（App 内那枚开关删掉，见 roadmap T140 行）。
 *    所以要防的下一步是"开关长回来"，也防"三个调用点各自抄一份判定" ——
 *    一份判定抄三遍，下一次改动只会改到其中一处。
 *
 * 读不到一律按**不能**处理（降级非精确闹钟）：延迟推送、聚合推送、幻念收货闹钟三条链
 * 都带 `SecurityException` 兜底，"晚一点到"与"从此不再醒"是两个后果。
 *
 * Android 12（API 31）以下没有 `SCHEDULE_EXACT_ALARM` 这个概念，恒为可排。
 */
object ExactAlarmPolicy {

    fun allowed(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return try {
            val am = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
                ?: return false
            am.canScheduleExactAlarms()
        } catch (e: Exception) {
            false
        }
    }
}
