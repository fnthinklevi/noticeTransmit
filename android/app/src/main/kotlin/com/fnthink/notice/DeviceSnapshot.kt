package com.fnthink.notice

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.StatFs
import android.os.SystemClock
import android.provider.Settings
import kotlin.math.roundToInt

/**
 * 设备快照（T17）：**一个**方法一次读全，替代"型号/厂商/版本/电量…各来一发"。
 *
 * 拆成两半是故意的：
 * - [normalize] 与几个换算函数是**纯函数**（不碰 Context），所以能在 JVM 里直测
 *   （仿 `ChannelRouting.kt` / `ChannelDispatch.kt` 的先例）。单位换算正是最容易
 *   悄悄出错的地方：`bytes / 1024 / 1024` 在 Long 上是**整除截断**、亮度是 0-255
 *   不是 0-100、电池温度是**十分之一摄氏度**。这些错不会崩，只会显示成一个
 *   看起来很合理的错数字。
 * - [readRaw] 才碰 Android API，逐字段 try/catch，读不到就放 null。
 *
 * ⚠ **"读不到"必须是 null，不能是 0 / -1**：填 0 会让"存储读不到"显示成"存储已用满"，
 * 那是把未知伪装成已知 —— 比不显示更糟。未知字段一律进 `unavailable` 列表，
 * 界面上要能看出"这一项没读到"（T18 消费）。
 */
object DeviceSnapshot {

    /** 快照里会被读到的字段名（Dart/界面按这个名字查 `unavailable`） */
    private const val KEY_MODEL = "model"
    private const val KEY_BRAND = "brand"
    private const val KEY_MANUFACTURER = "manufacturer"
    private const val KEY_OS_VERSION = "osVersion"
    private const val KEY_SDK_INT = "sdkInt"
    private const val KEY_NETWORK = "network"
    private const val KEY_BATTERY_LEVEL = "batteryLevel"
    private const val KEY_BATTERY_CHARGING = "batteryCharging"
    private const val KEY_BATTERY_TEMP = "batteryTemperatureC"
    private const val KEY_STORAGE_TOTAL = "storageTotalMb"
    private const val KEY_STORAGE_FREE = "storageFreeMb"
    private const val KEY_MEM_TOTAL = "memoryTotalMb"
    private const val KEY_MEM_AVAILABLE = "memoryAvailableMb"
    private const val KEY_BRIGHTNESS = "brightnessPercent"
    private const val KEY_BRIGHTNESS_MODE = "brightnessMode"
    private const val KEY_UPTIME = "uptimeSeconds"
    private const val KEY_CAPTURED_AT = "capturedAtMs"
    private const val KEY_UNAVAILABLE = "unavailable"

    /**
     * 单位换算与"未知"记账。输入是 [readRaw] 的原始值（可为 null），
     * 输出是给 Flutter 的扁平 Map + `unavailable` 列表。
     */
    fun normalize(raw: Map<String, Any?>, capturedAt: Long): Map<String, Any?> {
        val unavailable = mutableListOf<String>()

        fun put(map: MutableMap<String, Any?>, key: String, value: Any?) {
            if (value == null) unavailable.add(key) else map[key] = value
        }

        val out = LinkedHashMap<String, Any?>()
        put(out, KEY_MODEL, nonBlank(raw[KEY_MODEL] as? String))
        put(out, KEY_BRAND, nonBlank(raw[KEY_BRAND] as? String))
        put(out, KEY_MANUFACTURER, nonBlank(raw[KEY_MANUFACTURER] as? String))
        put(out, KEY_OS_VERSION, nonBlank(raw[KEY_OS_VERSION] as? String))
        put(out, KEY_SDK_INT, (raw[KEY_SDK_INT] as? Int)?.takeIf { it > 0 })
        put(out, KEY_NETWORK, nonBlank(raw[KEY_NETWORK] as? String))

        put(out, KEY_BATTERY_LEVEL, (raw[KEY_BATTERY_LEVEL] as? Int)?.takeIf { it in 0..100 })
        put(out, KEY_BATTERY_CHARGING, raw[KEY_BATTERY_CHARGING] as? Boolean)
        put(out, KEY_BATTERY_TEMP, temperatureC(raw[KEY_BATTERY_TEMP] as? Int))

        put(out, KEY_STORAGE_TOTAL, toMb(raw[KEY_STORAGE_TOTAL] as? Long))
        put(out, KEY_STORAGE_FREE, toMb(raw[KEY_STORAGE_FREE] as? Long))
        put(out, KEY_MEM_TOTAL, toMb(raw[KEY_MEM_TOTAL] as? Long))
        put(out, KEY_MEM_AVAILABLE, toMb(raw[KEY_MEM_AVAILABLE] as? Long))

        put(out, KEY_BRIGHTNESS, brightnessPercent(raw[KEY_BRIGHTNESS] as? Int))
        put(out, KEY_BRIGHTNESS_MODE, brightnessMode(raw[KEY_BRIGHTNESS_MODE] as? Int))

        val uptime = (raw[KEY_UPTIME] as? Long)?.takeIf { it >= 0L }
        put(out, KEY_UPTIME, uptime?.let { it / 1000L })

        out[KEY_CAPTURED_AT] = capturedAt
        out[KEY_UNAVAILABLE] = unavailable
        return out
    }

    /** 空串与全空白都算"没读到"（Build 字段在个别 ROM 上会返回 ""） */
    private fun nonBlank(v: String?): String? = v?.trim()?.takeIf { it.isNotEmpty() }

    /**
     * 字节 → MB，保留 1 位小数。
     *
     * ⚠ 不能写 `bytes / 1024 / 1024`：Long 整除会把 1.6GB 显示成 1GB。
     * 0 与负数都按"没读到"处理（0 字节的分区不是快照想要的信息）。
     */
    internal fun toMb(bytes: Long?): Double? {
        if (bytes == null || bytes <= 0L) return null
        return (bytes * 10.0 / 1048576.0).roundToInt() / 10.0
    }

    /** `BatteryManager.EXTRA_TEMPERATURE` 的单位是**十分之一摄氏度**，不做取整 */
    internal fun temperatureC(tenths: Int?): Double? {
        if (tenths == null || tenths <= 0) return null
        return tenths / 10.0
    }

    /**
     * 系统亮度值域通常是 0-255（不是 0-100），部分 ROM 在自动亮度下返回 -1，
     * 也有 ROM（含模拟器）直接用 0-100。
     * 0 是合法值（屏幕最暗），不能与"读不到"混为一谈 ⇒ 判的是负数，不是 `<= 0`。
     */
    internal fun brightnessPercent(raw: Int?): Int? {
        if (raw == null || raw < 0) return null
        if (raw <= 100) return raw
        return (raw.coerceAtMost(255) * 100.0 / 255.0).roundToInt()
    }

    internal fun brightnessMode(raw: Int?): String? = when (raw) {
        Settings.System.SCREEN_BRIGHTNESS_MODE_AUTOMATIC -> "auto"
        Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL -> "manual"
        else -> null
    }

    /**
     * 网络类型的判定顺序是刻意的：**先 VPN/以太网/WiFi，最后才蜂窝**。
     * VPN 之下跑的仍是蜂窝时，用户看到的应该是"走 VPN"——那才是他关心的事实。
     */
    internal fun networkTypeOf(hasNetwork: Boolean, transports: Set<Int>): String {
        if (!hasNetwork) return "none"
        if (transports.contains(NetworkCapabilities.TRANSPORT_VPN)) return "vpn"
        if (transports.contains(NetworkCapabilities.TRANSPORT_WIFI)) return "wifi"
        if (transports.contains(NetworkCapabilities.TRANSPORT_ETHERNET)) return "ethernet"
        if (transports.contains(NetworkCapabilities.TRANSPORT_CELLULAR)) return "cellular"
        return "other"
    }

    /**
     * 逐字段读 Android 状态。**每个字段单独容错**：任一读失败只让那一项进
     * `unavailable`，不换默认值、也不让整次快照失败。
     */
    fun readRaw(context: Context): Map<String, Any?> {
        val raw = LinkedHashMap<String, Any?>()
        fun grab(key: String, block: () -> Any?) {
            raw[key] = try {
                block()
            } catch (e: Exception) {
                null
            }
        }

        grab(KEY_MODEL) { Build.MODEL }
        grab(KEY_BRAND) { Build.BRAND }
        grab(KEY_MANUFACTURER) { Build.MANUFACTURER }
        grab(KEY_OS_VERSION) { Build.VERSION.RELEASE }
        grab(KEY_SDK_INT) { Build.VERSION.SDK_INT }
        grab(KEY_NETWORK) { readNetworkType(context) }

        val sticky = try {
            context.registerReceiver(
                null,
                IntentFilter(Intent.ACTION_BATTERY_CHANGED),
            )
        } catch (e: Exception) {
            null
        }
        grab(KEY_BATTERY_LEVEL) {
            (context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager)
                ?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        }
        grab(KEY_BATTERY_CHARGING) {
            sticky?.getIntExtra(BatteryManager.EXTRA_STATUS, -1)?.let {
                it == BatteryManager.BATTERY_STATUS_CHARGING ||
                    it == BatteryManager.BATTERY_STATUS_FULL
            }
        }
        grab(KEY_BATTERY_TEMP) { sticky?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1) }

        grab(KEY_STORAGE_TOTAL) { stat(context).totalBytes }
        grab(KEY_STORAGE_FREE) { stat(context).availableBytes }
        // 这次取值本身也要容错：它在两个 grab 之外，抛出会让整个协程失败、
        // result 永不回复 ⇒ Flutter 侧那个 await 永远挂着（比读不到更糟）。
        val mem = try {
            memoryInfo(context)
        } catch (e: Exception) {
            null
        }
        grab(KEY_MEM_TOTAL) { mem?.totalMem }
        grab(KEY_MEM_AVAILABLE) { mem?.availMem }

        grab(KEY_BRIGHTNESS) {
            Settings.System.getInt(context.contentResolver, Settings.System.SCREEN_BRIGHTNESS)
        }
        grab(KEY_BRIGHTNESS_MODE) {
            Settings.System.getInt(
                context.contentResolver,
                Settings.System.SCREEN_BRIGHTNESS_MODE,
            )
        }
        grab(KEY_UPTIME) { SystemClock.elapsedRealtime() }
        return raw
    }

    private fun stat(context: Context): StatFs = StatFs(context.applicationContext.dataDir.path)

    /**
     * 内存信息：Android 只有**填充式**的 `getMemoryInfo(out)`（android.jar 里没有无参
     * 重载），所以在这里读一次、两个字段共用同一份快照 —— 分两次读会出现
     * "可用内存比总内存还大"的错乱组合。
     */
    private fun memoryInfo(context: Context): ActivityManager.MemoryInfo? {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            ?: return null
        return ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
    }

    private fun readNetworkType(context: Context): String? {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return null
        val network = cm.activeNetwork ?: return networkTypeOf(false, emptySet())
        val caps = cm.getNetworkCapabilities(network) ?: return networkTypeOf(false, emptySet())
        val transports = setOf(
            NetworkCapabilities.TRANSPORT_VPN,
            NetworkCapabilities.TRANSPORT_WIFI,
            NetworkCapabilities.TRANSPORT_ETHERNET,
            NetworkCapabilities.TRANSPORT_CELLULAR,
        ).filter { caps.hasTransport(it) }.toSet()
        return networkTypeOf(true, transports)
    }
}
