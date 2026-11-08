package com.fnthink.notice

/**
 * 通知「应用名」解析里的纯函数（不碰 PackageManager，可在 JVM 单测）。
 *
 * ⚠ 包名大小写敏感：`PackageManager.getApplicationInfo` 按原串精确匹配。厂商渠道 ID
 * 里的原始包名一旦被 `lowercase()`，就查不到安装记录（如魅族推送渠道携带的
 * `mzpush_oripacname_com.eg.android.AlipayGphone`），随后回落成包名本身——2026-11-08
 * 真机反馈「支付宝通知显示的是包名而不是应用名」即此。这里保留原始大小写；
 * 友好名映射则反过来：两边都归一成小写再比。
 */
internal object AppNameResolution {

    /**
     * 厂商 push 渠道 ID 里可能携带的原始包名候选（按优先级排序，保留原大小写）。
     * 调用方逐个用 PackageManager 解析，命中第一个能解析出应用名的候选即停。
     */
    fun channelPackageCandidates(channelId: String): List<String> {
        val lower = channelId.lowercase()
        val out = mutableListOf<String>()

        // 魅族：mzpush_oripacname_<原始包名>（包名本身可能含大写，必须从原串提取）
        Regex("(?i)mzpush_oripacname_(.+)").find(channelId)?.let {
            out += it.groupValues[1]
        }

        if (lower.contains("miui") || lower.contains("xmsf") ||
            lower.contains("hw") || lower.contains("hms")
        ) {
            Regex("(?i)[a-z]+\\.[a-z]+\\.[a-z]+").find(channelId)?.let {
                out += it.value
            }
        }

        Regex("(?i)[a-z]+\\.[a-z]+\\.[a-z.]+").findAll(channelId).forEach {
            if (it.value.length > 10 && it.value.contains(".")) {
                out += it.value
            }
        }

        return out.distinct()
    }

    /** 已知应用的友好名；入参大小写不敏感，未命中时原样返回入参。 */
    fun friendlyAppName(packageName: String): String {
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
            pkg.startsWith("com.eg.android.alipaygphone") -> "支付宝"
            pkg.startsWith("com.alibaba.android.rimet") -> "钉钉"
            else -> packageName
        }
    }
}
