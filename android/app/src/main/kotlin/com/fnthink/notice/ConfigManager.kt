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
        private const val FLUTTER_PREFS_NAME = "FlutterSharedPreferences"
        private const val KEY_WEBHOOK_URLS = "flutter.webhook_channels"
        private const val KEY_ENABLED_PACKAGES = "flutter.enabled_packages"
        private const val KEY_APP_FILTER_MODE = "flutter.app_filter_mode"
        private const val KEY_WHITELIST_KEYWORDS = "flutter.whitelist_keywords"
        private const val KEY_BLACKLIST_KEYWORDS = "flutter.blacklist_keywords"
        private const val KEY_DEVICE_NAME = "flutter.device_name"
        private const val KEY_BATTERY_RULES = "flutter.battery_rules"
        private const val KEY_BATTERY_NOTIFY_ENABLED = "flutter.battery_notify_enabled"
    }

    private val prefs: SharedPreferences by lazy {
        context.getSharedPreferences(FLUTTER_PREFS_NAME, Context.MODE_PRIVATE)
    }

    fun getWebhookUrls(): List<String> {
        val json = prefs.getString(KEY_WEBHOOK_URLS, "[]")
        return try {
            val array = JSONArray(json)
            val list = mutableListOf<String>()
            for (i in 0 until array.length()) {
                val obj = array.getJSONObject(i)
                val url = obj.optString("url", "")
                val enabled = obj.optBoolean("enabled", true)
                if (enabled && url.isNotEmpty()) {
                    list.add(url)
                }
            }
            list
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse webhook channels", e)
            getStringList("flutter.webhook_urls")
        }
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

    fun getAppFilterMode(): String {
        return prefs.getString(KEY_APP_FILTER_MODE, "allow") ?: "allow"
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

    fun getBatteryNotifyEnabled(): Boolean {
        return prefs.getBoolean(KEY_BATTERY_NOTIFY_ENABLED, true)
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