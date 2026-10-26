package com.fnthink.notice

/**
 * T205：来电与短信两条链共用的放行判据（纯函数，JVM 可测）。
 *
 * 只有一个作者：`allowChain` 决定这两条链在监听关闭时是否还能走；
 * `allowSms` 再把短信自己的子开关/卡槽/验证码并进去。来电链没有这些子开关，
 * 只读 `allowChain`。
 *
 * 三句话：
 *  - 监听开着 ⇒ 与今天完全一样（零行为变化）；
 *  - 监听关掉、独立开关开着 ⇒ 只有电话/短信继续走，通知管道仍被服务那道闸挡住；
 *  - 两个都关 ⇒ 两条链都不发、也不落历史。
 */
object CallSmsForwardingGate {

    fun allowChain(
        monitoringEnabled: Boolean,
        callSmsForwarding: Boolean,
    ): Boolean = monitoringEnabled || callSmsForwarding

    /**
     * 短信的合成式：`(monitoringEnabled || callSmsForwarding) && smsMonitorEnabled`
     * 再把卡槽与验证码子闸并进来。新开关**不许盖过** `smsMonitorEnabled` ——
     * 「监听关、只转电话」是合法的一格，「监听关、只转短信」也一样。
     */
    fun allowSms(
        monitoringEnabled: Boolean,
        callSmsForwarding: Boolean,
        smsMonitorEnabled: Boolean,
        filterSlot: Int?,
        simSlot: Int?,
        codeMonitorEnabled: Boolean,
        extractedCode: String?,
    ): Boolean =
        allowChain(monitoringEnabled, callSmsForwarding) &&
            SmsMonitorGate.shouldProcessSms(
                smsMonitorEnabled = smsMonitorEnabled,
                filterSlot = filterSlot,
                simSlot = simSlot,
                codeMonitorEnabled = codeMonitorEnabled,
                extractedCode = extractedCode,
            )
}
