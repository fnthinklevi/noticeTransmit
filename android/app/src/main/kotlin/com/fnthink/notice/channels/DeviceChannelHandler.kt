package com.fnthink.notice.channels

import android.os.Build
import com.fnthink.notice.BatteryMonitor
import com.fnthink.notice.DeviceSnapshot
import com.fnthink.notice.MainActivity
import com.fnthink.notice.NotificationMonitorService
import com.fnthink.notice.PrefsHelper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.launch

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
            "getDeviceSnapshot" -> {
                // T17：一次调用读全（型号/版本/网络/电量与温度/存储/内存/亮度/运行时长）。
                // StatFs、ActivityManager、Settings 都是跨进程或 syscall ⇒ 不能在平台线程读
                // （handle 跑在主线程，这是本 handler 里唯一会卡 UI 的方法）。
                ioScope.launch {
                    val raw = DeviceSnapshot.readRaw(activity.applicationContext)
                    postSuccess(
                        result,
                        DeviceSnapshot.normalize(raw, System.currentTimeMillis()),
                    )
                }
            }
            "previewTemperatureRule" -> {
                // T25：温度规则试跑。三锥读数要 registerReceiver + 读 thermal_zone sysfs，
                // 与 getDeviceSnapshot 同一条理由 ⇒ 放 ioScope，且整次求值不发送、不落历史。
                val rulesJson = call.argument<String>("rulesJson") ?: "[]"
                val monitor = BatteryMonitor(activity.applicationContext)
                ioScope.launch {
                    postSuccess(
                        result,
                        try {
                            monitor.previewTemperatureRules(rulesJson)
                        } catch (e: Exception) {
                            e.printStackTrace()
                            // 求值出错必须回一个明确形状：回 null 会让界面停在"转圈"，
                            // 用户分不清是设备读不到还是代码坏了。
                            mapOf("ok" to false, "error" to (e.message ?: e.javaClass.simpleName))
                        },
                    )
                }
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
