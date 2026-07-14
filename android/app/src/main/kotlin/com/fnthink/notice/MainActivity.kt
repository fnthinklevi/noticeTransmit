package com.fnthink.notice

import android.app.ActivityManager
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
import kotlinx.coroutines.launch
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
        private const val REQUEST_SMS_PERMISSION = 1001
        private const val REQUEST_PHONE_PERMISSION = 1002
        private const val REQUEST_POST_NOTIFICATION_PERMISSION = 1003
    }

    private val channel = "com.fnthink.notice/notification"
    private var methodChannel: MethodChannel? = null
    private val prefs: SharedPreferences by lazy {
        getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
    }

    private val okHttpClient: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .writeTimeout(10, TimeUnit.SECONDS)
            .readTimeout(10, TimeUnit.SECONDS)
            .retryOnConnectionFailure(false)
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
                        methodChannel?.invokeMethod("onNotificationReceived", map)
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
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

    private fun stopOldService() {
        try {
            val serviceIntent = Intent(this, NotificationMonitorService::class.java)
            stopService(serviceIntent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onResume() {
        super.onResume()
        val filter = IntentFilter(ACTION_NOTIFICATION_RECEIVED)
        registerReceiver(notificationReceiver, filter, Context.RECEIVER_EXPORTED)
        val batteryFilter = IntentFilter(NotificationMonitorService.ACTION_BATTERY_CHANGED_NOTIFY)
        registerReceiver(batteryReceiver, batteryFilter, Context.RECEIVER_EXPORTED)
    }

    override fun onPause() {
        super.onPause()
        try {
            unregisterReceiver(notificationReceiver)
        } catch (e: Exception) {
            e.printStackTrace()
        }
        try {
            unregisterReceiver(batteryReceiver)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        CrashReport.initCrashReport(applicationContext)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
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
                    result.success(true)
                }
                "reloadHotfix" -> {
                    val intent = android.content.Intent("com.fnthink.notice.RELOAD_HOTFIX")
                    intent.setPackage(packageName)
                    sendBroadcast(intent)
                    result.success(true)
                }
                "isServiceRunning" -> {
                    result.success(isNotificationServiceRunning())
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
                "getAppVersion" -> {
                    try {
                        val info = packageManager.getPackageInfo(packageName, 0)
                        val versionName = info.versionName ?: "1.5.32"
                        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            info.longVersionCode.toInt()
                        } else {
                            info.versionCode
                        }
                        result.success(mapOf("versionName" to versionName, "versionCode" to versionCode))
                    } catch (e: Exception) {
                        e.printStackTrace()
                        result.success(mapOf("versionName" to "1.5.32", "versionCode" to 66))
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
                    testWebhook(url, result)
                }
                "getNotificationRecords" -> {
                    val records = getNotificationRecords()
                    result.success(records)
                }
                "clearNotificationRecords" -> {
                    clearNotificationRecords()
                    result.success(true)
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
            val obj = JSONObject(channel)
            jsonArray.put(obj)
            val url = channel["url"]?.toString() ?: ""
            val enabled = channel["enabled"] as? Boolean ?: true
            if (enabled && url.isNotEmpty()) {
                enabledUrls.add(url)
            }
        }
        prefs.edit()
            .putString("flutter.webhook_channels", jsonArray.toString())
            .putString("flutter.webhook_urls", org.json.JSONArray(enabledUrls).toString())
            .commit()
        PrefsHelper.webhookUrls = enabledUrls
        NotificationMonitorService.webhookUrls = enabledUrls
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

    private fun setBlacklistKeywords(keywords: List<String>) {
        val jsonArray = org.json.JSONArray(keywords)
        prefs.edit().putString("flutter.blacklist_keywords", jsonArray.toString()).apply()
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

    private fun getNotificationRecords(): List<Map<String, Any?>> {
        val recordsJson = prefs.getString("flutter.notification_records", "[]") ?: "[]"
        val list = mutableListOf<Map<String, Any?>>()
        try {
            val jsonArray = org.json.JSONArray(recordsJson)
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
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return list
    }

    private fun clearNotificationRecords() {
        prefs.edit().remove("flutter.notification_records").apply()
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
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun isNotificationListenerPermissionGranted(): Boolean {
        return NotificationMonitorService.isConnected
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

    private fun isNotificationServiceRunning(): Boolean {
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val runningServices = am.getRunningServices(100)
        for (service in runningServices) {
            if (service.service.className == NotificationMonitorService::class.java.name) {
                return true
            }
        }
        return false
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
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val packageManager = packageManager
                val packages = packageManager.getInstalledApplications(0)
                packages.size > 0
            } catch (e: Exception) {
                false
            }
        } else {
            true
        }
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

    private fun startNotificationListener() {
        try {
            toggleNotificationListenerService()
            val intent = Intent(this, NotificationMonitorService::class.java)
            startService(intent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopNotificationListener() {
        try {
            val pm = packageManager
            val component = ComponentName(this, NotificationMonitorService::class.java)
            pm.setComponentEnabledSetting(
                component,
                android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                android.content.pm.PackageManager.DONT_KILL_APP
            )
            Log.i("MainActivity", "Notification listener service disabled")
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun getDownloadDirectory(): String {
        val downloadsDir = android.os.Environment.getExternalStoragePublicDirectory(
            android.os.Environment.DIRECTORY_DOWNLOADS
        )
        val appDir = java.io.File(downloadsDir, "fnthink.notice")
        if (!appDir.exists()) {
            appDir.mkdirs()
        }
        return appDir.absolutePath
    }

    private fun toggleNotificationListenerService() {
        val pm = packageManager
        val component = ComponentName(this, NotificationMonitorService::class.java)
        pm.setComponentEnabledSetting(
            component,
            android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            android.content.pm.PackageManager.DONT_KILL_APP
        )
        pm.setComponentEnabledSetting(
            component,
            android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            android.content.pm.PackageManager.DONT_KILL_APP
        )
    }

    private fun testWebhook(url: String, result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            val (success, message) = try {
                val deviceName = PrefsHelper.deviceName.ifEmpty { Build.MODEL }
                val webhookType = WebhookPayloadBuilder.detectType(url)
                val payload = WebhookPayloadBuilder.buildTestPayload(webhookType, deviceName)

                val typeLabel = when (webhookType) {
                    WebhookPayloadBuilder.WebhookType.WECHAT_WORK -> "企业微信"
                    WebhookPayloadBuilder.WebhookType.DINGTALK -> "钉钉"
                    WebhookPayloadBuilder.WebhookType.FEISHU -> "飞书"
                    WebhookPayloadBuilder.WebhookType.GENERIC -> "通用"
                }

                val body = payload.toRequestBody("application/json; charset=utf-8".toMediaType())
                val request = Request.Builder()
                    .url(url)
                    .post(body)
                    .addHeader("User-Agent", "NotificationMonitor/1.0")
                    .build()

                okHttpClient.newCall(request).execute().use { response ->
                    val responseBody = response.body?.string() ?: ""
                    if (response.isSuccessful) {
                        true to "推送成功 ($typeLabel) (HTTP ${response.code})"
                    } else {
                        false to "推送失败 ($typeLabel) (HTTP ${response.code}): ${responseBody.take(200)}"
                    }
                }
            } catch (e: Exception) {
                false to "推送异常: ${e.message ?: e.javaClass.simpleName}"
            }

            runOnUiThread {
                try {
                    result.success(mapOf(
                        "success" to success,
                        "message" to message
                    ))
                } catch (e: Exception) {
                    result.error("TEST_ERROR", message, null)
                }
            }
        }
    }
}

object PrefsHelper {
    var webhookUrls: List<String> = emptyList()
    var deviceName: String = ""
}
