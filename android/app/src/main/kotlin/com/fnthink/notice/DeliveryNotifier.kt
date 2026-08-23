package com.fnthink.notice

import android.content.Context
import android.content.Intent

/**
 * 送达结果统一回传 Flutter。
 *
 * 链路：ACTION_DELIVERY_RESULT 广播 → MainActivity.deliveryReceiver → onDeliveryResult MethodChannel
 * 通知 / 短信 / 电话 / 邮件四条推送链路共用，保证首页推送记录逐条送达状态一致。
 */
object DeliveryNotifier {
    fun notify(
        context: Context,
        notificationId: String,
        type: WebhookPayloadBuilder.WebhookType,
        result: WebhookResponseParser.ParseResult
    ) {
        notify(context, notificationId, type.name, result)
    }

    /**
     * 支持任意通道标识（如 "EMAIL"），邮件链路与 webhook 共用同一回传链路。
     */
    fun notify(
        context: Context,
        notificationId: String,
        type: String,
        result: WebhookResponseParser.ParseResult
    ) {
        try {
            // 双写：广播走实时链路（MainActivity 存活时），持久化队列兜底
            // （Activity 被销毁期间的结果，Flutter 下次 loadRecords / resume 时 drain 补更新）
            DeliveryResultStore.push(
                context,
                notificationId,
                type,
                result.status.name,
                result.message,
                result.httpCode
            )
            val intent = Intent(MainActivity.ACTION_DELIVERY_RESULT).apply {
                setPackage(context.packageName)
                putExtra("notification_id", notificationId)
                putExtra("webhook_type", type)
                putExtra("status", result.status.name)
                putExtra("message", result.message)
                putExtra("http_code", result.httpCode)
            }
            context.sendBroadcast(intent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
