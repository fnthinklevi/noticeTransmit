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

    /**
     * 完整的 webhook 通道配置（含 secret / type / 模板，用于签名、送达校验与自定义模板）
     */
    data class WebhookChannelConfig(
        val url: String,
        val secret: String?,
        val type: WebhookPayloadBuilder.WebhookType,
        val messageFormat: String = "default",
        val messageTemplate: String? = null
    )

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

    /**
     * 返回启用的 webhook 通道完整配置（含 secret 与 type）
     */
    fun getWebhookChannelConfigs(): List<WebhookChannelConfig> {
        val json = prefs.getString(KEY_WEBHOOK_URLS, "[]")
        return try {
            val array = JSONArray(json)
            val list = mutableListOf<WebhookChannelConfig>()
            for (i in 0 until array.length()) {
                val obj = array.getJSONObject(i)
                val url = obj.optString("url", "")
                val enabled = obj.optBoolean("enabled", true)
                if (!enabled || url.isEmpty()) continue

                val secret = obj.optString("secret", "")
                    .takeIf { it.isNotEmpty() && it != "null" }
                val typeStr = obj.optString("type", obj.optString("channel_type", "generic"))
                val type = parseWebhookType(typeStr, url)
                val messageFormat = obj.optString("message_format", "default").ifEmpty { "default" }
                val messageTemplate = obj.optString("message_template", "")
                    .takeIf { it.isNotEmpty() && it != "null" }
                list.add(WebhookChannelConfig(url, secret, type, messageFormat, messageTemplate))
            }
            list
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse webhook channel configs", e)
            // 兜底：用 URL 列表，无签名
            getWebhookUrls().map {
                WebhookChannelConfig(it, null, WebhookPayloadBuilder.detectType(it))
            }
        }
    }

    private fun parseWebhookType(
        typeStr: String,
        url: String
    ): WebhookPayloadBuilder.WebhookType {
        return when (typeStr.lowercase()) {
            "wechat_work", "wechatwork", "0" -> WebhookPayloadBuilder.WebhookType.WECHAT_WORK
            "dingtalk", "1" -> WebhookPayloadBuilder.WebhookType.DINGTALK
            "feishu", "2" -> WebhookPayloadBuilder.WebhookType.FEISHU
            "generic", "3" -> WebhookPayloadBuilder.WebhookType.GENERIC
            else -> WebhookPayloadBuilder.detectType(url)
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