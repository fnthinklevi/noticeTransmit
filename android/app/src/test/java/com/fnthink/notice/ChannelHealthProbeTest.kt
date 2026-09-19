package com.fnthink.notice

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 通道健康探测 URL 校验单元测试（纯逻辑，JVM 直测）。
 *
 * probe() 本体走真实网络，不在 JVM 单测范围；
 * 此处守住 URL scheme 前置校验：仅 http/https 可探测。
 */
class ChannelHealthProbeTest {

    @Test
    fun isProbeableUrl_acceptsHttpAndHttps() {
        assertTrue(ChannelHealthProbe.isProbeableUrl("https://qyapi.weixin.qq.com"))
        assertTrue(ChannelHealthProbe.isProbeableUrl("http://192.168.1.10:8080/message"))
        assertTrue(ChannelHealthProbe.isProbeableUrl("https://ntfy.sh/mytopic"))
    }

    @Test
    fun isProbeableUrl_rejectsNonHttpSchemes() {
        assertFalse(ChannelHealthProbe.isProbeableUrl("ftp://example.com/file"))
        assertFalse(ChannelHealthProbe.isProbeableUrl("file:///etc/hosts"))
        assertFalse(ChannelHealthProbe.isProbeableUrl("javascript:alert(1)"))
    }

    @Test
    fun isProbeableUrl_rejectsEmptyAndMalformed() {
        assertFalse(ChannelHealthProbe.isProbeableUrl(""))
        assertFalse(ChannelHealthProbe.isProbeableUrl("   "))
        assertFalse(ChannelHealthProbe.isProbeableUrl("qyapi.weixin.qq.com"))
        assertFalse(ChannelHealthProbe.isProbeableUrl("not a url"))
    }
}
