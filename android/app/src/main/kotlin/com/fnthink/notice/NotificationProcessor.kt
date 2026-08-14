package com.fnthink.notice

import android.content.Context
import android.os.Build
import android.service.notification.StatusBarNotification
import android.util.Log
import java.text.SimpleDateFormat
import java.util.Collections
import java.util.Date
import java.util.Locale

class NotificationProcessor(private val context: Context) {
    companion object {
        private const val TAG = "NotificationProcessor"
        private const val MAX_NOTIFIED_KEYS = 200
    }

    private val notifiedKeys = Collections.synchronizedSet(LinkedHashSet<String>())

    fun processNotification(sbn: StatusBarNotification): NotificationInfo? {
        val notification = sbn.notification ?: return null
        val packageName = sbn.packageName
        val notificationId = sbn.id

        if (packageName == context.packageName) return null

        // 短信/电话应用由 SmsReceiver / PhoneCallReceiver 独占处理（携带 SIM 卡信息），
        // 通知栏监听跳过，避免同一事件产生两条记录（一条有 SIM、一条无 SIM）。
        if (isSmsPackage(packageName) || isCallPackage(packageName)) return null

        val isOngoing = (notification.flags and android.app.Notification.FLAG_ONGOING_EVENT) != 0
        val dedupKey = "$packageName:$notificationId"

        if (isOngoing && notifiedKeys.contains(dedupKey)) {
            return null
        }

        if (isOngoing) {
            notifiedKeys.remove(dedupKey)
            notifiedKeys.add(dedupKey)
            if (notifiedKeys.size > MAX_NOTIFIED_KEYS) {
                synchronized(notifiedKeys) {
                    val toRemove = notifiedKeys.size - MAX_NOTIFIED_KEYS + 50
                    val list = ArrayList(notifiedKeys)
                    for (i in 0 until toRemove) {
                        notifiedKeys.remove(list[i])
                    }
                }
            }
        }

        val extras = notification.extras
        val title = extras.getCharSequence(android.app.Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(android.app.Notification.EXTRA_TEXT)?.toString() ?: ""
        val bigText = extras.getCharSequence(android.app.Notification.EXTRA_BIG_TEXT)?.toString() ?: ""
        val subText = extras.getCharSequence(android.app.Notification.EXTRA_SUB_TEXT)?.toString() ?: ""
        val postTime = sbn.postTime

        val content = bigText.ifEmpty { text }
        if (title.isEmpty() && content.isEmpty()) return null

        val baseAppName = getAppNameByPackage(packageName)
        val isPushService = isVendorPushService(packageName)
        val resolvedAppName = if (isPushService) {
            resolveRealAppName(sbn, baseAppName, title, subText)
        } else {
            baseAppName
        }
        val appName = resolvedAppName
        val notifyType = detectNotificationType(packageName, appName, title, content)
        val timeStr = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
            .format(Date(postTime))

        return NotificationInfo(
            id = notificationId.toString(),
            title = title,
            content = content,
            subText = subText,
            packageName = packageName,
            appName = appName,
            postTime = postTime,
            time = timeStr,
            type = notifyType,
            deviceName = ""
        )
    }

    fun removeNotification(sbn: StatusBarNotification) {
        val dedupKey = "${sbn.packageName}:${sbn.id}"
        notifiedKeys.remove(dedupKey)
    }

    fun shouldNotify(
        packageName: String,
        title: String,
        content: String,
        subText: String,
        whitelistKeywords: List<String>,
        enabledPackages: Set<String>,
        blacklistKeywords: List<String>,
        filterMode: String = "allow"
    ): Boolean {
        // 委托给统一过滤引擎，与 SMS / Call 链路共用同一套规则
        // 修复点：黑名单优先级最高（原代码白名单命中后短路 return true，会跳过黑名单检查）
        return FilterEngine.shouldNotify(
            packageName = packageName,
            title = title,
            content = content,
            subText = subText,
            whitelistKeywords = whitelistKeywords,
            enabledPackages = enabledPackages,
            blacklistKeywords = blacklistKeywords,
            filterMode = filterMode,
            sourceType = "notification"
        )
    }

    private fun getAppNameByPackage(packageName: String): String {
        return try {
            val pm = context.packageManager
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
                friendlyName
            } else if (label.isNotEmpty() && label != packageName) {
                label
            } else {
                friendlyName
            }
        } catch (e: Exception) {
            getFriendlyAppName(packageName)
        }
    }

    private fun getFriendlyAppName(packageName: String): String {
        val pkg = packageName.lowercase()
        return when {
            pkg.startsWith("com.tencent.mm") -> "微信"
            pkg.startsWith("com.tencent.mobileqq") -> "QQ"
            pkg.startsWith("com.android.mms") || pkg.startsWith("com.google.android.apps.messaging") || pkg.contains("sms") || pkg.contains(".mms") -> "短信"
            pkg.startsWith("com.android.dialer") || pkg.startsWith("com.android.incallui") || pkg.startsWith("com.android.phone") || pkg.contains("incallui") || pkg.contains("dialer") -> "电话"
            pkg.startsWith("com.android.settings") -> "设置"
            pkg.startsWith("com.android.systemui") -> "系统界面"
            pkg.startsWith("com.xiaomi.xmsf") -> "小米推送"
            pkg.startsWith("com.huawei.android.push") -> "华为推送"
            pkg.startsWith("com.vivo.push") -> "vivo推送"
            pkg.startsWith("com.meizu.cloud") || pkg.startsWith("com.meizu.push") -> "魅族推送"
            pkg.startsWith("com.coloros.push") || pkg.startsWith("com.oppo.push") -> "OPPO推送"
            pkg.startsWith("com.google.android.gms") || pkg.contains("fcm") -> "Google服务"
            pkg.startsWith("com.eg.android.AlipayGphone") -> "支付宝"
            pkg.startsWith("com.alibaba.android.rimet") -> "钉钉"
            else -> packageName
        }
    }

    private fun isSmsPackage(packageName: String): Boolean {
        val pkg = packageName.lowercase()
        return pkg.startsWith("com.android.mms") ||
            pkg.startsWith("com.google.android.apps.messaging") ||
            pkg.startsWith("com.samsung.android.messaging") || // 三星短信
            pkg.startsWith("com.huawei.mms") || // 华为短信
            pkg.startsWith("com.huawei.android.mms") ||
            pkg.startsWith("com.vivo.mms") || // vivo 短信
            pkg.contains("sms") ||
            pkg.contains(".mms") // 兜底：各厂商短信应用
    }

    private fun isCallPackage(packageName: String): Boolean {
        val pkg = packageName.lowercase()
        return pkg.startsWith("com.android.dialer") ||
            pkg.startsWith("com.android.incallui") ||
            pkg.startsWith("com.android.phone") ||
            pkg.startsWith("com.google.android.dialer") || // Google 拨号器
            pkg.startsWith("com.samsung.android.dialer") || // 三星拨号器
            pkg.startsWith("com.samsung.android.incallui") || // 三星来电
            pkg.startsWith("com.huawei.contacts") || // 华为拨号/联系人
            pkg.startsWith("com.oplus.incallui") || pkg.startsWith("com.coloros.incallui") ||
            pkg.startsWith("com.bbk.incallui") || pkg.startsWith("com.vivo.incallui") ||
            pkg.contains("incallui") || // 兜底：各厂商来电界面
            pkg.contains("dialer") // 兜底：各厂商拨号器
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

    private fun resolveRealAppName(
        sbn: StatusBarNotification,
        baseName: String,
        title: String,
        subText: String
    ): String {
        val extras = sbn.notification?.extras ?: return baseName
        val pkg = sbn.packageName.lowercase()

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
                    return str
                }
            }
            if (value is String && value.isNotEmpty() && value.contains(".")) {
                val candidateAppName = getAppNameByPackage(value)
                if (candidateAppName != value && candidateAppName.isNotEmpty()) {
                    return candidateAppName
                }
            }
        }

        if (subText.isNotEmpty() && subText.length in 1..12) {
            val isAppName = !subText.contains("push", true) &&
                    !subText.contains("service", true) &&
                    !subText.contains("notification", true) &&
                    !subText.contains("条消息", true) &&
                    !subText.contains("新消息", true) &&
                    !subText.contains("通知", true)
            if (isAppName) {
                return subText
            }
        }

        val channelId = sbn.notification?.channelId
        if (!channelId.isNullOrEmpty()) {
            val channelLower = channelId.lowercase()

            val meizuMatch = Regex("mzpush_oripacname_(.+)").find(channelLower)
            if (meizuMatch != null) {
                val origPkg = meizuMatch.groupValues[1]
                return getAppNameByPackage(origPkg)
            }

            if (channelLower.contains("miui") || channelLower.contains("xmsf")) {
                val pkgMatch = Regex("([a-z]+\\.[a-z]+\\.[a-z]+)").find(channelLower)
                if (pkgMatch != null) {
                    val origPkg = pkgMatch.groupValues[1]
                    val candidate = getAppNameByPackage(origPkg)
                    if (candidate != origPkg && candidate.isNotEmpty()) {
                        return candidate
                    }
                }
            }

            if (channelLower.contains("hw") || channelLower.contains("hms")) {
                val pkgMatch = Regex("([a-z]+\\.[a-z]+\\.[a-z]+)").find(channelLower)
                if (pkgMatch != null) {
                    val origPkg = pkgMatch.groupValues[1]
                    val candidate = getAppNameByPackage(origPkg)
                    if (candidate != origPkg && candidate.isNotEmpty()) {
                        return candidate
                    }
                }
            }

            val pkgMatch = Regex("[a-z]+\\.[a-z]+\\.[a-z.]+").findAll(channelLower)
            for (match in pkgMatch) {
                val origPkg = match.value
                if (origPkg.length > 10 && origPkg.contains(".")) {
                    val candidate = getAppNameByPackage(origPkg)
                    if (candidate != origPkg && candidate.isNotEmpty()) {
                        return candidate
                    }
                }
            }
        }

        if (title.isNotEmpty()) {
            val bracketMatch = Regex("【([^】]+)】").find(title)
            if (bracketMatch != null) {
                val extracted = bracketMatch.groupValues[1]
                if (extracted.length in 1..12) {
                    return extracted
                }
            }
            val colonMatch = title.indexOf("：")
            if (colonMatch in 1..12) {
                val extracted = title.substring(0, colonMatch)
                if (extracted.isNotEmpty() && extracted.length <= 12) {
                    return extracted
                }
            }
        }

        val lowerBase = baseName.lowercase()
        if (lowerBase.contains("推送") || lowerBase.contains("push") || lowerBase.contains("服务") || lowerBase.contains("魅族")) {
            val firstWord = title.take(10)
            if (firstWord.isNotEmpty() && firstWord.length >= 2) {
                return firstWord
            }
        }

        return baseName
    }

    private fun detectNotificationType(packageName: String, appName: String, title: String, content: String): String {
        val pkg = packageName.lowercase()
        val appLower = appName.lowercase()
        val fullText = "$appName $title $content".lowercase()

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
}