package com.fnthink.notice

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
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
        const val ACTION_BATTERY_CHANGED_NOTIFY = "com.fnthink.notice.BATTERY_CHANGED_NOTIFY"
        const val EXTRA_BATTERY_LEVEL = "battery_level"
        const val EXTRA_BATTERY_CHARGING = "battery_charging"

        var webhookUrls: List<String> = emptyList()
        var deviceName: String = ""
        var enabledPackages: Set<String> = emptySet()
        var blacklistKeywords: List<String> = emptyList()
        var whitelistKeywords: List<String> = emptyList()
        var isConnected: Boolean = false
    }

    private lateinit var notificationProcessor: NotificationProcessor
    private lateinit var batteryMonitor: BatteryMonitor
    private lateinit var webhookSender: WebhookSender
    private lateinit var configManager: ConfigManager
    private var batteryChangedReceiver: android.content.BroadcastReceiver? = null

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "Service created")

        notificationProcessor = NotificationProcessor(this)
        batteryMonitor = BatteryMonitor(this)
        webhookSender = WebhookSender(this)
        configManager = ConfigManager(this)

        loadConfig()
        startBatteryMonitoring()
        createNotificationChannel()
        startForegroundService()
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
        if (intent != null && ACTION_UPDATE_CONFIG == intent.action) {
            Log.d(TAG, "Config update received")
            loadConfig()
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
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        super.onNotificationPosted(sbn)
        Log.d(TAG, "Notification posted: ${sbn.packageName}")

        val notificationInfo = notificationProcessor.processNotification(sbn)
        if (notificationInfo != null) {
            val config = ConfigSnapshot()
            if (notificationProcessor.shouldNotify(
                    notificationInfo.packageName,
                    notificationInfo.title,
                    notificationInfo.content,
                    notificationInfo.subText,
                    config.whitelistKeywords,
                    config.enabledPackages,
                    config.blacklistKeywords
                )
            ) {
                notificationInfo.deviceName = config.deviceName
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

        enabledPackages = configManager.getEnabledPackages()
        blacklistKeywords = configManager.getBlacklistKeywords()
        whitelistKeywords = configManager.getWhitelistKeywords()

        batteryMonitor.updateRules(configManager.getBatteryRules())

        Log.d(TAG, "Config loaded: ${loadedUrls.size} webhooks, ${enabledPackages.size} enabled packages")
    }

    private fun startBatteryMonitoring() {
        val filter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        batteryChangedReceiver = object : android.content.BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
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
            }
        }
        registerReceiver(batteryChangedReceiver, filter)
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

        startForeground(FOREGROUND_ID, notification)
        Log.i(TAG, "Foreground service started")
    }

    private inner class ConfigSnapshot {
        val whitelistKeywords = configManager.getWhitelistKeywords()
        val enabledPackages = configManager.getEnabledPackages()
        val blacklistKeywords = configManager.getBlacklistKeywords()
        val deviceName = configManager.getDeviceName()
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