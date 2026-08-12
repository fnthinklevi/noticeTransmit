package com.fnthink.notice

import android.content.Context
import android.content.Intent

/**
 * 送达结果统一回传 Flutter。
 *
 * 链路：ACTION_DELIVERY_RESULT 广播 → MainActivity.deliveryReceiver → onDeliveryResult MethodChannel
 * 通知 / 短信 / 电话三条推送链路共用，保证首页推送记录逐条送达状态一致。
 */
object DeliveryNotifier {
    fun notify(
        context: Context,
        notificationId: String,
        type: WebhookPayloadBuilder.WebhookType,
        result: WebhookResponseParser.ParseResult
    ) {
        try {
            val intent = Intent(MainActivity.ACTION_DELIVERY_RESULT).apply {
                setPackage(context.packageName)
                putExtra("notification_id", notificationId)
                putExtra("webhook_type", type.name)
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
