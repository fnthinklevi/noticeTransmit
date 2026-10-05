package com.fnthink.notice

import android.app.Notification
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log

/**
 * 「上岛 / 超级岛实时更新」那一枚提升请求（T55，Android 16 起）。
 *
 * ⚠ **谁该用它、谁不该用**（维护者 2026-10-05 纠正过一次，这条就是那次纠正的落点）：
 * 只有**幻念推送那两枚高优先级渠道**（收件 / 远程执行）用它 ——
 * 「被控端设备被取消就是靠悬浮通知发现的」，而那两条通知正是用户能据此察觉的东西。
 * **监控服务那条常驻通知不用它**：它一动，被拦下的每一条通知都会跟着弹一次悬浮横幅，
 * 而常驻通知本来只需要安静地待在通知栏里（那一条渠道维持 `IMPORTANCE_LOW`）。
 *
 * ⚠ 为什么用**平台那个 flag** 而不是 `NotificationCompat.Builder.setRequestPromotedOngoing`：
 * 本仓 androidx.core 是 1.13.1，那一 API 还没有（1.16 才加）。
 * ⚠ 为什么必须**先查运行时权限**：`POST_PROMOTED_NOTIFICATIONS` 在 36+ 才有，
 * 而 manifest 里声明 ≠ 用户给了 —— 没给就加 flag 是**静默无效**（上不了岛，无任何报错）。
 * ⚠ 拿不到权限、或 36 以下：**原样返回那枚通知**，绝不抛 ——
 *   少一个上岛胶囊不该让一条已经该到的通知发不出去。
 */
internal object NotificationPromoted {

    private const val TAG = "NotificationPromoted"

    /** 36+ 才有的那枚运行时权限。 */
    private const val PERM_PROMOTED = "android.permission.POST_PROMOTED_NOTIFICATIONS"

    /** 这一档在当前系统上存不存在（36+）。界面用它决定要不要显示这一行。 */
    fun isSupported(): Boolean = Build.VERSION.SDK_INT >= 36

    fun isGranted(context: Context): Boolean {
        if (!isSupported()) return true
        return try {
            context.checkSelfPermission(PERM_PROMOTED) == PackageManager.PERMISSION_GRANTED
        } catch (e: Exception) {
            false
        }
    }

    /** 36 以下、或没拿到权限 ⇒ 原样返回（不抛、不改 flag）。 */
    fun applyIfGranted(context: Context, notification: Notification): Notification {
        if (!isGranted(context)) return notification
        return try {
            notification.also { it.flags = it.flags or Notification.FLAG_PROMOTED_ONGOING }
        } catch (e: Exception) {
            Log.w(TAG, "请求提升为实时更新失败（通知照常发出）", e)
            notification
        }
    }
}
