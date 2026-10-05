package com.fnthink.notice

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * 远程执行的**状态栏通知**（片3c-5；契约 `delay.cancelChannels` 里的 `statusBar`）。
 *
 * ## 为什么单独一个渠道
 * 与 `FnthinkInboxDisplay` 那条收件渠道**分开**：这一条是"有人要动你的设备，
 * 10 秒后自动执行"，而收件那一条是"有消息到了"。混成一条渠道的话，用户在系统设置里
 * 关掉收件通知，就会**连撤销机会一起关掉** —— 而那时他看到的是"远程执行开着，
 * 但我找不到取消的地方"。
 *
 * ## 动作按钮那一枚才是这一格存在的理由
 * 没有它，这一格就是一条"10 秒后要执行 X"的提示，作用远小于界面横幅（后者在屏幕上）。
 * 它真正的价值是：**用户不在这个 App 里**（多半在别的页面甚至锁屏）时，
 * 那一下仍然按得到。
 */
object FnthinkRemoteExecDisplay {
    const val CHANNEL_ID = "fnthink_remote_exec"
    const val NOTIFICATION_ID = 90211

    /** 动作按钮与广播之间唯一的约定（[RemoteExecCancelReceiver] 是它的读者）。 */
    const val ACTION_CANCEL = "com.fnthink.notice.action.FNTHINK_REMOTE_CANCEL"
    const val EXTRA_EXEC_ID = "extra_fnthink_exec_id"

    data class Spec(
        val execId: String,
        val title: String,
        val text: String,
        val cancelLabel: String,
    )

    fun show(context: Context, spec: Spec): Boolean {
        return try {
            ensureChannel(context)
            val manager = NotificationManagerCompat.from(context)
            // 与收件那一条同一问：权限没给时 notify() 不报错也不显示，
            // 不问一句就会回一个假 true（而调用方据此认为"用户看得见撤销入口"）。
            if (!manager.areNotificationsEnabled()) return false

            val cancel = PendingIntent.getBroadcast(
                context,
                // requestCode 用 exec_id 的 hashCode：不同执行各是一枚，
                // 否则按第二条会按到第一条那条上（PendingIntent 相等看 data+requestCode）。
                spec.execId.hashCode(),
                Intent(ACTION_CANCEL).apply {
                    setPackage(context.packageName)
                    putExtra(EXTRA_EXEC_ID, spec.execId)
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(spec.title)
                .setContentText(spec.text)
                .setStyle(NotificationCompat.BigTextStyle().bigText(spec.text))
                .setGroup(GROUP_KEY)
                .setAutoCancel(true)
                .setCategory(NotificationCompat.CATEGORY_PROGRESS)
                // ⚠ HIGH 才让动作按钮在折叠时就露出来：这一条的全部价值就是那一下，
                //   折叠起来只剩一行字的话它就退化成一条提示了。
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                // 持续计时（那 10 秒）：内容一动就说明"它还在跑"。
                .setOngoing(true)
                .addAction(
                    NotificationCompat.Action.Builder(
                        null,
                        spec.cancelLabel,
                        cancel,
                    ).build(),
                )
            manager.notify(GROUP_KEY, spec.execId.hashCode(), builder.build())
            true
        } catch (e: SecurityException) {
            android.util.Log.w(TAG, "远程执行通知权限被拒", e)
            false
        } catch (e: Exception) {
            android.util.Log.e(TAG, "远程执行通知显示失败", e)
            false
        }
    }

    /** 执行结束（做了/没成/撤了）之后收掉那一枚 —— 不留一条永远不消失的常驻。 */
    fun clear(context: Context, execId: String) {
        try {
            NotificationManagerCompat.from(context).cancel(GROUP_KEY, execId.hashCode())
        } catch (e: Exception) {
            android.util.Log.w(TAG, "远程执行通知清理失败", e)
        }
    }

    private const val GROUP_KEY = "fnthink_remote_exec"

    private const val TAG = "FnthinkRemoteExec"

    private fun ensureChannel(context: Context) {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.O) return
        try {
            val manager = context.getSystemService(NotificationManager::class.java)
            if (manager.getNotificationChannel(CHANNEL_ID) != null) return
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    I18n.fnthinkRemoteExecChannelName(),
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = I18n.fnthinkRemoteExecChannelDescription()
                    // T55 同批：锁屏与角标原来没写 ⇒ 真机上读回 lockscreenVisibility=-1000
                    // （MIUI 不保存这一层，但通知层那一行仍要写，见 build 里的 setVisibility）。
                    lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                    setShowBadge(true)
                },
            )
        } catch (e: Exception) {
            android.util.Log.e(TAG, "远程执行通知渠道创建失败", e)
        }
    }
}

/**
 * 状态栏那个「撤销」按钮的读者。
 *
 * ⚠ **它只落盘，不去碰 Dart**：按一下的时候引擎多半不在（那正是这一格存在的理由 ——
 *   用户不在这个 App 里）。它把"这一条撤了"写进 [RemoteExecutionCancelStore]，
 * Dart 到点动手前会来问一句。
 *
 * ⚠ 顺带把那一枚通知收掉：用户已经动手了，再让一条"10 秒后执行"躺在通知栏里，
 * 等于告诉他"还有机会"—— 而其实没有了。
 */
class RemoteExecCancelReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != FnthinkRemoteExecDisplay.ACTION_CANCEL) return
        val execId = intent.getStringExtra(FnthinkRemoteExecDisplay.EXTRA_EXEC_ID) ?: return
        RemoteExecutionCancelStore.markCancelled(context, execId)
        FnthinkRemoteExecDisplay.clear(context, execId)
    }
}
