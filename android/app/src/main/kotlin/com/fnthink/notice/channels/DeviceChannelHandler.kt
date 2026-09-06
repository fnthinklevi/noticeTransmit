package com.fnthink.notice.channels

import android.os.Build
import com.fnthink.notice.MainActivity
import com.fnthink.notice.NotificationMonitorService
import com.fnthink.notice.PrefsHelper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 设备与桌面域：设备名/型号/厂商/SIM 数/ABI/应用版本、电池状态、监听服务运行态、
 * 桌面图标别名切换、桌面小部件一键添加（requestPinWidget）与支持性预检。
 */
internal class DeviceChannelHandler(activity: MainActivity) : ChannelHandler(activity) {
    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "getDeviceName" -> {
                var savedName = activity.readDeviceNameFromFile()
                if (savedName.isEmpty()) {
                    savedName = activity.prefs.getString("flutter.device_name", "") ?: ""
                    if (savedName.isNotEmpty()) {
                        activity.saveDeviceName(savedName)
                    }
                }
                if (savedName.isEmpty()) {
                    savedName = "${Build.BRAND} ${Build.MODEL}"
                    activity.saveDeviceName(savedName)
                    PrefsHelper.deviceName = savedName
                    NotificationMonitorService.deviceName = savedName
                }
                result.success(savedName)
            }
            "setDeviceName" -> {
                val name = call.argument<String>("name") ?: ""
                PrefsHelper.deviceName = name
                activity.saveDeviceName(name)
                NotificationMonitorService.deviceName = name
                activity.notifyServiceConfigChanged()
                result.success(true)
            }
            "isServiceRunning" -> {
                result.success(activity.isMonitoringEnabled())
            }
            "getDeviceModel" -> {
                result.success(Build.MODEL)
            }
            "getManufacturer" -> {
                result.success(Build.MANUFACTURER)
            }
            "getSimCardCount" -> {
                result.success(activity.getSimCardCount())
            }
            "getSupportedAbis" -> {
                result.success(Build.SUPPORTED_ABIS.toList())
            }
            "getAppVersion" -> {
                try {
                    val info = activity.packageManager.getPackageInfo(activity.packageName, 0)
                    val versionName = info.versionName ?: MainActivity.FALLBACK_VERSION
                    val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        info.longVersionCode.toInt()
                    } else {
                        info.versionCode
                    }
                    result.success(mapOf("versionName" to versionName, "versionCode" to versionCode))
                } catch (e: Exception) {
                    e.printStackTrace()
                    result.success(mapOf("versionName" to MainActivity.FALLBACK_VERSION, "versionCode" to MainActivity.FALLBACK_BUILD))
                }
            }
            "getBatteryStatus" -> {
                result.success(activity.getBatteryStatus())
            }
            "changeLauncherIcon" -> {
                val icon = call.argument<String>("icon") ?: "default"
                activity.changeLauncherIcon(icon)
                result.success(true)
            }
            "getLauncherIcon" -> {
                result.success(activity.getLauncherIcon())
            }
            "requestPinWidget" -> {
                // 一键添加桌面小部件（Android 8.0+ 系统弹窗确认；桌面不支持时降级手动添加）
                val wide = call.argument<Boolean>("wide") ?: false
                val ok = activity.requestPinWidget(wide)
                result.success(ok)
            }
            "isPinWidgetSupported" -> {
                // 当前桌面是否支持一键添加，Flutter 侧据此决定是否展示品牌分步引导
                val wide = call.argument<Boolean>("wide") ?: false
                result.success(activity.isPinWidgetSupported(wide))
            }
            else -> return false
        }
        return true
    }
}
