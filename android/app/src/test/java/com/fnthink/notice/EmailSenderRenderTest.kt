package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 邮件的「构造载荷」证据（T09 证据矩阵里 `email` 那一行的 payloadEvidence 指向本类）。
 *
 * 为什么单独一个类：`EmailSender` 过去只有"发信"那条路可测（要真 SMTP），主题/正文渲染
 * 三个函数都是 `private` ⇒ 邮件是唯一一类"界面上能填、原生真的会发，却零测试"的通道。
 * 这里钉的三件事各对应一类**改坏了没人报警**的缺陷：
 * 1. 变量名单（原生替换的键与 Dart 名单、界面提示必须同源，见 `template_vars_contract_test`）；
 * 2. `%subTextLine` 的"整行开关"语义（有副标题才留行，没有就连行删掉）；
 * 3. 留空时到底用哪份默认值（`DEFAULT_SUBJECT` / `DEFAULT_BODY_TEMPLATE` 与界面预置档位
 *    「默认」必须同源，跨语言那条由 Dart 守卫钉）。
 */
class EmailSenderRenderTest {

    private fun config(
        subject: String? = null,
        body: String? = null,
    ) = EmailSender.EmailConfig(
        id = "em-1",
        smtpHost = "smtp.example.com",
        smtpPort = 465,
        username = "alert@example.com",
        password = "code",
        fromEmail = "alert@example.com",
        toEmails = listOf("oncall@example.com"),
        useSSL = true,
        subjectTemplate = subject,
        bodyTemplate = body,
    )

    private fun info(
        appName: String = "示例应用",
        title: String = "标题文本",
        content: String = "正文文本",
        subText: String = "",
        packageName: String = "com.example.app",
        deviceName: String = "测试机",
        time: String = "2026-09-25 10:00:00",
        type: String = "notification",
    ) = NotificationInfo(
        id = "n-1",
        title = title,
        content = content,
        subText = subText,
        packageName = packageName,
        appName = appName,
        postTime = 1767223200000L,
        time = time,
        type = type,
        deviceName = deviceName,
    )

    @Test
    fun blankSubjectUsesTheRuntimeDefault() {
        val out = EmailSender.buildSubject(config(), info())
        assertEquals("🔔 示例应用 — 标题文本", out)
        // 常量与界面预置档位同源；改这里必须同步 ARB（Dart 守卫会红），别只改一边
        assertEquals("🔔 %appName% — %title%", EmailSender.DEFAULT_SUBJECT)
    }

    @Test
    fun subjectTemplateSubstitutesEveryEmailVariable() {
        val template =
            "%appName%|%title%|%content%|%subText%|%packageName%|%deviceName%|" +
                "%time%|%postTime%|%type%|%date%|%datetime%"
        val out = EmailSender.buildSubject(
            config(subject = template),
            info(subText = "副标题文本"),
        )
        assertFalse("留了未替换的占位符：$out", out.contains("%"))
        assertTrue(out.contains("示例应用"))
        assertTrue(out.contains("副标题文本"))
        assertTrue(out.contains("1767223200000"))
        // %date% / %datetime% 取当下，只能验形状（不能钉死数值，否则跨时区/跨天必红）
        assertTrue(
            "date/datetime 没有渲染成日期：$out",
            Regex("""\d{4}-\d{2}-\d{2}""").containsMatchIn(out),
        )
    }

    @Test
    fun subTextLineIsAnAllOrNothingLine() {
        val with = EmailSender.buildEmailBody(
            config(),
            info(subText = "二楼的短信"),
        )
        val without = EmailSender.buildEmailBody(config(), info())

        assertTrue("有副标题时没画出副标题行：$with", with.contains("副标题：二楼的短信"))
        assertFalse("没有副标题却留下占位符：$without", without.contains("subTextLine"))
        assertFalse(
            "没有副标题却画出一行假的「副标题：」：$without",
            without.contains("副标题："),
        )
        // 占位符那一行在无副标题时是**整行删掉**。两种形状的行数差写死在这里：
        // 动这条语义（改成留空行、或改成整段前缀拼接）的人会看见它在动。
        assertEquals(without.lines().size + 2, with.lines().size)
    }

    @Test
    fun blankBodyTemplateFallsBackToTheDefaultBody() {
        val default = EmailSender.buildEmailBody(config(), info())
        val blank = EmailSender.buildEmailBody(config(body = "   "), info())
        assertEquals(
            "正文模板全是空白时必须退回默认正文（ifBlank 那条），否则发出去的是空信",
            default,
            blank,
        )
        assertTrue(default.startsWith("【通知转发】"))
        assertTrue(default.contains("--- 由 NoticeTransmit 自动发送 ---"))
        assertFalse(default.contains("%"))
    }

    @Test
    fun customBodyTemplateIsHonoredVerbatimApartFromVariables() {
        val out = EmailSender.buildEmailBody(
            config(body = "自定义：%content% / %deviceName%"),
            info(content = "内容", deviceName = "楼上的手机"),
        )
        assertEquals("自定义：内容 / 楼上的手机", out)
    }

    @Test
    fun unknownVariableStaysInTextThisIsExistingBehaviour() {
        // 记录既成事实：原生不认的变量**原样留在正文里**（这就是为什么界面只列
        // `emailTemplateVars` 那 11 个，且 `template_vars_contract_test` 双向核对）。
        // 谁改成"未知变量替换成空串"，这里会红 —— 那是另一种语义，要连同提示一起定。
        val out = EmailSender.applyTemplate("编号：%orderId%", info())
        assertEquals("编号：%orderId%", out)
    }
}
