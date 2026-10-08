package com.fnthink.notice

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * T115 护栏②的**判据**本身（认证类失败的分型）。
 *
 * 为什么必须在原生这一侧做行为测试：Dart 的探测调度只看得到回包里那个 `authFailure` 布尔，
 * 而这个布尔来自 `EmailSender.isAuthFailure`。它判错的方向不是"探测不到"，是
 * **该挡的时候没挡**（授权码错着被频繁前后台反复送去认证 → 厂商临时封禁）或
 * **不该挡的时候挡了**（连不上也要等两小时才能再验一次）。两种都没有可见的报错，
 * 所以只能在这里钉住分类本身。
 */
class EmailSenderAuthFailureTest {

    @Test
    fun `认证异常算认证失败`() {
        assertTrue(
            "AuthenticationFailedException 就是「授权码错了」那一类",
            EmailSender.isAuthFailure(javax.mail.AuthenticationFailedException("535 Invalid user"))
        )
    }

    @Test
    fun `530 534 535 这三条 SMTP 应答算认证失败（与 classifyError 同源）`() {
        for (code in listOf("530", "534", "535")) {
            assertTrue(
                "$code 是认证被拒，厂商按连续失败计",
                EmailSender.isAuthFailure(
                    javax.mail.MessagingException("Could not connect to SMTP server: $code auth failed")
                )
            )
        }
    }

    @Test
    fun `连不上 超时 解析失败都不算认证失败`() {
        // 这几类没有封禁风险：把它们也挡进冷却，用户修好网络后要空等两小时才能再验一次。
        assertFalse(
            "连接被拒不是认证失败",
            EmailSender.isAuthFailure(java.net.ConnectException("Connection refused"))
        )
        assertFalse(
            "超时不是认证失败",
            EmailSender.isAuthFailure(java.net.SocketTimeoutException("read timed out"))
        )
        assertFalse(
            "域名解析失败不是认证失败",
            EmailSender.isAuthFailure(java.net.UnknownHostException("no such host"))
        )
        assertFalse(
            "SSL 握手失败不是认证失败",
            EmailSender.isAuthFailure(
                javax.net.ssl.SSLHandshakeException("certificate rejected")
            )
        )
        assertFalse(
            "普通 MessagingException（没有那几个应答码）不算认证失败",
            EmailSender.isAuthFailure(javax.mail.MessagingException("421 service busy"))
        )
    }

    @Test
    fun `认证失败优先于其它分类：AuthenticationFailedException 也是 MessagingException 的子类`() {
        // `when` 的分支顺序在这里是**语义**：把 `is MessagingException` 那臂放到最前面，
        // AuthenticationFailedException 仍然会被判成认证失败（它带的消息通常不含数字码），
        // 于是"535 Invalid user"这类反而漏挡 —— 这条用例把顺序钉住。
        val e = javax.mail.AuthenticationFailedException("Invalid credentials")
        assertTrue(
            "它确实是 MessagingException 的子类（所以分支顺序才有意义）",
            e is javax.mail.MessagingException
        )
        assertTrue("而判据给的是认证失败", EmailSender.isAuthFailure(e))
    }
}
