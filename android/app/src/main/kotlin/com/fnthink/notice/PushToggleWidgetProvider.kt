package com.fnthink.notice

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.widget.RemoteViews

/**
 * 桌面小部件：一键开启/暂停推送服务。
 *
 * 复用 [PushToggleManager]（三级状态机）与 [PushToggleActionReceiver] 的启停机制：
 * - 点击小部件 → 发送 ACTION_TOGGLE_PUSH 广播（本 Receiver 接收）
 * - 切换后调用 [PushToggleActionReceiver.notifyServiceToUpdate] 刷新前台服务通知，
 *   并 updateAllWidgets 刷新所有小部件 UI。
 *
 * 支持两种规格（自适应尺寸）：
 * - 2×2 紧凑布局（R.layout.push_toggle_widget）：左上角标题 + 中央圆形状态 + 底部提示
 * - 4×2 宽布局（R.layout.push_toggle_widget_wide）：左上角标题 + 左半圆形 + 右半当日推送计数
 * 通过 AppWidgetManager.getAppWidgetOptions 读取 OPTION_APPWIDGET_MIN_WIDTH，
 * 宽度 >= 220dp 使用宽布局，否则使用紧凑布局；用户拉伸尺寸时自动切换。
 *
 * 品牌适配说明：Android 桌面小部件由各厂商桌面（Launcher）托管，系统没有统一 API
 * 允许应用代码直接添加到桌面，必须由用户手动添加（桌面长按 → 小部件/插件 →
 * 选择「通知推送助手」）。Android 8.0+（API 26）可通过 requestPinAppWidget 弹出
 * 系统「添加到桌面」确认框，减少手动拖拽路径（更多页提供一键添加入口）。
 * 各品牌路径差异较大（小米/华为/OPPO/vivo/三星等），已在应用内
 * 「更多 → 桌面小部件」提供分品牌引导。
 */
open class PushToggleWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val TAG = "PushToggleWidget"
        const val ACTION_TOGGLE_PUSH = "com.fnthink.notice.widget.TOGGLE_PUSH"
        const val ACTION_UPDATE_WIDGET = "com.fnthink.notice.widget.UPDATE_WIDGET"

        /** 宽布局阈值（dp）：宽度 >= 该值使用 4×2 宽布局，否则使用 2×2 紧凑布局 */
        const val WIDE_LAYOUT_MIN_WIDTH_DP = 220

        /**
         * 请求把 2×2 小部件固定到桌面（Android 8.0+ 系统弹窗确认）。
         * 返回是否成功发起请求（部分 Launcher 不支持，返回 false 时降级为手动添加）。
         */
        fun requestPinWidget(context: Context, result: ((Boolean) -> Unit)? = null): Boolean {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, PushToggleWidgetProvider::class.java)
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                val callback: PendingIntent? = result?.let {
                    PendingIntent.getBroadcast(
                        context,
                        0,
                        Intent(context, PushToggleWidgetProvider::class.java)
                            .setAction(ACTION_UPDATE_WIDGET),
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                }
                return manager.requestPinAppWidget(component, null, callback)
            }
            return false
        }

        /** 刷新所有已添加的小部件（2×2 与 4×2 两种规格）。 */
        @JvmStatic
        fun updateAllWidgets(context: Context) {
            refreshProvider(context, PushToggleWidgetProvider::class.java)
            refreshProvider(context, PushToggleWidgetWideProvider::class.java)
        }

        /**
         * 仅在已存在小部件时刷新（无小部件时零开销）。
         * 供 WebhookSender 在推送计数变化后调用。
         */
        @JvmStatic
        fun updateAllWidgetsIfExists(context: Context) {
            val anyExists = hasWidget(context, PushToggleWidgetProvider::class.java) ||
                hasWidget(context, PushToggleWidgetWideProvider::class.java)
            if (!anyExists) return
            refreshProvider(context, PushToggleWidgetProvider::class.java)
            refreshProvider(context, PushToggleWidgetWideProvider::class.java)
        }

        @JvmStatic
        fun hasWidget(context: Context, clazz: Class<*>): Boolean {
            val manager = AppWidgetManager.getInstance(context)
            return manager.getAppWidgetIds(ComponentName(context, clazz)).isNotEmpty()
        }

        @JvmStatic
        fun refreshProvider(context: Context, clazz: Class<*>) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, clazz))
            for (id in ids) {
                updateWidget(context, manager, id)
            }
        }

        @JvmStatic
        fun updateWidget(
            context: Context,
            manager: AppWidgetManager,
            widgetId: Int,
        ) {
            val active = PushToggleManager.isPushActive()

            // 自适应尺寸：根据当前宽度选择布局（2×2 紧凑 / 4×2 宽）
            val options = manager.getAppWidgetOptions(widgetId)
            val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
            val useWide = minWidth >= WIDE_LAYOUT_MIN_WIDTH_DP
            val layoutRes = if (useWide) R.layout.push_toggle_widget_wide else R.layout.push_toggle_widget
            val views = RemoteViews(context.packageName, layoutRes)

            views.setInt(
                R.id.widget_root,
                "setBackgroundResource",
                if (active) R.drawable.widget_bg_active else R.drawable.widget_bg_paused,
            )

            // 左上角标题（跟随语言切换）
            views.setTextViewText(R.id.widget_title, I18n.appName())

            // 中央圆形：状态 + 颜色（推送=绿 / 暂停=红）
            val circleText = if (active)
                I18n.widgetActiveText() else I18n.widgetPausedText()
            views.setTextViewText(R.id.widget_circle, circleText)
            views.setInt(
                R.id.widget_circle,
                "setBackgroundResource",
                if (active) R.drawable.widget_circle_active else R.drawable.widget_circle_paused,
            )

            // 底部提示
            views.setTextViewText(
                R.id.widget_hint,
                if (active) I18n.widgetTapPause() else I18n.widgetTapResume(),
            )

            // 宽布局：右侧当日已推送通知数量
            if (useWide) {
                val todayCount = WidgetDailyCounter.getTodayCount(context)
                views.setTextViewText(R.id.widget_daily_count, todayCount.toString())
                views.setTextViewText(R.id.widget_daily_label, I18n.widgetDailyPushed())
            }

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

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        // 读取持久化的推送状态（服务可能尚未启动）
        PushToggleManager.init(context)
        I18n.init(context)
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        // 用户拉伸/压缩小部件时刷新布局（2×2 ⇄ 4×2 自适应切换）
        PushToggleManager.init(context)
        I18n.init(context)
        updateWidget(context, appWidgetManager, appWidgetId)
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
                I18n.init(context)
                updateAllWidgets(context)
            }
        }
    }
}
