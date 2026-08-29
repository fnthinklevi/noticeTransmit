package com.fnthink.notice

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.telephony.SmsMessage
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class SmsReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "SmsReceiver"
        private const val SMS_RECEIVED = "android.provider.Telephony.SMS_RECEIVED"
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        context ?: return
        intent ?: return
        if (intent.action != SMS_RECEIVED) return

        // goAsync：onReceive 返回后进程优先级骤降、随时可能被回收，
        // 而 Webhook 是异步请求，必须用 PendingResult 延长进程生命周期到发送完成。
        val pendingResult = goAsync()
        CoroutineScope(Dispatchers.IO).launch {
            try {
                handleSmsIntent(context, intent)
            } catch (e: Exception) {
                Log.e(TAG, "处理短信失败", e)
            } finally {
                try {
                    pendingResult.finish()
                } catch (_: Exception) {
                }
            }
        }
    }

    private fun handleSmsIntent(context: Context, intent: Intent) {
        val bundle = intent.extras
        if (bundle == null) {
            Log.w(TAG, "SMS_RECEIVED 缺少 extras，丢弃")
            return
        }
        // 个别 ROM 下 extras 类型可能与预期不符，用安全强转避免整条短信丢失
        val pdus = bundle.get("pdus") as? Array<*>
        if (pdus == null || pdus.isEmpty()) {
            Log.w(TAG, "SMS_RECEIVED pdus 为空，丢弃")
            return
        }
        val format = bundle.getString("format")

        var sender = ""
        var timestamp = 0L
        val body = StringBuilder()

        for (pdu in pdus) {
            // 单个分段解析失败不应连累其余分段（长短信按多段投递）
            try {
                val bytes = pdu as? ByteArray ?: continue
                val sms = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    SmsMessage.createFromPdu(bytes, format)
                } else {
                    @Suppress("DEPRECATION")
                    SmsMessage.createFromPdu(bytes)
                }
                if (sender.isEmpty()) {
                    sender = sms.originatingAddress ?: I18n.unknownSender()
                    timestamp = sms.timestampMillis
                }
                val text = sms.messageBody
                if (!text.isNullOrEmpty()) {
                    body.append(text)
                } else {
                    // 数据短信 / WAP Push：正文不在 messageBody，回退读用户数据区。
                    // 部分端口验证码走这类通道，此前会被判为空而整条丢弃。
                    decodeUserData(sms.userData)?.let { body.append(it) }
                }
            } catch (e: Exception) {
                Log.w(TAG, "解析单个 pdu 失败，跳过该分段: ${e.message}")
            }
        }

        val message = body.toString()
        if (message.isBlank()) {
            Log.w(TAG, "短信正文为空（特殊格式且无法解码），丢弃 sender=$sender")
            return
        }
        if (timestamp == 0L) timestamp = System.currentTimeMillis()

        val simInfo = SimInfoHelper.getSimInfoFromIntent(context, intent)?.displayLabel
        SmsDispatcher.handle(
            context = context,
            sender = sender,
            message = message,
            timestamp = timestamp,
            simInfo = simInfo,
            source = "broadcast"
        )
    }

    /**
     * 数据短信用户数据区解码：优先 UTF-8；出现替换字符说明非文本负载，
     * 退化为十六进制摘要，保证此类短信不会因正文为空被静默丢弃。
     */
    private fun decodeUserData(data: ByteArray?): String? {
        if (data == null || data.isEmpty()) return null
        return try {
            val text = String(data, Charsets.UTF_8)
            if (text.contains('\uFFFD')) {
                // Byte 有符号，需掩成无符号再格式化，否则负数会输出错误字节
                data.joinToString("") { "%02X".format(it.toInt() and 0xFF) }.take(200)
            } else {
                text
            }
        } catch (e: Exception) {
            Log.w(TAG, "数据短信解码失败: ${e.message}")
            null
        }
    }
}
