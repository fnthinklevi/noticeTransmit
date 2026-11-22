package com.fnthink.notice.channels

import com.fnthink.notice.MainActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 权限与系统设置域：通知监听/通知发送/短信/电话/应用列表权限的检查与申请，
 * 精确闹钟、电池优化白名单、应用详情页，以及国产 ROM 保活跳转（小米/魅族/华为/OPPO/vivo）。
 *
 * P1-2：实现已搬进 `PermissionOps`（MainActivity 只保留 `onRequestPermissionsResult` 的转交）；
 * 本 Handler 继续只负责「方法名 → 实现」的映射，调用面一个字符都没变。
 */
internal class PermissionChannelHandler(activity: MainActivity) : ChannelHandler(activity) {
    private val ops get() = activity.permissionOps

    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "isNotificationPermissionGranted" -> {
                result.success(ops.isNotificationListenerPermissionGranted())
            }
            "isPostNotificationPermissionGranted" -> {
                result.success(ops.isPostNotificationPermissionGranted())
            }
            "requestNotificationListenerPermission" -> {
                ops.requestNotificationListenerPermission()
                result.success(true)
            }
            "requestPostNotificationPermission" -> {
                ops.requestPostNotificationPermission()
                result.success(true)
            }
            // T55：提升/悬浮通知权限（36+ 才有；36 以下原生直接回 true，见那一侧注释）
            "isPromotedNotificationPermissionGranted" -> {
                result.success(ops.isPromotedNotificationPermissionGranted())
            }
            "requestPromotedNotificationPermission" -> {
                ops.requestPromotedNotificationPermission()
                result.success(true)
            }
            // T55：权限那一族有一枚是 36+ 才有的（提升/悬浮通知），界面要靠它决定显不显示
            "getSdkInt" -> {
                result.success(android.os.Build.VERSION.SDK_INT)
            }

            "isSmsPermissionGranted" -> {
                result.success(ops.isSmsPermissionGranted())
            }
            "isPhonePermissionGranted" -> {
                result.success(ops.isPhonePermissionGranted())
            }
            "getAppListPermissionState" -> {
                // 三态（granted / denied / unknown）。旧的布尔方法
                // `isAppListPermissionGranted` 已删：它把"系统不给状态"当成已授予，
                // 权限页因此在所有 Android 11+ 设备上恒显"已授予"（真机实测，见 ㊸）。
                result.success(activity.getAppListPermissionState())
            }
            "requestSmsPermission" -> {
                ops.requestSmsPermission()
                result.success(true)
            }
            "requestPhonePermission" -> {
                ops.requestPhonePermission()
                result.success(true)
            }
            // T124 片C：通话记录那一格（单独申请，不并进 phone —— 见 PermissionOps 那枚请求码上的一句）
            "isCallLogPermissionGranted" -> {
                result.success(ops.isCallLogPermissionGranted())
            }
            "requestCallLogPermission" -> {
                ops.requestCallLogPermission()
                result.success(true)
            }
            // T124 片C-2：定位那一格（FINE+COARSE 一起申请是系统"精确／大致"那一次弹框的形状；
            // 判据收在 permissionOps.isLocationPermissionGranted 一枚方法里 —— 大致也算给了）
            "isLocationPermissionGranted" -> {
                result.success(ops.isLocationPermissionGranted())
            }
            "requestLocationPermission" -> {
                ops.requestLocationPermission()
                result.success(true)
            }
            "canQueryAllPackages" -> {
                // ⚠ 语义是"允许去枚举"（只有明确拒绝才拦），不是"已授予"。
                // 显示权限状态请用 getAppListPermissionState。
                result.success(activity.canQueryAllPackages())
            }
            "requestQueryAllPackagesPermission" -> {
                ops.requestQueryAllPackagesPermission()
                result.success(true)
            }
            // T140 走 (c)：精确闹钟只剩一枚真值 = 系统授权。
            // 那一枚 App 内开关的两个通道方法（读/写）已一起删除，Dart 侧同步不再有调用点；
            // 不许"只删一侧"——那会让 Dart 的 invokeMethod 打到 no-method 上被 try/catch 吞成 false。
            "canScheduleExactAlarms" -> {
                result.success(ops.canScheduleExactAlarms())
            }
            "requestExactAlarmPermission" -> {
                ops.requestExactAlarmPermission()
                result.success(true)
            }
            "requestBatteryOptimization" -> {
                ops.requestBatteryOptimization()
                result.success(true)
            }
            // T137 验收③：收件渠道自己的系统设置页 —— 厂商的悬浮/锁屏/声音开关不在 AOSP
            // 可读范围里，界面只能"报自己那侧 + 一键跳"，没有"读回来"的那一半。
            "openInboxChannelSettings" -> {
                ops.openInboxChannelSettings()
                result.success(true)
            }
            "isIgnoringBatteryOptimizations" -> {
                result.success(ops.isIgnoringBatteryOptimizations())
            }
            "openAppDetailsSettings" -> {
                ops.openAppDetailsSettings()
                result.success(true)
            }
            "requestXiaomiAutoStart" -> {
                ops.requestXiaomiAutoStart()
                result.success(true)
            }
            "requestMeizuBackground" -> {
                ops.requestMeizuBackground()
                result.success(true)
            }
            "requestHuaweiLaunch" -> {
                ops.requestHuaweiLaunch()
                result.success(true)
            }
            "requestOppoBackground" -> {
                ops.requestOppoBackground()
                result.success(true)
            }
            "requestVivoBackground" -> {
                ops.requestVivoBackground()
                result.success(true)
            }
            // ── T198: 锁屏三项厂商跳转（骨架） ──────────────────────────────
            "requestXiaomiLockData" -> { ops.requestXiaomiLockData(); result.success(true) }
            "requestMeizuLockData" -> { ops.requestMeizuLockData(); result.success(true) }
            "requestHuaweiLockData" -> { ops.requestHuaweiLockData(); result.success(true) }
            "requestOppoLockData" -> { ops.requestOppoLockData(); result.success(true) }
            "requestVivoLockData" -> { ops.requestVivoLockData(); result.success(true) }
            "requestXiaomiSleep" -> { ops.requestXiaomiSleep(); result.success(true) }
            "requestMeizuSleep" -> { ops.requestMeizuSleep(); result.success(true) }
            "requestHuaweiSleep" -> { ops.requestHuaweiSleep(); result.success(true) }
            "requestOppoSleep" -> { ops.requestOppoSleep(); result.success(true) }
            "requestVivoSleep" -> { ops.requestVivoSleep(); result.success(true) }
            "requestXiaomiWifiSleep" -> { ops.requestXiaomiWifiSleep(); result.success(true) }
            "requestMeizuWifiSleep" -> { ops.requestMeizuWifiSleep(); result.success(true) }
            "requestHuaweiWifiSleep" -> { ops.requestHuaweiWifiSleep(); result.success(true) }
            "requestOppoWifiSleep" -> { ops.requestOppoWifiSleep(); result.success(true) }
            "requestVivoWifiSleep" -> { ops.requestVivoWifiSleep(); result.success(true) }
            else -> return false
        }
        return true
    }
}
