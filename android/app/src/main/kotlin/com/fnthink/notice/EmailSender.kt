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
            val rawMsg = e.message ?: ""
            val msg = when {
                rawMsg.contains("530", ignoreCase = true) ->
                    "SMTP 认证失败(530)，请检查账号和授权码"
                rawMsg.contains("534", ignoreCase = true) || rawMsg.contains("535", ignoreCase = true) ->
                    "SMTP 认证失败，请检查账号和授权码是否正确"
                rawMsg.contains("550", ignoreCase = true) ->
                    "收件人地址被拒绝(550)，请检查收件邮箱地址"
                rawMsg.contains("553", ignoreCase = true) ->
                    "发件人地址被拒绝(553)，请检查发件邮箱"
                rawMsg.contains("554", ignoreCase = true) ->
                    "邮件被服务端拒绝(554)，可能触发反垃圾策略"
                rawMsg.contains("421", ignoreCase = true) ->
                    "SMTP 服务暂时不可用(421)，请稍后重试"
                rawMsg.contains("450", ignoreCase = true) ->
                    "收件人邮箱不存在或已停用(450)"
                rawMsg.contains("504", ignoreCase = true) ->
                    "SMTP 认证方式不支持(504)，请检查 SSL 开关设置"
                rawMsg.contains("Connection refused", ignoreCase = true) ->
                    "连接被拒绝，请检查 SMTP 地址和端口"
                rawMsg.contains("UnknownHost", ignoreCase = true) || rawMsg.contains("Unable to resolve host", ignoreCase = true) ->
                    "无法解析 SMTP 服务器地址，请检查域名是否正确"
                rawMsg.contains("connect", ignoreCase = true) && rawMsg.contains("timed out", ignoreCase = true) ->
                    "连接超时，请检查网络或防火墙设置"
                else -> "邮件发送失败：${rawMsg.take(80)}"
            }
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
