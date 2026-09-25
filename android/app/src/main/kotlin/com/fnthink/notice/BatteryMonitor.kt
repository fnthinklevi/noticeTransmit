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
    @Volatile private var deviceName: String = ""
    private var notificationCallback: ((NotificationInfo) -> Unit)? = null

    /** v1.59：温度规则（独立于电量规则，由 TemperatureService 经通道同步） */
    private var temperatureRules = emptyList<BatteryRule>()

    /**
     * T19：判据（阈值 / crossing 迟滞 / 冷却 / 顺序）全在 [NotificationEngine]。
     * 本类只余"读数 + 渲染 + 投递"三件事，状态（prevLevel / prevTemps / 冷却截止）
     * 由引擎自持 —— 两处各存一份迟早一份松一份紧，表现是"某类告警永远不来"。
     */
    private val engine = NotificationEngine()

    companion object {
        private const val TAG = "BatteryMonitor"
        private const val POLLING_INTERVAL_MS = 60000L
    }

    /** 两族任一配了规则才值得花一次电池 syscall（原先只看电量规则，温度族被静默饿死） */
    fun hasRules(): Boolean = engine.hasRules(batteryRules, temperatureRules)

    private val handler = Handler(Looper.getMainLooper())
    private val pollingRunnable = object : Runnable {
        override fun run() {
            if (hasRules()) {
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

    /**
     * 采一次样并交给引擎；命中就把结论渲染成通知，否则返回 null。
     *
     * 分工是 T19 的重点：**读数是 Android 的，判据是纯 Kotlin 的**。判据搬进
     * [NotificationEngine] 之后，阈值 / crossing 迟滞 / 冷却 / 顺序都能在 JVM 上逐条钉住，
     * 不必再造 Robolectric，也不必靠真机"等一次温度波动"来验证。
     *
     * ⚠ 先判 `_enabled` / `hasRules()` 再读电池：与现状一致，总开关关掉或两族都没配规则时
     * 不该每 60s 还去做一次 `registerReceiver` syscall（引擎内部也会判，这里只是不白读）。
     */
    fun checkBatteryAndNotify(): NotificationInfo? {
        if (!_enabled || !hasRules()) return null
        val batteryInfo = getBatteryInfo() ?: return null
        val reading = EngineReading(
            level = batteryInfo.level,
            charging = batteryInfo.isCharging,

            // 温度与电量同源（一次 ACTION_BATTERY_CHANGED 同时取，避免重复唤醒设备）
            temperatures = readCurrentTemps(batteryInfo.temperatureC),
        )
        return when (
            val decision = engine.evaluate(
                enabled = _enabled,
                batteryRules = batteryRules,
                temperatureRules = temperatureRules,
                reading = reading,
                now = System.currentTimeMillis(),
            )
        ) {
            is EngineDecision.BatteryFire ->
                buildBatteryNotification(decision.rule, decision.level, decision.charging)

            is EngineDecision.TemperatureFire ->
                buildTemperatureNotification(decision.rule, decision.temperatureC)

            is EngineDecision.Silent -> {
                // 「未满足」与「首轮基准」是常态，不刷日志；其余（冷却中、未 crossing、
                // 读不到）才是"规则在但没响"的现场，T21 的影子比对也要靠这些原因分诊。
                if (decision.reason != Silence.NOT_TRIGGERED &&
                    decision.reason != Silence.BASELINE
                ) {
                    Log.d(TAG, "引擎本轮不推：${decision.reason}")
                }
                null
            }
        }
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
        val title = NotificationEngine.titleOf(rule, defaultTitle)
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
        val title = NotificationEngine.titleOf(rule, defaultTitle)
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
        // v1.59：电池温度。换算规则只此一份 —— 复用 `DeviceSnapshot.temperatureC`，
        // 与设备快照那条链共用"缺失 / ≤0 一律算读不到"的口径（0℃ 是合法读数，
        // 但传感器给 0 时是"不可用"，两者在 EXTRA_TEMPERATURE 上无法区分，宁可判缺失）。
        val temperatureC = DeviceSnapshot.temperatureC(
            intent.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1).takeIf { it > 0 },
        )

        return BatteryInfo(
            level = (level * 100 / scale).coerceIn(0, 100),
            isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                status == BatteryManager.BATTERY_STATUS_FULL,
            voltage = voltage,
            // T19 修掉的缺陷：这个值原先算出来了却没塞进 BatteryInfo ⇒
            // `readCurrentTemps(null)` 里永没有 battery_temp_above，
            // 用户配的「电池温度高于 X」规则**永远不响**，而界面上看不出任何异常。
            temperatureC = temperatureC,
        )
    }
}

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
