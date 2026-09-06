package com.fnthink.notice

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * SmsMonitorGate 纯逻辑单测：短信监听总开关 / 卡槽过滤 / 验证码开关的放行与拦截语义。
 */
class SmsMonitorGateTest {

    // ===== 短信监听总开关 =====

    @Test
    fun smsMonitorDisabled_blocksAll() {
        assertFalse(SmsMonitorGate.shouldProcessSms(false, null, null, true, null))
        assertFalse(SmsMonitorGate.shouldProcessSms(false, null, 0, true, null))
    }

    @Test
    fun defaultConfig_allows() {
        assertTrue(SmsMonitorGate.shouldProcessSms(true, null, null, true, null))
    }

    // ===== 卡槽过滤 =====

    @Test
    fun simFilter_matchingSim_allowed() {
        assertTrue(SmsMonitorGate.allowSim(0, 0))
        assertTrue(SmsMonitorGate.allowSim(1, 1))
    }

    @Test
    fun simFilter_otherSim_blocked() {
        assertFalse(SmsMonitorGate.allowSim(0, 1))
        assertFalse(SmsMonitorGate.allowSim(1, 0))
    }

    @Test
    fun simFilter_unknownSim_allowed() {
        // 通知兜底链路拿不到 SIM 信息：放行（产品确认的取舍）
        assertTrue(SmsMonitorGate.allowSim(0, null))
        assertTrue(SmsMonitorGate.allowSim(1, null))
    }

    @Test
    fun simFilter_allSlots_selected_allowed() {
        assertTrue(SmsMonitorGate.allowSim(null, 0))
        assertTrue(SmsMonitorGate.allowSim(null, 1))
        assertTrue(SmsMonitorGate.allowSim(null, null))
    }

    // ===== 验证码开关 =====

    @Test
    fun codeMonitorDisabled_verificationSms_blocked() {
        assertFalse(SmsMonitorGate.allowCode(false, "123456"))
    }

    @Test
    fun codeMonitorDisabled_nonCodeSms_allowed() {
        assertTrue(SmsMonitorGate.allowCode(false, null))
    }

    @Test
    fun codeMonitorEnabled_verificationSms_allowed() {
        assertTrue(SmsMonitorGate.allowCode(true, "123456"))
    }

    // ===== 组合语义 =====

    @Test
    fun combined_codeMonitorOff_blocksVerificationSmsOnly() {
        assertTrue(SmsMonitorGate.shouldProcessSms(true, null, 0, false, null))
        assertFalse(SmsMonitorGate.shouldProcessSms(true, null, 0, false, "123456"))
    }

    @Test
    fun combined_simFilterAndCodeMonitorOff() {
        // 卡2 的验证码短信（仅监听卡1 + 验证码关闭）→ 拦截
        assertFalse(SmsMonitorGate.shouldProcessSms(true, 0, 1, false, "123456"))
    }
}
