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
        private val KEY_TEMPERATURE_RULES = "flutter.temperature_rules"
        private const val KEY_BATTERY_NOTIFY_ENABLED = "flutter.battery_notify_enabled"
        private const val KEY_NOTIFICATION_RULES = "flutter.notification_rules"
        private const val KEY_SMS_MONITOR_ENABLED = "flutter.sms_monitor_enabled"
        private const val KEY_SMS_SIM_FILTER = "flutter.sms_sim_filter"
        private const val KEY_SMS_CODE_MONITOR_ENABLED = "flutter.sms_code_monitor_enabled"
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
        val messageTemplate: String? = null,
        // `extraConfig` 字段已删（roadmap D4 / ㊷）：v9 时代它承载 wecom_app 的
        // corpid/agentid/touser，v10 起那些搬进 app_channels.config；此后无人读它
        // （发送层零引用，testWebhook 那条也恒为 null，因为 Dart 不传）。
        // webhook_channels.extra_config **列本身保留**（删列要迁用户数据），只是不再解析。
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
     *
     * 读取优先级（C2）：
     *   1. 加密存储 `secure_webhook_channels`（flutter_secure_storage 同源，含 secret）
     *   2. 明文 `flutter.webhook_channels`（旧版本写入的完整数据，迁移兼容；
     *      新版本明文副本已脱敏、无 secret）
     */
    fun getWebhookChannelConfigs(): List<WebhookChannelConfig> {
        val json = getEncryptedWebhookChannels()
            ?: prefs.getString(KEY_WEBHOOK_URLS, "[]")
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
                // extra_config 不再解析（roadmap D4 / ㊷），见 WebhookChannelConfig 上的说明
                list.add(
                    WebhookChannelConfig(
                        url, secret, type, messageFormat, messageTemplate
                    )
                )
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

    /**
     * 自建应用通道完整配置读取（应用通道体系，与 webhook 通道分离存储）。
     * 返回 AppChannelSpec.kt 定义的 AppChannelConfig（未启用的通道被过滤）。
     */
    fun getAppChannelConfigs(): List<AppChannelConfig> {
        val json = try {
            SecurePrefs.get(context)
                .getString("secure_app_channels", null)
                ?.takeIf { it.isNotEmpty() && it != "[]" }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to read secure app channels", e)
            null
        } ?: return emptyList()
        return try {
            val array = JSONArray(json)
            (0 until array.length()).mapNotNull { i ->
                val obj = array.optJSONObject(i) ?: return@mapNotNull null
                if (!obj.optBoolean("enabled", true)) return@mapNotNull null
                AppChannelConfig(
                    id = obj.optString("id", ""),
                    name = obj.optString("name", ""),
                    type = obj.optString("type", ""),
                    baseUrl = obj.optString("base_url", obj.optString("url", "")),
                    secret = obj.optString("secret", "").takeIf { it.isNotEmpty() && it != "null" } ?: "",
                    config = obj.optJSONObject("config") ?: JSONObject(),
                    messageFormat = obj.optString("message_format", "default").ifEmpty { "default" },
                    enabled = obj.optBoolean("enabled", true),
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse app channel configs", e)
            emptyList()
        }
    }

    fun findAppChannelById(id: String): AppChannelConfig? =
        getAppChannelConfigs().firstOrNull { it.id == id }

    /** 写入自建应用通道（SecurePrefs 加密全量 + 明文脱敏镜像），服务刷新由 ACTION_UPDATE_CONFIG 触发 */
    fun setAppChannels(channels: List<JSONObject>) {
        val array = JSONArray()
        for (obj in channels) array.put(obj)
        try {
            SecurePrefs.get(context)
                .edit()
                .putString("secure_app_channels", array.toString())
                .apply()
        } catch (e: Exception) {
            Log.e(TAG, "写入加密自建应用通道失败", e)
        }
        val sanitized = JSONArray()
        for (i in 0 until array.length()) {
            val obj = array.getJSONObject(i)
            if (obj.has("secret")) obj.remove("secret")
            sanitized.put(obj)
        }
        prefs.edit()
            .putString("flutter.app_channels", sanitized.toString())
            .commit()
    }

    /** 从加密存储读取完整 webhook 通道 JSON（与 flutter_secure_storage 同文件同密钥） */
    private fun getEncryptedWebhookChannels(): String? {
        return try {
            SecurePrefs.get(context)
                .getString("secure_webhook_channels", null)
                ?.takeIf { it.isNotEmpty() && it != "[]" }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to read encrypted webhook channels", e)
            null
        }
    }

    /**
     * 解析存储的 `channel_type`（字符串或早期数字）为平台类型。
     *
     * 合法写法表已收敛进 `ChannelRegistry`（`ChannelSpec.storedTokens` / `legacyTokens`），
     * 这里只负责"查不到就按 host 猜"的兜底 —— 新增通道不再需要改本函数
     * （原来这里是 12 臂 `when`，漏一臂就把已知平台静默降级成 GENERIC）。
     */
    private fun parseWebhookType(
        typeStr: String,
        url: String
    ): WebhookPayloadBuilder.WebhookType {
        return ChannelRegistry.typeByStoredToken(typeStr)
            ?: WebhookPayloadBuilder.detectType(url)
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

    fun getTemperatureRules(): String {
        return prefs.getString(KEY_TEMPERATURE_RULES, "[]") ?: "[]"
    }

    fun setTemperatureRules(json: String) {
        prefs.edit().putString(KEY_TEMPERATURE_RULES, json).apply()
    }

    fun getBatteryRules(): String {
        return prefs.getString(KEY_BATTERY_RULES, "[]") ?: "[]"
    }

    fun getBatteryNotifyEnabled(): Boolean {
        return prefs.getBoolean(KEY_BATTERY_NOTIFY_ENABLED, true)
    }

    /** 短信监听总开关（首页「监听短信」，默认开） */
    fun getSmsMonitorEnabled(): Boolean {
        return prefs.getBoolean(KEY_SMS_MONITOR_ENABLED, true)
    }

    /** 「监听验证码」开关（默认开；关闭后验证码短信整条拦截） */
    fun getSmsCodeMonitorEnabled(): Boolean {
        return prefs.getBoolean(KEY_SMS_CODE_MONITOR_ENABLED, true)
    }

    /**
     * 监听卡过滤（同时作用于短信和电话）。
     * @return null=全部卡；0=仅卡1；1=仅卡2（slotIndex 0-based）
     */
    fun getSmsSimFilterSlot(): Int? {
        return when (prefs.getString(KEY_SMS_SIM_FILTER, "all")) {
            "1" -> 0
            "2" -> 1
            else -> null
        }
    }

    /**
     * 返回通知规则 JSON 数组字符串（结构与 Flutter 端 NotificationRule.toMap() 一致）。
     * 未配置时返回空串，规则引擎按默认（立即推送）处理。
     */
    fun getNotificationRules(): String {
        return prefs.getString(KEY_NOTIFICATION_RULES, "") ?: ""
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
