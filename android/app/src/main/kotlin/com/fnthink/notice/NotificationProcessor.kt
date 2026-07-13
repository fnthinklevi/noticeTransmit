package com.fnthink.notice

import android.content.Context
import android.os.Build
import android.service.notification.StatusBarNotification
import android.util.Log
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class NotificationProcessor(private val context: Context) {
    companion object {
        private const val TAG = "NotificationProcessor"
        private const val MAX_NOTIFIED_KEYS = 200
    }

    private val notifiedKeys = mutableSetOf<String>()
    private var hotfixAppNames: Map<String, String>? = null
    private var hotfixNotificationTypes: Map<String, String>? = null

    fun setHotfixConfig(appNames: Map<String, String>?, notificationTypes: Map<String, String>?) {
        hotfixAppNames = appNames
        hotfixNotificationTypes = notificationTypes
    }

    fun processNotification(sbn: StatusBarNotification): NotificationInfo? {
        val notification = sbn.notification ?: return null
        val packageName = sbn.packageName
        val notificationId = sbn.id

        if (packageName == context.packageName) return null

        val isOngoing = (notification.flags and android.app.Notification.FLAG_ONGOING_EVENT) != 0
        val dedupKey = "$packageName:$notificationId"

        if (isOngoing && notifiedKeys.contains(dedupKey)) {
            return null
        }

        if (isOngoing) {
            notifiedKeys.add(dedupKey)
            if (notifiedKeys.size > MAX_NOTIFIED_KEYS) {
                notifiedKeys.clear()
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
            resolveRealAppName(sbn, baseAppName, title, content, subText)
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
        blacklistKeywords: List<String>
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

    private fun resolveRealAppName(
        sbn: StatusBarNotification,
        baseName: String,
        title: String,
        content: String,
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
}