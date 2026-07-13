package com.fnthink.notice

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream

class ConfigManager(private val context: Context) {
    companion object {
        private const val TAG = "ConfigManager"
        private const val PREFS_NAME = "notification_monitor_prefs"
        private const val KEY_WEBHOOK_URLS = "webhook_urls"
        private const val KEY_ENABLED_PACKAGES = "enabled_packages"
        private const val KEY_WHITELIST_KEYWORDS = "whitelist_keywords"
        private const val KEY_BLACKLIST_KEYWORDS = "blacklist_keywords"
        private const val KEY_DEVICE_NAME = "device_name"
        private const val KEY_BATTERY_RULES = "battery_rules"
    }

    private val prefs: SharedPreferences by lazy {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    fun getWebhookUrls(): List<String> {
        return getStringList(KEY_WEBHOOK_URLS)
    }

    fun getEnabledPackages(): Set<String> {
        val json = prefs.getString(KEY_ENABLED_PACKAGES, "[]")
        return try {
            val array = JSONArray(json)
            val set = mutableSetOf<String>()
            for (i in 0 until array.length()) {
                set.add(array.getString(i))
            }
            set
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse enabled packages", e)
            emptySet()
        }
    }

    fun getWhitelistKeywords(): List<String> {
        return getStringList(KEY_WHITELIST_KEYWORDS)
    }

    fun getBlacklistKeywords(): List<String> {
        return getStringList(KEY_BLACKLIST_KEYWORDS)
    }

    fun getDeviceName(): String {
        return prefs.getString(KEY_DEVICE_NAME, "") ?: ""
    }

    fun getBatteryRules(): String {
        return prefs.getString(KEY_BATTERY_RULES, "[]") ?: "[]"
    }

    fun loadHotfixConfig(): HotfixConfig {
        val hotfixAppNames = mutableMapOf<String, String>()
        val hotfixNotificationTypes = mutableMapOf<String, String>()

        val hotfixFile = File(context.filesDir, "hotfix.json")
        if (hotfixFile.exists()) {
            try {
                val inputStream = FileInputStream(hotfixFile)
                val jsonStr = inputStream.bufferedReader().use { it.readText() }
                inputStream.close()

                val json = JSONObject(jsonStr)

                if (json.has("appNames")) {
                    val appNamesObj = json.getJSONObject("appNames")
                    val keys = appNamesObj.keys()
                    while (keys.hasNext()) {
                        val key = keys.next()
                        hotfixAppNames[key] = appNamesObj.getString(key)
                    }
                }

                if (json.has("notificationTypes")) {
                    val typesObj = json.getJSONObject("notificationTypes")
                    val keys = typesObj.keys()
                    while (keys.hasNext()) {
                        val key = keys.next()
                        hotfixNotificationTypes[key] = typesObj.getString(key)
                    }
                }

                Log.i(TAG, "Hotfix loaded: ${hotfixAppNames.size} app names, ${hotfixNotificationTypes.size} notification types")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load hotfix config", e)
            }
        }

        return HotfixConfig(hotfixAppNames, hotfixNotificationTypes)
    }

    private fun getStringList(key: String): List<String> {
        val json = prefs.getString(key, "[]")
        return try {
            val array = JSONArray(json)
            val list = mutableListOf<String>()
            for (i in 0 until array.length()) {
                list.add(array.getString(i))
            }
            list
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse string list for key: $key", e)
            emptyList()
        }
    }
}

data class HotfixConfig(
    val appNames: Map<String, String>,
    val notificationTypes: Map<String, String>
)