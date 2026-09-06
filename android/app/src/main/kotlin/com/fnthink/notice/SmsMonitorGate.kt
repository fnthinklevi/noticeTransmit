package com.fnthink.notice

/**
 * 短信/电话监听门控（纯逻辑，可单测：SmsMonitorGateTest）
 *
 * 三条短信链路（广播 / 短信库观察 / 通知兜底）在汇聚点 SmsDispatcher.handle 统一调用；
 * 电话链路在 PhoneCallReceiver 中仅使用卡槽过滤。所有配置实时读取，开关秒级生效。
 */
object SmsMonitorGate {

    /**
     * 短信是否放行。
     *
     * @param smsMonitorEnabled 用户配置的短信监听总开关（首页「监听短信」）
     * @param filterSlot 用户选择的监听卡槽；null=全部卡，0/1=仅卡1/卡2（slotIndex 0-based）
     * @param simSlot 本条短信识别出的卡槽；null=无法识别（通知兜底链路拿不到卡槽信息）
     * @param codeMonitorEnabled 用户配置的「监听验证码」开关
     * @param extractedCode 本条短信提取出的验证码；null=非验证码短信
     */
    fun shouldProcessSms(
        smsMonitorEnabled: Boolean,
        filterSlot: Int?,
        simSlot: Int?,
        codeMonitorEnabled: Boolean,
        extractedCode: String?
    ): Boolean =
        smsMonitorEnabled &&
            allowSim(filterSlot, simSlot) &&
            allowCode(codeMonitorEnabled, extractedCode)

    /**
     * 卡槽过滤：无法识别 SIM 时放行（通知兜底链路无卡槽信息，用户已知晓并确认该取舍）；
     * 识别出且不属于所选卡 → 拦截。
     */
    fun allowSim(filterSlot: Int?, simSlot: Int?): Boolean =
        filterSlot == null || simSlot == null || simSlot == filterSlot

    /** 验证码开关：关闭且本条短信识别为验证码短信 → 整条拦截 */
    fun allowCode(codeMonitorEnabled: Boolean, extractedCode: String?): Boolean =
        codeMonitorEnabled || extractedCode == null
}
