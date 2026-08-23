package com.fnthink.notice

import android.app.ActivityManager
import android.app.AlarmManager
import android.app.DownloadManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.tencent.bugly.crashreport.CrashReport
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {

    companion object {
        const val ACTION_NOTIFICATION_RECEIVED = "com.fnthink.notice.NOTIFICATION_RECEIVED"
        const val EXTRA_NOTIFICATION_DATA = "notification_data"
        // webhook 送达结果广播：WebhookSender 发送后异步回传，Flutter 用于逐条记录显示送达状态
        const val ACTION_DELIVERY_RESULT = "com.fnthink.notice.DELIVERY_RESULT"
        private const val REQUEST_SMS_PERMISSION = 1001
        private const val REQUEST_PHONE_PERMISSION = 1002
        private const val REQUEST_POST_NOTIFICATION_PERMISSION = 1003

        // 回退版本号：getAppVersion 原生获取失败时使用。
        // 发版时须与 lib/update_manager.dart 中的 _fallbackVersion / _fallbackBuild 同步更新。
        const val FALLBACK_VERSION = "1.5.60"
        const val FALLBACK_BUILD = 95
    }

    private val channel = "com.fnthink.notice/notification"
    private var methodChannel: MethodChannel? = null
    private val activityJob = SupervisorJob()
    private val activityScope = CoroutineScope(activityJob + Dispatchers.Main)
    private val prefs: SharedPreferences by lazy {
        getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
    }

    private val okHttpClient: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .writeTimeout(10, TimeUnit.SECONDS)
            .readTimeout(10, TimeUnit.SECONDS)
            .retryOnConnectionFailure(false)
            // SSL 证书固定：防止中间人攻击。取消注释并填入证书 SHA256 base64 哈希即可启用。
            // .certificatePinner(
            //     CertificatePinner.Builder()
            //         .add("notice.fnthink.top", CERT_PINS)
            //         .build()
            // )
            .build()
    }

    private val notificationReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == ACTION_NOTIFICATION_RECEIVED) {
                val data = intent.getStringExtra(EXTRA_NOTIFICATION_DATA)
                if (data != null) {
                    try {
                        val json = JSONObject(data)
                        val map = json.toMap()
                        if (methodChannel != null) {
                            methodChannel?.invokeMethod("onNotificationReceived", map)
                            // Flutter 已接收，从离线缓存移除（避免 Flutter 重启后重复入库）
                            val id = json.optString("id", "")
                            if (id.isNotEmpty()) {
                                HistoryCache.remove(applicationContext, id)
                            }
                        } else {
                            // Flutter 引擎未就绪 → 缓存到 SP 待批量导入
                            cacheNotificationRecord(data)
                        }
                    } catch (e: Exception) {
                        // invokeMethod 异常时也缓存
                        try { cacheNotificationRecord(data) } catch (_: Exception) {}
                    }
                }
            }
        }
    }

    private val deliveryReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == ACTION_DELIVERY_RESULT) {
                val notificationId = intent.getStringExtra("notification_id") ?: return
                val data = mapOf(
                    "notificationId" to notificationId,
                    "webhookType" to (intent.getStringExtra("webhook_type") ?: ""),
                    "status" to (intent.getStringExtra("status") ?: ""),
                    "message" to (intent.getStringExtra("message") ?: ""),
                    "httpCode" to (intent.getIntExtra("http_code", 0)),
                )
                try {
                    methodChannel?.invokeMethod("onDeliveryResult", data)
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        }
    }

    private val batteryReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == NotificationMonitorService.ACTION_BATTERY_CHANGED_NOTIFY) {
                val level = intent.getIntExtra(NotificationMonitorService.EXTRA_BATTERY_LEVEL, -1)
                val isCharging = intent.getBooleanExtra(NotificationMonitorService.EXTRA_BATTERY_CHARGING, false)
                try {
                    methodChannel?.invokeMethod(
                        "onBatteryChanged",
                        mapOf(
                            "level" to level,
                            "isCharging" to isCharging
                        )
                    )
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        }
    }

    private fun JSONObject.toMap(): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>()
        val keys = keys()
        while (keys.hasNext()) {
            val key = keys.next()
            map[key] = get(key)
        }
        return map
    }

    override fun onResume() {
        super.onResume()
        // receiver 已在 onCreate() 注册，这里仅回放缓存
        flushCachedNotificationRecords()
    }

    override fun onPause() {
        super.onPause()
        try {
            unregisterReceiver(batteryReceiver)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        CrashReport.initCrashReport(applicationContext)
        // 修复历史版本可能禁用了监听组件的情况，确保组件启用以便系统能重新绑定通知监听器
        try {
            toggleNotificationListenerService()
        } catch (e: Exception) {
            e.printStackTrace()
        }
        // 注册 receiver 在全生命周期（onCreate→onDestroy），避免锁屏 onPause 后丢失通知广播
        val filter = IntentFilter(ACTION_NOTIFICATION_RECEIVED)
        registerReceiver(notificationReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        val deliveryFilter = IntentFilter(ACTION_DELIVERY_RESULT)
        registerReceiver(deliveryReceiver, deliveryFilter, Context.RECEIVER_NOT_EXPORTED)
        val batteryFilter = IntentFilter(NotificationMonitorService.ACTION_BATTERY_CHANGED_NOTIFY)
        registerReceiver(batteryReceiver, batteryFilter, Context.RECEIVER_NOT_EXPORTED)
    }

    override fun onDestroy() {
        try { unregisterReceiver(notificationReceiver) } catch (_: Exception) {}
        try { unregisterReceiver(deliveryReceiver) } catch (_: Exception) {}
        try { unregisterReceiver(batteryReceiver) } catch (_: Exception) {}
        activityJob.cancel()
        super.onDestroy()
    }

    /**
     * 根据当前语言偏好更新桌面应用名（最近任务）：
     * 中文 → 通知推送助手 | English → NoticeTransmit
     */
    private fun updateAppLabel() {
        val locale = prefs.getString("flutter.locale", "zh") ?: "zh"
        val label = if (locale == "en") "NoticeTransmit" else "通知推送助手"
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                setTaskDescription(ActivityManager.TaskDescription(label))
            }
        } catch (_: Exception) {}
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 冷启动时更新桌面应用名为当前语言
        updateAppLabel()
        // 校正桌面图标别名（zh/en），避免历史残留的英文别名导致最近任务页显示旧名称
        switchLocaleAlias()

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "setLocaleLabel" -> {
                    val locale = call.arguments as? String ?: "zh"
                    prefs.edit().putString("flutter.locale", locale).apply()
                    // 同步给 Webhook 推送国际化模块
                    I18n.setLocale(locale)
                    switchLocaleAlias()
                    updateAppLabel()
                    result.success(true)
                }
                "isNotificationPermissionGranted" -> {
                    result.success(isNotificationListenerPermissionGranted())
                }
                "isPostNotificationPermissionGranted" -> {
                    result.success(isPostNotificationPermissionGranted())
                }
                "requestNotificationListenerPermission" -> {
                    requestNotificationListenerPermission()
                    result.success(true)
                }
                "requestPostNotificationPermission" -> {
                    requestPostNotificationPermission()
                    result.success(true)
                }
                "isSmsPermissionGranted" -> {
                    result.success(isSmsPermissionGranted())
                }
                "isPhonePermissionGranted" -> {
                    result.success(isPhonePermissionGranted())
                }
                "isAppListPermissionGranted" -> {
                    result.success(isAppListPermissionGranted())
                }
                "requestXiaomiAutoStart" -> {
                    requestXiaomiAutoStart()
                    result.success(true)
                }
                "requestMeizuBackground" -> {
                    requestMeizuBackground()
                    result.success(true)
                }
                "requestHuaweiLaunch" -> {
                    requestHuaweiLaunch()
                    result.success(true)
                }
                "requestOppoBackground" -> {
                    requestOppoBackground()
                    result.success(true)
                }
                "requestVivoBackground" -> {
                    requestVivoBackground()
                    result.success(true)
                }
                "setWebhookUrls" -> {
                    val urls = call.argument<List<String>>("urls") ?: emptyList()
                    val validUrls = urls.filter { it.isNotEmpty() }
                    PrefsHelper.webhookUrls = validUrls
                    saveWebhookUrls(validUrls)
                    NotificationMonitorService.webhookUrls = validUrls
                    notifyServiceConfigChanged()
                    result.success(true)
                }
                "getWebhookChannels" -> {
                    result.success(getWebhookChannels())
                }
                "setWebhookChannels" -> {
                    val channels = call.argument<List<Map<String, Any?>>>("channels") ?: emptyList()
                    setWebhookChannels(channels)
                    result.success(true)
                }
                "getEmailChannels" -> {
                    result.success(EmailManager.loadChannelsAsMap(this@MainActivity))
                }
                "setEmailChannels" -> {
                    val channels = call.argument<List<Map<String, Any?>>>("channels") ?: emptyList()
                    EmailManager.saveChannels(this@MainActivity, channels)
                    result.success(true)
                }
                "testEmail" -> {
                    val configMap = call.arguments as? Map<String, Any?> ?: emptyMap()
                    testEmail(configMap, result)
                }
                "getDeviceName" -> {
                    var savedName = readDeviceNameFromFile()
                    if (savedName.isEmpty()) {
                        savedName = prefs.getString("flutter.device_name", "") ?: ""
                        if (savedName.isNotEmpty()) {
                            saveDeviceName(savedName)
                        }
                    }
                    if (savedName.isEmpty()) {
                        savedName = "${android.os.Build.BRAND} ${android.os.Build.MODEL}"
                        saveDeviceName(savedName)
                        PrefsHelper.deviceName = savedName
                        NotificationMonitorService.deviceName = savedName
                    }
                    result.success(savedName)
                }
                "setDeviceName" -> {
                    val name = call.argument<String>("name") ?: ""
                    PrefsHelper.deviceName = name
                    saveDeviceName(name)
                    NotificationMonitorService.deviceName = name
                    notifyServiceConfigChanged()
                    result.success(true)
                }
                "isServiceRunning" -> {
                    result.success(isMonitoringEnabled())
                }
                "isExactAlarmEnabled" -> {
                    result.success(
                        prefs.getBoolean("flutter.exact_alarm_enabled", false)
                    )
                }
                "setExactAlarmEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    prefs.edit().putBoolean("flutter.exact_alarm_enabled", enabled).apply()
                    // 通知服务重新加载配置并重排延迟推送闹钟（切换精确/非精确模式）
                    notifyServiceConfigChanged()
                    result.success(true)
                }
                "canScheduleExactAlarms" -> {
                    result.success(canScheduleExactAlarms())
                }
                "requestExactAlarmPermission" -> {
                    requestExactAlarmPermission()
                    result.success(true)
                }
                "requestBatteryOptimization" -> {
                    requestBatteryOptimization()
                    result.success(true)
                }
                "isIgnoringBatteryOptimizations" -> {
                    result.success(isIgnoringBatteryOptimizations())
                }
                "getDeviceModel" -> {
                    result.success(Build.MODEL)
                }
                "getManufacturer" -> {
                    result.success(Build.MANUFACTURER)
                }
                "getDownloadDirectory" -> {
                    result.success(getDownloadDirectory())
                }
                "saveFile" -> {
                    val fileName = call.argument<String>("fileName") ?: "export.json"
                    val content = call.argument<String>("content") ?: ""
                    saveFileWithPicker(fileName, content, result)
                }
                "getSupportedAbis" -> {
                    result.success(Build.SUPPORTED_ABIS.toList())
                }
                "getAppVersion" -> {
                    try {
                        val info = packageManager.getPackageInfo(packageName, 0)
                        val versionName = info.versionName ?: FALLBACK_VERSION
                        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            info.longVersionCode.toInt()
                        } else {
                            info.versionCode
                        }
                        result.success(mapOf("versionName" to versionName, "versionCode" to versionCode))
                    } catch (e: Exception) {
                        e.printStackTrace()
                        result.success(mapOf("versionName" to FALLBACK_VERSION, "versionCode" to FALLBACK_BUILD))
                    }
                }
                "startNotificationListener" -> {
                    startNotificationListener()
                    result.success(true)
                }
                "stopNotificationListener" -> {
                    stopNotificationListener()
                    result.success(true)
                }
                "testWebhook" -> {
                    val url = call.argument<String>("url") ?: ""
                    val secret = call.argument<String>("secret")
                    testWebhook(url, secret, result)
                }
                "clearNotificationRecords" -> {
                    clearNotificationRecords()
                    result.success(true)
                }
                "syncDailyPushCount" -> {
                    // 统一状态栏与 DB 统计：Flutter 启动/恢复时把当日记录数同步为原生计数基数
                    val count = call.argument<Int>("count") ?: 0
                    val date = call.argument<String>("date") ?: ""
                    val today = NotificationMonitorService.todayDateString()
                    if (date == today) {
                        // 同一天：取较大值（避免覆盖服务运行期间已累加的计数）
                        NotificationMonitorService.pushCount =
                            maxOf(NotificationMonitorService.pushCount, count)
                    } else {
                        NotificationMonitorService.pushCount = count
                        NotificationMonitorService.applyTodayDate(date)
                    }
                    result.success(true)
                }
                "drainOfflineCache" -> {
                    // Flutter 启动时拉取离线期间缓存的通知（避免软件被杀后历史丢失）
                    result.success(HistoryCache.drainAll(applicationContext))
                }
                "drainDeliveryResults" -> {
                    // Flutter 启动 / resume 时补偿拉取 Activity 销毁期间丢失的送达结果
                    // （广播无人接收时由 DeliveryResultStore 持久化兜底）
                    result.success(DeliveryResultStore.drain(applicationContext))
                }
                "getBatteryStatus" -> {
                    result.success(getBatteryStatus())
                }
                "setBatterySetting" -> {
                    val key = call.argument<String>("key") ?: ""
                    val value = call.argument<Boolean>("value") ?: false
                    setBatterySetting(key, value)
                    result.success(true)
                }
                "setBatteryRules" -> {
                    val rules = call.argument<List<Map<String, Any>>>("rules") ?: emptyList()
                    setBatteryRules(rules)
                    result.success(true)
                }
                "getInstalledApps" -> {
                    val apps = getInstalledApps()
                    saveInstalledAppsCache(apps)
                    result.success(apps)
                }
                "getCachedInstalledApps" -> {
                    result.success(getCachedInstalledApps())
                }
                "saveInstalledAppsCache" -> {
                    val apps = call.argument<List<Map<String, Any?>>>("apps") ?: emptyList()
                    saveInstalledAppsCache(apps)
                    result.success(true)
                }
                "canQueryAllPackages" -> {
                    result.success(canQueryAllPackages())
                }
                "requestQueryAllPackagesPermission" -> {
                    requestQueryAllPackagesPermission()
                    result.success(true)
                }
                "setEnabledPackages" -> {
                    val packages = call.argument<List<String>>("packages") ?: emptyList()
                    setEnabledPackages(packages)
                    result.success(true)
                }
                "getEnabledPackages" -> {
                    result.success(getEnabledPackages())
                }
                "setAppFilter" -> {
                    val packages = call.argument<List<String>>("packages") ?: emptyList()
                    val mode = call.argument<String>("mode") ?: "allow"
                    setAppFilter(packages, mode)
                    result.success(true)
                }
                "getAppFilterMode" -> {
                    result.success(getAppFilterMode())
                }
                "setBlacklistKeywords" -> {
                    val keywords = call.argument<List<String>>("keywords") ?: emptyList()
                    setBlacklistKeywords(keywords)
                    result.success(true)
                }
                "getBlacklistKeywords" -> {
                    result.success(getBlacklistKeywords())
                }
                "setWhitelistKeywords" -> {
                    val keywords = call.argument<List<String>>("keywords") ?: emptyList()
                    setWhitelistKeywords(keywords)
                    result.success(true)
                }
                "getWhitelistKeywords" -> {
                    result.success(getWhitelistKeywords())
                }
                "setNotificationRules" -> {
                    // 保存通知规则（优先级分级 / 延迟推送等由原生 RuleEngine 执行），并通知服务热更新配置
                    val rules = call.argument<List<Map<String, Any?>>>("rules") ?: emptyList()
                    setNotificationRules(rules)
                    result.success(true)
                }
                "pushRecordNow" -> {
                    // 历史记录"现在推送"：把记录转发给服务手动补推（忽略推送暂停开关）
                    val record = call.argument<Map<String, Any?>>("record") ?: emptyMap()
                    pushRecordNow(record)
                    result.success(true)
                }
                "openAppDetailsSettings" -> {
                    openAppDetailsSettings()
                    result.success(true)
                }
                "requestSmsPermission" -> {
                    requestSmsPermission()
                    result.success(true)
                }
                "requestPhonePermission" -> {
                    requestPhonePermission()
                    result.success(true)
                }
                "getAppNameByPackage" -> {
                    val packageName = call.argument<String>("packageName") ?: ""
                    result.success(getAppNameByPackage(packageName))
                }
                "changeLauncherIcon" -> {
                    val icon = call.argument<String>("icon") ?: "default"
                    changeLauncherIcon(icon)
                    result.success(true)
                }
                "getLauncherIcon" -> {
                    result.success(getLauncherIcon())
                }
                "requestPinWidget" -> {
                    // 一键添加桌面小部件（Android 8.0+ 系统弹窗确认；不支持时降级手动添加）
                    val wide = call.argument<Boolean>("wide") ?: false
                    val ok = requestPinWidget(wide)
                    result.success(ok)
                }
                "startSystemDownload" -> {
                    // 使用系统下载器（DownloadManager）下载更新 APK，无需存储权限
                    val url = call.argument<String>("url") ?: ""
                    val fileName = call.argument<String>("fileName") ?: "app_update.apk"
                    val title = call.argument<String>("title") ?: "通知推送助手"
                    result.success(startSystemDownload(url, fileName, title))
                }
                "getSystemDownloadProgress" -> {
                    val id = call.argument<String>("downloadId")?.toLongOrNull() ?: -1L
                    result.success(querySystemDownloadProgress(id))
                }
                "getDownloadedApkPath" -> {
                    val id = call.argument<String>("downloadId")?.toLongOrNull() ?: -1L
                    result.success(getDownloadedApkPath(id))
                }
                "installSystemDownload" -> {
                    val id = call.argument<String>("downloadId")?.toLongOrNull() ?: -1L
                    result.success(installSystemDownload(id))
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            REQUEST_SMS_PERMISSION -> {
                val granted = grantResults.isNotEmpty() &&
                        grantResults[0] == PackageManager.PERMISSION_GRANTED
                methodChannel?.invokeMethod(
                    "onSmsPermissionResult",
                    mapOf("granted" to granted)
                )
            }
            REQUEST_PHONE_PERMISSION -> {
                val granted = grantResults.isNotEmpty() &&
                        grantResults[0] == PackageManager.PERMISSION_GRANTED
                if (granted) {
                    // 授权后立即使 SIM 缓存失效，避免最长 60 秒内 SIM 识别仍为空
                    SimInfoHelper.invalidateCache()
                }
                methodChannel?.invokeMethod(
                    "onPhonePermissionResult",
                    mapOf("granted" to granted)
                )
            }
        }
    }

    private fun saveWebhookUrls(urls: List<String>) {
        val jsonArray = org.json.JSONArray(urls)
        prefs.edit().putString("flutter.webhook_urls", jsonArray.toString()).apply()
    }

    private fun getWebhookChannels(): List<Map<String, Any?>> {
        val channelsJson = prefs.getString("flutter.webhook_channels", null)
        val result = mutableListOf<Map<String, Any?>>()

        if (!channelsJson.isNullOrEmpty()) {
            try {
                val jsonArray = org.json.JSONArray(channelsJson)
                for (i in 0 until jsonArray.length()) {
                    val obj = jsonArray.getJSONObject(i)
                    val map = mutableMapOf<String, Any?>()
                    val keys = obj.keys()
                    while (keys.hasNext()) {
                        val key = keys.next()
                        map[key] = obj.get(key)
                    }
                    result.add(map)
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        if (result.isEmpty()) {
            val urlsJson = prefs.getString("flutter.webhook_urls", null)
            if (!urlsJson.isNullOrEmpty()) {
                try {
                    val jsonArray = org.json.JSONArray(urlsJson)
                    for (i in 0 until jsonArray.length()) {
                        val url = jsonArray.getString(i)
                        if (url.isNotEmpty()) {
                            result.add(mapOf("url" to url, "enabled" to true))
                        }
                    }
                } catch (_: Exception) {}
            }
        }

        if (result.isEmpty()) {
            val singleUrl = prefs.getString("flutter.webhook_url", "") ?: ""
            if (singleUrl.isNotEmpty()) {
                result.add(mapOf("url" to singleUrl, "enabled" to true))
            }
        }

        return result
    }

    private fun setWebhookChannels(channels: List<Map<String, Any?>>) {
        val jsonArray = org.json.JSONArray()
        val enabledUrls = mutableListOf<String>()
        for (channel in channels) {
            // 注意：JSONObject(Map) 会把 null 值序列化为字符串 "null"，
            // 导致原生端把未设置的 secret / message_template 误读为非空值（签名错误、模板异常）。
            // 因此显式过滤 null 字段后再序列化。
            val obj = org.json.JSONObject()
            for ((k, v) in channel) {
                if (v != null) obj.put(k, v)
            }
            jsonArray.put(obj)
            val url = channel["url"]?.toString() ?: ""
            val enabled = channel["enabled"] as? Boolean ?: true
            if (enabled && url.isNotEmpty()) {
                enabledUrls.add(url)
            }
        }

        // 完整通道配置（含 secret / message_template）→ 加密存储（C2）。
        // 与 flutter_secure_storage 同文件同密钥，Flutter 端亦可读取。
        try {
            SecurePrefs.get(this).edit()
                .putString("secure_webhook_channels", jsonArray.toString())
                .apply()
        } catch (e: Exception) {
            Log.e("MainActivity", "写入加密 webhook 通道失败", e)
        }

        // 明文副本仅存脱敏数据（剔除 secret），供 URL 同步与低版本原生端兜底，
        // 不再让 Webhook 签名密钥以明文 XML 持久化。
        val sanitized = org.json.JSONArray()
        for (i in 0 until jsonArray.length()) {
            val obj = jsonArray.getJSONObject(i)
            if (obj.has("secret")) obj.remove("secret")
            sanitized.put(obj)
        }
        prefs.edit()
            .putString("flutter.webhook_channels", sanitized.toString())
            .putString("flutter.webhook_urls", org.json.JSONArray(enabledUrls).toString())
            .commit()
        PrefsHelper.webhookUrls = enabledUrls
        NotificationMonitorService.webhookUrls = enabledUrls
        notifyServiceConfigChanged()
    }

    private fun saveDeviceName(name: String) {
        prefs.edit().putString("flutter.device_name", name).apply()
        try {
            val file = java.io.File(filesDir, "device_name.txt")
            file.writeText(name)
        } catch (_: Exception) {}
    }

    private fun readDeviceNameFromFile(): String {
        return try {
            val file = java.io.File(filesDir, "device_name.txt")
            if (file.exists()) file.readText().trim() else ""
        } catch (_: Exception) {
            ""
        }
    }

    private fun getInstalledApps(): List<Map<String, Any?>> {
        val pm = packageManager
        val apps = pm.getInstalledApplications(0)
        val result = mutableListOf<Map<String, Any?>>()
        for (appInfo in apps) {
            try {
                val appName = pm.getApplicationLabel(appInfo).toString()
                val packageName = appInfo.packageName
                val isSystemApp = (appInfo.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0
                result.add(
                    mapOf(
                        "packageName" to packageName,
                        "appName" to appName,
                        "isSystemApp" to isSystemApp
                    )
                )
            } catch (_: Exception) {
            }
        }
        result.sortBy { it["appName"].toString().lowercase() }
        return result
    }

    private fun saveInstalledAppsCache(apps: List<Map<String, Any?>>) {
        try {
            val jsonArray = org.json.JSONArray()
            for (app in apps) {
                val obj = JSONObject(app)
                jsonArray.put(obj)
            }
            prefs.edit()
                .putString("flutter.installed_apps_cache", jsonArray.toString())
                .putLong("flutter.installed_apps_cache_time", System.currentTimeMillis())
                .apply()
        } catch (e: Exception) {
            Log.e("MainActivity", "保存应用列表缓存失败", e)
        }
    }

    private fun getCachedInstalledApps(): List<Map<String, Any?>> {
        val json = prefs.getString("flutter.installed_apps_cache", null) ?: return emptyList()
        val list = mutableListOf<Map<String, Any?>>()
        try {
            val jsonArray = org.json.JSONArray(json)
            for (i in 0 until jsonArray.length()) {
                val obj = jsonArray.getJSONObject(i)
                val map = mutableMapOf<String, Any?>()
                val keys = obj.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    map[key] = obj.get(key)
                }
                list.add(map)
            }
        } catch (_: Exception) {
        }
        return list
    }

    private fun getAppNameByPackage(packageName: String): String {
        return try {
            val pm = packageManager
            val appInfo = pm.getApplicationInfo(packageName, 0)
            pm.getApplicationLabel(appInfo).toString()
        } catch (e: Exception) {
            packageName
        }
    }

    private fun canQueryAllPackages(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val pm = packageManager
                val apps = pm.getInstalledApplications(0)
                val launcherIntent = Intent(Intent.ACTION_MAIN, null)
                    .addCategory(Intent.CATEGORY_LAUNCHER)
                val launchableApps = pm.queryIntentActivities(launcherIntent, 0)
                apps.size > launchableApps.size * 2
            } catch (e: Exception) {
                false
            }
        } else {
            true
        }
    }

    private fun requestSmsPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(android.Manifest.permission.RECEIVE_SMS),
                REQUEST_SMS_PERMISSION
            )
        }
    }

    private fun requestPhonePermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(android.Manifest.permission.READ_PHONE_STATE),
                REQUEST_PHONE_PERMISSION
            )
        }
    }

    private fun requestQueryAllPackagesPermission() {
        try {
            openAppDetailsSettings()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun setEnabledPackages(packages: List<String>) {
        val jsonArray = org.json.JSONArray(packages)
        prefs.edit().putString("flutter.enabled_packages", jsonArray.toString()).apply()
        notifyServiceConfigChanged()
    }

    private fun getEnabledPackages(): List<String> {
        val json = prefs.getString("flutter.enabled_packages", null) ?: return emptyList()
        val list = mutableListOf<String>()
        try {
            val jsonArray = org.json.JSONArray(json)
            for (i in 0 until jsonArray.length()) {
                list.add(jsonArray.getString(i))
            }
        } catch (_: Exception) {
        }
        return list
    }

    private fun setAppFilter(packages: List<String>, mode: String) {
        val jsonArray = org.json.JSONArray(packages)
        prefs.edit().putString("flutter.enabled_packages", jsonArray.toString()).apply()
        prefs.edit().putString("flutter.app_filter_mode", mode).apply()
        notifyServiceConfigChanged()
    }

    private fun getAppFilterMode(): String {
        return prefs.getString("flutter.app_filter_mode", "allow") ?: "allow"
    }

    private fun setBlacklistKeywords(keywords: List<String>) {
        val jsonArray = org.json.JSONArray(keywords)
        prefs.edit().putString("flutter.blacklist_keywords", jsonArray.toString()).apply()
        notifyServiceConfigChanged()
    }

    private fun getBlacklistKeywords(): List<String> {
        val json = prefs.getString("flutter.blacklist_keywords", null) ?: return emptyList()
        val list = mutableListOf<String>()
        try {
            val jsonArray = org.json.JSONArray(json)
            for (i in 0 until jsonArray.length()) {
                list.add(jsonArray.getString(i))
            }
        } catch (_: Exception) {
        }
        return list
    }

    private fun setWhitelistKeywords(keywords: List<String>) {
        val jsonArray = org.json.JSONArray(keywords)
        prefs.edit().putString("flutter.whitelist_keywords", jsonArray.toString()).apply()
        notifyServiceConfigChanged()
    }

    private fun setNotificationRules(rules: List<Map<String, Any?>>) {
        try {
            val jsonArray = org.json.JSONArray()
            for (rule in rules) {
                // 注意：JSONObject(Map) 会把 null 值序列化为字符串 "null"，
                // 因此显式过滤 null 字段后再序列化，避免原生 RuleEngine 误读。
                val obj = org.json.JSONObject()
                for ((k, v) in rule) {
                    if (v != null) obj.put(k, v)
                }
                jsonArray.put(obj)
            }
            prefs.edit()
                .putString("flutter.notification_rules", jsonArray.toString())
                .apply()
            notifyServiceConfigChanged()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun getWhitelistKeywords(): List<String> {
        val json = prefs.getString("flutter.whitelist_keywords", null) ?: return emptyList()
        val list = mutableListOf<String>()
        try {
            val jsonArray = org.json.JSONArray(json)
            for (i in 0 until jsonArray.length()) {
                list.add(jsonArray.getString(i))
            }
        } catch (_: Exception) {
        }
        return list
    }

    private fun clearNotificationRecords() {
        prefs.edit().remove("flutter.notification_records").apply()
        // 同步重置状态栏当日计数（与 DB 清空保持一致）
        NotificationMonitorService.pushCount = 0
        NotificationMonitorService.applyTodayDate(NotificationMonitorService.todayDateString())
    }

    private fun getBatteryStatus(): Map<String, Any?> {
        return try {
            val batteryManager = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
            val level = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
            val chargingStatus = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_STATUS)
            val isCharging = chargingStatus == BatteryManager.BATTERY_STATUS_CHARGING ||
                    chargingStatus == BatteryManager.BATTERY_STATUS_FULL
            mapOf(
                "level" to level,
                "isCharging" to isCharging,
                "status" to chargingStatus
            )
        } catch (e: Exception) {
            mapOf(
                "level" to -1,
                "isCharging" to false,
                "status" to -1,
                "error" to e.message
            )
        }
    }

    private fun setBatterySetting(key: String, value: Boolean) {
        val prefsKey = "flutter.$key"
        prefs.edit().putBoolean(prefsKey, value).apply()
        notifyServiceConfigChanged()
    }

    private fun setBatteryRules(rules: List<Map<String, Any>>) {
        try {
            val jsonArray = org.json.JSONArray()
            for (rule in rules) {
                val obj = org.json.JSONObject()
                obj.put("id", rule["id"] as? String ?: "")
                obj.put("type", rule["type"] as? String ?: "")
                obj.put("value", (rule["value"] as? Int) ?: 0)
                obj.put("enabled", (rule["enabled"] as? Boolean) ?: false)
                obj.put("title", rule["title"] as? String ?: "")
                obj.put("content", rule["content"] as? String ?: "")
                jsonArray.put(obj)
            }
            prefs.edit().putString("flutter.battery_rules", jsonArray.toString()).apply()
            notifyServiceConfigChanged()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun isNotificationListenerPermissionGranted(): Boolean {
        val flat = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners"
        ) ?: ""
        return flat.contains(packageName)
    }

    private fun requestNotificationListenerPermission() {
        try {
            val intent = Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        } catch (e: Exception) {
            try {
                val intent = Intent(Settings.ACTION_SECURITY_SETTINGS)
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
            } catch (e2: Exception) {
                e2.printStackTrace()
            }
        }
    }

    private fun isPostNotificationPermissionGranted(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                this,
                android.Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    private fun requestPostNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                REQUEST_POST_NOTIFICATION_PERMISSION
            )
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            powerManager.isIgnoringBatteryOptimizations(packageName)
        } else {
            true
        }
    }

    private fun isSmsPermissionGranted(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            ContextCompat.checkSelfPermission(
                this,
                android.Manifest.permission.RECEIVE_SMS
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    private fun isPhonePermissionGranted(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            ContextCompat.checkSelfPermission(
                this,
                android.Manifest.permission.READ_PHONE_STATE
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    private fun isAppListPermissionGranted(): Boolean {
        return canQueryAllPackages()
    }

    private fun requestBatteryOptimization() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val intent = Intent()
                intent.action = Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                intent.data = Uri.parse("package:$packageName")
                startActivity(intent)
            } catch (e: Exception) {
                try {
                    val intent = Intent(Settings.ACTION_BATTERY_SAVER_SETTINGS)
                    startActivity(intent)
                } catch (e2: Exception) {
                    e2.printStackTrace()
                }
            }
        }
    }

    private fun requestXiaomiAutoStart() {
        try {
            val intent = Intent()
            intent.component = ComponentName(
                "com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity"
            )
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        } catch (e: Exception) {
            try {
                val intent = Intent("miui.intent.action.OP_AUTO_START")
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
            } catch (e2: Exception) {
                try {
                    val intent = Intent()
                    intent.component = ComponentName(
                        "com.miui.securitycenter",
                        "com.miui.permcenter.permissions.PermissionsEditorActivity"
                    )
                    intent.putExtra("extra_pkgname", packageName)
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                } catch (e3: Exception) {
                    openAppDetailsSettings()
                }
            }
        }
    }

    private fun requestMeizuBackground() {
        try {
            val intent = Intent("com.meizu.safe.security.SHOW_APPSEC")
            intent.addCategory(Intent.CATEGORY_DEFAULT)
            intent.putExtra("packageName", packageName)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        } catch (e: Exception) {
            try {
                val intent = Intent()
                intent.component = ComponentName(
                    "com.meizu.safe",
                    "com.meizu.safe.permission.SmartBGControlActivity"
                )
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
            } catch (e2: Exception) {
                openAppDetailsSettings()
            }
        }
    }

    private fun requestHuaweiLaunch() {
        try {
            val intent = Intent()
            intent.component = ComponentName(
                "com.huawei.systemmanager",
                "com.huawei.systemmanager.optimize.process.ProtectActivity"
            )
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        } catch (e: Exception) {
            try {
                val intent = Intent()
                intent.component = ComponentName(
                    "com.huawei.systemmanager",
                    "com.huawei.permissionmanager.ui.MainActivity"
                )
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
            } catch (e2: Exception) {
                openAppDetailsSettings()
            }
        }
    }

    private fun requestOppoBackground() {
        try {
            val intent = Intent()
            intent.component = ComponentName(
                "com.coloros.safecenter",
                "com.coloros.safecenter.permission.startup.StartupAppListActivity"
            )
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        } catch (e: Exception) {
            try {
                val intent = Intent()
                intent.component = ComponentName(
                    "com.oppo.safe",
                    "com.oppo.safe.permission.startup.StartupAppListActivity"
                )
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
            } catch (e2: Exception) {
                openAppDetailsSettings()
            }
        }
    }

    private fun requestVivoBackground() {
        try {
            val intent = Intent()
            intent.component = ComponentName(
                "com.vivo.permissionmanager",
                "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
            )
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        } catch (e: Exception) {
            try {
                val intent = Intent()
                intent.component = ComponentName(
                    "com.iqoo.secure",
                    "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity"
                )
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
            } catch (e2: Exception) {
                openAppDetailsSettings()
            }
        }
    }

    private fun openAppDetailsSettings() {
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            intent.data = Uri.fromParts("package", packageName, null)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /** Android 12+ 是否已授权精确闹钟；12 以下系统无此概念，恒为 true */
    private fun canScheduleExactAlarms(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                val am = getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return false
                am.canScheduleExactAlarms()
            } catch (e: Exception) {
                false
            }
        } else {
            true
        }
    }

    /**
     * 引导用户授权精确闹钟（B1）。
     * Android 12~13：系统弹授权对话框（ACTION_REQUEST_SCHEDULE_EXACT_ALARM）。
     * Android 14+：SCHEDULE_EXACT_ALARM 默认拒绝且无系统授权入口，跳应用详情页引导手动开启；
     * 未授权时 DelayedPushManager 会捕获 SecurityException 自动降级为非精确闹钟，不阻塞功能。
     */
    private fun requestExactAlarmPermission() {
        try {
            if (canScheduleExactAlarms()) return
            if (Build.VERSION.SDK_INT in Build.VERSION_CODES.S..Build.VERSION_CODES.TIRAMISU) {
                // data 为可选参数：官方文档 "Optionally, the Intent's data URI can specify the package name"。
                // 部分 ROM（尤其国产）Settings 组件对该 action 的 intent-filter 不匹配带 data 的 intent，
                // 设置 data 反而触发 ActivityNotFoundException；不带 data 时系统默认取调用者包名。
                val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
            } else {
                openAppDetailsSettings()
            }
        } catch (e: Exception) {
            openAppDetailsSettings()
        }
    }

    /**
     * 历史记录"现在推送"：把单条记录以 JSON 转发给前台服务手动补推。
     * 服务侧 pushRecordNow 会忽略推送暂停开关，按当前配置立即推送 webhook + 邮件。
     */
    private fun pushRecordNow(record: Map<String, Any?>) {
        try {
            val intent = Intent(this, NotificationMonitorService::class.java).apply {
                action = NotificationMonitorService.ACTION_PUSH_RECORD_NOW
                putExtra(NotificationMonitorService.EXTRA_RECORD_DATA, JSONObject(record).toString())
            }
            startService(intent)
        } catch (e: Exception) {
            Log.e("MainActivity", "pushRecordNow failed", e)
        }
    }

    private fun startNotificationListener() {
        try {
            // 开启监听：仅置位持久化开关并通知服务，绝不禁用组件（避免系统撤销通知访问权限）
            setMonitoringEnabledPref(true)
            val intent = Intent(this, NotificationMonitorService::class.java)
            intent.action = NotificationMonitorService.ACTION_SET_MONITORING
            intent.putExtra(NotificationMonitorService.EXTRA_MONITORING_ENABLED, true)
            startService(intent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopNotificationListener() {
        try {
            // 关闭监听：只关闭转发/前台，保留组件启用以不丢失通知访问权限
            setMonitoringEnabledPref(false)
            val intent = Intent(this, NotificationMonitorService::class.java)
            intent.action = NotificationMonitorService.ACTION_SET_MONITORING
            intent.putExtra(NotificationMonitorService.EXTRA_MONITORING_ENABLED, false)
            startService(intent)
            Log.i("MainActivity", "Notification monitoring disabled (component kept enabled)")
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun setMonitoringEnabledPref(enabled: Boolean) {
        try {
            val prefs = getSharedPreferences(
                NotificationMonitorService.PREFS_NAME,
                Context.MODE_PRIVATE
            )
            prefs.edit().putBoolean(
                NotificationMonitorService.PREF_MONITORING_ENABLED,
                enabled
            ).apply()
        } catch (e: Exception) {
            e.printStackTrace()
        }
        NotificationMonitorService.monitoringEnabled = enabled
    }

    private fun isMonitoringEnabled(): Boolean {
        return try {
            val prefs = getSharedPreferences(
                NotificationMonitorService.PREFS_NAME,
                Context.MODE_PRIVATE
            )
            prefs.getBoolean(NotificationMonitorService.PREF_MONITORING_ENABLED, false)
        } catch (e: Exception) {
            false
        }
    }

    private fun notifyServiceConfigChanged() {
        try {
            val intent = Intent(this, NotificationMonitorService::class.java)
            intent.action = NotificationMonitorService.ACTION_UPDATE_CONFIG
            startService(intent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun getDownloadDirectory(): String {
        val downloadsDir = android.os.Environment.getExternalStoragePublicDirectory(
            android.os.Environment.DIRECTORY_DOWNLOADS
        )
        val appDir = java.io.File(downloadsDir, "FnthinkNotice")
        if (!appDir.exists()) {
            appDir.mkdirs()
        }
        return appDir.absolutePath
    }

    // 文件选择器保存
    private var pendingSaveResult: MethodChannel.Result? = null
    private var pendingSaveContent: String = ""
    private val SAVE_FILE_REQUEST_CODE = 9001

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == SAVE_FILE_REQUEST_CODE) {
            val uri = data?.data
            if (resultCode == RESULT_OK && uri != null) {
                try {
                    contentResolver.openOutputStream(uri)?.use { outputStream ->
                        outputStream.write(pendingSaveContent.toByteArray(Charsets.UTF_8))
                        outputStream.flush()
                    }
                    pendingSaveResult?.success(mapOf("success" to true, "message" to "导出成功"))
                } catch (e: Exception) {
                    pendingSaveResult?.success(mapOf("success" to false, "message" to "写入失败: ${e.message}"))
                }
            } else {
                pendingSaveResult?.success(mapOf("success" to false, "message" to "已取消"))
            }
        }
    }

    private fun saveFileWithPicker(fileName: String, content: String, result: MethodChannel.Result) {
        pendingSaveResult = result
        pendingSaveContent = content
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/json"
            putExtra(Intent.EXTRA_TITLE, fileName)
        }
        startActivityForResult(intent, SAVE_FILE_REQUEST_CODE)
    }

    private fun toggleNotificationListenerService() {
        val pm = packageManager
        val component = ComponentName(this, NotificationMonitorService::class.java)
        // 确保组件处于启用状态（历史版本可能曾被禁用），以便系统能重新绑定通知监听器
        pm.setComponentEnabledSetting(
            component,
            android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            android.content.pm.PackageManager.DONT_KILL_APP
        )
    }

    // 可选应用图标：17 图标 × 2 语言 = 34 个别名
    // key 格式: "iconKey_locale" 例如 "blue_zh"、"default_en"
    private fun getIconAliases(): Map<String, ComponentName> = mapOf(
        "default_zh" to ComponentName(packageName, "$packageName.LauncherDefaultZh"),
        "default_en" to ComponentName(packageName, "$packageName.LauncherDefaultEn"),
        "blue_zh" to ComponentName(packageName, "$packageName.LauncherBlueZh"),
        "blue_en" to ComponentName(packageName, "$packageName.LauncherBlueEn"),
        "cyan_zh" to ComponentName(packageName, "$packageName.LauncherCyanZh"),
        "cyan_en" to ComponentName(packageName, "$packageName.LauncherCyanEn"),
        "teal_zh" to ComponentName(packageName, "$packageName.LauncherTealZh"),
        "teal_en" to ComponentName(packageName, "$packageName.LauncherTealEn"),
        "mint_zh" to ComponentName(packageName, "$packageName.LauncherMintZh"),
        "mint_en" to ComponentName(packageName, "$packageName.LauncherMintEn"),
        "green_zh" to ComponentName(packageName, "$packageName.LauncherGreenZh"),
        "green_en" to ComponentName(packageName, "$packageName.LauncherGreenEn"),
        "yellow_zh" to ComponentName(packageName, "$packageName.LauncherYellowZh"),
        "yellow_en" to ComponentName(packageName, "$packageName.LauncherYellowEn"),
        "orange_zh" to ComponentName(packageName, "$packageName.LauncherOrangeZh"),
        "orange_en" to ComponentName(packageName, "$packageName.LauncherOrangeEn"),
        "red_zh" to ComponentName(packageName, "$packageName.LauncherRedZh"),
        "red_en" to ComponentName(packageName, "$packageName.LauncherRedEn"),
        "pink_zh" to ComponentName(packageName, "$packageName.LauncherPinkZh"),
        "pink_en" to ComponentName(packageName, "$packageName.LauncherPinkEn"),
        "rose_zh" to ComponentName(packageName, "$packageName.LauncherRoseZh"),
        "rose_en" to ComponentName(packageName, "$packageName.LauncherRoseEn"),
        "purple_zh" to ComponentName(packageName, "$packageName.LauncherPurpleZh"),
        "purple_en" to ComponentName(packageName, "$packageName.LauncherPurpleEn"),
        "indigo_zh" to ComponentName(packageName, "$packageName.LauncherIndigoZh"),
        "indigo_en" to ComponentName(packageName, "$packageName.LauncherIndigoEn"),
        "brown_zh" to ComponentName(packageName, "$packageName.LauncherBrownZh"),
        "brown_en" to ComponentName(packageName, "$packageName.LauncherBrownEn"),
        "gray_zh" to ComponentName(packageName, "$packageName.LauncherGrayZh"),
        "gray_en" to ComponentName(packageName, "$packageName.LauncherGrayEn"),
        "graphite_zh" to ComponentName(packageName, "$packageName.LauncherGraphiteZh"),
        "graphite_en" to ComponentName(packageName, "$packageName.LauncherGraphiteEn"),
        "black_zh" to ComponentName(packageName, "$packageName.LauncherBlackZh"),
        "black_en" to ComponentName(packageName, "$packageName.LauncherBlackEn"),
    )

    private fun getAliasKey(icon: String): String {
        val locale = prefs.getString("flutter.locale", "zh") ?: "zh"
        return "${icon}_${if (locale == "en") "en" else "zh"}"
    }

    private fun changeLauncherIcon(icon: String) {
        try {
            val key = getAliasKey(icon)
            val aliases = getIconAliases()
            val target = aliases[key] ?: aliases["default_zh"]!!
            val pm = packageManager
            for (comp in aliases.values) {
                val state = if (comp == target)
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                else
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED
                pm.setComponentEnabledSetting(comp, state, PackageManager.DONT_KILL_APP)
            }
            prefs.edit().putString("flutter.selected_icon", icon).apply()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun switchLocaleAlias() {
        try {
            val icon = prefs.getString("flutter.selected_icon", "default") ?: "default"
            val key = getAliasKey(icon)
            val aliases = getIconAliases()
            val target = aliases[key] ?: aliases["default_zh"]!!
            val pm = packageManager
            for (comp in aliases.values) {
                val state = if (comp == target)
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                else
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED
                pm.setComponentEnabledSetting(comp, state, PackageManager.DONT_KILL_APP)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun getLauncherIcon(): String {
        return prefs.getString("flutter.selected_icon", "default") ?: "default"
    }

    /**
     * 一键添加桌面小部件（Android 8.0+ 通过 requestPinAppWidget 弹出系统确认框）。
     * @param wide true 请求 4×2 宽规格，false 请求 2×2 规格。
     * @return 是否成功发起请求（Android < 8.0 或 Launcher 不支持时返回 false）
     */
    private fun requestPinWidget(wide: Boolean): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val manager = android.appwidget.AppWidgetManager.getInstance(this)
        val clazz = if (wide) PushToggleWidgetWideProvider::class.java
            else PushToggleWidgetProvider::class.java
        val component = android.content.ComponentName(this, clazz)
        val callback = PendingIntent.getBroadcast(
            this,
            0,
            Intent(this, clazz)
                .setAction(PushToggleWidgetProvider.ACTION_UPDATE_WIDGET),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return manager.requestPinAppWidget(component, null, callback)
    }

    /**
     * 使用系统下载器（DownloadManager）下载更新 APK。
     * 下载到公共 Download/FnthinkNotice 目录，无需存储权限；进度在通知栏可见，
     * 应用内通过 getSystemDownloadProgress 轮询同步进度条。
     * @return downloadId（String，MethodChannel 避免 Long 精度丢失），失败返回 null
     */
    private fun startSystemDownload(url: String, fileName: String, title: String): String? {
        if (url.isEmpty()) return null
        return try {
            val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            val request = DownloadManager.Request(Uri.parse(url)).apply {
                setTitle(title)
                setDescription(fileName)
                setNotificationVisibility(
                    DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED
                )
                setMimeType("application/vnd.android.package-archive")
                setAllowedOverMetered(true)
                setAllowedOverRoaming(true)
                setDestinationInExternalPublicDir(
                    Environment.DIRECTORY_DOWNLOADS,
                    "FnthinkNotice/$fileName"
                )
            }
            dm.enqueue(request).toString()
        } catch (e: Exception) {
            Log.e("MainActivity", "startSystemDownload failed", e)
            null
        }
    }

    /** 查询系统下载器任务状态与进度（Flutter 侧轮询，用于应用内进度条）。 */
    private fun querySystemDownloadProgress(id: Long): Map<String, Any?> {
        if (id < 0) return mapOf("status" to -1, "progress" to 0.0)
        return try {
            val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            val cursor = dm.query(DownloadManager.Query().setFilterById(id))
            if (cursor != null && cursor.moveToFirst()) {
                val status = cursor.getInt(
                    cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)
                )
                val bytes = cursor.getLong(
                    cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)
                )
                val total = cursor.getLong(
                    cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)
                )
                val reason = if (status == DownloadManager.STATUS_FAILED) {
                    cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON))
                } else {
                    0
                }
                cursor.close()
                mapOf(
                    "status" to status,
                    "bytesDownloaded" to bytes,
                    "totalBytes" to total,
                    "progress" to if (total > 0) bytes.toDouble() / total else 0.0,
                    "reason" to reason,
                    "reasonText" to downloadErrorReasonText(reason),
                )
            } else {
                cursor?.close()
                mapOf("status" to -1, "progress" to 0.0)
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "querySystemDownloadProgress failed", e)
            mapOf("status" to -1, "progress" to 0.0)
        }
    }

    /** DownloadManager.COLUMN_REASON 失败码 → 可读文案（用于诊断下载失败原因）。 */
    private fun downloadErrorReasonText(reason: Int): String = when (reason) {
        DownloadManager.ERROR_UNKNOWN -> "未知错误"
        DownloadManager.ERROR_FILE_ERROR -> "文件错误"
        DownloadManager.ERROR_UNHANDLED_HTTP_CODE -> "服务器返回异常状态码（HTTP 错误）"
        DownloadManager.ERROR_HTTP_DATA_ERROR -> "网络数据错误"
        DownloadManager.ERROR_TOO_MANY_REDIRECTS -> "重定向过多"
        DownloadManager.ERROR_INSUFFICIENT_SPACE -> "存储空间不足"
        DownloadManager.ERROR_DEVICE_NOT_FOUND -> "设备未找到"
        DownloadManager.ERROR_CANNOT_RESUME -> "无法断点续传"
        DownloadManager.ERROR_FILE_ALREADY_EXISTS -> "文件已存在"
        // 以下常量在部分 SDK 的 android.jar 中缺失，直接使用官方稳定数值
        1010 -> "下载被阻止"
        1011 -> "无法覆盖文件"
        1012 -> "文件不存在（服务器 404）"
        else -> "reason=$reason"
    }

    /** 获取系统下载器已下载 APK 的本地文件路径（用于 open_filex 打开安装）。 */
    private fun getDownloadedApkPath(id: Long): String? {
        if (id < 0) return null
        return try {
            val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            val cursor = dm.query(DownloadManager.Query().setFilterById(id))
            if (cursor != null && cursor.moveToFirst()) {
                val status = cursor.getInt(
                    cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)
                )
                val localUri = cursor.getString(
                    cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI)
                )
                cursor.close()
                if (status == DownloadManager.STATUS_SUCCESSFUL && !localUri.isNullOrEmpty()) {
                    val uri = Uri.parse(localUri)
                    if (uri.scheme == "file") uri.path else localUri
                } else {
                    null
                }
            } else {
                cursor?.close()
                null
            }
        } catch (e: Exception) {
            null
        }
    }

    /**
     * 通过系统安装器安装系统下载器下载的 APK。
     * Android 10+ 优先使用 content uri（MediaStore），旧版本回退 file uri。
     * @return 是否成功启动安装流程
     */
    private fun installSystemDownload(id: Long): Boolean {
        if (id < 0) return false
        // 安装未知来源应用权限（Android 8.0+），缺失时引导用户去开启
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            try {
                startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:$packageName")
                    )
                )
            } catch (e: Exception) {
                // 部分厂商缺少该设置入口，直接放行尝试安装
            }
            return false
        }
        return try {
            val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            val cursor = dm.query(DownloadManager.Query().setFilterById(id))
            if (cursor != null && cursor.moveToFirst()) {
                val status = cursor.getInt(
                    cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)
                )
                if (status != DownloadManager.STATUS_SUCCESSFUL) {
                    cursor.close()
                    return false
                }
                val mediaUri = try {
                    cursor.getString(
                        cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_MEDIAPROVIDER_URI)
                    )
                } catch (e: Exception) {
                    null
                }
                val localUri = cursor.getString(
                    cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI)
                )
                cursor.close()
                val uri: Uri = when {
                    !mediaUri.isNullOrEmpty() -> Uri.parse(mediaUri)
                    !localUri.isNullOrEmpty() -> Uri.parse(localUri)
                    else -> return false
                }
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "application/vnd.android.package-archive")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                startActivity(intent)
                true
            } else {
                cursor?.close()
                false
            }
        } catch (e: Exception) {
            false
        }
    }

    private fun testWebhook(url: String, secret: String?, result: MethodChannel.Result) {
        activityScope.launch(Dispatchers.IO) {
            val (success, message, signed) = try {
                val deviceName = PrefsHelper.deviceName.ifEmpty { Build.MODEL }
                val webhookType = WebhookPayloadBuilder.detectType(url)
                val chatId = WebhookPayloadBuilder.extractChatIdFromUrl(url)

                val typeLabel = when (webhookType) {
                    WebhookPayloadBuilder.WebhookType.WECHAT_WORK -> "企业微信"
                    WebhookPayloadBuilder.WebhookType.DINGTALK -> "钉钉"
                    WebhookPayloadBuilder.WebhookType.FEISHU -> "飞书"
                    WebhookPayloadBuilder.WebhookType.TELEGRAM -> "Telegram"
                    WebhookPayloadBuilder.WebhookType.BARK -> "Bark"
                    WebhookPayloadBuilder.WebhookType.SERVER_CHAN -> "Server酱"
                    WebhookPayloadBuilder.WebhookType.PUSH_PLUS -> "PushPlus"
                    WebhookPayloadBuilder.WebhookType.GENERIC -> "通用"
                }

                if (webhookType == WebhookPayloadBuilder.WebhookType.SERVER_CHAN) {
                    // Server酱：POST form（application/x-www-form-urlencoded），内容不进 URL
                    val formBody = WebhookPayloadBuilder.buildServerChanFormBody(
                        title = I18n.testTitle(),
                        content = I18n.testContent(),
                        deviceName = deviceName
                    )
                    val request = Request.Builder()
                        .url(url)
                        .post(formBody.toRequestBody("application/x-www-form-urlencoded; charset=utf-8".toMediaType()))
                        .addHeader("User-Agent", "NotificationMonitor/1.0")
                        .build()
                    okHttpClient.newCall(request).execute().use { response ->
                        val responseBody = response.body?.string() ?: ""
                        val parseResult = WebhookResponseParser.parse(webhookType, response.code, responseBody)
                        Triple(
                            parseResult.status == WebhookResponseParser.DeliveryStatus.SUCCESS,
                            parseResult.message,
                            false
                        )
                    }
                } else if (webhookType == WebhookPayloadBuilder.WebhookType.PUSH_PLUS) {
                    // PushPlus：POST JSON，token 注入 body
                    val token = WebhookPayloadBuilder.extractTokenFromUrl(url)
                    if (token.isEmpty()) {
                        Triple(false, "PushPlus 链接缺少 token 参数", false)
                    } else {
                        val payload = WebhookPayloadBuilder.buildPushPlusPayload(
                            title = I18n.testTitle(),
                            content = I18n.testContent(),
                            deviceName = deviceName,
                            time = "",
                            token = token
                        )
                        val request = Request.Builder()
                            .url(url)
                            .post(payload.toRequestBody("application/json; charset=utf-8".toMediaType()))
                            .addHeader("User-Agent", "NotificationMonitor/1.0")
                            .build()
                        okHttpClient.newCall(request).execute().use { response ->
                            val responseBody = response.body?.string() ?: ""
                            val parseResult = WebhookResponseParser.parse(webhookType, response.code, responseBody)
                            Triple(
                                parseResult.status == WebhookResponseParser.DeliveryStatus.SUCCESS,
                                parseResult.message,
                                false
                            )
                        }
                    }
                } else {
                    val payload = WebhookPayloadBuilder.buildTestPayload(webhookType, deviceName, chatId)

                    // 调用签名器（与正式推送走同一套签名逻辑）
                    val signedReq = WebhookSigner.sign(webhookType, url, payload, secret)

                    val body = signedReq.payload.toRequestBody("application/json; charset=utf-8".toMediaType())
                    val requestBuilder = Request.Builder()
                        .url(signedReq.url)
                        .post(body)
                        .addHeader("User-Agent", "NotificationMonitor/1.0")
                    for ((k, v) in signedReq.headers) {
                        requestBuilder.addHeader(k, v)
                    }
                    val request = requestBuilder.build()

                    okHttpClient.newCall(request).execute().use { response ->
                        val responseBody = response.body?.string() ?: ""
                        val parseResult = WebhookResponseParser.parse(webhookType, response.code, responseBody)

                        val signedLabel = if (!secret.isNullOrEmpty()) " [已签名]" else ""
                    val detail = "$typeLabel$signedLabel HTTP ${response.code} · ${parseResult.status.name}"
                    val fullMessage = "$detail\n${parseResult.message.take(300)}"

                    Triple(
                        parseResult.status == WebhookResponseParser.DeliveryStatus.SUCCESS,
                        fullMessage,
                        !secret.isNullOrEmpty()
                    )
                }
                }
            } catch (e: Exception) {
                Triple(false, "推送异常: ${e.message ?: e.javaClass.simpleName}", !secret.isNullOrEmpty())
            }

            withContext(Dispatchers.Main) {
                try {
                    result.success(mapOf(
                        "success" to success,
                        "message" to message,
                        "signed" to signed
                    ))
                } catch (e: Exception) {
                    result.error("TEST_ERROR", message, null)
                }
            }
        }
    }

    private fun testEmail(configMap: Map<String, Any?>, result: MethodChannel.Result) {
        activityScope.launch(Dispatchers.IO) {
            try {
                val toEmails = (configMap["toEmail"]?.toString() ?: "")
                    .split(",")
                    .map { it.trim() }
                    .filter { it.isNotEmpty() }

                val config = EmailSender.EmailConfig(
                    smtpHost = configMap["smtpHost"]?.toString() ?: "",
                    smtpPort = (configMap["smtpPort"] as? Number)?.toInt() ?: 465,
                    username = configMap["username"]?.toString() ?: "",
                    password = configMap["password"]?.toString() ?: "",
                    fromEmail = configMap["fromEmail"]?.toString() ?: "",
                    toEmails = toEmails,
                    useSSL = configMap["useSSL"] != false
                )

                val (success, message) = EmailSender.sendTestEmail(config)
                withContext(Dispatchers.Main) {
                    result.success(mapOf("success" to success, "message" to message))
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.success(mapOf("success" to false, "message" to "测试邮件异常: ${e.message}"))
                }
            }
        }
    }

    /** 缓存未送达的通知记录（Flutter 引擎未就绪时使用） */
    private fun cacheNotificationRecord(data: String) {
        try {
            val prefs = applicationContext.getSharedPreferences("flutter.notification_cache", android.content.Context.MODE_PRIVATE)
            val cached = prefs.getString("pending_records", "[]") ?: "[]"
            val arr = org.json.JSONArray(cached)
            arr.put(org.json.JSONObject(data))
            while (arr.length() > 200) arr.remove(0)
            prefs.edit().putString("pending_records", arr.toString()).apply()
        } catch (_: Exception) {}
    }

    /** 批量导入缓存的未送达通知记录 */
    private fun flushCachedNotificationRecords() {
        try {
            val prefs = applicationContext.getSharedPreferences("flutter.notification_cache", android.content.Context.MODE_PRIVATE)
            val cached = prefs.getString("pending_records", "[]") ?: "[]"
            val arr = org.json.JSONArray(cached)
            for (i in 0 until arr.length()) {
                try {
                    val json = arr.getJSONObject(i)
                    val map = mutableMapOf<String, Any?>()
                    val keys = json.keys()
                    while (keys.hasNext()) {
                        val key = keys.next()
                        map[key] = json.get(key)
                    }
                    methodChannel?.invokeMethod("onNotificationReceived", map)
                } catch (_: Exception) {}
            }
            prefs.edit().remove("pending_records").apply()
        } catch (_: Exception) {}
    }
}

object PrefsHelper {
    @Volatile var webhookUrls: List<String> = emptyList()
    @Volatile var deviceName: String = ""
}
