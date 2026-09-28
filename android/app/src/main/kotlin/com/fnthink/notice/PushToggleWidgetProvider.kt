package com.fnthink.notice

import android.app.AlarmManager
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
 * - 2×2 紧凑布局（R.layout.push_toggle_widget）：图标 + 应用名 / 状态大字 / 一行提示
 * - 4×2 宽布局（R.layout.push_toggle_widget_wide）：左同上（窄一号），右半是当日推送计数面板
 * 整张卡片的容器色就是状态本身：绿=在转发，红=我按了暂停，石板灰=进程不在了。
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

        /** 状态判定的盘源：与 Dart/服务共用同一份 prefs（读盘不读内存缓存，见 [WidgetLiveness]） */
        private const val PREFS_FLUTTER = "FlutterSharedPreferences"
        private const val PREFS_TOGGLE = "push_toggle_state"
        private const val KEY_MONITORING = "flutter.monitoring_enabled"
        private const val KEY_SERVICE_RUNNING = "flutter.notif_service_running"
        private const val KEY_HEARTBEAT = "flutter.notif_heartbeat_at"
        private const val KEY_PUSH_ACTIVE = "push_active"

        /** PendingIntent 请求码：切换=0，打开应用=1（同一 requestCode 会让两套意图互相覆盖） */
        private const val REQ_TOGGLE = 0
        private const val REQ_OPEN_APP = 1

        /** 兜底自刷新闹钟的请求码（本仓库已用 0/1/2001/3001/3002/9001/9002，这里避开） */
        private const val REQ_LIVENESS_ALARM = 3101

        /**
         * 兜底刷新间隔。取 15 分钟不是随手写的：`setAndAllowWhileIdle` 在 Doze 下的
         * 实际最小频率就在 ~15 分钟，写 5 分钟只会让系统在维护窗口里把它合并成同一次唤醒 ——
         * 白排一次，却不会更早触发。正常路径（划掉任务）走 onDestroy/onTaskRemoved 的即时重绘，
         * 这条闹钟只兜"没来得及写就被强杀"那种情况。
         */
        private const val LIVENESS_ALARM_INTERVAL_MS = 15 * 60 * 1000L

        /**
         * 小部件该显示哪一态。**不再单看 [PushToggleManager.isPushActive]** ——
         * 那是"用户暂停了没有"，与"进程还在不在"是两件事，且未初始化时兜底 true，
         * 会让被清理后的桌面继续显示绿色「推送中」。
         */
        @JvmStatic
        internal fun resolveState(context: Context): WidgetLiveness.Verdict {
            val flutter = context.getSharedPreferences(PREFS_FLUTTER, Context.MODE_PRIVATE)
            val toggle = context.getSharedPreferences(PREFS_TOGGLE, Context.MODE_PRIVATE)
            return WidgetLiveness.resolve(
                monitoringEnabled = flutter.getBoolean(KEY_MONITORING, true),
                pushActive = toggle.getBoolean(KEY_PUSH_ACTIVE, true),
                // 缺省 false：从没写过 = 无从断定活着，宁可显示「已关闭」让用户点一下确认
                serviceRunning = flutter.getBoolean(KEY_SERVICE_RUNNING, false),
                heartbeatAt = flutter.getLong(KEY_HEARTBEAT, 0L),
                now = System.currentTimeMillis(),
            )
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
            val verdict = resolveState(context)
            val state = verdict.state
            val closed = state == WidgetLiveness.State.CLOSED

            // 自适应尺寸：根据当前宽度选择布局（2×2 紧凑 / 4×2 宽）
            val options = manager.getAppWidgetOptions(widgetId)
            val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
            val useWide = minWidth >= WIDE_LAYOUT_MIN_WIDTH_DP
            val layoutRes = if (useWide) R.layout.push_toggle_widget_wide else R.layout.push_toggle_widget
            val views = RemoteViews(context.packageName, layoutRes)

            views.setInt(
                R.id.widget_root,
                "setBackgroundResource",
                backgroundFor(state),
            )

            // 左上角标题（跟随语言切换）
            views.setTextViewText(R.id.widget_title, I18n.appName())
            views.setTextColor(R.id.widget_title, context.getColor(onColorFor(state)))

            // 图标与文字都跟着状态走：颜色之外必须有第二条通道（色盲用户、低对比环境）。
            // 图标挂在标题的**复合 drawable** 上而不是单独的 ImageView —— 小组件每多一个 view
            // 就多一次远程 inflation，lint 的 UseCompoundDrawables 说的就是这件事。
            views.setTextViewCompoundDrawablesRelative(R.id.widget_title, iconFor(state), 0, 0, 0)
            val strong = context.getColor(onColorFor(state)) // 主信息：状态字、大数字
            val weak = context.getColor(accentColorFor(state)) // 辅助：提示行、面板标签

            views.setTextViewText(R.id.widget_status, statusText(state))
            views.setTextColor(R.id.widget_status, strong)

            // 底部提示：CLOSED 要说清"为什么"并给出下一步，不能只写"已关闭"三个字
            views.setTextViewText(R.id.widget_hint, hintText(verdict))
            views.setTextColor(R.id.widget_hint, weak)

            // 宽布局：右侧当日已推送通知数量
            if (useWide) {
                val todayCount = WidgetDailyCounter.getTodayCount(context)
                views.setTextViewText(R.id.widget_daily_count, todayCount.toString())
                views.setTextColor(R.id.widget_daily_count, strong)
                views.setTextViewText(R.id.widget_daily_label, I18n.widgetDailyPushed())
                views.setTextColor(R.id.widget_daily_label, weak)
            }

            val pendingIntent = if (closed) {
                // 服务不在，点组件"恢复转发"是骗人的：后台 startService 会被系统拒（原实现
                // 就是把它塞进 startService 的 try/catch 里静默失败）。所以这一态直接打开应用，
                // 由应用侧既有的重绑链路（MainActivity 的强制重绑）把服务带回前台。
                PendingIntent.getActivity(
                    context,
                    REQ_OPEN_APP,
                    Intent(context, MainActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
            } else {
                PendingIntent.getBroadcast(
                    context,
                    REQ_TOGGLE,
                    Intent(context, PushToggleWidgetProvider::class.java)
                        .setAction(ACTION_TOGGLE_PUSH),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
            }
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

            // 兜底刷新：只有"卡片此刻显示的是活着的状态"才需要闹钟去发现它什么时候死的；
            // 已经显示「已关闭」就撤掉闹钟 —— 不然桌面上一张永远灰的卡片会每 15 分钟
            // 白叫一次这个进程。
            scheduleLivenessRefresh(context, alive = state != WidgetLiveness.State.CLOSED)

            manager.updateAppWidget(widgetId, views)
        }

        /**
         * 排 / 撤那枚兜底闹钟。
         *
         * 用 `setAndAllowWhileIdle` 而不是精确闹钟：它不需要 SCHEDULE_EXACT_ALARM 权限，
         * 也不去蹭用户给的"精确闹钟"能力（那是给延迟/聚合推送用的）。
         * 触发时发的是**指向自己的显式广播**，因此不需要在 Manifest 里为这个 action 加过滤器。
         */
        internal fun scheduleLivenessRefresh(context: Context, alive: Boolean) {
            try {
                val am = context.getSystemService(AlarmManager::class.java) ?: return
                val intent = Intent(context, PushToggleWidgetProvider::class.java)
                    .setAction(ACTION_UPDATE_WIDGET)
                if (alive) {
                    val pi = PendingIntent.getBroadcast(
                        context,
                        REQ_LIVENESS_ALARM,
                        intent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    )
                    am.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        System.currentTimeMillis() + LIVENESS_ALARM_INTERVAL_MS,
                        pi,
                    )
                } else {
                    // FLAG_NO_CREATE：不为"撤销"这件事凭空造一个 PendingIntent 出来
                    val pi = PendingIntent.getBroadcast(
                        context,
                        REQ_LIVENESS_ALARM,
                        intent,
                        PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
                    ) ?: return
                    am.cancel(pi)
                    pi.cancel()
                }
            } catch (e: Exception) {
                Log.w(TAG, "liveness alarm update failed: ${e.message}")
            }
        }

        private fun backgroundFor(state: WidgetLiveness.State): Int = when (state) {
            WidgetLiveness.State.PUSHING -> R.drawable.widget_bg_active
            WidgetLiveness.State.PAUSED -> R.drawable.widget_bg_paused
            WidgetLiveness.State.CLOSED -> R.drawable.widget_bg_closed
        }

        /** 三态各一枚图标：勾 / 双竖条 / 电源符号。 */
        private fun iconFor(state: WidgetLiveness.State): Int = when (state) {
            WidgetLiveness.State.PUSHING -> R.drawable.widget_ic_pushing
            WidgetLiveness.State.PAUSED -> R.drawable.widget_ic_paused
            WidgetLiveness.State.CLOSED -> R.drawable.widget_ic_closed
        }

        /** 主信息色（状态字、大数字）。 */
        private fun onColorFor(state: WidgetLiveness.State): Int = when (state) {
            WidgetLiveness.State.PUSHING -> R.color.widget_pushing_on
            WidgetLiveness.State.PAUSED -> R.color.widget_paused_on
            WidgetLiveness.State.CLOSED -> R.color.widget_closed_on
        }

        /** 辅助信息色（提示行、面板标签）：同一色系的弱调，保持一张卡内只有一个音高。 */
        private fun accentColorFor(state: WidgetLiveness.State): Int = when (state) {
            WidgetLiveness.State.PUSHING -> R.color.widget_pushing_accent
            WidgetLiveness.State.PAUSED -> R.color.widget_paused_accent
            WidgetLiveness.State.CLOSED -> R.color.widget_closed_accent
        }

        private fun statusText(state: WidgetLiveness.State): String = when (state) {
            WidgetLiveness.State.PUSHING -> I18n.widgetActiveText()
            WidgetLiveness.State.PAUSED -> I18n.widgetPausedText()
            WidgetLiveness.State.CLOSED -> I18n.widgetClosedText()
        }

        /** CLOSED 的副文案按原因分叉：「去应用里打开监听」与「被清理了，点我打开应用」不是一回事。 */
        private fun hintText(verdict: WidgetLiveness.Verdict): String = when (verdict.state) {
            WidgetLiveness.State.PUSHING -> I18n.widgetTapPause()
            WidgetLiveness.State.PAUSED -> I18n.widgetTapResume()
            WidgetLiveness.State.CLOSED -> when (verdict.reason) {
                WidgetLiveness.Reason.LISTENER_DISABLED -> I18n.widgetClosedListenerOff()
                WidgetLiveness.Reason.NEVER_STARTED -> I18n.widgetClosedNeverStarted()
                else -> I18n.widgetClosedKilled()
            }
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
