package com.fnthink.notice

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log
import android.widget.RemoteViews
import androidx.core.content.ContextCompat

/**
 * 桌面小部件：一键开启/暂停推送服务。
 *
 * 复用 [PushToggleManager]（三级状态机）与 [PushToggleActionReceiver] 的启停机制：
 * - 点击小部件 → 发送 ACTION_TOGGLE_PUSH 广播（本 Receiver 接收）
 * - 切换后调用 [PushToggleActionReceiver.notifyServiceToUpdate] 刷新前台服务通知，
 *   并 updateAllWidgets 刷新所有小部件 UI。
 *
 * 品牌适配说明：Android 桌面小部件由各厂商桌面（Launcher）托管，系统没有统一 API
 * 允许应用代码直接添加到桌面，必须由用户手动添加（桌面长按 → 小部件/插件 →
 * 选择「通知推送助手」）。各品牌路径差异较大（小米/华为/OPPO/vivo/三星等），
 * 已在应用内「更多 → 桌面小部件」提供分品牌引导。
 */
class PushToggleWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val TAG = "PushToggleWidget"
        const val ACTION_TOGGLE_PUSH = "com.fnthink.notice.widget.TOGGLE_PUSH"
        const val ACTION_UPDATE_WIDGET = "com.fnthink.notice.widget.UPDATE_WIDGET"
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        // 读取持久化的推送状态（服务可能尚未启动）
        PushToggleManager.init(context)
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_TOGGLE_PUSH -> {
                PushToggleManager.init(context)
                PushToggleManager.toggle(context)
                Log.i(TAG, "Toggled push, active=${PushToggleManager.isPushActive()}")
                // 刷新前台服务通知（按钮文案 / 状态）
                PushToggleActionReceiver.notifyServiceToUpdate(context)
                // 刷新所有小部件 UI
                updateAllWidgets(context)
            }
            ACTION_UPDATE_WIDGET -> {
                PushToggleManager.init(context)
                updateAllWidgets(context)
            }
        }
    }

    private fun updateAllWidgets(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(
            ComponentName(context, PushToggleWidgetProvider::class.java),
        )
        for (id in ids) {
            updateWidget(context, manager, id)
        }
    }

    private fun updateWidget(
        context: Context,
        manager: AppWidgetManager,
        widgetId: Int,
    ) {
        val views = RemoteViews(context.packageName, R.layout.push_toggle_widget)
        val active = PushToggleManager.isPushActive()

        views.setInt(
            R.id.widget_root,
            "setBackgroundResource",
            if (active) R.drawable.widget_bg_active else R.drawable.widget_bg_paused,
        )
        views.setTextViewText(
            R.id.widget_status,
            if (active) "推送中" else "已暂停",
        )
        views.setTextColor(
            R.id.widget_status,
            ContextCompat.getColor(
                context,
                if (active) R.color.widget_active_text else R.color.widget_paused_text,
            ),
        )
        views.setTextViewText(
            R.id.widget_hint,
            if (active) "点击暂停推送" else "点击恢复推送",
        )

        val pendingIntent = PendingIntent.getBroadcast(
            context,
            0,
            Intent(context, PushToggleWidgetProvider::class.java)
                .setAction(ACTION_TOGGLE_PUSH),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

        manager.updateAppWidget(widgetId, views)
    }
}
