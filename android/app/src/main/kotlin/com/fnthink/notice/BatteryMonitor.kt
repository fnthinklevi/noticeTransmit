package com.fnthink.notice

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.*

class BatteryMonitor(private val context: Context) {
    companion object {
        private const val TAG = "BatteryMonitor"
    }

    private var batteryRules = emptyList<BatteryRule>()
    private var lastNotifiedLevel = -1
    private var deviceName: String = ""

    fun setDeviceName(name: String) {
        deviceName = name
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

    fun getBatteryInfo(): BatteryInfo {
        val intent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        return intent?.let { parseBatteryIntent(it) } ?: BatteryInfo(0, false, 0)
    }

    fun checkBatteryAndNotify(): NotificationInfo? {
        if (batteryRules.isEmpty()) return null

        val batteryInfo = getBatteryInfo()
        val currentLevel = batteryInfo.level

        if (currentLevel == lastNotifiedLevel) return null

        for (rule in batteryRules) {
            val shouldNotify = when (rule.type) {
                "below" -> currentLevel <= rule.threshold && !batteryInfo.isCharging
                "above" -> currentLevel >= rule.threshold && batteryInfo.isCharging
                "exact" -> currentLevel == rule.threshold
                else -> false
            }

            if (shouldNotify) {
                lastNotifiedLevel = currentLevel
                val title = "电量${rule.type}${rule.threshold}%"
                val content = "当前电量: ${currentLevel}%${if (batteryInfo.isCharging) " (充电中)" else ""}"

                return NotificationInfo(
                    id = "battery_${System.currentTimeMillis()}",
                    title = title,
                    content = content,
                    subText = "",
                    packageName = "com.fnthink.notice",
                    appName = "通知传输器",
                    postTime = System.currentTimeMillis(),
                    time = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date()),
                    type = "battery",
                    deviceName = deviceName
                )
            }
        }

        return null
    }

    private fun parseBatteryRules(jsonArray: JSONArray): List<BatteryRule> {
        val rules = mutableListOf<BatteryRule>()
        for (i in 0 until jsonArray.length()) {
            try {
                val obj = jsonArray.getJSONObject(i)
                rules.add(BatteryRule(
                    id = obj.optString("id", ""),
                    type = obj.optString("type", "below"),
                    threshold = obj.optInt("threshold", 20),
                    enabled = obj.optBoolean("enabled", true)
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
    val enabled: Boolean
)

data class BatteryInfo(
    val level: Int,
    val isCharging: Boolean,
    val voltage: Int
)