package com.fnthink.notice

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.fnthink.notice.BuildConfig
import kotlinx.coroutines.*

class NotificationMonitorService : NotificationListenerService() {
    companion object {
        private const val TAG = "NotificationMonitorService"
        private const val FOREGROUND_ID = 1001
        private const val CHANNEL_ID = "notification_monitor_channel"
        private const val CHANNEL_NAME = "通知监听"
        const val ACTION_UPDATE_CONFIG = "com.fnthink.notice.UPDATE_CONFIG"
        const val ACTION_SET_MONITORING = "com.fnthink.notice.SET_MONITORING"
        const val EXTRA_MONITORING_ENABLED = "monitoring_enabled"
        const val PREFS_NAME = "FlutterSharedPreferences"
        const val PREF_MONITORING_ENABLED = "flutter.monitoring_enabled"
        // 服务存活心跳 / 补扫水位（持久化：进程被回收时内存字段会随进程消失，
        // 只有落盘才能判定「服务中断过 → 期间事件可能丢失 → 需补扫」）
        const val PREF_LAST_ALIVE = "flutter.notif_last_alive_at"
        const val PREF_LAST_SCAN = "flutter.notif_last_scan_at"
        const val ACTION_BATTERY_CHANGED_NOTIFY = "com.fnthink.notice.BATTERY_CHANGED_NOTIFY"
        const val EXTRA_BATTERY_LEVEL = "battery_level"
        const val EXTRA_BATTERY_CHARGING = "battery_charging"
        // 息屏/Doze 下由精确-允许空闲闹钟唤醒，执行电量阈值检查（修复息屏时不推送）
        const val ACTION_BATTERY_ALARM = "com.fnthink.notice.BATTERY_ALARM"
        private const val BATTERY_ALARM_INTERVAL_MS = 15 * 60 * 1000L
        private const val BATTERY_ALARM_REQUEST_CODE = 2001
        // 前台通知刷新（推送启停状态变更后由 PushToggleActionReceiver 触发）
        const val ACTION_REFRESH_FOREGROUND = "com.fnthink.notice.REFRESH_FOREGROUND"
        // 历史记录"现在推送"：由 MainActivity.pushRecordNow 转发，手动补推单条记录
        const val ACTION_PUSH_RECORD_NOW = "com.fnthink.notice.PUSH_RECORD_NOW"
        const val EXTRA_RECORD_DATA = "record_data"

        @Volatile var webhookUrls: List<String> = emptyList()
        @Volatile var deviceName: String = ""
        @Volatile var isConnected: Boolean = false
        // 通知监听器是否已与系统建立连接（断开时 onNotificationPosted 不再回调，
        // 前台通知显示"监听已断开"警告，提醒用户重新授权通知使用权）
        @Volatile var listenerConnected: Boolean = true
        @Volatile var monitoringEnabled: Boolean = true
        @Volatile var pushCount: Int = 0
        // 当日日期（yyyy-MM-dd），跨日重置 pushCount；供 MainActivity 同步 DB 今日计数基数
        @Volatile var todayDate: String = ""

        /** 当前日期字符串（yyyy-MM-dd） */
        fun todayDateString(): String {
            val now = java.util.Date()
            val fmt = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.getDefault())
            return fmt.format(now)
        }

        fun applyTodayDate(date: String) {
            todayDate = date
        }

        /** 跨日重置计数器（E2：@Synchronized 消除极小概率竞态窗口） */
        @Synchronized
        fun resetDailyIfNeeded(now: String) {
            if (now != todayDate) {
                todayDate = now
                pushCount = 0
            }
        }
    }

    private lateinit var notificationProcessor: NotificationProcessor
    private lateinit var batteryMonitor: BatteryMonitor
    private lateinit var webhookSender: WebhookSender
    private lateinit var appChannelSender: AppChannelSender
    private lateinit var configManager: ConfigManager
    private lateinit var delayedPushManager: DelayedPushManager
    private lateinit var mergePushManager: MergePushManager
    private var batteryChangedReceiver: android.content.BroadcastReceiver? = null
    private var delayedPushReceiver: android.content.BroadcastReceiver? = null
    private var mergePushReceiver: android.content.BroadcastReceiver? = null
    private var batteryAlarmPendingIntent: PendingIntent? = null
    @Volatile private var cachedConfig: ConfigSnapshot? = null
    private val notificationManager by lazy { getSystemService(NotificationManager::class.java) }
    private val serviceScope = CoroutineScope(
        Dispatchers.IO + SupervisorJob() + CoroutineExceptionHandler { _, e ->
            // E2：未捕获协程异常兜底记录，避免静默吞没
            Log.e(TAG, "Unhandled coroutine exception", e)
        }
    )

    // / 检查是否已跨日，是则重置计数器（委托给 @Synchronized 封装，消除竞态）
    private fun checkDailyReset() {
        val now = todayDateString()
        resetDailyIfNeeded(now)
        Log.i(TAG, "Daily push count check: $now count=$pushCount")
    }

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "Service created")

        monitoringEnabled = readMonitoringEnabled()
        checkDailyReset()

        // 初始化国际化（从 SharedPreferences 读取 locale 注入 I18n）
        I18n.init(this)
        // 初始化推送启停状态（从 SharedPreferences 恢复，前台通知一键暂停/恢复）
        PushToggleManager.init(this)
        // N7：恢复开发者诊断日志开关（默认关闭，更多页连点版本号 7 次切换）
        DiagLog.init(this)

        // ⚠ 必须先于 startForegroundService()：buildForegroundNotification 的聚合预览
        // （P2）会访问 mergePushManager（lateinit），延迟初始化会在服务 onCreate 即抛
        // UninitializedPropertyAccessException 导致打开 App 闪退
        delayedPushManager = DelayedPushManager(this)
        mergePushManager = MergePushManager(this)

        createNotificationChannel()
        // 先进入前台，满足 startForegroundService 的 5s 内必须 startForeground 的约束
        startForegroundService()

        notificationProcessor = NotificationProcessor(this)
        batteryMonitor = BatteryMonitor(this)
        webhookSender = WebhookSender(this)
        webhookSender.activate()
        appChannelSender = AppChannelSender(this)
        configManager = ConfigManager(this)
        registerDelayedPushReceiver()
        registerMergePushReceiver()

        // 轮询 Handler 绑的是主 Looper（BatteryMonitor.pollingRunnable），回调体就在
        // 主线程执行；而 AppChannelSender 内部 runBlocking 取 token 后再同步发 HTTP，
        // 留在主线程会 ANR。与 batteryChangedReceiver.onReceive 同规，交 IO 协程。
        batteryMonitor.setNotificationCallback { batteryInfo ->
            serviceScope.launch {
                try {
                    dispatchDeviceAlert(batteryInfo)
                    Log.d(TAG, "Battery notification via polling sent: ${batteryInfo.title}")
                } catch (e: Exception) {
                    Log.e(TAG, "Battery polling dispatch failed", e)
                }
            }
        }

        loadConfig()
        applyMonitoringState()
        // T24：亮度与网络是事件，不监听就只能靠 60s 轮询看见（用户已经把屏幕点亮了
        // 才收到"亮度低"）。变化时只做一件事：叫同一条采集判定链再跑一次 ——
        // 与电量广播同构，不另起一套"设备态触发"。
        startDeviceStateWatchers()
        // v1.59：初始化后统一显隐决策（覆盖「通知权限被撤后服务重启」的场景：
        // 权限缺失时这里会撤掉刚 startForeground 的通知，保证显示状态与权限一致）
        refreshForegroundVisibility()
        registerSmsObserver()

        // N4 失败推送自动重试队列：初始化上下文 + 启动重放（服务启动 + 网络恢复触发）
        RetryQueue.startWatching(applicationContext)

        // N9 漏通知修复：启动补扫 —— 进程被系统回收期间 onNotificationPosted 事件
        // 永久丢失（通知仍驻留通知栏），延迟 1.5 秒（等初始化完成）后按持久化水位
        // 补扫仍驻留的通知（主线程调用，activeNotifications 仅主线程可读）
        mainHandler.postDelayed({ recoverMissedOnStartup() }, 1500L)
    }

    // —— 短信库兜底监听：SMS_RECEIVED 广播丢失时，改从短信库捕获并补推 ——
    private var smsObserver: SmsObserver? = null

    /** T24：亮度 / 网络变化监听（与短信观察器同一套生命周期纪律：成对、幂等、必撤） */
    private var brightnessWatcher: BrightnessWatcher? = null
    private var networkWatcher: NetworkWatcher? = null

    /**
     * 启动两个触发源监听。幂等（重复调用不重复注册）。
     *
     * ⚠ 注册失败只降级不致命：亮度/网络触发源这一次不可用，电量与温度照旧 ——
     * 但不能静默，日志必须留下（用户在界面上看不到"这一族今天不工作"）。
     */
    private fun startDeviceStateWatchers() {
        if (brightnessWatcher == null) {
            val w = BrightnessWatcher(applicationContext) { onDeviceStateChanged() }
            w.start()
            brightnessWatcher = w.takeIf { it.isWatching() }
        }
        if (networkWatcher == null) {
            val w = NetworkWatcher(applicationContext) { onDeviceStateChanged() }
            w.start()
            networkWatcher = w.takeIf { it.isWatching() }
        }
    }

    private fun stopDeviceStateWatchers() {
        brightnessWatcher?.stop()
        brightnessWatcher = null
        networkWatcher?.stop()
        networkWatcher = null
    }

    /**
     * 亮度/网络变了 ⇒ 再采一次并判定。走的是与电量广播**完全同一条**路：
     * `checkBatteryAndNotify()`（唯一读数构造点）+ `dispatchDeviceAlert()`
     * （唯一的设备态出站口，T23 的约束判定就在里面）。
     *
     * onCapabilitiesChanged 可能连发多次（网络切换过程里系统会回调好几轮），而引擎的
     * 跨越判定自带"上一轮已记录就不算事件"，因此重复触发是幂等的；这里再加一层
     * 单飞：一轮判定没跑完时后来的变化直接丢弃，避免在 IO 协程里排队跑好几遍。
     */
    private fun onDeviceStateChanged() {
        if (!monitoringEnabled) return
        if (!deviceStateEvaluating.compareAndSet(false, true)) return
        serviceScope.launch {
            try {
                val info = batteryMonitor.checkBatteryAndNotify() ?: return@launch
                dispatchDeviceAlert(info)
            } catch (e: Exception) {
                Log.e(TAG, "Device state alert dispatch failed", e)
            } finally {
                deviceStateEvaluating.set(false)
            }
        }
    }

    private val deviceStateEvaluating = java.util.concurrent.atomic.AtomicBoolean(false)

    private fun registerSmsObserver() {
        if (ContextCompat.checkSelfPermission(
                this, android.Manifest.permission.READ_SMS
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            Log.i(TAG, "READ_SMS 未授予，跳过短信库兜底监听")
            return
        }
        try {
            val observer = SmsObserver(this)
            contentResolver.registerContentObserver(
                Uri.parse("content://sms"), true, observer
            )
            smsObserver = observer
            observer.markBaseline()
            Log.i(TAG, "短信库兜底监听已注册")
        } catch (e: Exception) {
            Log.w(TAG, "注册短信库兜底监听失败: ${e.message}")
            smsObserver = null
        }
    }

    private fun unregisterSmsObserver() {
        smsObserver?.let {
            try {
                contentResolver.unregisterContentObserver(it)
            } catch (_: Exception) {
            }
            try {
                it.destroy()
            } catch (_: Exception) {
            }
        }
        smsObserver = null
    }

    // —— 监听断线自恢复（锁屏 / Doze / 内存压力下系统可能解绑监听连接）——
    // 断开时间戳：用于重连后补扫断线期间新发布的活跃通知（0 = 无断线发生）
    @Volatile private var disconnectedAt: Long = 0L
    private val mainHandler = Handler(Looper.getMainLooper())
    private var rebindRetry: Runnable? = null

    override fun onListenerConnected() {
        super.onListenerConnected()
        isConnected = true
        listenerConnected = true
        touchAlive()
        cancelRebindRetry()
        // 恢复连接后立即刷新前台通知，撤掉"监听已断开"警告
        try { refreshForegroundVisibility() } catch (_: Exception) {}
        Log.i(TAG, "Notification listener connected")
        recoverMissedNotifications()
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        isConnected = false
        listenerConnected = false
        disconnectedAt = System.currentTimeMillis()
        // 监听断开后 onNotificationPosted 不再回调，通知会静默漏读。
        // 走统一显隐入口：通知权限若也已被撤则直接隐藏，否则切换为
        // 「未授予通知读取权限，通知监听已暂停」警告文案，并主动重新请求绑定。
        try { refreshForegroundVisibility() } catch (_: Exception) {}
        Log.i(TAG, "Notification listener disconnected, requesting rebind")
        requestRebindCompat()
    }

    /**
     * 重新请求绑定监听连接。官方文档明确：
     * requestRebind(ComponentName) 是 onListenerDisconnected 之后唯一安全的恢复调用。
     * 调用可能被系统节流或失败，15 秒后仍未重连则再试一次。
     */
    private fun requestRebindCompat() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        try {
            NotificationListenerService.requestRebind(
                ComponentName(this, NotificationMonitorService::class.java)
            )
            rebindRetry?.let { mainHandler.removeCallbacks(it) }
            val retry = Runnable {
                if (!isConnected) {
                    Log.w(TAG, "Still disconnected after rebind, retrying")
                    try {
                        NotificationListenerService.requestRebind(
                            ComponentName(this, NotificationMonitorService::class.java)
                        )
                    } catch (e: Exception) {
                        Log.e(TAG, "rebind retry failed", e)
                    }
                }
            }
            rebindRetry = retry
            mainHandler.postDelayed(retry, 15_000L)
        } catch (e: Exception) {
            Log.e(TAG, "requestRebind failed", e)
        }
    }

    private fun cancelRebindRetry() {
        rebindRetry?.let { mainHandler.removeCallbacks(it) }
        rebindRetry = null
    }

    /**
     * 重连补漏：断线期间新发布且仍驻留在通知栏的通知不会触发 onNotificationPosted，
     * 从系统活跃通知快照中按 postTime 过滤出断线之后发布的条目，走同一处理管道补推，
     * 避免静默漏读。常驻通知由 processNotification 内 dedupKey 去重跳过；
     * 断线之前发布的普通通知（postTime < disconnectedAt）不回放，防止重复推送。
     */
    private fun recoverMissedNotifications() {
        val since = disconnectedAt
        if (since <= 0L) return
        disconnectedAt = 0L
        touchAlive()
        scanActiveSince(since, tag = "断线重连补漏")
    }

    /**
     * **服务启动补扫**（N9 漏通知修复核心）：覆盖「进程被系统回收 → 系统延迟/未重新绑定
     * 监听器 → 期间 `onNotificationPosted` 事件永久丢失，但通知仍驻留通知栏」的漏读。
     *
     * 原实现只在 `onListenerDisconnected → onListenerConnected` 路径补扫，而进程被回收时
     * 该回调不触发、`disconnectedAt` 随进程消失（重建后为 0）→ 冷启动**永不补扫**。
     *
     * 判定依据（`RecoveryWatermark`）：持久化的服务存活心跳 `PREF_LAST_ALIVE`——
     * - 首次安装（无心跳）→ 不补扫（避免回放通知栏既有历史通知）；
     * - 心跳新鲜（服务未中断）→ 不补扫（事件不会丢）；
     * - 心跳陈旧（中断过）→ 以 `max(心跳, 上次补扫水位)` 为下界补扫，双水位防重复回放。
     */
    private fun recoverMissedOnStartup() {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        val lastAlive = prefs.getLong(PREF_LAST_ALIVE, 0L)
        val lastScan = prefs.getLong(PREF_LAST_SCAN, 0L)
        val since = RecoveryWatermark.scanSinceOrNull(lastAlive, lastScan, now)
        // 水位推进到 now（无论是否补扫），防止下次启动重复回放同一段
        prefs.edit()
            .putLong(PREF_LAST_SCAN, now)
            .putLong(PREF_LAST_ALIVE, now)
            .apply()
        if (since == null) {
            Log.d(TAG, "启动补扫跳过（首次安装或服务未中断）")
            return
        }
        touchAlive()
        scanActiveSince(since, tag = "启动补扫")
    }

    /** 补扫通知栏中「postTime >= since」的仍驻留通知，走与实时回调完全相同的处理管道 */
    private fun scanActiveSince(since: Long, tag: String) {
        try {
            val active = activeNotifications ?: return
            val missed = active.filter { it.postTime >= since }
            if (missed.isEmpty()) return
            Log.i(TAG, "$tag: ${missed.size} notification(s) (postTime >= $since)")
            for (sbn in missed) {
                dispatchPosted(sbn)
            }
        } catch (e: Exception) {
            Log.e(TAG, "$tag 失败", e)
        }
    }

    /** 服务存活心跳：持久化到 prefs，供冷启动补扫判定「服务中断时长 */
    @Volatile
    private var lastAliveWritten: Long = 0L

    private fun touchAlive() {
        try {
            val now = System.currentTimeMillis()
            // 心跳的语义是「只有落盘才能判定服务是否中断过」（见补扫注释）：apply() 在
            // 进程被强杀时可能整笔丢失 → 冷启动读到陈旧心跳 → 补扫 → 重复推送。
            // 但逐条 commit() 会把同步磁盘 IO 压在通知风暴的主线程上。折中：节流到
            // 30 秒一次 commit()（本方法只在主线程回调里被调用，无并发）。
            if (now - lastAliveWritten < 30_000L) return
            lastAliveWritten = now
            getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putLong(PREF_LAST_ALIVE, now)
                .commit()
        } catch (_: Exception) {}
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent != null) {
            when (intent.action) {
                ACTION_UPDATE_CONFIG -> {
                    DiagLog.w(TAG, "Config update received")
                    loadConfig()
                }
                ACTION_SET_MONITORING -> {
                    val enabled = intent.getBooleanExtra(EXTRA_MONITORING_ENABLED, true)
                    monitoringEnabled = enabled
                    Log.i(TAG, "Monitoring set to $enabled")
                    applyMonitoringState()
                }
                ACTION_REFRESH_FOREGROUND -> {
                    // 推送启停状态变更后刷新前台通知（按钮文案 / 状态文案）
                    Log.d(TAG, "Refresh foreground notification (push toggle)")
                    updateForegroundNotification()
                }
                ACTION_PUSH_RECORD_NOW -> {
                    // 历史记录"现在推送"：手动补推单条记录（忽略暂停开关）
                    val data = intent.getStringExtra(EXTRA_RECORD_DATA)
                    if (!data.isNullOrEmpty()) {
                        pushRecordNow(data)
                    }
                }
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? {
        return super.onBind(intent)
    }

    override fun onDestroy() {
        super.onDestroy()
        batteryChangedReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {}
        }
        delayedPushReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {}
        }
        // 聚合到点接收器同样必须注销：只注册不注销会让系统持有本 Service 引用
        // （连带 MergePushManager / NotificationProcessor / Handler）直到进程结束。
        mergePushReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {}
        }
        mergePushReceiver = null
        delayedPushReceiver = null
        batteryMonitor.stopPolling()
        cancelRebindRetry()
        mainHandler.removeCallbacksAndMessages(null)
        cancelBatteryAlarm()
        webhookSender.destroy()
        appChannelSender.destroy()
        unregisterSmsObserver()
        // T24：两个触发源监听必须撤 —— 系统持有回调对象就等于持有整个 Service
        // （连带 NotificationProcessor / Handler），"只注册不注销"这条本仓库已付过学费。
        stopDeviceStateWatchers()
        RetryQueue.stopWatching()
        serviceScope.cancel()
        // v1.59：服务销毁时显式撤掉常驻通知（场景「进程终止不得残留」）。
        // 系统在服务销毁时会自动移除 FGS 通知，此处显式 cancel 双保险，
        // 覆盖厂商 ROM 上 stopForeground 被延迟/吞掉的极端情况。
        try {
            stopForegroundCompat()
        } catch (_: Exception) {}
        notificationManager.cancel(FOREGROUND_ID)
        Log.i(TAG, "Service destroyed")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        super.onNotificationPosted(sbn)
        // N9：存活心跳（持久化）——供冷启动补扫判定「服务中断时长」
        touchAlive()
        dispatchPosted(sbn)
    }

    // 单条通知完整处理管道：提取 → 过滤 → 规则决策 → 分发
    // （onNotificationPosted 与重连补漏 recoverMissedNotifications 共用）
    private fun dispatchPosted(sbn: StatusBarNotification) {
        if (!monitoringEnabled) return
        Log.d(TAG, "Notification posted: ${sbn.packageName}")

        // PackageManager 查询、多轮包名反查、历史缓存全量 JSON 读与 commit() 同步写盘
        // 均为重活，通知风暴下在主线程执行是 NotificationListenerService 的典型 ANR 隐患。
        // 全部下沉到 IO 协程（serviceScope 在 onDestroy 时 cancel，随服务销毁而停止）。
        serviceScope.launch {
            try {
                val rawInfo = notificationProcessor.processNotification(sbn)
                if (rawInfo != null) {
                    val config = cachedConfig ?: ConfigSnapshot()
                    rawInfo.deviceName = config.deviceName

                    val filterResult = notificationProcessor.filter(
                        rawInfo.packageName,
                        rawInfo.title,
                        rawInfo.content,
                        rawInfo.subText,
                        config.whitelistKeywords,
                        config.enabledPackages,
                        config.blacklistKeywords,
                        config.appFilterMode
                    )
                    if (!filterResult.allowed) {
                        // 被过滤（黑名单/应用过滤）的也写入历史，送达状态=失败+原因。
                        // 之前静默丢弃会让用户以为"通知没读到"。
                        // 隐私：不记录通知标题与命中关键词（可能含验证码/余额等敏感内容）
                        Log.d(TAG, "Notification filtered out (${filterResult.source.name}): ${rawInfo.appName}")
                        webhookSender.sendBroadcast(rawInfo)
                        DeliveryNotifier.notify(
                            this@NotificationMonitorService,
                            rawInfo.id,
                            "FILTER",
                            WebhookResponseParser.ParseResult(
                                WebhookResponseParser.DeliveryStatus.BIZ_FAIL,
                                0, filterResult.blockReason(), false
                            )
                        )
                    } else {
                        // 白名单命中：标题加备注标签，推送与历史均可见
                        val info = filterResult.whitelistTag()?.let { tag ->
                            rawInfo.copy(title = "$tag${rawInfo.title}")
                        } ?: rawInfo
                        // 规则引擎决策：立即推送 / 延迟推送 / 仅记录 / 静默忽略
                        when (val decision = RuleEngine.decide(info, config.rulesJson)) {
                            RuleEngine.Decision.Block -> {
                                Log.d(TAG, "Notification blocked by rule: ${info.appName}")
                            }
                            RuleEngine.Decision.Record -> {
                                webhookSender.sendBroadcast(info)
                                Log.d(TAG, "Notification recorded only: ${info.appName}")
                            }
                            is RuleEngine.Decision.Delay -> {
                                // 立即写入历史（pending 状态），到点后补推 webhook
                                webhookSender.sendBroadcast(info)
                                delayedPushManager.enqueue(info, decision.fireAt)
                                DiagLog.w(TAG, "Notification delayed push at ${decision.fireAt}: ${info.appName}")
                            }
                            is RuleEngine.Decision.Merge -> {
                                // P2 聚合推送：成员先各自记录历史（独立可见），窗口结束时
                                // 由 MergePushManager 合并为一条聚合推送；成员的送达结果
                                // 到点以 MERGE 伪通道补标（见 MergePushManager 风险标注 3）
                                webhookSender.sendBroadcast(info)
                                // append 返回「需立即推送的组」（队列超限移出的最旧组 /
                                // F3 达到 maxItems 提前触发的当前组），需在**锁外**推送。
                                // 不能在 MergePushManager 内部自行推送：那里处于 @Synchronized
                                // 临界区且是每条通知的热路径，网络 IO 会长时间占用对象锁
                                // （阻塞前台通知刷新）并有跨线程死锁风险。
                                val flushGroups = mergePushManager.append(
                                    info,
                                    decision.windowMs,
                                    decision.maxItems,
                                    decision.groupByTitle,
                                )
                                for (group in flushGroups) {
                                    flushMergedGroup(group)
                                }
                                updateForegroundNotification()
                                DiagLog.w(TAG, "Notification merged (window ${decision.windowMs}ms): ${info.appName}")
                            }
                            RuleEngine.Decision.Push -> {
                                dispatchToChannels(info)
                                checkDailyReset()
                                pushCount++
                                updateForegroundNotification()
                                DiagLog.w(TAG, "Notification sent: ${info.appName}")
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error processing notification", e)
                // 兜底降级历史：本 catch 此前只写 logcat，于是提取阶段（processNotification）
                // 一旦抛异常，这条通知**既不入历史也不推送**，用户完全无从得知内容丢了。
                // 这里只使用 sbn 直接可得的字段（不再调 PackageManager，避免二次抛错），
                // 正文不含通知内容与异常细节（与日志脱敏同规）。
                try {
                    val now = System.currentTimeMillis()
                    val timeStr = java.text.SimpleDateFormat(
                        "yyyy-MM-dd HH:mm:ss",
                        java.util.Locale.getDefault(),
                    ).format(java.util.Date(sbn.postTime))
                    webhookSender.sendBroadcast(
                        NotificationInfo(
                            id = "${sbn.packageName}:${sbn.tag}:${sbn.id}:$now",
                            title = I18n.processFailedTitle(),
                            content = I18n.processFailedBody(),
                            subText = "",
                            packageName = sbn.packageName ?: "",
                            appName = sbn.packageName ?: "",
                            postTime = sbn.postTime,
                            time = timeStr,
                            type = "notification",
                            deviceName = PrefsHelper.deviceName,
                        ),
                    )
                } catch (e2: Exception) {
                    Log.e(TAG, "降级历史记录也失败", e2)
                }
            }
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        super.onNotificationRemoved(sbn)
        notificationProcessor.removeNotification(sbn)
        Log.d(TAG, "Notification removed: ${sbn.packageName}")
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        // 用户划掉最近任务：系统可能回收进程。START_STICKY 会重启服务但延迟不确定；
        // 主动排程 1 秒后拉起，减小「监听 + 前台服务」的空窗期（漏通知窗口）。
        try {
            val restart = Intent(applicationContext, NotificationMonitorService::class.java)
            val pi = PendingIntent.getService(
                applicationContext,
                0,
                restart,
                PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
            )
            getSystemService(AlarmManager::class.java)?.set(
                AlarmManager.RTC,
                System.currentTimeMillis() + 1000L,
                pi
            )
            Log.i(TAG, "Task removed: service restart scheduled in 1s")
        } catch (e: Exception) {
            Log.w(TAG, "onTaskRemoved: restart scheduling failed", e)
        }
    }

    private fun loadConfig() {
        val loadedDeviceName = configManager.getDeviceName()
        deviceName = loadedDeviceName
        batteryMonitor.setDeviceName(loadedDeviceName)
        webhookSender.setDeviceName(loadedDeviceName)

        // 加载完整通道配置（含 secret 与 type，启用签名与送达校验）
        val loadedConfigs = configManager.getWebhookChannelConfigs()
        webhookUrls = loadedConfigs.map { it.url }
        webhookSender.updateChannelConfigs(loadedConfigs)

        // 自建应用通道（应用通道体系，与 webhook 并行推送）
        val loadedAppConfigs = configManager.getAppChannelConfigs()
        appChannelSender.updateConfigs(loadedAppConfigs)

        batteryMonitor.setEnabled(configManager.getBatteryNotifyEnabled())
        batteryMonitor.updateRules(configManager.getBatteryRules())
        batteryMonitor.setTemperatureEnabled(configManager.getTemperatureNotifyEnabled())
        batteryMonitor.updateTemperatureRules(configManager.getTemperatureRules())
        // T24：亮度/网络规则与族开关（同一族镜像键）
        batteryMonitor.setDeviceStateEnabled(configManager.getDeviceStateNotifyEnabled())
        batteryMonitor.updateDeviceStateRules(configManager.getDeviceStateRules())

        cachedConfig = ConfigSnapshot()
        // 服务重启后恢复未到期的延迟推送闹钟（进程被杀 → START_STICKY 重建场景）
        delayedPushManager.rescheduleAll()
        // 聚合组恢复：过期组不丢弃（与延迟队列不同），重排闹钟尽快补推
        mergePushManager.rescheduleAll()

        Log.d(TAG, "Config loaded: ${loadedConfigs.size} webhook channels (signed)")
    }

    private fun readMonitoringEnabled(): Boolean {
        return try {
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            // 缺失兜底取 true：服务已存活说明用户在用，宁可多推也不静默停推。
            // 首页状态查询的兜底不同（按监听器实际绑定态），见 MainActivity.isMonitoringEnabled
            prefs.getBoolean(PREF_MONITORING_ENABLED, true)
        } catch (e: Exception) {
            true
        }
    }

    private fun applyMonitoringState() {
        if (monitoringEnabled) {
            startForegroundService()
            if (batteryChangedReceiver == null) {
                startBatteryMonitoring()
            }
            batteryMonitor.startPolling()
            Log.i(TAG, "Monitoring enabled")
        } else {
            batteryMonitor.stopPolling()
            cancelBatteryAlarm()
            batteryChangedReceiver?.let {
                try {
                    unregisterReceiver(it)
                } catch (_: Exception) {}
            }
            batteryChangedReceiver = null
            stopForegroundCompat()
            Log.i(TAG, "Monitoring disabled")
        }
    }

    /**
     * 常驻通知显隐与内容的统一决策入口（v1.59，场景 5 权限缺失处理）：
     *
     * 1. 通知权限（POST_NOTIFICATIONS）未授予 → 直接隐藏（cancel，含清理权限被撤
     *    前显示过的残留；此后 startForeground 仍会调用以满足 5s 约束，但系统不会
     *    展示任何通知，且此处会继续 cancel 防残留）。
     * 2. 已授予 → 按 monitoringEnabled 显示或隐藏；内容文案由
     *    buildForegroundNotification 依 listenerConnected / pushActive 决定
     *    （使用权断开时显示「未授予通知读取权限，通知监听已暂停」）。
     *
     * 所有显隐变化（开始/停止/使用权断开重连/初始化）都经此入口，保证各场景
     * 的显示与消失及时准确。
     */
    private fun refreshForegroundVisibility() {
        val postAllowed = notificationManager.areNotificationsEnabled()
        if (!postAllowed) {
            // 场景 5b：通知权限缺失 → 直接隐藏
            notificationManager.cancel(FOREGROUND_ID)
            Log.i(TAG, "Foreground notification hidden: POST_NOTIFICATIONS not granted")
            return
        }
        if (monitoringEnabled) {
            // 场景 1 / 4 / 5a：显示（内容随 listenerConnected / pushActive 变化）
            startForegroundService()
        } else {
            // 场景 2：停止监听 → 立即消失
            stopForegroundCompat()
        }
    }

    private fun stopForegroundCompat() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (e: Exception) {
            Log.e(TAG, "stopForeground failed", e)
        }
        // 双保险：部分 ROM 对 REMOVE 的处理有延迟，显式 cancel 确保立即消失（v1.59）
        try {
            notificationManager.cancel(FOREGROUND_ID)
        } catch (_: Exception) {}
    }

    /**
     * 注册延迟推送闹钟接收器：到点后取出队列中已到期的通知并补推 webhook + 邮件。
     * 应用内广播（ACTION_PUSH_DUE 由 AlarmManager 触发），无需对外导出。
     */
    private fun registerDelayedPushReceiver() {
        val filter = IntentFilter(DelayedPushManager.ACTION_PUSH_DUE)
        delayedPushReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action != DelayedPushManager.ACTION_PUSH_DUE) return
                Log.d(TAG, "Delayed push alarm fired")
                serviceScope.launch {
                    try {
                        val due = delayedPushManager.drainDue()
                        for (info in due) {
                            dispatchToChannels(info, alsoBroadcastRecord = false)
                            checkDailyReset()
                            pushCount++
                            updateForegroundNotification()
                            Log.d(TAG, "Delayed notification sent: ${info.appName}")
                        }
                        // 闹钟是一次性的（setAndAllowWhileIdle）：drain 后必须重排下一条到期推送，
                        // 否则队列中多条延迟推送只有第一条会按时触发，其余要等新入队/服务重启才补推
                        delayedPushManager.rescheduleAll()
                    } catch (e: Exception) {
                        Log.e(TAG, "Error sending delayed pushes", e)
                    }
                }
            }
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(delayedPushReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(delayedPushReceiver, filter)
            }
            Log.d(TAG, "Delayed push receiver registered")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to register delayed push receiver", e)
        }
    }

    /**
     * 推送一个聚合组（**唯一实现**，到点推送与超限兜底共用）。
     *
     * ⚠ 两处调用点必须共用本方法：历史上兜底推送曾自己 `WebhookSender(context)` 新建实例
     * 直接推送，而通道配置只注入到本 Service 持有的实例上（`updateChannelConfigs`），
     * 新建实例的 `channelConfigs` 恒为空 → **兜底推送从未真正发出**。
     * 统一走本方法即可保证「通道配置已注入」且行为不分叉。
     *
     * ⚠ 必须在**锁外**调用（`MergePushManager` 的 `@Synchronized` 方法内不得触发网络 IO）。
     *
     * ⚠ 送达状态必须回传**真实结果**，不能写死 SUCCESS：否则推送失败时成员记录显示
     * 「已合并推送」，用户以为送达而内容实际丢失（历史缺陷，见 MergePushManager 标注 3）。
     */
    private fun flushMergedGroup(group: MergePushManager.MergeGroup) {
        // P1：窗口期内只收到一条通知 → 不做合并推送，按普通单条推送处理
        // （标题为消息原文、逐通道回传真实送达结果，不出现「已合并推送 (1 条)」）。
        // 成员记录早已在入组时写好历史（pending），sendToSingleUrl 会按通道真实结果
        // notifyDeliveryResult 补终态，与普通推送语义完全一致。
        if (group.items.size == 1) {
            try {
                val single = group.items[0]
                checkDailyReset()
                pushCount++
                dispatchToChannels(single, alsoBroadcastRecord = false)
                updateForegroundNotification()
                DiagLog.w(TAG, "聚合组仅 1 条，按单条推送: ${group.key}")
            } catch (e: Exception) {
                Log.e(TAG, "Error flushing single-member group: ${group.key}", e)
            }
            return
        }
        try {
            val merged = group.buildMergedInfo()
            checkDailyReset()
            // 计数语义（风险标注 4）：按聚合组 +1，而非成员逐条 +N
            pushCount++
            dispatchToChannels(merged, alsoBroadcastRecord = false) { result, viaBackup ->
                mergePushManager.markMembersDelivered(group, result, viaBackup)
                if (result.status == WebhookResponseParser.DeliveryStatus.SUCCESS) {
                    DiagLog.w(TAG, "Merged push sent: ${group.key} (${group.items.size} 条) id=${merged.id}")
                } else {
                    Log.w(TAG, "Merged push FAILED: ${group.key} status=${result.status} msg=${result.message}")
                }
            }
            updateForegroundNotification()
        } catch (e: Exception) {
            Log.e(TAG, "Error flushing merged group: ${group.key}", e)
        }
    }

    /**
     * 注册聚合推送闹钟接收器（P2）：到点取出到期聚合组，合并为一条聚合通知
     * 统一推送 webhook + 邮件，并对成员逐条回传 MERGE 伪通道送达结果补标历史。
     */
    private fun registerMergePushReceiver() {
        val filter = IntentFilter(MergePushManager.ACTION_MERGE_DUE)
        mergePushReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action != MergePushManager.ACTION_MERGE_DUE) return
                Log.d(TAG, "Merge push alarm fired")
                serviceScope.launch {
                    try {
                        val groups = mergePushManager.drainDue()
                        for (group in groups) {
                            flushMergedGroup(group)
                        }
                        // 一次性闹钟：drain 后重排下一条到期聚合组
                        mergePushManager.rescheduleAll()
                    } catch (e: Exception) {
                        Log.e(TAG, "Error sending merged pushes", e)
                    }
                }
            }
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(mergePushReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(mergePushReceiver, filter)
            }
            Log.d(TAG, "Merge push receiver registered")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to register merge push receiver", e)
        }
    }

    private fun startBatteryMonitoring() {
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_BATTERY_CHANGED)
            // 插拔充电专用广播：息屏/Doze 下仍可靠投递，是修复“锁屏插电无反应”的关键
            addAction(Intent.ACTION_POWER_CONNECTED)
            addAction(Intent.ACTION_POWER_DISCONNECTED)
            // 息屏/Doze 下由允许空闲闹钟唤醒，执行电量阈值检查（修复息屏时不推送）
            addAction(ACTION_BATTERY_ALARM)
        }
        batteryChangedReceiver = object : android.content.BroadcastReceiver() {
            private val wakeLockTag = "BatteryMonitor::PowerWakeLock"
            override fun onReceive(context: Context?, intent: Intent?) {
                // 关键：onReceive 内的任何未捕获异常都会让系统直接杀掉整个进程
                // （表现为“打开即闪退”），因此整段必须包在 try/catch 中。
                var wakeLock: PowerManager.WakeLock? = null
                try {
                    val action = intent?.action

                    // 闹钟唤醒时重新排程下一次检查，保证息屏期间持续轮询
                    if (action == ACTION_BATTERY_ALARM) {
                        scheduleBatteryAlarm()
                    }

                    // 息屏插入/拔出充电、或闹钟唤醒时，短暂持锁确保电量读取与 webhook 发送完成
                    if (action == Intent.ACTION_POWER_CONNECTED ||
                        action == Intent.ACTION_POWER_DISCONNECTED ||
                        action == ACTION_BATTERY_ALARM
                    ) {
                        try {
                            val pm = context?.getSystemService(Context.POWER_SERVICE) as? PowerManager
                            wakeLock = pm?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, wakeLockTag)
                            wakeLock?.acquire(5000L)
                        } catch (_: Exception) {
                            wakeLock = null
                        }
                    }

                    val batteryInfo = batteryMonitor.checkBatteryAndNotify()
                    if (batteryInfo != null) {
                        // onReceive 在主线程：推送必须交 IO 协程。AppChannelSender 内部
                        // runBlocking 取 token 后再同步发 HTTP，留在主线程会 ANR。
                        serviceScope.launch {
                            try {
                                dispatchDeviceAlert(batteryInfo)
                                Log.d(TAG, "Battery notification sent: ${batteryInfo.title}")
                            } catch (e: Exception) {
                                Log.e(TAG, "Battery alert dispatch failed", e)
                            }
                        }
                    }

                    val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
                    val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
                    val status = intent?.getIntExtra(BatteryManager.EXTRA_STATUS, BatteryManager.BATTERY_STATUS_UNKNOWN)
                    val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                        status == BatteryManager.BATTERY_STATUS_FULL
                    val actualLevel = if (level >= 0) (level * 100 / scale).coerceIn(0, 100) else -1

                    val notifyIntent = Intent(ACTION_BATTERY_CHANGED_NOTIFY).apply {
                        setPackage(context?.packageName)
                        putExtra(EXTRA_BATTERY_LEVEL, actualLevel)
                        putExtra(EXTRA_BATTERY_CHARGING, isCharging)
                    }
                    context?.sendBroadcast(notifyIntent)
                } catch (e: Exception) {
                    Log.e(TAG, "Error in battery receiver onReceive", e)
                } finally {
                    // 延迟释放唤醒锁，确保异步 webhook 发送有机会完成
                    wakeLock?.let { wl ->
                        Handler(Looper.getMainLooper()).postDelayed({
                            try { wl.release() } catch (_: Exception) {}
                        }, 3000L)
                    }
                }
            }
        }
        try {
            // Android 13+ (targetSdk 34+) 动态注册必须显式声明 exported 标志，
            // 否则混入自定义 action（ACTION_BATTERY_ALARM）的 filter 不再满足"仅系统广播"豁免，
            // 会抛 SecurityException 导致电量监听与息屏闹钟整体失效。
            // 该 receiver 只接收系统广播与应用内闹钟广播，无需对外导出。
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(
                    batteryChangedReceiver,
                    filter,
                    Context.RECEIVER_NOT_EXPORTED
                )
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                registerReceiver(batteryChangedReceiver, filter, 0)
            } else {
                @Suppress("DEPRECATION")
                registerReceiver(batteryChangedReceiver, filter)
            }
            // 立即排程首次空闲闹钟（Handler 轮询在 Doze 下会被节流，此处为息屏兜底）
            scheduleBatteryAlarm()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start battery monitoring", e)
        }
    }

    /**
     * 安排一次「允许在空闲（Doze）时触发」的唤醒闹钟。
     * 使用 setAndAllowWhileIdle（非精确闹钟），无需 SCHEDULE_EXACT_ALARM 权限，
     * 设备进入 Doze 后会在维护窗口被唤醒执行电量检查；闹钟触发时自身会再次排程。
     */
    private fun scheduleBatteryAlarm() {
        try {
            val am = getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            val intent = Intent(ACTION_BATTERY_ALARM).apply { setPackage(packageName) }
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val pi = PendingIntent.getBroadcast(this, BATTERY_ALARM_REQUEST_CODE, intent, flags)
            batteryAlarmPendingIntent = pi
            val triggerAt = System.currentTimeMillis() + BATTERY_ALARM_INTERVAL_MS
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi)
            } else {
                @Suppress("DEPRECATION")
                am.setRepeating(AlarmManager.RTC_WAKEUP, triggerAt, BATTERY_ALARM_INTERVAL_MS, pi)
            }
            Log.d(TAG, "Battery idle alarm scheduled (15min)")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to schedule battery alarm", e)
        }
    }

    private fun cancelBatteryAlarm() {
        try {
            val pi = batteryAlarmPendingIntent ?: return
            val am = getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            am.cancel(pi)
            batteryAlarmPendingIntent = null
            Log.d(TAG, "Battery idle alarm cancelled")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to cancel battery alarm", e)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "后台通知监听前台服务"
                    setShowBadge(false)
                    enableVibration(false)
                    enableLights(false)
                }
                val notificationManager = getSystemService(NotificationManager::class.java)
                notificationManager.createNotificationChannel(channel)
                Log.i(TAG, "Notification channel created")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to create notification channel", e)
            }
        }
    }

    private fun startForegroundService() {
        val notification = buildForegroundNotification()

        // 注意：不请求 EXTRA_REQUEST_PROMOTED_ONGOING（Android 16 Live Update 提升）。
        // 该标志会让常驻通知被提升为实时更新，在小米 HyperOS 上表现为「超级岛」常驻胶囊。
        // 我们的前台通知仅需在通知栏展示，不参与系统胶囊/灵动岛。

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(FOREGROUND_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(FOREGROUND_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(FOREGROUND_ID, notification)
        }
        Log.i(TAG, "Foreground service started")
        // v1.59：通知权限未授予时系统不会展示任何通知；显式 cancel 防止
        // 权限被撤前显示过的旧通知残留（场景 5b：权限缺失直接隐藏）
        if (!notificationManager.areNotificationsEnabled()) {
            notificationManager.cancel(FOREGROUND_ID)
        }
    }

    // / 更新前台通知显示当前已推送数量与推送启停状态
    private fun updateForegroundNotification() {
        // v1.59：通知权限已撤时不再 notify，并撤掉可能残留的旧通知
        if (!notificationManager.areNotificationsEnabled()) {
            notificationManager.cancel(FOREGROUND_ID)
            return
        }
        val notification = buildForegroundNotification()
        notificationManager.notify(FOREGROUND_ID, notification)
    }

    /**
     * 构建前台通知（含推送启停 Action 按钮，文案随 push 状态切换）。
     * - 推送激活：显示「暂停推送」按钮 + 「正在监听通知…」
     * - 推送暂停：显示「恢复推送」按钮 + 「推送已暂停…」
     * - 有活跃聚合组（P2）：InboxStyle 逐组展示待合并通知（应用 ×条数 + 剩余秒数），
     *   聚合窗口结束后自动恢复常规样式
     */
    private fun buildForegroundNotification(): Notification {
        val contentIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, contentIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val pushActive = PushToggleManager.isPushActive()
        val title = I18n.serviceTitle()
        // 监听断开优先显示警告（此时既收不到通知也不推送），避免用户误以为服务正常
        val contentText = if (!listenerConnected) {
            I18n.serviceListenerDisconnected()
        } else if (pushActive) {
            I18n.serviceListening(pushCount)
        } else {
            I18n.servicePushPaused(pushCount)
        }

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(contentText)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            // 归类为服务通知：系统（含各品牌灵动岛/超级岛）对服务类常驻通知默认不上岛
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOngoing(true)
            .setStyle(NotificationCompat.BigTextStyle().bigText(contentText))

        // P2 聚合预览：推送激活且存在待合并通知时，InboxStyle 逐组展示。
        // isInitialized 防御：本方法在 startForegroundService() 极早期被调用，
        // 若未来初始化顺序再被调整，未初始化时静默跳过聚合预览，绝不允许崩服务
        val mergeActive =
            this::mergePushManager.isInitialized && pushActive && listenerConnected
        if (mergeActive) {
            val groups = mergePushManager.activeGroups()
            if (groups.isNotEmpty()) {
                val now = System.currentTimeMillis()
                val totalItems = groups.sumOf { it.items.size }
                val inbox = NotificationCompat.InboxStyle()
                    .setSummaryText(contentText)
                for (group in groups) {
                    val etaSec = maxOf(0L, (group.windowEnd - now) / 1000)
                    val latest = group.items.last()
                    val line = if (group.items.size > 1) {
                        "${group.items.first().appName} ×${group.items.size} · ${latest.title} · ${I18n.mergeEta(etaSec)}"
                    } else {
                        "${latest.title} · ${I18n.mergeEta(etaSec)}"
                    }
                    inbox.addLine(line)
                }
                builder
                    .setContentText(I18n.mergePendingSummary(totalItems))
                    .setStyle(inbox)
            }
        }

        // 推送启停 Action 按钮（点击触发 PushToggleActionReceiver）
        val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        if (pushActive) {
            val pauseIntent = Intent(this, PushToggleActionReceiver::class.java).apply {
                action = PushToggleActionReceiver.ACTION_PAUSE_PUSH
            }
            val pausePi = PendingIntent.getBroadcast(this, 1, pauseIntent, piFlags)
            builder.addAction(0, I18n.actionPausePush(), pausePi)
        } else {
            val resumeIntent = Intent(this, PushToggleActionReceiver::class.java).apply {
                action = PushToggleActionReceiver.ACTION_RESUME_PUSH
            }
            val resumePi = PendingIntent.getBroadcast(this, 2, resumeIntent, piFlags)
            builder.addAction(0, I18n.actionResumePush(), resumePi)
        }

        return builder.build()
    }

    private inner class ConfigSnapshot {
        val whitelistKeywords = configManager.getWhitelistKeywords()
        val enabledPackages = configManager.getEnabledPackages()
        val blacklistKeywords = configManager.getBlacklistKeywords()
        val deviceName = configManager.getDeviceName()
        val appFilterMode = configManager.getAppFilterMode()
        val rulesJson = configManager.getNotificationRules()
        /** T23：设备态告警是否也过关键词约束（默认关） */
        val deviceAlertConstraint = configManager.getDeviceAlertConstraintEnabled()
    }

    /**
     * 设备态告警（电量 / 温度）的**唯一**出站口。
     *
     * 为什么要有这一处：这两条路原先各自直接 `dispatchToChannels`，把「已到达的通知要不要转」
     * 那套约束整个绕过了 —— 用户拉黑了某个关键词，电量告警里出现照样照推。
     * 判定不重写一份：走的就是 [NotificationProcessor.filter] → `FilterEngine` 那一个点。
     *
     * `sourceType = "device"` 是刻意的：应用黑白名单只作用于 `notification`（设备态告警是
     * 本机自己产生的，"只转发这些应用"对它没有意义），关键词黑白名单照常生效。
     *
     * 开关默认关 ⇒ 行为与今天逐字节一致；拦下时必须留痕（历史 + 送达状态），
     * 否则用户只会看到"今天没响"，分不清是没触发还是被约束拦了。
     */
    private fun dispatchDeviceAlert(info: NotificationInfo) {
        val config = cachedConfig ?: ConfigSnapshot()
        if (config.deviceAlertConstraint) {
            val result = notificationProcessor.filter(
                info.packageName,
                info.title,
                info.content,
                info.subText,
                config.whitelistKeywords,
                config.enabledPackages,
                config.blacklistKeywords,
                config.appFilterMode,
                sourceType = "device",
            )
            if (!result.allowed) {
                Log.d(
                    TAG,
                    "Device alert filtered (${result.source.name}): ${info.appName}",
                )
                webhookSender.sendBroadcast(info)
                DeliveryNotifier.notify(
                    this,
                    info.id,
                    "FILTER",
                    WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.BIZ_FAIL,
                        0,
                        result.blockReason(),
                        false,
                    ),
                )
                return
            }
        }
        dispatchToChannels(info)
    }

    /**
     * 历史记录"现在推送"：把单条记录按当前配置立即补推（webhook + 邮件）。
     * 绕过推送暂停开关（用户明确点击了"现在推送"）。
     */
    private fun pushRecordNow(data: String) {
        serviceScope.launch {
            try {
                val record = org.json.JSONObject(data)
                val info = NotificationInfo.fromJson(record)
                if (info.title.isEmpty() && info.content.isEmpty()) {
                    Log.w(TAG, "Push record now skipped: empty title/content")
                    return@launch
                }
                dispatchToChannels(info, alsoBroadcastRecord = false, force = true)
                checkDailyReset()
                pushCount++
                updateForegroundNotification()
                Log.d(TAG, "Manual push now: ${info.appName}")
            } catch (e: Exception) {
                Log.e(TAG, "Error pushing record now", e)
            }
        }
    }

    /**
     * 三族扇出的**唯一**入口（T12）。原先这段在三处各写一遍、共 7 个调用点，
     * 任何"发送前先做的判断"（推送开关、主备分流）都只能挑几个点加 —— 一旦漏一处，
     * 表现就是"某条路径的通知不受策略约束"。所以先收口，再在收口处加分流。
     *
     * @param alsoBroadcastRecord 是否把这条通知写进历史记录。通知到达的主链路要写；
     *   延迟补推 / 聚合 flush / 手动「现在推送」的记录在到达时已经写过，再播一次就多一条历史。
     * @param force 忽略「推送暂停」开关（只给手动补推用）。
     * @param onWebhooksComplete webhook 全部通道结束后的汇总回调，第二个参数是**本轮是否
     *   降级走了备用通道**（聚合推送要用真实结果逐成员回写，见 [MergePushManager] 头注释 3，
     *   备用标记同理 —— 成员记录也得知道自己是通过备用通道补发的）。
     */
    private fun dispatchToChannels(
        info: NotificationInfo,
        alsoBroadcastRecord: Boolean = true,
        force: Boolean = false,
        onWebhooksComplete: ((WebhookResponseParser.ParseResult, Boolean) -> Unit)? = null,
    ) {
        val routed = routeChannels()
        // 降级标记必须**逐结果**传给三个发送器，不能只在服务里记一笔：
        // 一次扇出的结果会经广播/持久化队列异步落到不同记录（如聚合成员），
        // 事后已经没有「哪一轮」的上下文可对。
        val webhookCallback = onWebhooksComplete?.let { outer ->
            { r: WebhookResponseParser.ParseResult -> outer(r, routed.viaBackup) }
        }

        if (alsoBroadcastRecord) webhookSender.sendBroadcast(info)
        webhookSender.sendWebhooksOnly(
            info,
            force = force,
            onAllComplete = webhookCallback,
            configs = routed.webhooks,
            viaBackup = routed.viaBackup,
        )
        appChannelSender.sendOnly(
            info,
            force = force,
            configs = routed.apps,
            viaBackup = routed.viaBackup,
        )
        dispatchEmail(
            info,
            force = force,
            configs = routed.emails,
            viaBackup = routed.viaBackup,
        )
    }

    /** 一次扇出对应的三族目标集合（路由后的结果，可能比配置里少） */
    private class RoutedChannels(
        val webhooks: List<ConfigManager.WebhookChannelConfig>,
        val apps: List<AppChannelConfig>,
        val emails: List<EmailSender.EmailConfig>,
        /** 本轮为「降级走备用」：直接取 [ChannelRouting.Decision.engagedBackup]，不自行推断 */
        val viaBackup: Boolean,
    )

    /**
     * 主备路由（T12）：三族候选合成**一次**决策。
     *
     * 分开按族决策会出现「webhook 已经走备用、邮件还在推主通道」的半吊子状态 ——
     * 而「主通道是否全不可用」本来就是设备级判断。
     *
     * 每次现读配置与健康记录（不在进程内缓存）：角色、健康度、锁存都会变，
     * 缓存就得再定一条「谁负责让它失效」的契约，代价大于每次解析几个通道。
     */
    private fun routeChannels(): RoutedChannels {
        val webhooks = configManager.getWebhookChannelConfigs()
        val apps = configManager.getAppChannelConfigs()
        val emails = EmailManager.getEnabledConfigs(this)
        val now = System.currentTimeMillis()

        fun available(family: String, id: String): Boolean = ChannelAvailability.reasonOf(
            fails = ChannelAvailability.failsOf(this, family, id),
            record = ChannelAvailability.readHealth(this, family, id),
            nowMs = now,
        ).isAvailable

        val members = ArrayList<ChannelRouting.Member>()
        webhooks.forEach {
            members.add(ChannelRouting.Member("webhook:" + it.id, it.role, available("webhook", it.id)))
        }
        apps.forEach {
            members.add(ChannelRouting.Member("app:" + it.id, it.role, available("app", it.id)))
        }
        emails.forEach {
            members.add(ChannelRouting.Member("email:" + it.id, it.role, available("email", it.id)))
        }

        val engaged = BackupModeStore.isEngaged(this)
        val decision = ChannelRouting.route(members, engaged)
        // 只在真的发生降级时锁存；已经锁着就不重复写盘
        if (decision.engagedBackup && !engaged) BackupModeStore.engage(this)

        val want = decision.keys.toHashSet()
        return RoutedChannels(
            webhooks.filter { ("webhook:" + it.id) in want },
            apps.filter { ("app:" + it.id) in want },
            emails.filter { ("email:" + it.id) in want },
            viaBackup = decision.engagedBackup,
        )
    }

    private fun dispatchEmail(
        info: NotificationInfo,
        force: Boolean = false,
        configs: List<EmailSender.EmailConfig>? = null,
        viaBackup: Boolean = false,
    ) {
        try {
            // 路由后可能为空（本轮不该推邮件）：与「没配邮件通道」走同一条早退路径。
            // 局部量另起名：与同名参数在嵌套作用域里重名会触发 name-shadowed 警告。
            val selected = configs ?: EmailManager.getEnabledConfigs(this)
            if (selected.isEmpty()) return

            // 推送暂停：邮件同样不发送，回传 paused 状态（与 webhook 行为一致）。
            // paused 分支**不带**备用标记：这条消息根本没投递出去，标"走了备用"只会误导。
            if (!force && !PushToggleManager.isPushActive()) {
                val paused = WebhookResponseParser.ParseResult(
                    WebhookResponseParser.DeliveryStatus.PAUSED,
                    0, "Push paused (skipped)", false
                )
                DeliveryNotifier.notify(this, info.id, "EMAIL", paused)
                return
            }

            EmailSender.sendNotification(selected, info, serviceScope) { success, msg ->
                val result = if (success) {
                    WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.SUCCESS, 0, msg, false
                    )
                } else {
                    WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.BIZ_FAIL, 0, msg, false
                    )
                }
                DeliveryNotifier.notify(this, info.id, "EMAIL", result, viaBackup = viaBackup)
            }
        } catch (e: Exception) {
            Log.e(TAG, "邮件分发异常: ${e.message}", e)
        }
    }
}

data class NotificationInfo(
    val id: String,
    val title: String,
    val content: String,
    val subText: String,
    val packageName: String,
    val appName: String,
    val postTime: Long,
    val time: String,
    val type: String,
    var deviceName: String,
    // 优先级分级：0=低 1=中 2=高（来自系统通知优先级，规则引擎据此评估「通知优先级」条件）
    val priority: Int = 1,
    // F3 聚合深化：聚合推送专用模板变量（普通单条通知恒为 0/""，模板可用 %count% / %titles%）
    val mergeCount: Int = 0,
    val mergeTitles: String = ""
) {
    /** 序列化为 JSON（与 WebhookSender.sendBroadcast 字段保持一致，用于延迟推送队列持久化） */
    fun toJson(): org.json.JSONObject = org.json.JSONObject().apply {
        put("id", id)
        put("title", title)
        put("content", content)
        put("subText", subText)
        put("packageName", packageName)
        put("appName", appName)
        put("postTime", postTime)
        put("time", time)
        put("type", type)
        put("deviceName", deviceName)
        put("priority", priority)
        if (mergeCount > 0) put("mergeCount", mergeCount)
        if (mergeTitles.isNotEmpty()) put("mergeTitles", mergeTitles)
    }

    companion object {
        /** 从 JSON 还原（兼容旧数据缺失 priority 字段） */
        fun fromJson(json: org.json.JSONObject): NotificationInfo = NotificationInfo(
            id = json.optString("id", ""),
            title = json.optString("title", ""),
            content = json.optString("content", ""),
            subText = json.optString("subText", ""),
            packageName = json.optString("packageName", ""),
            appName = json.optString("appName", ""),
            postTime = json.optLong("postTime", 0L),
            time = json.optString("time", ""),
            type = json.optString("type", "other"),
            deviceName = json.optString("deviceName", ""),
            priority = json.optInt("priority", 1),
            mergeCount = json.optInt("mergeCount", 0),
            mergeTitles = json.optString("mergeTitles", "")
        )
    }
}
