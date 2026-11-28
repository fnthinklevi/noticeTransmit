package com.fnthink.notice

/**
 * 「这条通知该走短信/电话专用链路，还是普通通知链路」的**唯一判据**（P2-4）。
 *
 * 旧实现（2026-11-27 审计）用 `contains("sms")` / `contains(".mms")` /
 * `contains("dialer")` / `contains("incallui")` 判包名：名字里带 `sms` 的
 * 非短信应用（备份、营销、工具类）整包通知都被送进短信链路（要求标题+正文都非空，
 * 否则直接丢），界面上表现为"这个应用的通知一条都不来"。电话侧同理。
 *
 * 现在的判据顺序：
 *  1. **系统默认应用**（`Telephony.Sms.getDefaultSmsPackage` / `TelecomManager.defaultDialerPackage`）
 *     精确相等 —— 这是最可靠的一档，OEM 换什么包名都能认；
 *  2. **已知系统组件前缀**（只收系统短信/拨号/来电界面的包名，不做 contains）；
 *  3. 短信/电话包发的通知还要**类别对得上**：`CATEGORY_MESSAGE` / `CATEGORY_CALL`
 *     （null = 该应用没设类别，按"可能是"处理）。短信包发的"备份完成"（类别 PSTN/STATUS）
 *     因此走普通通知路径，不会被短信链路吞掉；
 *  4. 其余一律普通通知。
 *
 * 纯对象不碰 Android 运行时：`CATEGORY_MESSAGE` / `CATEGORY_CALL` 是 AOSP 的编译期
 * 常量，这里抄同一串并在用例里与 `Notification` 常量对账（见
 * `NotificationSourceClassifierTest`）。
 */
object NotificationSourceClassifier {
    /** 与 `android.app.Notification.CATEGORY_MESSAGE` 同值（AOSP "msg"）。 */
    const val CATEGORY_MESSAGE = "msg"

    /** 与 `android.app.Notification.CATEGORY_CALL` 同值（AOSP "call"）。 */
    const val CATEGORY_CALL = "call"

    enum class Kind { SMS, CALL, OTHER }

    /**
     * 已知系统短信应用的包名前缀（`startsWith`，不是 `contains`）。
     *
     * 只收"这个包就是系统短信"的那几家；各厂商定制短信若换了包名，靠默认短信应用
     * 那一档兜住 —— 那才是系统自己认的答案，比我们猜包名可靠。
     */
    private val SMS_PREFIXES = listOf(
        "com.android.mms",
        "com.android.messaging",
        "com.google.android.apps.messaging",
        "com.samsung.android.messaging",
        "com.huawei.mms",
        "com.huawei.android.mms",
        "com.vivo.mms",
    )

    /**
     * 已知系统拨号器/来电界面的包名前缀。
     *
     * `com.android.phone` 是电话进程（SIM 提示也从这来），所以它必须同时满足类别
     * 是 CALL 或 null 才跳过；别的一律普通通知。
     */
    private val CALL_PREFIXES = listOf(
        "com.android.dialer",
        "com.android.incallui",
        "com.android.phone",
        "com.google.android.dialer",
        "com.samsung.android.dialer",
        "com.samsung.android.incallui",
        "com.oplus.dialer",
        "com.oplus.incallui",
        "com.coloros.incallui",
        "com.bbk.incallui",
        "com.vivo.incallui",
        "com.huawei.contacts",
    )

    fun classify(
        packageName: String,
        category: String?,
        defaultSmsPackage: String,
        defaultDialerPackage: String,
    ): Kind {
        val pkg = packageName.trim().lowercase()
        if (pkg.isEmpty()) return Kind.OTHER
        val smsDefault = defaultSmsPackage.trim().lowercase()
        val dialDefault = defaultDialerPackage.trim().lowercase()
        val messageCategory = category == null || category == CATEGORY_MESSAGE
        val callCategory = category == null || category == CATEGORY_CALL

        val isSms = (smsDefault.isNotEmpty() && pkg == smsDefault) ||
            SMS_PREFIXES.any { pkg.startsWith(it) }
        if (isSms && messageCategory) return Kind.SMS

        val isCall = (dialDefault.isNotEmpty() && pkg == dialDefault) ||
            CALL_PREFIXES.any { pkg.startsWith(it) }
        if (isCall && callCategory) return Kind.CALL

        return Kind.OTHER
    }
}
