package com.fnthink.notice

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * 远程「让这台响一条」（T124 片B 的 `alert:ring`）。
 *
 * 与收件显示（[FnthinkInboxDisplay]）**共用同一条 HIGH 渠道**：用户在这一条渠道上
 * 改过的静音/横幅设置，对"对面让我响"与"来了一条收件"应当是同一套 —— 另开一条渠道
 * 等于把用户关掉的声音在另一条渠道上偷偷打开。渠道的创建点也共用
 * （[FnthinkInboxDisplay.ensureChannel]）。
 *
 * ⚠ **全屏那半没做**：片B 的前提是"零新权限"，而 Android 14 起 `setFullScreenIntent`
 * 要 `USE_FULL_SCREEN_INTENT` 清单权限 + 用户的特殊授权（"全屏通知"那一档）——
 * 那是一次**新的权限面决定**，要加得按片C 那套来（清单＋申请入口＋隐私政策三处＋默认关）。
 * 现在交付的是响铃＋震动＋高优先横幅；`CATEGORY_ALARM` 让系统按"闹钟类"对待它
 * （勿扰模式的例外档会放它进来 —— 与用户对"提醒"的期待一致）。
 *
 * ⚠ **tag 与收件不同名**：收件的 tag 是 messageId（同一条重发＝替换），这一条用固定
 * 常量 tag ⇒ 连按两次只是**同一条通知重弹**（不堆叠），而它与任何一条收件都不互相顶掉
 * （Android 按 (package, tag, id) 认一条通知）。这一条由 JVM 用例钉住。
 */
object FnthinkAlertDisplay {
    /** 通知的身份（tag）。固定值：见类注释那条"不堆叠、不顶掉收件"。 */
    const val TAG = "fnthink-alert"

    /** 三元组里的 id。与 [FnthinkInboxDisplay.NOTIFICATION_ID] 不同值，避免任何撞位联想。 */
    const val NOTIFICATION_ID = 90211

    /** 震动节奏（毫秒）：等一下 → 震半秒 → 歇 1/4 秒 → 再震半秒。 */
    private val VIBRATE_PATTERN = longArrayOf(0, 500, 250, 500)

    /**
     * 真响一条。返回 false = **没有显示**（没给通知权限 / 渠道被系统禁用），
     * 调用方据此把这一次执行记成失败 —— 对面收到 done 会以为这台的用户被提醒过了。
     * 不抛：一条显示失败不该让整轮收货崩在半路。
     */
    fun show(context: Context): Boolean {
        return try {
            val manager = NotificationManagerCompat.from(context)
            // 与收件显示同一条判据：33+ 没给 POST_NOTIFICATIONS 时 notify() 不报错也不显示
            // —— 不问一句就会回一个假 true。
            if (!manager.areNotificationsEnabled()) return false
            FnthinkInboxDisplay.ensureChannel(context)
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pending = PendingIntent.getActivity(
                context,
                NOTIFICATION_ID,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val builder = NotificationCompat.Builder(
                context,
                FnthinkInboxDisplay.CHANNEL_ID,
            )
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(I18n.fnthinkAlertTitle())
                .setContentText(I18n.fnthinkAlertText())
                .setContentIntent(pending)
                .setAutoCancel(true)
                // 闹钟类：勿扰的例外档会放它进来，且系统按"要人立刻看"处理它。
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                // 8 以下那条路只看 priority（渠道那一层管 8+）—— 两处都要写，少一处
                // 就变成"新系统响、老系统不响"那种按版本分裂的行为。
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                // <8 那一路的声音与震动靠这两行；8+ 由渠道决定（渠道默认就是响+震）。
                .setDefaults(NotificationCompat.DEFAULT_ALL)
                .setVibrate(VIBRATE_PATTERN)
            manager.notify(TAG, NOTIFICATION_ID, builder.build())
            true
        } catch (e: SecurityException) {
            android.util.Log.w("FnthinkAlertDisplay", "响铃通知权限被拒", e)
            false
        } catch (e: Exception) {
            android.util.Log.e("FnthinkAlertDisplay", "响铃通知显示失败", e)
            false
        }
    }
}
