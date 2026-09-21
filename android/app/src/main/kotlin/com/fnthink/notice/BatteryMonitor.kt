package com.fnthink.notice

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.*

class BatteryMonitor(private val context: Context) {
    private var batteryRules = emptyList<BatteryRule>()
    @Volatile private var _enabled = true
    @Volatile private var prevLevel = -1
    @Volatile private var prevIsCharging = false
    @Volatile private var initialized = false
    @Volatile private var deviceName: String = ""
    private var notificationCallback: ((NotificationInfo) -> Unit)? = null

    // v1.59 温度维度状态：各维度上次温度（crossing 判定）+ 触发冷却期（防温度波动重复推送）
    private val prevTemps = mutableMapOf<String, Double>()
    private val tempCooldownUntil = mutableMapOf<String, Long>()
    private var temperatureRules = emptyList<BatteryRule>()

    companion object {
        private const val TAG = "BatteryMonitor"
        private const val POLLING_INTERVAL_MS = 60000L

        /** 温度规则触发后的冷却期（毫秒）：温度在阈值附近波动，需冷却防抖 */
        const val TEMP_COOLDOWN_MS = 30 * 60 * 1000L

        /** 温度规则类型集合（与 Dart battery_service 的规则类型契约一致） */
        val TEMP_RULE_TYPES = setOf(
            "battery_temp_above", // 电池温度（BatteryManager，最可靠）
            "device_temp_above",  // 设备整体温度（thermal_zone 最热温区）
            "screen_temp_above",  // 屏幕温度（display/lcd 温区，部分机型不可得）
        )

        /** 温度 crossing：由低于阈值变为达到阈值（纯函数，JVM 可测） */
        fun isTempCrossing(prev: Double?, current: Double, threshold: Int): Boolean =
            prev != null && prev < threshold && current >= threshold

        /** 冷却期是否生效中（纯函数） */
        fun isCooldownActive(cooldownUntil: Long, now: Long): Boolean = cooldownUntil > now
    }

    private val handler = Handler(Looper.getMainLooper())
    private val pollingRunnable = object : Runnable {
        override fun run() {
            if (batteryRules.isNotEmpty()) {
                val batteryInfo = checkBatteryAndNotify()
                if (batteryInfo != null) {
                    notificationCallback?.invoke(batteryInfo)
                    Log.d(TAG, "Battery notification via polling: ${batteryInfo.title}")
                }
            }
            handler.postDelayed(this, POLLING_INTERVAL_MS)
        }
    }

    fun setDeviceName(name: String) {
        deviceName = name
    }

    fun setEnabled(enabled: Boolean) {
        _enabled = enabled
    }

    fun setNotificationCallback(callback: (NotificationInfo) -> Unit) {
        notificationCallback = callback
    }

    fun updateRules(rulesJson: String) {
        try {
            val jsonArray = JSONArray(rulesJson)
            batteryRules = parseBatteryRules(jsonArray)
            Log.d(TAG, "Battery rules updated: ${batteryRules.size} rules")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse battery rules", e)
            batteryRules = emptyList()
        }
    }

    fun startPolling() {
        stopPolling()
        handler.post(pollingRunnable)
        Log.d(TAG, "Battery polling started (60s interval)")
    }

    fun stopPolling() {
        handler.removeCallbacks(pollingRunnable)
        Log.d(TAG, "Battery polling stopped")
    }

    fun getBatteryInfo(): BatteryInfo? {
        val intent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        return intent?.let { parseBatteryIntent(it) }
    }

    fun checkBatteryAndNotify(): NotificationInfo? {
        if (!_enabled || batteryRules.isEmpty()) return null

        val batteryInfo = getBatteryInfo() ?: return null
        val currentLevel = batteryInfo.level
        val isCharging = batteryInfo.isCharging

        // v1.59：温度维度读数（与电量同一次 ACTION_BATTERY_CHANGED 采样）
        val currentTemps = readCurrentTemps(batteryInfo.temperatureC)

        // 首次调用只记录基准状态，避免服务启动/重启时因当前已满足条件而误报
        if (!initialized) {
            prevLevel = currentLevel
            prevIsCharging = isCharging
            initialized = true
            return null
        }

        // v1.59 温度维度先行判定（与电量规则同循环、状态独立，互不干扰）：
        // 每个温度规则一条独立状态（prevTemps）+ 独立冷却期，避免互相挤占
        for (rule in batteryRules + temperatureRules) {
            if (rule.type in TEMP_RULE_TYPES) {
                val dimValue = currentTemps[rule.type] ?: continue // 该维度读不到 → 规则不触发
                val prevTemp = prevTemps[rule.type]
                prevTemps[rule.type] = dimValue

                val triggered = dimValue >= rule.threshold
                // crossing：由不满足变为满足（与电量规则同语义）
                val isCrossing = isTempCrossing(prevTemp, dimValue, rule.threshold)
                // 冷却：触发后 TEMP_COOLDOWN_MS 内不重复推送（温度在阈值附近波动属正常）
                val cooling = isCooldownActive(
                    tempCooldownUntil[rule.type] ?: 0L,
                    System.currentTimeMillis(),
                )

                if (triggered && isCrossing && !cooling) {
                    tempCooldownUntil[rule.type] =
                        System.currentTimeMillis() + TEMP_COOLDOWN_MS
                    return buildTemperatureNotification(rule, dimValue)
                }
                continue
            }

            val triggered = when (rule.type) {
                "level_below" -> currentLevel <= rule.threshold && !isCharging
                "level_above" -> currentLevel >= rule.threshold && isCharging
                "level_equals" -> currentLevel == rule.threshold
                "charging" -> isCharging && !prevIsCharging
                "discharging" -> !isCharging && prevIsCharging
                else -> false
            }
            // 仅“由不满足变为满足”的瞬间触发，避免轮询/广播重复推送
            val isCrossing = when (rule.type) {
                "level_below" -> prevLevel > rule.threshold
                "level_above" -> prevLevel < rule.threshold
                "level_equals" -> prevLevel != rule.threshold
                "charging", "discharging" -> true
                else -> false
            }

            if (triggered && isCrossing) {
                prevLevel = currentLevel
                prevIsCharging = isCharging
                return buildBatteryNotification(rule, currentLevel, isCharging)
            }
        }

        prevLevel = currentLevel
        prevIsCharging = isCharging
        return null
    }

    /**
     * 当前各温度维度的读数（℃）。与电量采样同源（一次 ACTION_BATTERY_CHANGED
     * 同时取电量与电池温度，避免重复唤醒设备），设备/屏幕维度来自 thermal_zone
     * sysfs 探测（部分机型不可得 → 该维度不参与判定）。
     */
    /** 温度规则触发通知：标题含维度与阈值，正文为当前温度读数 */
    private fun buildTemperatureNotification(
        rule: BatteryRule,
        currentTempC: Double,
    ): NotificationInfo {
        val dimLabel = I18n.temperatureDimLabel(rule.type)
        val defaultTitle = I18n.temperatureRuleTitle(dimLabel, rule.threshold)
        val title = if (rule.title.isNotBlank()) rule.title else defaultTitle
        val content = I18n.temperatureContent(dimLabel, currentTempC)
        return NotificationInfo(
            id = "battery_${System.currentTimeMillis()}",
            title = title,
            content = content,
            subText = "",
            packageName = "com.fnthink.notice",
            appName = I18n.appName(),
            postTime = System.currentTimeMillis(),
            time = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date()),
            type = "battery",
            deviceName = deviceName
        )
    }

    /** v1.59：更新温度规则列表（独立于电量规则，由 TemperatureService 经通道同步） */
    fun updateTemperatureRules(rulesJson: String) {
        try {
            val jsonArray = org.json.JSONArray(rulesJson)
            temperatureRules = parseBatteryRules(jsonArray)
            Log.d(TAG, "Temperature rules updated: ${temperatureRules.size} rules")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse temperature rules", e)
        }
    }

    private fun readCurrentTemps(batteryTempC: Double?): Map<String, Double> {
        val temps = mutableMapOf<String, Double>()
        if (batteryTempC != null) temps["battery_temp_above"] = batteryTempC
        val zones = DeviceThermalReader.readZones()
        // 设备整体：取最热温区（CPU/GPU/电池等温区中的最高者，代表整机热状态）
        DeviceThermalReader.hottest(zones)?.let { temps["device_temp_above"] = it }
        // 屏幕：type 含 display/lcd/tsd 的温区（部分机型存在，探测式支持）
        DeviceThermalReader.byTypeFragments(zones, listOf("display", "lcd", "tsd", "screen"))
            ?.let { temps["screen_temp_above"] = it }
        return temps
    }

    private fun buildBatteryNotification(
        rule: BatteryRule,
        currentLevel: Int,
        isCharging: Boolean
    ): NotificationInfo {
        // 中英双语（跟随应用语言设置），避免英文模式下推送内容仍为中文
        val defaultTitle = I18n.batteryRuleTitle(rule.type, rule.threshold)
        val title = if (rule.title.isNotBlank()) rule.title else defaultTitle
        val content = I18n.batteryLevelText(currentLevel, isCharging)
        return NotificationInfo(
            id = "battery_${System.currentTimeMillis()}",
            title = title,
            content = content,
            subText = "",
            packageName = "com.fnthink.notice",
            appName = I18n.appName(),
            postTime = System.currentTimeMillis(),
            time = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date()),
            type = "battery",
            deviceName = deviceName
        )
    }

    private fun parseBatteryRules(jsonArray: JSONArray): List<BatteryRule> {
        val rules = mutableListOf<BatteryRule>()
        for (i in 0 until jsonArray.length()) {
            try {
                val obj = jsonArray.getJSONObject(i)
                rules.add(BatteryRule(
                    id = obj.optString("id", ""),
                    type = obj.optString("type", "level_below"),
                    threshold = obj.optInt("value", 20),
                    enabled = obj.optBoolean("enabled", true),
                    title = obj.optString("title", "")
                ))
            } catch (e: Exception) {
                Log.w(TAG, "Failed to parse battery rule at index $i", e)
            }
        }
        return rules.filter { it.enabled }
    }

    private fun parseBatteryIntent(intent: Intent): BatteryInfo {
        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, 0)
        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
        val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, BatteryManager.BATTERY_STATUS_UNKNOWN)
        val voltage = intent.getIntExtra(BatteryManager.EXTRA_VOLTAGE, 0)
        // v1.59：电池温度（EXTRA_TEMPERATURE 单位 0.1℃，如 265 = 26.5℃）
        val temperatureC = intent.getIntExtra(
            BatteryManager.EXTRA_TEMPERATURE,
            Int.MIN_VALUE,
        ).takeIf { it != Int.MIN_VALUE }?.let { it / 10.0 }

        return BatteryInfo(
            level = (level * 100 / scale).coerceIn(0, 100),
            isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                    status == BatteryManager.BATTERY_STATUS_FULL,
            voltage = voltage
        )
    }
}

data class BatteryRule(
    val id: String,
    val type: String,
    val threshold: Int,
    val enabled: Boolean,
    val title: String = ""
)

data class BatteryInfo(
    val level: Int,
    val isCharging: Boolean,
    val voltage: Int,
    val temperatureC: Double? = null,
)


// ═══════════════════════════════════════════════════════════════════
// v1.59 温度维度：通知构建 + 热区读取器
// ═══════════════════════════════════════════════════════════════════

/**
 * thermal_zone sysfs 读取器（v1.59 温度维度数据源）。
 *
 * Android 无统一的「屏幕/SoC 温度」公开 API；`/sys/class/thermal/thermal_zone *
 * 的 type/temp 是各机型暴露温区的通用途径（Android 10+ 部分机型限制读取，
 * 读取失败/为空时该维度自然不可用，温度规则不触发——不会误报）。
 */
object DeviceThermalReader {

    private var cachedAt = 0L
    private var cachedZones: List<Pair<String, Double>> = emptyList()

    /** 温区列表：type → ℃（读取失败或非法值跳过；30s 缓存避免频繁 IO） */
    fun readZones(): List<Pair<String, Double>> {
        val now = System.currentTimeMillis()
        if (now - cachedAt < 30_000L) return cachedZones
        val zones = mutableListOf<Pair<String, Double>>()
        try {
            val dir = java.io.File("/sys/class/thermal")
            val zoneFiles = dir.listFiles { f -> f.name.startsWith("thermal_zone") } ?: emptyArray()
            for (zone in zoneFiles) {
                try {
                    val type = java.io.File(zone, "type").readText().trim()
                    val raw = java.io.File(zone, "temp").readText().trim().toIntOrNull()
                        ?: continue
                    if (raw <= 0) continue // 空温区（0 或 -）跳过
                    zones.add(type to raw / 1000.0)
                } catch (_: Exception) {
                }
            }
        } catch (_: Exception) {
        }
        cachedAt = now
        cachedZones = zones
        return zones
    }

    /** 最热温区的温度（设备整体热状态的代理指标） */
    fun hottest(zones: List<Pair<String, Double>>): Double? =
        zones.maxByOrNull { it.second }?.second

    /** type 含任一片段（lcd/display/screen 等）的温区温度（屏幕维度，探测式） */
    fun byTypeFragments(
        zones: List<Pair<String, Double>>,
        fragments: List<String>,
    ): Double? = zones
        .filter { (type, _) -> fragments.any { type.lowercase().contains(it) } }
        .maxByOrNull { it.second }?.second
}