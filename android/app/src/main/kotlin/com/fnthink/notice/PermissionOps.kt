package com.fnthink.notice

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

/**
 * 权限与系统设置跳转的单一作者（P1-2）。
 *
 * 为什么从 MainActivity 搬出来：这 20 多枚方法与 Activity 的生命周期、MethodChannel
 * 装配、通道镜像、安装器、图标别名全部混在一个 2700 行的类里。它们只依赖
 * `startActivity` / `requestPermissions` / `packageName` / `contentResolver` /
 * `getSystemService` 这几样 Activity 能力，搬进独立类后：
 *  - 权限页那一族（[com.fnthink.notice.channels.PermissionChannelHandler]）只面对一份实现；
 *  - 请求码与回传判据有唯一作者，Activity 只保留 `onRequestPermissionsResult` 的转交；
 *  - 新增一枚权限时不必再往 MainActivity 里塞第 N 个方法。
 *
 * ⚠ 本类**不持有** Activity 生命周期之外的资源，也不缓存权限结果：每次调用现读系统状态，
 * 与拆分前逐字一致。
 */
internal class PermissionOps(private val activity: Activity) {
    companion object {
        internal const val REQUEST_SMS_PERMISSION = 1001
        internal const val REQUEST_PHONE_PERMISSION = 1002
        internal const val REQUEST_POST_NOTIFICATION_PERMISSION = 1003

        // T124 片C：通话记录（READ_CALL_LOG）是**单独一次申请**，不并进 phone 那一次 ——
        // "一条一开"：并进去等于用户点"电话状态"时顺手把通话记录也问了（而那是另一档数据面）。
        internal const val REQUEST_CALL_LOG_PERMISSION = 1004

        // T124 片C-2：定位那一档（FINE+COARSE **一起**申请是系统的形状 —— Android 12+ 的
        // "精确／大致"二选一就长在那一次弹框里；这不是"打包两条面"，而是一条面的两种精度）。
        // ⚠ 不申请 ACCESS_BACKGROUND_LOCATION：后台读不到就诚实失败（location-unavailable）。
        internal const val REQUEST_LOCATION_PERMISSION = 1005

        /** T55：提升/悬浮通知的请求码；与 T84 那批 71–78 不重叠。 */
        internal const val PROMOTED_PERMISSION_REQUEST_CODE = 9101
    }

    fun requestSmsPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(android.Manifest.permission.RECEIVE_SMS),
                REQUEST_SMS_PERMISSION,
            )
        }
    }

    fun requestPhonePermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(android.Manifest.permission.READ_PHONE_STATE),
                REQUEST_PHONE_PERMISSION,
            )
        }
    }

    /** T124 片C：通话记录的**单独一次**申请（见 [REQUEST_CALL_LOG_PERMISSION] 上那句）。 */
    fun requestCallLogPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(android.Manifest.permission.READ_CALL_LOG),
                REQUEST_CALL_LOG_PERMISSION,
            )
        }
    }

    /**
     * T124 片C-2：定位的**一次**申请（FINE+COARSE 同框 —— 见 [REQUEST_LOCATION_PERMISSION] 上那句）。
     */
    fun requestLocationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(
                    android.Manifest.permission.ACCESS_FINE_LOCATION,
                    android.Manifest.permission.ACCESS_COARSE_LOCATION,
                ),
                REQUEST_LOCATION_PERMISSION,
            )
        }
    }

    fun requestQueryAllPackagesPermission() {
        try {
            openAppDetailsSettings()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun isNotificationListenerPermissionGranted(): Boolean {
        val flat = Settings.Secure.getString(
            activity.contentResolver,
            "enabled_notification_listeners",
        ) ?: ""
        return flat.contains(activity.packageName)
    }

    /**
     * T55：申请 **POST_PROMOTED_NOTIFICATIONS**（Android 16 起"提升/悬浮通知"的运行时权限）。
     *
     * ⚠ 为什么必须走原生而不能用 permission_handler：那一版（13.x）的枚举里**没有**这一枚，
     *   硬塞进现有枚举等于让"没这一项"这件事在编译期看不见 —— 而漏申请的代价是
     *   `FLAG_PROMOTED_ONGOING` 静默无效（上不了岛），没有任何报错。
     * ⚠ 36 以下**直接回已授予**：那一档系统没有这个权限，也没有"用户拒绝"这回事 ——
     *   在那里弹一个不存在的权限框，用户只会看到一个莫名其妙的应用信息页。
     */
    fun requestPromotedNotificationPermission() {
        if (Build.VERSION.SDK_INT < 36) return
        try {
            activity.requestPermissions(
                arrayOf("android.permission.POST_PROMOTED_NOTIFICATIONS"),
                PROMOTED_PERMISSION_REQUEST_CODE,
            )
        } catch (e: Exception) {
            Log.w("PermissionOps", "申请提升通知权限失败（其余能力不受影响）", e)
        }
    }

    fun isPromotedNotificationPermissionGranted(): Boolean {
        if (Build.VERSION.SDK_INT < 36) return true
        return ContextCompat.checkSelfPermission(
            activity,
            "android.permission.POST_PROMOTED_NOTIFICATIONS",
        ) == PackageManager.PERMISSION_GRANTED
    }

    fun requestNotificationListenerPermission() {
        try {
            val intent = Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(intent)
        } catch (e: Exception) {
            try {
                val intent = Intent(Settings.ACTION_SECURITY_SETTINGS)
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                activity.startActivity(intent)
            } catch (e2: Exception) {
                e2.printStackTrace()
            }
        }
    }

    fun isPostNotificationPermissionGranted(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                activity,
                android.Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    fun requestPostNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                REQUEST_POST_NOTIFICATION_PERMISSION,
            )
        }
    }

    fun isIgnoringBatteryOptimizations(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager =
                activity.getSystemService(Context.POWER_SERVICE) as PowerManager
            powerManager.isIgnoringBatteryOptimizations(activity.packageName)
        } else {
            true
        }
    }

    fun isSmsPermissionGranted(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            ContextCompat.checkSelfPermission(
                activity,
                android.Manifest.permission.RECEIVE_SMS,
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    fun isPhonePermissionGranted(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            ContextCompat.checkSelfPermission(
                activity,
                android.Manifest.permission.READ_PHONE_STATE,
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    fun isCallLogPermissionGranted(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            ContextCompat.checkSelfPermission(
                activity,
                android.Manifest.permission.READ_CALL_LOG,
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    /** T124 片C-2：FINE 或 COARSE **任一**给了就算给了（"大致位置"是能用的一种，不是拒绝）。 */
    fun isLocationPermissionGranted(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val fine = ContextCompat.checkSelfPermission(
            activity,
            android.Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        val coarse = ContextCompat.checkSelfPermission(
            activity,
            android.Manifest.permission.ACCESS_COARSE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        return fine || coarse
    }

    fun requestBatteryOptimization() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val intent = Intent()
                intent.action = Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                intent.data = Uri.parse("package:${activity.packageName}")
                activity.startActivity(intent)
            } catch (e: Exception) {
                try {
                    val intent = Intent(Settings.ACTION_BATTERY_SAVER_SETTINGS)
                    activity.startActivity(intent)
                } catch (e2: Exception) {
                    e2.printStackTrace()
                }
            }
        }
    }

    /**
     * T137 验收③：直接跳到收件渠道（fnthink_inbox_v2）自己的系统设置页。
     *
     * 为什么只有"跳"没有"读"：厂商（MIUI 等）在 AOSP 之上另有按应用的悬浮/锁屏/声音开关，
     * 而那几枚不在任何 APK 可读的 API 里（六厂商官方口径，roadmap §8 附录）——
     * 界面能诚实做的只有"报我们自己那侧 + 把用户送到能看见全部开关的那一页"。
     * 26 以下没有按渠道跳转这一档（渠道本身也不存在），退回应用详情页。
     */
    fun openInboxChannelSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val intent = Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                intent.putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
                intent.putExtra(Settings.EXTRA_CHANNEL_ID, FnthinkInboxDisplay.CHANNEL_ID)
                activity.startActivity(intent)
                return
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
        openAppDetailsSettings()
    }

    fun requestXiaomiAutoStart() {
        try {
            val intent = Intent()
            intent.component = ComponentName(
                "com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity",
            )
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(intent)
        } catch (e: Exception) {
            try {
                val intent = Intent("miui.intent.action.OP_AUTO_START")
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                activity.startActivity(intent)
            } catch (e2: Exception) {
                try {
                    val intent = Intent()
                    intent.component = ComponentName(
                        "com.miui.securitycenter",
                        "com.miui.permcenter.permissions.PermissionsEditorActivity",
                    )
                    intent.putExtra("extra_pkgname", activity.packageName)
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    activity.startActivity(intent)
                } catch (e3: Exception) {
                    openAppDetailsSettings()
                }
            }
        }
    }

    fun requestMeizuBackground() {
        try {
            val intent = Intent("com.meizu.safe.security.SHOW_APPSEC")
            intent.addCategory(Intent.CATEGORY_DEFAULT)
            intent.putExtra("packageName", activity.packageName)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(intent)
        } catch (e: Exception) {
            try {
                val intent = Intent()
                intent.component = ComponentName(
                    "com.meizu.safe",
                    "com.meizu.safe.permission.SmartBGControlActivity",
                )
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                activity.startActivity(intent)
            } catch (e2: Exception) {
                openAppDetailsSettings()
            }
        }
    }

    fun requestHuaweiLaunch() {
        try {
            val intent = Intent()
            intent.component = ComponentName(
                "com.huawei.systemmanager",
                "com.huawei.systemmanager.optimize.process.ProtectActivity",
            )
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(intent)
        } catch (e: Exception) {
            try {
                val intent = Intent()
                intent.component = ComponentName(
                    "com.huawei.systemmanager",
                    "com.huawei.permissionmanager.ui.MainActivity",
                )
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                activity.startActivity(intent)
            } catch (e2: Exception) {
                openAppDetailsSettings()
            }
        }
    }

    fun requestOppoBackground() {
        try {
            val intent = Intent()
            intent.component = ComponentName(
                "com.coloros.safecenter",
                "com.coloros.safecenter.permission.startup.StartupAppListActivity",
            )
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(intent)
        } catch (e: Exception) {
            try {
                val intent = Intent()
                intent.component = ComponentName(
                    "com.oppo.safe",
                    "com.oppo.safe.permission.startup.StartupAppListActivity",
                )
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                activity.startActivity(intent)
            } catch (e2: Exception) {
                openAppDetailsSettings()
            }
        }
    }

    fun requestVivoBackground() {
        try {
            val intent = Intent()
            intent.component = ComponentName(
                "com.vivo.permissionmanager",
                "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
            )
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(intent)
        } catch (e: Exception) {
            try {
                val intent = Intent()
                intent.component = ComponentName(
                    "com.iqoo.secure",
                    "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
                )
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                activity.startActivity(intent)
            } catch (e2: Exception) {
                openAppDetailsSettings()
            }
        }
    }

    // ── T198: 锁屏三项厂商跳转（骨架） ────────────────────────────────────────
    //
    // 三项（锁屏断开数据 / 睡眠模式 / WLAN 锁屏休眠）的 Intent 都是厂商私有，
    // Android 原生没有公开 Intent 可跳。今天先搭骨架：
    //   - 下面 15 个 internal 方法全部兜底到 openAppDetailsSettings()
    //   - 真机逐 ROM 核到具体 Intent 后，照 requestXiaomiAutoStart() 同款 try/catch 链填进去
    // 每个厂商 × 每项 = 1 个方法：LockData（锁屏断开数据）/ Sleep（睡眠模式）/ WifiSleep（WLAN 锁屏休眠）

    fun requestXiaomiLockData() = openAppDetailsSettings()
    fun requestMeizuLockData() = openAppDetailsSettings()
    fun requestHuaweiLockData() = openAppDetailsSettings()
    fun requestOppoLockData() = openAppDetailsSettings()
    fun requestVivoLockData() = openAppDetailsSettings()

    fun requestXiaomiSleep() = openAppDetailsSettings()
    fun requestMeizuSleep() = openAppDetailsSettings()
    fun requestHuaweiSleep() = openAppDetailsSettings()
    fun requestOppoSleep() = openAppDetailsSettings()
    fun requestVivoSleep() = openAppDetailsSettings()

    fun requestXiaomiWifiSleep() = openAppDetailsSettings()
    fun requestMeizuWifiSleep() = openAppDetailsSettings()
    fun requestHuaweiWifiSleep() = openAppDetailsSettings()
    fun requestOppoWifiSleep() = openAppDetailsSettings()
    fun requestVivoWifiSleep() = openAppDetailsSettings()

    fun openAppDetailsSettings() {
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            intent.data = Uri.fromParts("package", activity.packageName, null)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(intent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /**
     * Android 12+ 是否已授权精确闹钟；12 以下系统无此概念，恒为 true。
     *
     * ⚠ 判定本身住在 [ExactAlarmPolicy]（T140 走 (c) 之后那一枚唯一作者）：这里只是通道侧的转交。
     * 界面报的那一份与排闹钟时读的那一份**必须是同一个表达式**，否则又是两句话。
     */
    fun canScheduleExactAlarms(): Boolean = ExactAlarmPolicy.allowed(activity)

    /**
     * 引导用户授权精确闹钟（B1）。
     * Android 12~13：系统弹授权对话框（ACTION_REQUEST_SCHEDULE_EXACT_ALARM）。
     * Android 14+：SCHEDULE_EXACT_ALARM 默认拒绝且无系统授权入口，跳应用详情页引导手动开启；
     * 未授权时 DelayedPushManager 会捕获 SecurityException 自动降级为非精确闹钟，不阻塞功能。
     */
    fun requestExactAlarmPermission() {
        try {
            if (canScheduleExactAlarms()) return
            if (Build.VERSION.SDK_INT in Build.VERSION_CODES.S..Build.VERSION_CODES.TIRAMISU) {
                // data 为可选参数：官方文档 "Optionally, the Intent's data URI can specify the package name"。
                // 部分 ROM（尤其国产）Settings 组件对该 action 的 intent-filter 不匹配带 data 的 intent，
                // 设置 data 反而触发 ActivityNotFoundException；不带 data 时系统默认取调用者包名。
                val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                activity.startActivity(intent)
            } else {
                openAppDetailsSettings()
            }
        } catch (e: Exception) {
            openAppDetailsSettings()
        }
    }
}
