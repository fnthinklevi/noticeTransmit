package com.fnthink.notice

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log

class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        context ?: return
        val action = intent?.action ?: return

        Log.d(TAG, "Received action: $action")

        when (action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED -> {
                // goAsync：onReceive 返回后进程优先级立刻回落、随时可能被系统回收，
                // 那时 3 秒后的 postDelayed 根本不会执行 → 开机不自启（表现为
                // 「重启手机后一条通知都没收到」）。挂住 PendingResult 让延迟任务跑完。
                val pendingResult = goAsync()
                try {
                    Handler(Looper.getMainLooper()).postDelayed({
                        try {
                            val serviceIntent = Intent(context, NotificationMonitorService::class.java)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                context.startForegroundService(serviceIntent)
                            } else {
                                context.startService(serviceIntent)
                            }
                            Log.d(TAG, "Notification service started on boot")
                            reArmPresence(context, action)
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to start service on boot", e)
                        } finally {
                            pendingResult.finish()
                        }
                    }, 3000)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to post delayed start", e)
                    pendingResult.finish()
                }
            }
        }
    }

    /**
     * 幻念那颗"到点去问一次货"的闹钟：重启之后要不要补（T33 第二片 / §4-9 片1c）。
     *
     * 三档各有它自己的理由，其中两档是**故意不补**：
     *  - `BOOT_COMPLETED` ⇒ **补**。同一颗 APK 重开，Dart 上次交下来的 entry handle 仍然指向
     *    那个函数，间隔也还是 Dart 写的那一份（[FnthinkPresenceAlarm.armIfWantedAfterBoot]
     *    不自己算，也不在这儿读设置页）。
     *  - `MY_PACKAGE_REPLACED` ⇒ **不补，而且主动撤**。升级换了 APK，AOT 快照里那个回调 id 是
     *    会挪位置的：handle 没跟着换时，最坏的表现不是"起不了引擎"，而是**进到另一个 Dart 函数里**。
     *    正确的重建时机是 App 自己下一次开起来（那才会重写 handle 并按开关重排），不是在这儿拿
     *    一份过期的线索去敲门。
     *  - `LOCKED_BOOT_COMPLETED` ⇒ **不补也不撤**。这一支跑在用户解锁之前，而 Dart 写的那两份
     *    读数（开关、闹钟自己的节奏）都在**凭据加密**的存储里，这时候读到的是空的 ——
     *    拿它当"用户关掉了"会把一次正常重启误判成关掉，还会顺手清掉那份节奏。
     *    宁可等 `BOOT_COMPLETED`（紧接着就来），不在这儿猜。
     */
    private fun reArmPresence(context: Context, action: String) {
        val alarm = FnthinkPresenceAlarm(context)
        when (action) {
            Intent.ACTION_BOOT_COMPLETED -> alarm.armIfWantedAfterBoot()
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                Log.d(TAG, "包被替换：撤掉幻念收货闹钟，等 App 下一次起来重新交 handle 与节奏")
                alarm.cancel()
            }
            else -> Log.d(TAG, "$action 不重排幻念收货闹钟（凭据未解锁，那两份读数不可信）")
        }
    }
}
