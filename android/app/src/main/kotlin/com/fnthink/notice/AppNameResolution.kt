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
        // 显示名走 I18n（英文模式下不能把「微信」「设置」原样画在历史/通知栏）。
        return when {
            pkg.startsWith("com.tencent.mm") -> I18n.msg("app.wechat")
            pkg.startsWith("com.tencent.mobileqq") -> I18n.msg("app.qq")
            pkg.startsWith("com.android.mms") || pkg.startsWith("com.google.android.apps.messaging") || pkg.contains("sms") || pkg.contains(".mms") -> I18n.msg("app.sms")
            pkg.startsWith("com.android.dialer") || pkg.startsWith("com.android.incallui") || pkg.startsWith("com.android.phone") || pkg.contains("incallui") || pkg.contains("dialer") -> I18n.msg("app.phone")
            pkg.startsWith("com.android.settings") -> I18n.msg("app.settings")
            pkg.startsWith("com.android.systemui") -> I18n.msg("app.systemui")
            pkg.startsWith("com.xiaomi.xmsf") -> I18n.msg("app.xiaomiPush")
            pkg.startsWith("com.huawei.android.push") -> I18n.msg("app.huaweiPush")
            pkg.startsWith("com.vivo.push") -> I18n.msg("app.vivoPush")
            pkg.startsWith("com.meizu.cloud") || pkg.startsWith("com.meizu.push") -> I18n.msg("app.meizuPush")
            pkg.startsWith("com.coloros.push") || pkg.startsWith("com.oppo.push") -> I18n.msg("app.oppoPush")
            pkg.startsWith("com.google.android.gms") || pkg.contains("fcm") -> I18n.msg("app.googleServices")
            pkg.startsWith("com.eg.android.alipaygphone") -> I18n.msg("app.alipay")
            pkg.startsWith("com.alibaba.android.rimet") -> I18n.msg("app.dingtalk")
            else -> packageName
        }
    }
}
