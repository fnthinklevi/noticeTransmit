package com.fnthink.notice

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * 幻念推送的**收件显示**（T48 的前置）：把一条落在 `fnthink_messages` 里的消息显示成通知。
 *
 * 这台 App 此前没有"从 Dart 显示一条系统通知"的能力（原生唯一的 post 是前台服务自己那条常驻通知，
 * `DeliveryNotifier` 的 notify 是送达结果回传而不是系统通知）。收货链路已经把消息取回来并落库了，
 * 但用户看不见 —— 那等于"可以慢不能丢"只做到了一半。
 *
 * 三条写在代码旁边的取舍：
 *  ① **通知的身份是 `tag = messageId`，`id` 是一个固定常量**。Android 用 (package, tag, id) 三元组
 *    认一条通知。用 `messageId.hashCode()` 当 id 看着也行，但它会撞：撞上的两条**互相顶掉**，
 *    后到的那条把先到的从通知栏里抹掉，而用户以为没收到 —— 那是"静默丢"的一种新写法。
 *    tag 唯一 ⇒ 同一条重发是**替换**（不叠两条），不同条不会互相覆盖。
 *  ② 显示不了就说显示不了：通知权限被关、渠道被系统禁用 ⇒ 返回 false。调用方据此把 ack 的
 *    取值退回 `delivered`（"到我机器了"）而不是 `displayed`（"用户看得见"）—— 报后者等于
 *    替服务端宣布一条没发生的结论，而服务端收到 ack 就把正文删了。
 *  ③ 点通知只做一件事：把 App 带到前台，顺带一枚 `message_id` extra。
 *    ⚠ 今天 Dart 侧还没有读它的地方（收件页在 T44/T46 才落地），所以现在点开的表现就是"打开 App"。
 *    extra 现在就带上，是为了页面落地时不必再动原生这一处、也不必先发一个版本才能定位到那条。
 *    不在原生里做"标记已读"—— 已读是设备侧那一份事实，走 Dart 的一条咽喉。
 */
object FnthinkInboxDisplay {

    /** 系统渠道 id。独立于前台服务那条常驻渠道：音量/呼吸灯/是否上岛按渠道整体决定，混用会让"收件"跟着服务通知走 LOW。 */
    const val CHANNEL_ID = "fnthink_inbox"

    /** 三元组里的那个 id 固定；区分靠 tag。见类注释 ①。 */
    const val NOTIFICATION_ID = 90210

    /** 点通知时带的那枚 extra。**当前无人读它**（收件页落地后由 Dart 侧消费），名字先定下来是为了以后不必改原生。 */
    const val EXTRA_MESSAGE_ID = "extra_fnthink_message_id"

    /** 一条要显示的东西的**全部决定**都在这里，`show` 只负责执行 —— 纯函数部分能在 JVM 上测。 */
    data class Spec(
        val messageId: String,
        val tag: String,
        val notificationId: Int,
        val channel: String,
        val groupKey: String,
        val title: String,
        val text: String,
        val sender: String,
    )

    /**
     * 由消息决定通知的形状。
     *
     * 标题为空时退回正文第一行：一条只有正文的推送（端点那一侧很多平台只给 `message` 一个字段）
     * 若显示成空标题，用户在通知栏看到的就是一片空白，会以为推送坏了。
     */
    fun specFor(
        messageId: String,
        sender: String,
        title: String,
        body: String,
    ): Spec {
        val trimmedTitle = title.trim()
        val fallback = body.lineSequence().firstOrNull { it.isNotBlank() }?.trim().orEmpty()
        return Spec(
            messageId = messageId,
            tag = messageId,
            notificationId = NOTIFICATION_ID,
            channel = CHANNEL_ID,
            // 按发送方归组：一台 NAS 推十条会收成一组，而不是把通知栏刷满。
            groupKey = "fnthink:$sender",
            title = trimmedTitle.ifEmpty { fallback },
            text = body,
            sender = sender,
        )
    }

    /**
     * 真发一条。返回 false = **没有显示**（权限或渠道被关），调用方要按"未显示"处理。
     * 这里不抛：收件循环里一条显示失败不该让整轮失败（那条消息已经落库了）。
     */
    fun show(context: Context, spec: Spec): Boolean {
        return try {
            ensureChannel(context)
            val manager = NotificationManagerCompat.from(context)
            // areNotificationsEnabled 在 33+ 覆盖了"用户没给 POST_NOTIFICATIONS"这一档：
            // 权限没给时 notify() 不报错也不显示 —— 不问一句就会回一个假 true。
            // （它是 compat 包里的普通方法而非 getter 对，Kotlin 不会给属性语法，必须带括号。）
            if (!manager.areNotificationsEnabled()) return false
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra(EXTRA_MESSAGE_ID, spec.messageId)
            }
            val pending = PendingIntent.getActivity(
                context,
                // requestCode 用 tag 的 hashCode：不同消息的 PendingIntent 不会互相替换，
                // 否则点第二条会打开第一条（PendingIntent 相等判定看的是 data+requestCode）。
                spec.tag.hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val builder = NotificationCompat.Builder(context, spec.channel)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(spec.title)
                .setContentText(spec.text)
                .setStyle(NotificationCompat.BigTextStyle().bigText(spec.text))
                .setContentIntent(pending)
                .setGroup(spec.groupKey)
                .setAutoCancel(true)
                .setCategory(NotificationCompat.CATEGORY_MESSAGE)
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            manager.notify(spec.tag, spec.notificationId, builder.build())
            true
        } catch (e: SecurityException) {
            // 权限这一档：areNotificationsEnabled() 已经问过一句，但系统/OEM 仍可能在这里抛
            // SecurityException（33+ 的 POST_NOTIFICATIONS 被拒之外，厂商还有自己的闸）。
            // 单独接住它并回 false —— 与"没显示"是同一件事，不能让它冒到外层当成"显示成功了"。
            android.util.Log.w("FnthinkInboxDisplay", "收件通知权限被拒", e)
            false
        } catch (e: Exception) {
            android.util.Log.e("FnthinkInboxDisplay", "收件通知显示失败", e)
            false
        }
    }

    private fun ensureChannel(context: Context) {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.O) return
        try {
            val manager = context.getSystemService(NotificationManager::class.java)
            if (manager.getNotificationChannel(CHANNEL_ID) != null) return
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    I18n.fnthinkInboxChannelName(),
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply {
                    description = I18n.fnthinkInboxChannelDescription()
                },
            )
        } catch (e: Exception) {
            android.util.Log.e("FnthinkInboxDisplay", "收件通知渠道创建失败", e)
        }
    }
}
