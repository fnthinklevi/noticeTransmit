package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 6e 邮件探测的会话口径（JVM）。
 *
 * `EmailSender.verifyConnection` 之所以敢说"探测通过 ≈ 配置可用"，前提是它和实发
 * 用的是**同一份** SMTP 会话属性：SSL/STARTTLS 一旦分叉，就会出现"探测说通、真发被拒"
 * （或反之），而这种分裂在界面上只是徽标与实收不一致，没有任何报错。
 * 端口与 SSL 的组合（465 直连 / 587 STARTTLS）是邮件通道最常见的配错点，
 * 因此这里把两种形状的属性逐项钉死，而不是只断言"两个函数都调用了 sessionFor"。
 */
class EmailSenderSessionTest {

    private fun config(useSSL: Boolean) = EmailSender.EmailConfig(
        smtpHost = "smtp.example.com",
        smtpPort = if (useSSL) 465 else 587,
        username = "alert@example.com",
        password = "auth-code",
        fromEmail = "alert@example.com",
        toEmails = listOf("oncall@example.com"),
        useSSL = useSSL,
    )

    @Test
    fun `SSL 直连走 ssl-enable 与显式 socketFactory，不开 STARTTLS`() {
        val session = EmailSender.sessionFor(config(useSSL = true))
        assertEquals("smtp.example.com", session.getProperty("mail.smtp.host"))
        assertEquals("465", session.getProperty("mail.smtp.port"))
        assertEquals("true", session.getProperty("mail.smtp.auth"))
        assertEquals("true", session.getProperty("mail.smtp.ssl.enable"))
        assertEquals("465", session.getProperty("mail.smtp.socketFactory.port"))
        assertEquals(
            "javax.net.ssl.SSLSocketFactory",
            session.getProperty("mail.smtp.socketFactory.class")
        )
        // 465 上再开 STARTTLS 会让部分服务商直接断连
        assertNull(session.getProperty("mail.smtp.starttls.enable"))
    }

    @Test
    fun `非 SSL 走 STARTTLS，不开 ssl-enable`() {
        val session = EmailSender.sessionFor(config(useSSL = false))
        assertEquals("587", session.getProperty("mail.smtp.port"))
        assertEquals("true", session.getProperty("mail.smtp.starttls.enable"))
        assertNull(session.getProperty("mail.smtp.ssl.enable"))
        assertNull(session.getProperty("mail.smtp.socketFactory.class"))
    }

    @Test
    fun `三档超时都是 15s（探测必须会结束，不能靠调用方掐表）`() {
        val session = EmailSender.sessionFor(config(useSSL = true))
        for (key in listOf(
            "mail.smtp.connectiontimeout",
            "mail.smtp.timeout",
            "mail.smtp.writetimeout"
        )) {
            assertEquals("$key 缺失或改了值", "15000", session.getProperty(key))
        }
    }

    /** 会话属性只允许有一处构造点：出现第二份 = 探测与实发开始各说各话。 */
    @Test
    fun `smtp 属性在 EmailSender 里只有 sessionFor 一处`() {
        val src = stripComments(
            java.io.File("src/main/kotlin/com/fnthink/notice/EmailSender.kt").readText()
        )
        val sites = Regex("\"mail\\.smtp\\.[A-Za-z.]+\"").findAll(src).count()
        assertEquals(
            "mail.smtp.* 属性赋值处必须恰好是 sessionFor 里那 10 处（多一处 = 第二份会话口径，" +
                "探测与实发会各说各话；少一处 = 本测试钉的属性已经不成立，改测试要留理由）",
            10,
            sites
        )
        assertTrue(
            "sendEmail 必须复用 sessionFor（否则本文件钉的属性与实发无关）",
            Regex("fun sendEmail[\\s\\S]{0,200}?sessionFor\\(").containsMatchIn(src)
        )
        assertTrue(
            "verifyConnection 也必须复用 sessionFor",
            Regex("fun verifyConnection[\\s\\S]{0,400}?sessionFor\\(").containsMatchIn(src)
        )
    }
}
