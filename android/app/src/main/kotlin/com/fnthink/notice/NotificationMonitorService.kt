package com.fnthink.notice

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.io.File
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit

class NotificationMonitorService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotificationMonitor"
        private const val FOREGROUND_ID = 1001
        private const val CHANNEL_ID = "notification_monitor_service"
        const val ACTION_BATTERY_CHANGED_NOTIFY = "com.fnthink.notice.BATTERY_CHANGED_NOTIFY"
        const val EXTRA_BATTERY_LEVEL = "battery_level"
        const val EXTRA_BATTERY_CHARGING = "battery_charging"
        var isConnected = false
            private set
        var webhookUrls: List<String> = emptyList()
        var deviceName: String = ""
        var enabledPackages: Set<String> = emptySet()
        var blacklistKeywords: List<String> = emptyList()
        var whitelistKeywords: List<String> = emptyList()

        private val listenerCallbacks = mutableListOf<(NotificationInfo) -> Unit>()

        fun addNotificationListener(callback: (NotificationInfo) -> Unit) {
            listenerCallbacks.add(callback)
        }

        fun removeNotificationListener(callback: (NotificationInfo) -> Unit) {
            listenerCallbacks.remove(callback)
        }

        fun clearListeners() {
            listenerCallbacks.clear()
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private lateinit var prefs: SharedPreferences

    private fun readDeviceNameFromFile(): String {
        return try {
            val file = java.io.File(filesDir, "device_name.txt")
            if (file.exists()) {
                file.readText().trim()
            } else {
                ""
            }
        } catch (e: Exception) {
            Log.e(TAG, "读取设备名文件失败", e)
            ""
        }
    }

    private fun writeDeviceNameToFile(name: String) {
        try {
            val file = java.io.File(filesDir, "device_name.txt")
            file.writeText(name)
        } catch (e: Exception) {
            Log.e(TAG, "写入设备名文件失败", e)
        }
    }

    private val notifiedKeys = mutableSetOf<String>()
    private val MAX_NOTIFIED_KEYS = 200

    private var lastBatteryLevel = -1
    private var lastIsCharging = false
    private val triggeredLevelRules = mutableSetOf<String>()

    private val batteryReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            intent ?: return
            when (intent.action) {
                Intent.ACTION_BATTERY_CHANGED -> handleBatteryChanged(intent)
            }
        }
    }

    private val okHttpClient: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .writeTimeout(15, TimeUnit.SECONDS)
            .readTimeout(15, TimeUnit.SECONDS)
            .retryOnConnectionFailure(true)
            .build()
    }

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "NotificationMonitorService onCreate")

        startForegroundCompat()
        
        prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        acquireWakeLocks()
        registerBatteryReceiver()
        registerHotfixReceiver()

        CoroutineScope(Dispatchers.IO).launch {
            try {
                loadConfigFromPrefs()
                loadHotfixConfig()
                Log.i(TAG, "后台加载配置完成")
            } catch (e: Exception) {
                Log.e(TAG, "后台加载配置失败", e)
            }
        }
    }

    private var hotfixReceiver: android.content.BroadcastReceiver? = null

    private fun registerHotfixReceiver() {
        hotfixReceiver = object : android.content.BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: android.content.Intent?) {
                Log.i(TAG, "收到热更新重载广播")
                loadHotfixConfig()
            }
        }
        val filter = android.content.IntentFilter("com.fnthink.notice.RELOAD_HOTFIX")
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(hotfixReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(hotfixReceiver, filter)
            }
        } catch (e: Exception) {
            Log.e(TAG, "注册热更新广播失败", e)
        }
    }

    private fun loadConfigFromPrefs() {
        val channelsJson = prefs.getString("flutter.webhook_channels", null)
        val urls = mutableListOf<String>()

        if (!channelsJson.isNullOrEmpty()) {
            try {
                val jsonArray = org.json.JSONArray(channelsJson)
                for (i in 0 until jsonArray.length()) {
                    val obj = jsonArray.getJSONObject(i)
                    val enabled = obj.optBoolean("enabled", true)
                    val url = obj.optString("url", "").trim()
                    if (enabled && url.isNotEmpty()) {
                        urls.add(url)
                    }
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        if (urls.isEmpty()) {
            val savedUrlsJson = prefs.getString("flutter.webhook_urls", "[]") ?: "[]"
            try {
                val jsonArray = org.json.JSONArray(savedUrlsJson)
                for (i in 0 until jsonArray.length()) {
                    val url = jsonArray.getString(i).trim()
                    if (url.isNotEmpty()) {
                        urls.add(url)
                    }
                }
            } catch (e: Exception) {
                val singleUrl = prefs.getString("flutter.webhook_url", "") ?: ""
                if (singleUrl.isNotEmpty()) {
                    urls.add(singleUrl)
                }
            }
        }

        webhookUrls = urls
        PrefsHelper.webhookUrls = urls

        var savedDeviceName = readDeviceNameFromFile()
        if (savedDeviceName.isEmpty()) {
            savedDeviceName = prefs.getString("flutter.device_name", "") ?: ""
        }
        if (savedDeviceName.isNotEmpty()) {
            deviceName = savedDeviceName
            PrefsHelper.deviceName = savedDeviceName
            if (prefs.getString("flutter.device_name", "") != savedDeviceName) {
                prefs.edit().putString("flutter.device_name", savedDeviceName).apply()
            }
            writeDeviceNameToFile(savedDeviceName)
        } else {
            val defaultName = "${Build.BRAND} ${Build.MODEL}"
            deviceName = defaultName
            PrefsHelper.deviceName = defaultName
            prefs.edit().putString("flutter.device_name", defaultName).apply()
            writeDeviceNameToFile(defaultName)
        }

        val enabledPkgsJson = prefs.getString("flutter.enabled_packages", null)
        if (enabledPkgsJson != null) {
            try {
                val jsonArray = org.json.JSONArray(enabledPkgsJson)
                val pkgs = mutableSetOf<String>()
                for (i in 0 until jsonArray.length()) {
                    pkgs.add(jsonArray.getString(i))
                }
                enabledPackages = pkgs
            } catch (_: Exception) {}
        }

        val blacklistJson = prefs.getString("flutter.blacklist_keywords", null)
        if (blacklistJson != null) {
            try {
                val jsonArray = org.json.JSONArray(blacklistJson)
                val keywords = mutableListOf<String>()
                for (i in 0 until jsonArray.length()) {
                    keywords.add(jsonArray.getString(i))
                }
                blacklistKeywords = keywords
            } catch (_: Exception) {}
        }

        val whitelistJson = prefs.getString("flutter.whitelist_keywords", null)
        if (whitelistJson != null) {
            try {
                val jsonArray = org.json.JSONArray(whitelistJson)
                val keywords = mutableListOf<String>()
                for (i in 0 until jsonArray.length()) {
                    keywords.add(jsonArray.getString(i))
                }
                whitelistKeywords = keywords
            } catch (_: Exception) {}
        }

        Log.d(TAG, "Loaded config: urls=$urls, device=$savedDeviceName")
    }

    private fun saveNotificationRecord(info: NotificationInfo) {
        try {
            val recordsJson = prefs.getString("flutter.notification_records", "[]") ?: "[]"
            val records = org.json.JSONArray(recordsJson)
            
            val newRecord = JSONObject().apply {
                put("id", info.id)
                put("title", info.title)
                put("content", info.content)
                put("subText", info.subText)
                put("packageName", info.packageName)
                put("appName", info.appName)
                put("postTime", info.postTime)
                put("time", info.time)
                put("type", info.type)
                put("deviceName", info.deviceName)
                put("timestamp", System.currentTimeMillis())
            }
            
            records.put(0, newRecord)
            
            while (records.length() > 500) {
                records.remove(records.length() - 1)
            }
            
            prefs.edit().putString("flutter.notification_records", records.toString()).apply()
        } catch (e: Exception) {
            Log.e(TAG, "保存通知记录失败", e)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        releaseWakeLocks()
        unregisterBatteryReceiver()
        hotfixReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (e: Exception) {
                Log.e(TAG, "注销热更新广播失败", e)
            }
        }
        Log.d(TAG, "NotificationMonitorService onDestroy")
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        isConnected = true
        startForegroundCompat()
        Log.i(TAG, "Notification listener connected")
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        isConnected = false
        Log.d(TAG, "Notification listener disconnected")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        sbn ?: return

        val notification = sbn.notification ?: return
        val packageName = sbn.packageName
        val notificationId = sbn.id
        val channelId = notification.channelId

        Log.i(TAG, "收到通知: pkg=$packageName, channel=$channelId, id=$notificationId")

        if (packageName == this.packageName) return

        val isOngoing = (notification.flags and Notification.FLAG_ONGOING_EVENT) != 0
        val dedupKey = "$packageName:$notificationId"

        if (isOngoing && notifiedKeys.contains(dedupKey)) {
            return
        }

        if (isOngoing) {
            notifiedKeys.add(dedupKey)
            if (notifiedKeys.size > MAX_NOTIFIED_KEYS) {
                notifiedKeys.clear()
            }
        }

        val extras = notification.extras

        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""
        val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString() ?: ""
        val postTime = sbn.postTime
        val id = sbn.id.toString()

        val content = bigText.ifEmpty { text }

        if (title.isEmpty() && content.isEmpty()) return

        val baseAppName = getAppNameByPackage(packageName)
        val isPushService = isVendorPushService(packageName)
        val resolvedAppName = if (isPushService) {
            resolveRealAppName(sbn, baseAppName, title, content, subText)
        } else {
            baseAppName
        }
        val appName = resolvedAppName
        val notifyType = detectNotificationType(packageName, appName, title, content)
        val timeStr = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
            .format(Date(postTime))

        if (isPushService) {
            dumpNotificationExtras(TAG, "厂商推送通知", sbn)
        }

        Log.i(TAG, "通知: pkg=$packageName, baseApp=$baseAppName, app=$appName, type=$notifyType, isPush=$isPushService, title=$title")

        val passFilter = shouldNotify(packageName, title, content, subText)
        if (!passFilter) {
            Log.d(TAG, "Notification filtered out: $packageName - $title")
            return
        }

        val info = NotificationInfo(
            id = id,
            title = title,
            content = content,
            subText = subText,
            packageName = packageName,
            appName = appName,
            postTime = postTime,
            time = timeStr,
            type = notifyType,
            deviceName = deviceName
        )

        Log.d(TAG, "Notification posted: $packageName [$notifyType] - $title")

        for (callback in listenerCallbacks) {
            try {
                callback(info)
            } catch (e: Exception) {
                Log.e(TAG, "Callback error", e)
            }
        }

        sendWebhook(info)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        super.onNotificationRemoved(sbn)
        sbn ?: return
        val dedupKey = "${sbn.packageName}:${sbn.id}"
        notifiedKeys.remove(dedupKey)
    }

    private fun getAppNameByPackage(packageName: String): String {
        return try {
            val pm = packageManager
            val appInfo = pm.getApplicationInfo(packageName, 0)
            val label = pm.getApplicationLabel(appInfo).toString()
            val friendlyName = getFriendlyAppName(packageName)

            val isLabelSuspicious = label.isEmpty() ||
                    label == packageName ||
                    label.length > 12 ||
                    label.contains("推送") ||
                    label.contains("服务") ||
                    label.contains("system", ignoreCase = true) ||
                    label.contains("push", ignoreCase = true)

            if (isLabelSuspicious && friendlyName != packageName && friendlyName.isNotEmpty()) {
                Log.d(TAG, "Using friendly name for $packageName: label=$label -> friendly=$friendlyName")
                friendlyName
            } else if (label.isNotEmpty() && label != packageName) {
                label
            } else {
                friendlyName
            }
        } catch (e: Exception) {
            val friendlyName = getFriendlyAppName(packageName)
            Log.d(TAG, "getAppNameByPackage error for $packageName, using friendly: $friendlyName", e)
            friendlyName
        }
    }

    private var hotfixAppNames: Map<String, String>? = null
    private var hotfixNotificationTypes: Map<String, String>? = null

    private fun loadHotfixConfig() {
        try {
            val appFlutterDir = File(applicationInfo.dataDir, "app_flutter")
            val hotfixDir = File(appFlutterDir, "hotfix")
            if (!hotfixDir.exists()) {
                Log.i(TAG, "热更新目录不存在，跳过加载")
                return
            }

            val appNamesFile = File(hotfixDir, "app_names.json")
            if (appNamesFile.exists()) {
                val json = appNamesFile.readText()
                val jsonObject = org.json.JSONObject(json)
                val map = mutableMapOf<String, String>()
                val keys = jsonObject.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    map[key.lowercase()] = jsonObject.getString(key)
                }
                hotfixAppNames = map
                Log.i(TAG, "加载热更新应用名称映射: ${map.size} 条")
            }

            val typesFile = File(hotfixDir, "notification_types.json")
            if (typesFile.exists()) {
                val json = typesFile.readText()
                val jsonObject = org.json.JSONObject(json)
                val map = mutableMapOf<String, String>()
                val keys = jsonObject.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    map[key.lowercase()] = jsonObject.getString(key)
                }
                hotfixNotificationTypes = map
                Log.i(TAG, "加载热更新通知类型映射: ${map.size} 条")
            }
        } catch (e: Exception) {
            Log.e(TAG, "加载热更新配置失败", e)
        }
    }

    private fun getFriendlyAppName(packageName: String): String {
        val pkg = packageName.lowercase()
        hotfixAppNames?.let { map ->
            for ((prefix, name) in map) {
                if (pkg.startsWith(prefix)) {
                    return name
                }
            }
        }
        return when {
            pkg.startsWith("com.tencent.mm") -> "微信"
            pkg.startsWith("com.tencent.mobileqq") -> "QQ"
            pkg.startsWith("com.tencent.tim") -> "TIM"
            pkg.startsWith("com.xingin") || pkg.startsWith("com.xhs") -> "小红书"
            pkg.startsWith("com.zhihu.android") -> "知乎"
            pkg.startsWith("com.sina.weibo") -> "微博"
            pkg.startsWith("com.alibaba.android.rimet") -> "钉钉"
            pkg.startsWith("com.alibaba.android.babylon") || pkg.startsWith("com.taobao.taobao") -> "淘宝"
            pkg.startsWith("com.tmall.wireless") -> "天猫"
            pkg.startsWith("com.jingdong.app.mall") -> "京东"
            pkg.startsWith("com.xunmeng.pinduoduo") || pkg.startsWith("com.xunmeng.pinduoduoplus") -> "拼多多"
            pkg.startsWith("com.netease.cloudmusic") -> "网易云音乐"
            pkg.startsWith("com.tencent.qqmusic") -> "QQ音乐"
            pkg.startsWith("com.baidu.netdisk") -> "百度网盘"
            pkg.startsWith("com.eg.android.AlipayGphone") -> "支付宝"
            pkg.startsWith("tv.danmaku.bili") || pkg.startsWith("com.bilibili.app.in") -> "哔哩哔哩"
            pkg.startsWith("com.ss.android.ugc.aweme") || pkg.startsWith("com.ss.android.ugc.aweme.mobile") -> "抖音"
            pkg.startsWith("com.smile.gifmaker") -> "快手"
            pkg.startsWith("com.meituan") -> "美团"
            pkg.startsWith("com.dianping.v1") -> "大众点评"
            pkg.startsWith("me.ele") || pkg.startsWith("com.ele") -> "饿了么"
            pkg.startsWith("com.sankuai") -> "美团"
            pkg.startsWith("com.sdu.didi.psngr") || pkg.startsWith("com.didi") -> "滴滴出行"
            pkg.startsWith("com.netease.mail") || pkg.startsWith("com.netease.mobile.mail") -> "网易邮箱"
            pkg.startsWith("com.tencent.qqmail") -> "QQ邮箱"
            pkg.startsWith("com.google.android.gm") -> "Gmail"
            pkg.startsWith("com.android.chrome") -> "Chrome浏览器"
            pkg.startsWith("com.android.browser") -> "浏览器"
            pkg.startsWith("com.android.mms") || pkg.startsWith("com.google.android.apps.messaging") || pkg.contains("sms") -> "短信"
            pkg.startsWith("com.android.dialer") || pkg.startsWith("com.android.incallui") || pkg.startsWith("com.android.phone") -> "电话"
            pkg.startsWith("com.android.contacts") -> "联系人"
            pkg.startsWith("com.android.settings") -> "设置"
            pkg.startsWith("com.android.systemui") -> "系统界面"
            pkg.startsWith("com.miui.home") -> "小米桌面"
            pkg.startsWith("com.miui.securitycenter") -> "手机管家"
            pkg.startsWith("com.xiaomi.market") -> "应用商店"
            pkg.startsWith("com.xiaomi.account") -> "小米账号"
            pkg.startsWith("com.xiaomi.xmsf") -> "小米推送"
            pkg.startsWith("com.huawei.android.push") -> "华为推送"
            pkg.startsWith("com.huawei.hwid") -> "华为账号"
            pkg.startsWith("com.huawei.appmarket") -> "应用市场"
            pkg.startsWith("com.huawei.browser") -> "华为浏览器"
            pkg.startsWith("com.coloros") || pkg.startsWith("com.oppo") -> "OPPO系统"
            pkg.startsWith("com.vivo.push") -> "vivo推送"
            pkg.startsWith("com.vivo.browser") -> "vivo浏览器"
            pkg.startsWith("com.vivo.appstore") -> "vivo应用商店"
            pkg.startsWith("com.google.android.gms") || pkg.contains("fcm") -> "Google服务"
            pkg.startsWith("com.meizu.cloud") || pkg.startsWith("com.meizu.push") -> "魅族推送"
            pkg.startsWith("com.meizu") -> "魅族"
            pkg.startsWith("com.hihonor") || pkg.startsWith("com.honor") -> "荣耀"
            pkg.startsWith("com.oneplus") -> "一加"
            pkg.startsWith("com.realme") -> "realme"
            pkg.startsWith("com.smartisan") -> "锤子"
            pkg.startsWith("com.lenovo") -> "联想"
            pkg.startsWith("com.zte") -> "中兴"
            pkg.startsWith("com.coolpad") -> "酷派"
            pkg.startsWith("com.nubia") -> "努比亚"
            pkg.startsWith("com.blackshark") -> "黑鲨"
            pkg.startsWith("com.rog") -> "ROG"
            pkg.startsWith("com.miui") || pkg.startsWith("com.xiaomi") -> "小米"
            pkg.startsWith("com.android.calendar") -> "日历"
            pkg.startsWith("com.android.calculator") -> "计算器"
            pkg.startsWith("com.android.clock") || pkg.startsWith("com.android.alarm") -> "时钟"
            pkg.startsWith("com.android.weather") -> "天气"
            pkg.startsWith("com.android.notes") || pkg.startsWith("com.android.notepad") -> "笔记"
            pkg.startsWith("com.mi.browser") -> "小米浏览器"
            pkg.contains("launcher") -> "桌面"
            else -> packageName
        }
    }

    private fun isVendorPushService(packageName: String): Boolean {
        val pkg = packageName.lowercase()
        return when {
            pkg.startsWith("com.xiaomi.xmsf") -> true
            pkg.startsWith("com.xiaomi.push") -> true
            pkg.startsWith("com.miui.push") -> true
            pkg.startsWith("com.huawei.android.push") -> true
            pkg.startsWith("com.huawei.hms.push") -> true
            pkg.startsWith("com.vivo.push") -> true
            pkg.startsWith("com.vivo.notification") -> true
            pkg.startsWith("com.coloros.push") -> true
            pkg.startsWith("com.oppo.push") -> true
            pkg.startsWith("com.heytap.push") -> true
            pkg.startsWith("com.meizu.cloud") -> true
            pkg.startsWith("com.meizu.push") -> true
            pkg.startsWith("com.flyme.push") -> true
            pkg.startsWith("com.samsung.android.push") -> true
            pkg.startsWith("com.google.android.gms") && pkg.contains("push") -> true
            else -> false
        }
    }

    private fun dumpNotificationExtras(tag: String, prefix: String, sbn: StatusBarNotification) {
        try {
            val extras = sbn.notification?.extras ?: return
            val keys = extras.keySet()
            val sb = StringBuilder()
            sb.append("$prefix [${sbn.packageName}] extras:\n")
            for (key in keys) {
                val value = extras.get(key)
                val valueStr = when {
                    value == null -> "null"
                    value is CharSequence -> value.toString()
                    value is ByteArray -> "[${value.size} bytes]"
                    else -> "${value.javaClass.simpleName}: $value"
                }
                sb.append("  $key = $valueStr\n")
            }
            sb.append("  notification.channelId = ${sbn.notification.channelId}")
            Log.i(tag, sb.toString())
        } catch (e: Exception) {
            Log.e(tag, "dumpNotificationExtras error", e)
        }
    }

    private fun resolveRealAppName(
        sbn: StatusBarNotification,
        baseName: String,
        title: String,
        content: String,
        subText: String
    ): String {
        val extras = sbn.notification?.extras ?: return baseName
        val pkg = sbn.packageName.lowercase()

        // 1. 尝试从常见的厂商推送 extras 字段中获取应用名称
        val vendorExtraKeys = listOf(
            "miui_android_notification_channel_id",
            "miui_primary_key",
            "miui_notification_id",
            "hw_push_id",
            "hw_from",
            "vivo_push_id",
            "oppo_push_id",
            "meizu_push_id",
            "flyme_push_id",
            "heytap_push_id",
            "push_app_name",
            "target_package",
            "src_package",
            "original_package",
            "ext_org_package",
            "ext_org_app_name"
        )
        for (key in vendorExtraKeys) {
            val value = extras.get(key)
            if (value is CharSequence && value.isNotEmpty()) {
                val str = value.toString()
                if (str.isNotEmpty() && str.length <= 12 && !str.contains("push", true) && !str.contains("service", true)) {
                    Log.d(TAG, "从厂商推送字段 [$key] 提取应用名: $str")
                    return str
                }
            }
            if (value is String && value.isNotEmpty() && value.contains(".")) {
                // 可能是包名
                val candidateAppName = getAppNameByPackage(value)
                if (candidateAppName != value && candidateAppName.isNotEmpty()) {
                    Log.d(TAG, "从厂商推送字段 [$key] 提取包名并解析: $value -> $candidateAppName")
                    return candidateAppName
                }
            }
        }

        // 2. 尝试从 subText 中提取应用名称
        if (subText.isNotEmpty() && subText.length in 1..12) {
            val isAppName = !subText.contains("push", true) &&
                    !subText.contains("service", true) &&
                    !subText.contains("notification", true) &&
                    !subText.contains("条消息", true) &&
                    !subText.contains("新消息", true) &&
                    !subText.contains("通知", true)
            if (isAppName) {
                Log.d(TAG, "从 subText 提取应用名: $subText")
                return subText
            }
        }

        // 3. 尝试从 notification channel id 中提取原始包名（魅族/小米/华为等厂商推送）
        val channelId = sbn.notification?.channelId
        if (!channelId.isNullOrEmpty()) {
            val channelLower = channelId.lowercase()

            // 魅族推送: mzpush_oripacname_<package_name>
            val meizuMatch = Regex("mzpush_oripacname_(.+)").find(channelLower)
            if (meizuMatch != null) {
                val origPkg = meizuMatch.groupValues[1]
                val candidate = getAppNameByPackage(origPkg)
                Log.i(TAG, "从魅族推送 channelId 提取原始包名: $channelId -> $origPkg -> $candidate")
                return candidate
            }

            // 小米推送: miui_*_<package_name> 或 xmsf_*_<package_name>
            if (channelLower.contains("miui") || channelLower.contains("xmsf")) {
                val pkgMatch = Regex("([a-z]+\\.[a-z]+\\.[a-z]+)").find(channelLower)
                if (pkgMatch != null) {
                    val origPkg = pkgMatch.groupValues[1]
                    val candidate = getAppNameByPackage(origPkg)
                    if (candidate != origPkg && candidate.isNotEmpty()) {
                        Log.i(TAG, "从小米推送 channelId 提取包名: $channelId -> $origPkg -> $candidate")
                        return candidate
                    }
                }
            }

            // 华为推送: hw_*_<package_name> 或 hms_*_<package_name>
            if (channelLower.contains("hw") || channelLower.contains("hms")) {
                val pkgMatch = Regex("([a-z]+\\.[a-z]+\\.[a-z]+)").find(channelLower)
                if (pkgMatch != null) {
                    val origPkg = pkgMatch.groupValues[1]
                    val candidate = getAppNameByPackage(origPkg)
                    if (candidate != origPkg && candidate.isNotEmpty()) {
                        Log.i(TAG, "从华为推送 channelId 提取包名: $channelId -> $origPkg -> $candidate")
                        return candidate
                    }
                }
            }

            // 通用：检查 channelId 中是否包含包名格式的字符串
            val pkgMatch = Regex("[a-z]+\\.[a-z]+\\.[a-z.]+").findAll(channelLower)
            for (match in pkgMatch) {
                val origPkg = match.value
                if (origPkg.length > 10 && origPkg.contains(".")) {
                    val candidate = getAppNameByPackage(origPkg)
                    if (candidate != origPkg && candidate.isNotEmpty()) {
                        Log.i(TAG, "从 channelId 提取包名: $channelId -> $origPkg -> $candidate")
                        return candidate
                    }
                }
            }
        }

        // 4. 尝试从 title 中分离应用名（某些推送格式是 "应用名: 标题" 或 "【应用名】标题"）
        if (title.isNotEmpty()) {
            val bracketMatch = Regex("【([^】]+)】").find(title)
            if (bracketMatch != null) {
                val extracted = bracketMatch.groupValues[1]
                if (extracted.length in 1..12) {
                    Log.d(TAG, "从标题括号中提取应用名: $extracted")
                    return extracted
                }
            }
            val colonMatch = title.indexOf("：")
            if (colonMatch in 1..12) {
                val extracted = title.substring(0, colonMatch)
                if (extracted.isNotEmpty() && extracted.length <= 12) {
                    Log.d(TAG, "从标题冒号前提取应用名: $extracted")
                    return extracted
                }
            }
        }

        // 5. 如果还是不行，但 baseName 看起来像推送服务名称，返回更友好的名称
        val lowerBase = baseName.lowercase()
        if (lowerBase.contains("推送") || lowerBase.contains("push") || lowerBase.contains("服务") || lowerBase.contains("魅族")) {
            // 尝试用通知标题中的第一个词作为应用名
            val firstWord = title.take(10)
            if (firstWord.isNotEmpty() && firstWord.length >= 2) {
                Log.d(TAG, "使用标题前几个字作为应用名: $firstWord")
                return firstWord
            }
        }

        return baseName
    }

    private fun detectNotificationType(packageName: String, appName: String, title: String, content: String): String {
        val pkg = packageName.lowercase()
        val appLower = appName.lowercase()
        val fullText = "$appName $title $content".lowercase()

        hotfixNotificationTypes?.let { map ->
            for ((keyword, type) in map) {
                if (pkg.contains(keyword) || appLower.contains(keyword) || fullText.contains(keyword)) {
                    return type
                }
            }
        }

        return when {
            pkg.contains("tencent.mm") || appLower.contains("微信") || appLower.contains("wechat") -> "wechat"
            pkg.contains("tencent.mobileqq") || appLower.contains("qq") -> "qq"
            pkg.contains("mms") || pkg.contains("sms") || appLower.contains("短信") -> "sms"
            pkg.contains("dialer") || pkg.contains("phone") || pkg.contains("incallui") || appLower.contains("电话") -> "call"
            pkg.contains("alipay") || appLower.contains("支付宝") -> "alipay"
            pkg.contains("taobao") || pkg.contains("tmall") || appLower.contains("淘宝") || appLower.contains("天猫") -> "taobao"
            pkg.contains("jd") || appLower.contains("京东") -> "jd"
            pkg.contains("weibo") || appLower.contains("微博") -> "weibo"
            pkg.contains("douyin") || appLower.contains("抖音") -> "douyin"
            pkg.contains("bilibili") || appLower.contains("哔哩哔哩") || appLower.contains("b站") -> "bilibili"
            pkg.contains("netease.cloudmusic") || pkg.contains("qqmusic") -> "music"
            pkg.contains("baidu.netdisk") || appLower.contains("百度网盘") -> "netdisk"
            pkg.contains("xingin") || pkg.contains("xhs") || appLower.contains("小红书") -> "xiaohongshu"
            pkg.contains("zhihu") || appLower.contains("知乎") -> "zhihu"
            pkg.contains("meituan") || pkg.contains("dianping") || pkg.contains("sankuai") ||
                    appLower.contains("美团") || appLower.contains("大众点评") -> "meituan"
            pkg.contains("ele") || appLower.contains("饿了么") -> "eleme"
            pkg.contains("pinduoduo") || appLower.contains("拼多多") -> "pinduoduo"
            pkg.contains("kuaishou") || appLower.contains("快手") -> "kuaishou"
            pkg.contains("android.systemui") -> "system"
            pkg.contains("miui") && (pkg.contains("home") || pkg.contains("security") || pkg.contains("settings")) -> "system"
            pkg.contains("com.android.settings") -> "system"
            pkg.contains("com.android.systemui") -> "system"
            pkg.contains("xiaomi") && pkg.contains("xmsf") -> "system"
            pkg.contains("huawei.android.push") -> "system"
            pkg.contains("vivo") && pkg.contains("push") -> "system"
            pkg.contains("fcm") || pkg.contains("google.android.gms") -> "system"
            else -> "other"
        }
    }

    private fun shouldNotify(
        packageName: String,
        title: String,
        content: String,
        subText: String
    ): Boolean {
        val fullText = "$title $content $subText".lowercase()

        if (whitelistKeywords.isNotEmpty()) {
            for (keyword in whitelistKeywords) {
                if (keyword.isNotEmpty() && fullText.contains(keyword.lowercase())) {
                    return true
                }
            }
        }

        if (enabledPackages.isNotEmpty() && !enabledPackages.contains(packageName)) {
            return false
        }

        if (blacklistKeywords.isNotEmpty()) {
            for (keyword in blacklistKeywords) {
                if (keyword.isNotEmpty() && fullText.contains(keyword.lowercase())) {
                    return false
                }
            }
        }

        return true
    }

    private fun registerBatteryReceiver() {
        try {
            val filter = IntentFilter().apply {
                addAction(Intent.ACTION_BATTERY_CHANGED)
            }
            registerReceiver(batteryReceiver, filter)
            Log.d(TAG, "Battery receiver registered")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to register battery receiver", e)
        }
    }

    private fun unregisterBatteryReceiver() {
        try {
            unregisterReceiver(batteryReceiver)
            Log.d(TAG, "Battery receiver unregistered")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to unregister battery receiver", e)
        }
    }

    private fun handleBatteryChanged(intent: Intent) {
        try {
            val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
            val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)

            if (level == -1 || scale == -1) return

            val batteryPct = (level * 100 / scale).coerceIn(0, 100)
            val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                    status == BatteryManager.BATTERY_STATUS_FULL

            val batteryNotifyEnabled = prefs.getBoolean("flutter.battery_notify_enabled", true)
            val rules = loadBatteryRules()

            if (!batteryNotifyEnabled) {
                lastBatteryLevel = batteryPct
                lastIsCharging = isCharging
                return
            }

            if (lastBatteryLevel == -1) {
                lastBatteryLevel = batteryPct
                lastIsCharging = isCharging
                for (rule in rules) {
                    val id = rule.id
                    when (rule.type) {
                        "level_above" -> {
                            if (batteryPct >= rule.value) triggeredLevelRules.add(id)
                        }
                        "level_below" -> {
                            if (batteryPct < rule.value) triggeredLevelRules.add(id)
                        }
                        "level_equals" -> {
                            if (batteryPct == rule.value) triggeredLevelRules.add(id)
                        }
                    }
                }
                return
            }

            for (rule in rules) {
                if (!rule.enabled) continue
                when (rule.type) {
                    "charging" -> {
                        if (isCharging && !lastIsCharging) {
                            sendBatteryNotification(
                                type = "battery_charging",
                                title = rule.title.ifEmpty { "充电中" },
                                content = "当前电量：${batteryPct}%",
                                appName = "电池监控"
                            )
                        }
                    }
                    "discharging" -> {
                        if (!isCharging && lastIsCharging) {
                            sendBatteryNotification(
                                type = "battery_discharging",
                                title = rule.title.ifEmpty { "断开充电" },
                                content = "当前电量：${batteryPct}%",
                                appName = "电池监控"
                            )
                        }
                    }
                    "level_above" -> {
                        val wasAbove = triggeredLevelRules.contains(rule.id)
                        val isNowAbove = batteryPct >= rule.value
                        if (isNowAbove && !wasAbove) {
                            sendBatteryNotification(
                                type = "battery_level_above_${rule.value}",
                                title = rule.title.ifEmpty { "电量达到${rule.value}%" },
                                content = "当前电量：${batteryPct}%",
                                appName = "电池监控"
                            )
                            triggeredLevelRules.add(rule.id)
                        } else if (!isNowAbove && wasAbove) {
                            triggeredLevelRules.remove(rule.id)
                        }
                    }
                    "level_below" -> {
                        val wasBelow = triggeredLevelRules.contains(rule.id)
                        val isNowBelow = batteryPct < rule.value
                        if (isNowBelow && !wasBelow && !isCharging) {
                            sendBatteryNotification(
                                type = "battery_level_below_${rule.value}",
                                title = rule.title.ifEmpty { "电量低于${rule.value}%" },
                                content = "当前电量：${batteryPct}%，请及时充电",
                                appName = "电池监控"
                            )
                            triggeredLevelRules.add(rule.id)
                        } else if (!isNowBelow && wasBelow) {
                            triggeredLevelRules.remove(rule.id)
                        }
                    }
                    "level_equals" -> {
                        val wasEqual = triggeredLevelRules.contains(rule.id)
                        val isNowEqual = batteryPct == rule.value
                        if (isNowEqual && !wasEqual) {
                            sendBatteryNotification(
                                type = "battery_level_equals_${rule.value}",
                                title = rule.title.ifEmpty { "电量等于${rule.value}%" },
                                content = "当前电量：${batteryPct}%",
                                appName = "电池监控"
                            )
                            triggeredLevelRules.add(rule.id)
                        } else if (!isNowEqual && wasEqual) {
                            triggeredLevelRules.remove(rule.id)
                        }
                    }
                }
            }

            lastBatteryLevel = batteryPct
            lastIsCharging = isCharging

            val batteryIntent = Intent(ACTION_BATTERY_CHANGED_NOTIFY).apply {
                setPackage(packageName)
                putExtra(EXTRA_BATTERY_LEVEL, batteryPct)
                putExtra(EXTRA_BATTERY_CHARGING, isCharging)
            }
            sendBroadcast(batteryIntent)
        } catch (e: Exception) {
            Log.e(TAG, "处理电量变化失败", e)
        }
    }

    data class BatteryRule(
        val id: String,
        val type: String,
        val value: Int,
        val enabled: Boolean,
        val title: String,
        val content: String
    )

    private fun loadBatteryRules(): List<BatteryRule> {
        val jsonStr = prefs.getString("flutter.battery_rules", null)
        if (jsonStr.isNullOrEmpty()) {
            return defaultBatteryRules()
        }
        return try {
            val list = org.json.JSONArray(jsonStr)
            val rules = mutableListOf<BatteryRule>()
            for (i in 0 until list.length()) {
                val obj = list.getJSONObject(i)
                rules.add(
                    BatteryRule(
                        id = obj.getString("id"),
                        type = obj.getString("type"),
                        value = obj.getInt("value"),
                        enabled = obj.getBoolean("enabled"),
                        title = obj.optString("title", ""),
                        content = obj.optString("content", "")
                    )
                )
            }
            rules
        } catch (e: Exception) {
            defaultBatteryRules()
        }
    }

    private fun defaultBatteryRules(): List<BatteryRule> {
        return listOf(
            BatteryRule("charging", "charging", 0, true, "开始充电", ""),
            BatteryRule("full", "level_above", 100, true, "电量充满", ""),
            BatteryRule("low30", "level_below", 30, true, "电量低于30%", ""),
            BatteryRule("low20", "level_below", 20, true, "电量低于20%", ""),
            BatteryRule("discharging", "discharging", 0, false, "断开充电", "")
        )
    }

    private fun sendBatteryNotification(
        type: String,
        title: String,
        content: String,
        appName: String
    ) {
        val timeStr = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
            .format(Date(System.currentTimeMillis()))

        val info = NotificationInfo(
            id = "battery_${System.currentTimeMillis()}",
            title = title,
            content = content,
            subText = "",
            packageName = "android.system.battery",
            appName = appName,
            postTime = System.currentTimeMillis(),
            time = timeStr,
            type = type,
            deviceName = deviceName
        )

        for (callback in listenerCallbacks) {
            try {
                callback(info)
            } catch (e: Exception) {
                Log.e(TAG, "Callback error", e)
            }
        }

        sendWebhook(info)
    }

    private fun acquireWakeLocks() {
        try {
            val powerManager = getSystemService(POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "NotificationMonitor::WakeLock"
            ).apply {
                setReferenceCounted(false)
                acquire()
            }
            Log.d(TAG, "WakeLock acquired")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to acquire WakeLock", e)
        }

        try {
            val wifiManager = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
            wifiLock = wifiManager.createWifiLock(
                WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                "NotificationMonitor::WifiLock"
            ).apply {
                setReferenceCounted(false)
                acquire()
            }
            Log.d(TAG, "WifiLock acquired")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to acquire WifiLock", e)
        }
    }

    private fun releaseWakeLocks() {
        try {
            wakeLock?.let {
                if (it.isHeld) it.release()
            }
            wakeLock = null
        } catch (e: Exception) {
            Log.e(TAG, "Failed to release WakeLock", e)
        }

        try {
            wifiLock?.let {
                if (it.isHeld) it.release()
            }
            wifiLock = null
        } catch (e: Exception) {
            Log.e(TAG, "Failed to release WifiLock", e)
        }
    }

    private fun startForegroundCompat() {
        try {
            createNotificationChannel()

            val notificationIntent = packageManager.getLaunchIntentForPackage(packageName)
            val pendingIntent = PendingIntent.getActivity(
                this, 0, notificationIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val notification = NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("通知监听服务")
                .setContentText("正在监听通知并推送")
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .setPriority(NotificationCompat.PRIORITY_MIN)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .build()

            startForeground(FOREGROUND_ID, notification)
            Log.i(TAG, "Foreground service started")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start foreground", e)
        }
    }

    private fun createNotificationChannel() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "通知监听服务",
                    NotificationManager.IMPORTANCE_MIN
                ).apply {
                    description = "后台通知监听前台服务"
                    setShowBadge(false)
                    enableVibration(false)
                    enableLights(false)
                }
                val notificationManager = getSystemService(NotificationManager::class.java)
                notificationManager.createNotificationChannel(channel)
                Log.i(TAG, "Notification channel created")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create notification channel", e)
        }
    }

    private fun sendWebhook(info: NotificationInfo) {
        try {
            val intent = Intent(MainActivity.ACTION_NOTIFICATION_RECEIVED).apply {
                setPackage(this@NotificationMonitorService.packageName)
                val json = JSONObject().apply {
                    put("id", info.id)
                    put("title", info.title)
                    put("content", info.content)
                    put("subText", info.subText)
                    put("packageName", info.packageName)
                    put("appName", info.appName)
                    put("postTime", info.postTime)
                    put("time", info.time)
                    put("type", info.type)
                    put("deviceName", info.deviceName)
                    put("timestamp", System.currentTimeMillis())
                }
                putExtra(MainActivity.EXTRA_NOTIFICATION_DATA, json.toString())
            }
            sendBroadcast(intent)
        } catch (e: Exception) {
            Log.e(TAG, "发送广播失败", e)
        }

        saveNotificationRecord(info)

        if (webhookUrls.isEmpty()) return

        for (url in webhookUrls) {
            if (url.isEmpty()) continue

            val webhookType = WebhookPayloadBuilder.detectType(url)
            val payload = WebhookPayloadBuilder.buildPayload(
                type = webhookType,
                title = info.title,
                content = info.content,
                appName = info.appName,
                packageName = info.packageName,
                time = info.time,
                deviceName = info.deviceName,
                notifyType = info.type
            )

            CoroutineScope(Dispatchers.IO).launch {
                var retryCount = 0
                val maxRetries = 3

                while (retryCount < maxRetries) {
                    try {
                        val body = payload.toRequestBody("application/json; charset=utf-8".toMediaType())
                        val request = Request.Builder()
                            .url(url)
                            .post(body)
                            .addHeader("User-Agent", "NotificationMonitor/1.0")
                            .build()

                        okHttpClient.newCall(request).execute().use { response ->
                            if (response.isSuccessful) {
                                Log.d(TAG, "Webhook sent successfully to ${url.take(30)}... (attempt ${retryCount + 1})")
                                return@launch
                            } else {
                                val respBody = response.body?.string() ?: ""
                                Log.e(TAG, "Webhook failed for ${url.take(30)}...: ${response.code} - ${respBody.take(200)} (attempt ${retryCount + 1})")
                            }
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Webhook send error for ${url.take(30)}... (attempt ${retryCount + 1})", e)
                    }

                    retryCount++
                    if (retryCount < maxRetries) {
                        try {
                            Thread.sleep(2000L * retryCount)
                        } catch (_: InterruptedException) {}
                    }
                }
            }
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
    val deviceName: String
)
