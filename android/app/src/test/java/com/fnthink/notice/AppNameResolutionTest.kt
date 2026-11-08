package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 2026-11-08 真机反馈：魅族推送的支付宝通知显示的是包名而不是「支付宝」。
 *
 * 两处根因都在这里锁住：渠道 ID 里的原始包名被小写化（PackageManager 按包名精确匹配，
 * 查不到就回落成包名）；友好名映射把含大写的字面量与小写串比（永不命中）。
 */
class AppNameResolutionTest {

    @Test
    fun meizuChannel_preservesPackageCase() {
        val candidates = AppNameResolution.channelPackageCandidates(
            "mzpush_oripacname_com.eg.android.AlipayGphone",
        )
        assertEquals("com.eg.android.AlipayGphone", candidates.first())
        assertTrue(
            "候选里不允许出现小写化包名（查不到会回落成包名）",
            candidates.none { it == "com.eg.android.alipaygphone" },
        )
    }

    @Test
    fun genericChannel_preservesPackageCase() {
        val candidates = AppNameResolution.channelPackageCandidates(
            "chat_com.Example.MixedCase",
        )
        assertTrue(candidates.contains("com.Example.MixedCase"))
    }

    @Test
    fun friendlyName_alipayIsCaseInsensitive() {
        assertEquals("支付宝", AppNameResolution.friendlyAppName("com.eg.android.alipaygphone"))
        assertEquals("支付宝", AppNameResolution.friendlyAppName("com.eg.android.AlipayGphone"))
    }

    @Test
    fun friendlyName_existingMappingsUnchanged() {
        assertEquals("微信", AppNameResolution.friendlyAppName("com.tencent.mm"))
        assertEquals("魅族推送", AppNameResolution.friendlyAppName("com.meizu.cloud.pushsdk"))
        assertEquals("短信", AppNameResolution.friendlyAppName("com.android.mms"))
    }

    @Test
    fun friendlyName_unknownPackageFallsBackToItself() {
        assertEquals("com.example.unknown", AppNameResolution.friendlyAppName("com.example.unknown"))
    }
}
