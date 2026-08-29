package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * SmsDispatcher.extractCode 单元测试。
 *
 * extractCode 是纯函数（仅依赖 Regex，不触碰 Android 框架），
 * 可直接在 JVM 上运行，用于守住验证码提取的正确性与防误提取边界。
 */
class SmsDispatcherTest {

    @Test
    fun extractCode_chineseWithColon() {
        assertEquals("123456", SmsDispatcher.extractCode("您的验证码是：123456"))
    }

    @Test
    fun extractCode_chineseNoSeparator() {
        assertEquals("8888", SmsDispatcher.extractCode("【腾讯】验证码8888，5分钟内有效"))
    }

    @Test
    fun extractCode_english() {
        assertEquals("123456", SmsDispatcher.extractCode("Your verification code is 123456"))
    }

    @Test
    fun extractCode_numberBeforeKeyword() {
        assertEquals("123456", SmsDispatcher.extractCode("123456 是您的验证码"))
    }

    @Test
    fun extractCode_withSpacesAroundDigits() {
        assertEquals("9012", SmsDispatcher.extractCode("验证码 9012，请勿泄露"))
    }

    @Test
    fun extractCode_ignoresPhoneNumber() {
        // 手机号共 11 位且后随数字，码位是 6 位时右侧断言失败，不应被截断当作验证码
        assertNull(SmsDispatcher.extractCode("验证码已发送至手机13800138000"))
    }

    @Test
    fun extractCode_returnsNullWithoutKeyword() {
        assertNull(SmsDispatcher.extractCode("今天天气不错"))
        assertNull(SmsDispatcher.extractCode("您的订单金额 12345 元"))
    }

    @Test
    fun extractCode_returnsNullForBlank() {
        assertNull(SmsDispatcher.extractCode(""))
        assertNull(SmsDispatcher.extractCode("   "))
    }
}
