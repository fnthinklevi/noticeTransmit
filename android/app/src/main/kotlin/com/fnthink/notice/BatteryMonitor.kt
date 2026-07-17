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
    companion object {
        private const val TAG = "BatteryMonitor"
        private const val POLLING_INTERVAL_MS = 60000L
    }

    private var batteryRules = emptyList<BatteryRule>()
    @Volatile private var _enabled = true
    @Volatile private var prevLevel = -1
    @Volatile private var prevIsCharging = false
    @Volatile private var initialized = false
    @Volatile private var deviceName: String = ""
    private var notificationCallback: ((NotificationInfo) -> Unit)? = null

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

        // 首次调用只记录基准状态，避免服务启动/重启时因当前已满足条件而误报
        if (!initialized) {
            prevLevel = currentLevel
            prevIsCharging = isCharging
            initialized = true
            return null
        }

        for (rule in batteryRules) {
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

    private fun buildBatteryNotification(
        rule: BatteryRule,
        currentLevel: Int,
        isCharging: Boolean
    ): NotificationInfo {
        val defaultTitle = when (rule.type) {
            "charging" -> "开始充电"
            "discharging" -> "断开充电"
            "level_above" -> "电量达到${rule.threshold}%"
            "level_below" -> "电量低于${rule.threshold}%"
            "level_equals" -> "电量等于${rule.threshold}%"
            else -> "电量提醒"
        }
        val title = if (rule.title.isNotBlank()) rule.title else defaultTitle
        val content = "当前电量: ${currentLevel}%${if (isCharging) " (充电中)" else ""}"
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
    val voltage: Int
)