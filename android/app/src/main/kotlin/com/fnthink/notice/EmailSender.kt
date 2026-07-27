package com.fnthink.notice

import android.util.Log
import java.util.*
import javax.mail.*
import javax.mail.internet.*
import kotlinx.coroutines.*

/// SMTP 邮件发送器
///
/// 使用 javax.mail 实现，支持 SSL 直连(465) 和 STARTTLS(587)。
/// 在后台协程中异步发送，不阻塞通知处理流程。
object EmailSender {

    private const val TAG = "EmailSender"

    data class EmailConfig(
        val smtpHost: String,
        val smtpPort: Int,
        val username: String,
        val password: String,
        val fromEmail: String,
        val toEmails: List<String>,
        val useSSL: Boolean,
        val subjectTemplate: String? = null,
        val bodyTemplate: String? = null
    )

    /** 发送通知邮件 */
    fun sendNotification(
        configs: List<EmailConfig>,
        info: NotificationInfo,
        scope: CoroutineScope
    ) {
        for (config in configs) {
            scope.launch(Dispatchers.IO) {
                try {
                    val subject = buildSubject(config, info)
                    val body = buildEmailBody(config, info)
                    sendEmail(config, subject, body)
                    Log.d(TAG, "邮件发送成功 → ${config.toEmails.joinToString()}")
                } catch (e: Exception) {
                    Log.e(TAG, "邮件发送失败: ${e.message}", e)
                }
            }
        }
    }

    /** 发送测试邮件，返回 Pair(success, message) */
    fun sendTestEmail(config: EmailConfig): Pair<Boolean, String> {
        return try {
            val subject = "🧪 通知推送助手 — 邮件通道测试"
            val body = """
                这是一封测试邮件。
                发送时间：${Date()}
                SMTP 服务器：${config.smtpHost}:${config.smtpPort}
                发件人：${config.fromEmail}
                收件人：${config.toEmails.joinToString()}
            """.trimIndent()
            sendEmail(config, subject, body)
            Log.d(TAG, "测试邮件发送成功")
            Pair(true, "测试邮件发送成功")
        } catch (e: AuthenticationFailedException) {
            val msg = "认证失败，请检查账号和授权码是否正确"
            Log.e(TAG, msg, e)
            Pair(false, msg)
        } catch (e: javax.net.ssl.SSLHandshakeException) {
            val msg = "SSL 连接失败，请检查端口号或关闭 SSL 后重试"
            Log.e(TAG, msg, e)
            Pair(false, msg)
        } catch (e: java.net.ConnectException) {
            val msg = "无法连接服务器 ${config.smtpHost}:${config.smtpPort}，请检查地址和端口"
            Log.e(TAG, msg, e)
            Pair(false, msg)
        } catch (e: java.net.SocketTimeoutException) {
            val msg = "连接超时，请检查网络或防火墙设置"
            Log.e(TAG, msg, e)
            Pair(false, msg)
        } catch (e: javax.mail.SendFailedException) {
            val msg = "邮件发送被拒: ${e.message}"
            Log.e(TAG, msg, e)
            Pair(false, msg)
        } catch (e: javax.mail.MessagingException) {
            val msg = "邮件协议错误: ${e.message}"
            Log.e(TAG, msg, e)
            Pair(false, msg)
        } catch (e: Exception) {
            val msg = "发送失败: ${e.message}"
            Log.e(TAG, msg, e)
            Pair(false, msg)
        }
    }

    private fun sendEmail(config: EmailConfig, subject: String, body: String) {
        val props = Properties().apply {
            put("mail.smtp.host", config.smtpHost)
            put("mail.smtp.port", config.smtpPort.toString())
            put("mail.smtp.auth", "true")

            if (config.useSSL) {
                put("mail.smtp.ssl.enable", "true")
                put("mail.smtp.socketFactory.port", config.smtpPort.toString())
                put("mail.smtp.socketFactory.class", "javax.net.ssl.SSLSocketFactory")
            } else {
                put("mail.smtp.starttls.enable", "true")
            }

            put("mail.smtp.connectiontimeout", "15000")
            put("mail.smtp.timeout", "15000")
            put("mail.smtp.writetimeout", "15000")
        }

        val session = Session.getInstance(props, object : Authenticator() {
            override fun getPasswordAuthentication(): PasswordAuthentication {
                return PasswordAuthentication(config.username, config.password)
            }
        })

        val message = MimeMessage(session).apply {
            setFrom(InternetAddress(config.fromEmail))
            config.toEmails.forEach { recipient ->
                addRecipient(Message.RecipientType.TO, InternetAddress(recipient))
            }
            this.subject = subject
            setText(body, "UTF-8")
            setHeader("X-Mailer", "NoticeTransmit/1.0")
            setHeader("X-Priority", "3")
        }

        Transport.send(message)
    }

    /** 模板变量替换，支持主题模板与正文模板 */
    private fun applyTemplate(template: String, info: NotificationInfo): String {
        return template
            .replace("%appName%", info.appName)
            .replace("%title%", info.title)
            .replace("%content%", info.content)
            .replace("%subText%", info.subText)
            .replace("%packageName%", info.packageName)
            .replace("%deviceName%", info.deviceName)
            .replace("%time%", info.time)
            .replace("%postTime%", info.postTime.toString())
            .replace("%type%", info.type)
            .replace("%date%", java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.getDefault()).format(Date()))
            .replace("%datetime%", java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.getDefault()).format(Date()))
    }

    private fun buildSubject(config: EmailConfig, info: NotificationInfo): String {
        val defaultSubject = "🔔 %appName% — %title%"
        val template = config.subjectTemplate ?: defaultSubject
        return applyTemplate(template, info)
    }

    private fun buildEmailBody(config: EmailConfig, info: NotificationInfo): String {
        val template = config.bodyTemplate?.ifBlank { null } ?: """
【通知转发】

应用：%appName%
标题：%title%
内容：%content%
%subTextLine
包名：%packageName%
时间：%time%
设备：%deviceName%

--- 由 NoticeTransmit 自动发送 ---
        """.trimIndent()
        val body = applyTemplate(template, info)
        return if (info.subText.isNotEmpty()) {
            body.replace("%subTextLine", "副标题：${info.subText}\n")
        } else {
            body.lines().filter { !it.contains("%subTextLine") }.joinToString("\n")
        }
    }

    private fun List<String>.joinToString(): String = joinToString(", ")
}
