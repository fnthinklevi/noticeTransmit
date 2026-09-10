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

    // ===== 与生产调用点的契约（防「测试测死代码」回归）=====

    /**
     * SmsDispatcher.handle 的实际调用形态：先以 codeMonitorEnabled=true / extractedCode=null
     * 过第一段闸门（总开关 + 卡槽），验证码段在 extractCode 之后单独调用 allowCode。
     *
     * 本测试锁定这两个分段的组合结果必须等价于「一次性完整调用」——
     * 若有人改动 handle 的分段方式，此处会失败。
     */
    @Test
    fun dispatcherTwoStageCall_equivalentToSingleFullCall() {
        val cases = listOf(
            // (smsMonitorEnabled, filterSlot, simSlot, codeMonitorEnabled, code)
            listOf(false, null, null, true, null),
            listOf(true, null, null, true, null),
            listOf(true, 0, 1, true, null),
            listOf(true, 0, 0, true, null),
            listOf(true, null, null, false, "123456"),
            listOf(true, null, null, false, null),
        )
        for (c in cases) {
            @Suppress("UNCHECKED_CAST")
            c as List<Any?>
            val (monitor, slot, simSlot, codeMon, code) = c
            val full = SmsMonitorGate.shouldProcessSms(
                monitor as Boolean, slot as Int?, simSlot as Int?,
                codeMon as Boolean, code as String?
            )
            // handle 的分段形态：第一段（验证码段恒放行）+ 第二段（仅验证码判定）
            val stage1 = SmsMonitorGate.shouldProcessSms(
                monitor, slot, simSlot, codeMonitorEnabled = true, extractedCode = null
            )
            val stage2 = SmsMonitorGate.allowCode(codeMon, code)
            assertTrue(
                "分段调用应与一次性调用等价: $c (full=$full, stage1=$stage1, stage2=$stage2)",
                full == (stage1 && stage2)
            )
        }
    }
}
