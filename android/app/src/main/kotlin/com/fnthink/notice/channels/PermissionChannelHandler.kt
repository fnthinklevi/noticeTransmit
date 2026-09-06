package com.fnthink.notice.channels

import com.fnthink.notice.MainActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 权限与系统设置域：通知监听/通知发送/短信/电话/应用列表权限的检查与申请，
 * 精确闹钟、电池优化白名单、应用详情页，以及国产 ROM 保活跳转（小米/魅族/华为/OPPO/vivo）。
 */
internal class PermissionChannelHandler(activity: MainActivity) : ChannelHandler(activity) {
    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "isNotificationPermissionGranted" -> {
                result.success(activity.isNotificationListenerPermissionGranted())
            }
            "isPostNotificationPermissionGranted" -> {
                result.success(activity.isPostNotificationPermissionGranted())
            }
            "requestNotificationListenerPermission" -> {
                activity.requestNotificationListenerPermission()
                result.success(true)
            }
            "requestPostNotificationPermission" -> {
                activity.requestPostNotificationPermission()
                result.success(true)
            }
            "isSmsPermissionGranted" -> {
                result.success(activity.isSmsPermissionGranted())
            }
            "isPhonePermissionGranted" -> {
                result.success(activity.isPhonePermissionGranted())
            }
            "isAppListPermissionGranted" -> {
                result.success(activity.isAppListPermissionGranted())
            }
            "requestSmsPermission" -> {
                activity.requestSmsPermission()
                result.success(true)
            }
            "requestPhonePermission" -> {
                activity.requestPhonePermission()
                result.success(true)
            }
            "canQueryAllPackages" -> {
                result.success(activity.canQueryAllPackages())
            }
            "requestQueryAllPackagesPermission" -> {
                activity.requestQueryAllPackagesPermission()
                result.success(true)
            }
            "isExactAlarmEnabled" -> {
                result.success(
                    activity.prefs.getBoolean("flutter.exact_alarm_enabled", false)
                )
            }
            "setExactAlarmEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                activity.prefs.edit().putBoolean("flutter.exact_alarm_enabled", enabled).apply()
                // 通知服务重新加载配置并重排延迟推送闹钟（切换精确/非精确模式）
                activity.notifyServiceConfigChanged()
                result.success(true)
            }
            "canScheduleExactAlarms" -> {
                result.success(activity.canScheduleExactAlarms())
            }
            "requestExactAlarmPermission" -> {
                activity.requestExactAlarmPermission()
                result.success(true)
            }
            "requestBatteryOptimization" -> {
                activity.requestBatteryOptimization()
                result.success(true)
            }
            "isIgnoringBatteryOptimizations" -> {
                result.success(activity.isIgnoringBatteryOptimizations())
            }
            "openAppDetailsSettings" -> {
                activity.openAppDetailsSettings()
                result.success(true)
            }
            "requestXiaomiAutoStart" -> {
                activity.requestXiaomiAutoStart()
                result.success(true)
            }
            "requestMeizuBackground" -> {
                activity.requestMeizuBackground()
                result.success(true)
            }
            "requestHuaweiLaunch" -> {
                activity.requestHuaweiLaunch()
                result.success(true)
            }
            "requestOppoBackground" -> {
                activity.requestOppoBackground()
                result.success(true)
            }
            "requestVivoBackground" -> {
                activity.requestVivoBackground()
                result.success(true)
            }
            else -> return false
        }
        return true
    }
}
