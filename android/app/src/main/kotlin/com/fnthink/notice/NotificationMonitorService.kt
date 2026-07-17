package com.fnthink.notice

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.pm.ServiceInfo
import android.content.Intent
import android.content.IntentFilter
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

        @Volatile var webhookUrls: List<String> = emptyList()
        @Volatile var deviceName: String = ""
        @Volatile var isConnected: Boolean = false
        @Volatile var monitoringEnabled: Boolean = true
    }

    private lateinit var notificationProcessor: NotificationProcessor
    private lateinit var batteryMonitor: BatteryMonitor
    private lateinit var webhookSender: WebhookSender
    private lateinit var configManager: ConfigManager
    private var batteryChangedReceiver: android.content.BroadcastReceiver? = null
    private var batteryAlarmPendingIntent: PendingIntent? = null
    private var cachedConfig: ConfigSnapshot? = null

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "Service created")

        monitoringEnabled = readMonitoringEnabled()

        createNotificationChannel()
        // 先进入前台，满足 startForegroundService 的 5s 内必须 startForeground 的约束
        startForegroundService()

        notificationProcessor = NotificationProcessor(this)
        batteryMonitor = BatteryMonitor(this)
        webhookSender = WebhookSender(this)
        webhookSender.activate()
        configManager = ConfigManager(this)

        batteryMonitor.setNotificationCallback { batteryInfo ->
            webhookSender.sendNotification(batteryInfo)
            Log.d(TAG, "Battery notification via polling sent: ${batteryInfo.title}")
        }

        loadConfig()
        applyMonitoringState()
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        isConnected = true
        Log.i(TAG, "Notification listener connected")
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        isConnected = false
        Log.i(TAG, "Notification listener disconnected")
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
        batteryMonitor.stopPolling()
        cancelBatteryAlarm()
        webhookSender.destroy()
        Log.i(TAG, "Service destroyed")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        super.onNotificationPosted(sbn)
        if (!monitoringEnabled) return
        Log.d(TAG, "Notification posted: ${sbn.packageName}")

        val notificationInfo = notificationProcessor.processNotification(sbn)
        if (notificationInfo != null) {
            val config = cachedConfig ?: ConfigSnapshot()
            notificationInfo.deviceName = config.deviceName

            if (notificationProcessor.shouldNotify(
                    notificationInfo.packageName,
                    notificationInfo.title,
                    notificationInfo.content,
                    notificationInfo.subText,
                    config.whitelistKeywords,
                    config.enabledPackages,
                    config.blacklistKeywords,
                    config.appFilterMode
                )
            ) {
                webhookSender.sendNotification(notificationInfo)
                Log.d(TAG, "Notification sent: ${notificationInfo.appName} - ${notificationInfo.title}")
            }
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        super.onNotificationRemoved(sbn)
        notificationProcessor.removeNotification(sbn)
        Log.d(TAG, "Notification removed: ${sbn.packageName}")
    }

    private fun loadConfig() {
        val hotfixConfig = configManager.loadHotfixConfig()
        notificationProcessor.setHotfixConfig(hotfixConfig.appNames, hotfixConfig.notificationTypes)
        val loadedDeviceName = configManager.getDeviceName()
        deviceName = loadedDeviceName
        batteryMonitor.setDeviceName(loadedDeviceName)
        webhookSender.setDeviceName(loadedDeviceName)

        val loadedUrls = configManager.getWebhookUrls()
        webhookUrls = loadedUrls
        webhookSender.updateUrls(loadedUrls)

        batteryMonitor.setEnabled(configManager.getBatteryNotifyEnabled())
        batteryMonitor.updateRules(configManager.getBatteryRules())

        cachedConfig = ConfigSnapshot()

        Log.d(TAG, "Config loaded: ${loadedUrls.size} webhooks")
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
            registerReceiver(batteryChangedReceiver, filter)
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
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("通知传输器")
            .setContentText("正在监听通知")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(FOREGROUND_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(FOREGROUND_ID, notification)
        }
        Log.i(TAG, "Foreground service started")
    }

    private inner class ConfigSnapshot {
        val whitelistKeywords = configManager.getWhitelistKeywords()
        val enabledPackages = configManager.getEnabledPackages()
        val blacklistKeywords = configManager.getBlacklistKeywords()
        val deviceName = configManager.getDeviceName()
        val appFilterMode = configManager.getAppFilterMode()
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
    var deviceName: String
)