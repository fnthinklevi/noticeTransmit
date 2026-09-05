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
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.IBinder
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
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
    private lateinit var configManager: ConfigManager
    private lateinit var delayedPushManager: DelayedPushManager
    private var batteryChangedReceiver: android.content.BroadcastReceiver? = null
    private var delayedPushReceiver: android.content.BroadcastReceiver? = null
    private var batteryAlarmPendingIntent: PendingIntent? = null
    @Volatile private var cachedConfig: ConfigSnapshot? = null
    private val notificationManager by lazy { getSystemService(NotificationManager::class.java) }
    private val serviceScope = CoroutineScope(
        Dispatchers.IO + SupervisorJob() + CoroutineExceptionHandler { _, e ->
            // E2：未捕获协程异常兜底记录，避免静默吞没
            Log.e(TAG, "Unhandled coroutine exception", e)
        }
    )

    /// 检查是否已跨日，是则重置计数器（委托给 @Synchronized 封装，消除竞态）
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

        createNotificationChannel()
        // 先进入前台，满足 startForegroundService 的 5s 内必须 startForeground 的约束
        startForegroundService()

        notificationProcessor = NotificationProcessor(this)
        batteryMonitor = BatteryMonitor(this)
        webhookSender = WebhookSender(this)
        webhookSender.activate()
        configManager = ConfigManager(this)
        delayedPushManager = DelayedPushManager(this)
        registerDelayedPushReceiver()

            batteryMonitor.setNotificationCallback { batteryInfo ->
                webhookSender.sendNotification(batteryInfo)
                dispatchEmail(batteryInfo)
                Log.d(TAG, "Battery notification via polling sent: ${batteryInfo.title}")
        }

        loadConfig()
        applyMonitoringState()
        registerSmsObserver()
    }

    // —— 短信库兜底监听：SMS_RECEIVED 广播丢失时，改从短信库捕获并补推 ——
    private var smsObserver: SmsObserver? = null

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
        cancelRebindRetry()
        // 恢复连接后立即刷新前台通知，撤掉"监听已断开"警告
        try { updateForegroundNotification() } catch (_: Exception) {}
        Log.i(TAG, "Notification listener connected")
        recoverMissedNotifications()
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        isConnected = false
        listenerConnected = false
        disconnectedAt = System.currentTimeMillis()
        // 监听断开后 onNotificationPosted 不再回调，通知会静默漏读。
        // 刷新前台通知给出明确警告，并主动重新请求绑定自恢复。
        try { updateForegroundNotification() } catch (_: Exception) {}
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
        try {
            val active = activeNotifications ?: return
            val missed = active.filter { it.postTime >= since }
            if (missed.isEmpty()) return
            Log.i(TAG, "Recovering ${missed.size} notification(s) posted while disconnected")
            for (sbn in missed) {
                dispatchPosted(sbn)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to recover missed notifications", e)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent != null) {
            when (intent.action) {
                ACTION_UPDATE_CONFIG -> {
                    Log.d(TAG, "Config update received")
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
        delayedPushReceiver = null
        batteryMonitor.stopPolling()
        cancelRebindRetry()
        mainHandler.removeCallbacksAndMessages(null)
        cancelBatteryAlarm()
        webhookSender.destroy()
        unregisterSmsObserver()
        serviceScope.cancel()
        Log.i(TAG, "Service destroyed")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        super.onNotificationPosted(sbn)
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
                        Log.d(TAG, "Notification filtered out (${filterResult.source.name}): ${rawInfo.appName} - ${rawInfo.title} reason=${filterResult.blockReason()}")
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
                                Log.d(TAG, "Notification blocked by rule: ${info.appName} - ${info.title}")
                            }
                            RuleEngine.Decision.Record -> {
                                webhookSender.sendBroadcast(info)
                                Log.d(TAG, "Notification recorded only: ${info.appName} - ${info.title}")
                            }
                            is RuleEngine.Decision.Delay -> {
                                // 立即写入历史（pending 状态），到点后补推 webhook
                                webhookSender.sendBroadcast(info)
                                delayedPushManager.enqueue(info, decision.fireAt)
                                Log.d(TAG, "Notification delayed push at ${decision.fireAt}: ${info.appName} - ${info.title}")
                            }
                            RuleEngine.Decision.Push -> {
                                webhookSender.sendNotification(info)
                                dispatchEmail(info)
                                checkDailyReset()
                                pushCount++
                                updateForegroundNotification()
                                Log.d(TAG, "Notification sent: ${info.appName} - ${info.title}")
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error processing notification", e)
            }
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        super.onNotificationRemoved(sbn)
        notificationProcessor.removeNotification(sbn)
        Log.d(TAG, "Notification removed: ${sbn.packageName}")
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

        batteryMonitor.setEnabled(configManager.getBatteryNotifyEnabled())
        batteryMonitor.updateRules(configManager.getBatteryRules())

        cachedConfig = ConfigSnapshot()
        // 服务重启后恢复未到期的延迟推送闹钟（进程被杀 → START_STICKY 重建场景）
        delayedPushManager.rescheduleAll()

        Log.d(TAG, "Config loaded: ${loadedConfigs.size} webhook channels (signed)")
    }

    private fun readMonitoringEnabled(): Boolean {
        return try {
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
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
                            webhookSender.sendWebhooksOnly(info)
                            dispatchEmail(info)
                            checkDailyReset()
                            pushCount++
                            updateForegroundNotification()
                            Log.d(TAG, "Delayed notification sent: ${info.appName} - ${info.title}")
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
                        webhookSender.sendNotification(batteryInfo)
                        dispatchEmail(batteryInfo)
                        Log.d(TAG, "Battery notification sent: ${batteryInfo.title}")
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
    }

    /// 更新前台通知显示当前已推送数量与推送启停状态
    private fun updateForegroundNotification() {
        val notification = buildForegroundNotification()
        notificationManager.notify(FOREGROUND_ID, notification)
    }

    /**
     * 构建前台通知（含推送启停 Action 按钮，文案随 push 状态切换）。
     * - 推送激活：显示「暂停推送」按钮 + 「正在监听通知…」
     * - 推送暂停：显示「恢复推送」按钮 + 「推送已暂停…」
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
                webhookSender.sendWebhooksOnly(info, force = true)
                dispatchEmail(info, force = true)
                checkDailyReset()
                pushCount++
                updateForegroundNotification()
                Log.d(TAG, "Manual push now: ${info.appName} - ${info.title}")
            } catch (e: Exception) {
                Log.e(TAG, "Error pushing record now", e)
            }
        }
    }

    private fun dispatchEmail(info: NotificationInfo, force: Boolean = false) {
        try {
            val configs = EmailManager.getEnabledConfigs(this)
            if (configs.isEmpty()) return

            // 推送暂停：邮件同样不发送，回传 paused 状态（与 webhook 行为一致）
            if (!force && !PushToggleManager.isPushActive()) {
                val paused = WebhookResponseParser.ParseResult(
                    WebhookResponseParser.DeliveryStatus.PAUSED,
                    0, "Push paused (skipped)", false
                )
                DeliveryNotifier.notify(this, info.id, "EMAIL", paused)
                return
            }

            EmailSender.sendNotification(configs, info, serviceScope) { success, msg ->
                val result = if (success) {
                    WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.SUCCESS, 0, msg, false
                    )
                } else {
                    WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.BIZ_FAIL, 0, msg, false
                    )
                }
                DeliveryNotifier.notify(this, info.id, "EMAIL", result)
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
    val priority: Int = 1
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
            priority = json.optInt("priority", 1)
        )
    }
}