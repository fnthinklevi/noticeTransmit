package com.fnthink.notice

import android.app.Notification
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
 *    读它的那一端是 T83 落地的：`MainActivity.consumeOpenTargetFrom` 把它接进 `FnthinkOpenTarget`，
 *    Dart 侧经 `takeFnthinkOpenTarget` 取走那唯一一次，随后打开历史页并展开这一条。
 *    不在原生里做"标记已读"—— 已读是设备侧那一份事实，走 Dart 的一条咽喉。
 */
object FnthinkInboxDisplay {

    /**
     * 系统渠道 id。独立于前台服务那条常驻渠道：音量/呼吸灯/是否上岛按渠道整体决定，混用会让"收件"跟着服务通知走 LOW。
     *
     * ⚠ **T55（2026-10-05 维护者拍板走方案一）：这一段 id 是本轮换过的**。
     * 渠道 importance **创建后不可改**（`ensureChannel` 见到同名渠道就 return），而原来这枚是
     * `IMPORTANCE_DEFAULT` —— 进通知栏、有声，**不弹 heads-up**，"通知到了但岛不弹"。
     * 两条出路（换 id ／ 走 `NotificationChannelCompat` 加引导）里维护者选了换 id，代价是：
     * **已装用户升级后系统设置里会多出一枚同名但没人用的旧渠道**（它停在 DEFAULT），
     * 且旧渠道上用户改过的设置不再作用到新渠道。这一条写在这里，别让后人以为是重命名写错了。
     * ⚠ 旧 id 保留在 [LEGACY_CHANNEL_ID] 里，**不是**给谁回退用的（本类没有任何地方读它），
     * 只是让"上一版用的是哪个"有据可查。要不要在升级时 `deleteNotificationChannel` 清掉它，
     * 是一次独立的取舍（会删掉用户在那枚渠道上的历史设置），维护者没拍板 ⇒ 没做。
     */
    const val CHANNEL_ID = "fnthink_inbox_v2"

    /** 上一版那枚渠道（DEFAULT）。见 [CHANNEL_ID] 的注释：只留名，不删、不读。 */
    const val LEGACY_CHANNEL_ID = "fnthink_inbox"

    /** 三元组里的那个 id 固定；区分靠 tag。见类注释 ①。 */
    const val NOTIFICATION_ID = 90210

    /** 点通知时带的那枚 extra。读者是 `MainActivity`（T83），Dart 侧不许重打这个字符串。 */
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
        /** 桌面图标角标上的那个数（T55）。数法在 Dart 侧（`countFnthinkInboxUnread`），这里只收。 */
        val unreadCount: Int,
    )

    /**
     * 由消息决定通知的形状。
     *
     * 标题为空时退回正文第一行：一条只有正文的推送（端点那一侧很多平台只给 `message` 一个字段）
     * 若显示成空标题，用户在通知栏看到的就是一片空白，会以为推送坏了。
     *
     * [unreadCount] 负数按 0 算：`setNumber(-1)` 在部分桌面上的表现是"角标消失"，而调用方
     * 传负数的唯一原因是"我没数到"——那该显示 0，不该让桌面自己发挥。
     */
    fun specFor(
        messageId: String,
        sender: String,
        title: String,
        body: String,
        unreadCount: Int = 0,
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
            unreadCount = unreadCount.coerceAtLeast(0),
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
                // T55 ① 上岛：渠道那一层是 `IMPORTANCE_HIGH`（8+，真正决定弹不弹横幅），
                // 这一行是给 8 以下那条路兜的（那边只看 priority）—— 两处都要写，
                // 少一处就变成"新系统弹、 老系统不弹"那种按版本分裂的行为。
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                // T55 ② 锁屏能看见正文：`VISIBILITY_PUBLIC` 是在锁屏上直接显示正文。
                // ⚠ 另两档都不对：`SECRET` 锁屏上什么都不显示，`PRIVATE` 只显示"有内容"四个字。
                // 渠道那一层另有 `lockscreenVisibility`（管用户在设置里改的那一档）；
                // 这一行管**这一条通知**，两边都要，否则用户改完设置仍可能看到 PRIVATE 那一档。
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                // T55 ③ 角标 = 未读数。⚠ 两条平台边界写在这里，别当它是"设了就一定看得见"：
                // ① 角标**由桌面决定要不要显示** —— Pixel/Samsung/AOSP 系认这个数，
                //    少数桌面只显示一个点、不显示数字；② 用户在系统设置里关掉这一枚渠道的
                //    角标，这里写什么都没用（与"横幅弹不弹"同一档用户主权）。
                .setNumber(spec.unreadCount)
            // T55：请求提升为「上岛 / 超级岛实时更新」（Android 16+）。
            // ⚠ 这一枚**才**该要：它是用户能看见的那条（收件到达），
            //   而监控服务那条常驻通知不动 —— 它一动，被拦下的每一条通知都会跟着弹横幅。
            //   拿不到 POST_PROMOTED_NOTIFICATIONS 时原样发出（静默降级，不抛）。
            manager.notify(
                spec.tag,
                spec.notificationId,
                NotificationPromoted.applyIfGranted(context, builder.build()),
            )
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
                    // T55 ① 上岛：DEFAULT 只进通知栏、不弹 heads-up；HIGH 才弹。
                    // ⚠ 这一行**只在渠道不存在时生效**（下一行就是那个 return），
                    // 所以升档只能换 CHANNEL_ID —— 见 CHANNEL_ID 上面那段取舍。
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = I18n.fnthinkInboxChannelDescription()
                    // T55 ② 锁屏：这一层是**用户可在系统设置里改的那一档**，
                    // 通知那一层的 `setVisibility` 管不了它 —— 两层都要 PUBLIC。
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                    // T55 ③ 角标：渠道默认 `setShowBadge(true)`，这里**显式写出来**而不是靠默认 ——
                    // 靠默认的那天默认值一改，这条就静默失效，而报告里看不出任何东西。
                    setShowBadge(true)
                },
            )
        } catch (e: Exception) {
            android.util.Log.e("FnthinkInboxDisplay", "收件通知渠道创建失败", e)
        }
    }
}
