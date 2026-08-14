package com.fnthink.notice

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 推送启停 Action 接收器
 *
 * 接收前台通知 Action 按钮点击广播：
 * - ACTION_PAUSE_PUSH：暂停推送（监听继续，仅不发送 webhook）
 * - ACTION_RESUME_PUSH：恢复推送
 *
 * 切换后通知 NotificationMonitorService 更新前台通知文案与按钮。
 */
class PushToggleActionReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "PushToggleAction"
        const val ACTION_PAUSE_PUSH = "com.fnthink.notice.action.PAUSE_PUSH"
        const val ACTION_RESUME_PUSH = "com.fnthink.notice.action.RESUME_PUSH"

        /// 通过显式 Intent 触发 NotificationMonitorService 刷新前台通知（按钮文案 / 状态）。
        /// internal：桌面小部件 PushToggleWidgetProvider 也复用此逻辑。
        @JvmStatic
        internal fun notifyServiceToUpdate(context: Context) {
            val intent = Intent(context, NotificationMonitorService::class.java).apply {
                action = NotificationMonitorService.ACTION_REFRESH_FOREGROUND
            }
            // Android 8+ 后台启动 Service 受限，但本应用是前台服务，可以 startForegroundService 触发更新
            // 这里复用 startService 即可（服务已在运行，onStartCommand 会刷新通知）
            try {
                context.startService(intent)
            } catch (e: Exception) {
                Log.w(TAG, "startService for refresh failed: ${e.message}")
            }
        }
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        context ?: return
        intent ?: return
        when (intent.action) {
            ACTION_PAUSE_PUSH -> {
                PushToggleManager.pause(context)
                Log.i(TAG, "Received PAUSE_PUSH")
                notifyServiceToUpdate(context)
            }
            ACTION_RESUME_PUSH -> {
                PushToggleManager.resume(context)
                Log.i(TAG, "Received RESUME_PUSH")
                notifyServiceToUpdate(context)
            }
        }
    }
}
