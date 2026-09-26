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
        /** Dart 侧 SharedPreferences 的文件名（[ChannelAvailability] 读健康记录也要用）*/
        const val FLUTTER_PREFS_NAME = "FlutterSharedPreferences"
        private const val KEY_WEBHOOK_URLS = "flutter.webhook_channels"
        private const val KEY_ENABLED_PACKAGES = "flutter.enabled_packages"
        private const val KEY_APP_FILTER_MODE = "flutter.app_filter_mode"
        private const val KEY_WHITELIST_KEYWORDS = "flutter.whitelist_keywords"
        private const val KEY_BLACKLIST_KEYWORDS = "flutter.blacklist_keywords"
        private const val KEY_DEVICE_NAME = "flutter.device_name"
        // T20：这两把键的**唯一写入者是 Dart**（`EngineRuleRepository` 写的兼容镜像）。
        // 原生侧没有 SQLCipher 依赖，打不开存规则的加密库，所以规则入 DB 之后仍然要靠
        // 这份镜像喂 BatteryMonitor —— T21/T22 切主路径之前不许撤，撤了就是"改了规则不生效"。
        private const val KEY_BATTERY_RULES = "flutter.battery_rules"
        private const val KEY_TEMPERATURE_RULES = "flutter.temperature_rules"
        /** T24：亮度 + 网络规则同族（引擎按 type 路由，不再为分组多开一份镜像键） */
        private const val KEY_DEVICE_STATE_RULES = "flutter.device_state_rules"

        /** T24：各族自己的总开关（键名与 Dart 那侧的 setTemperatureSetting / setBatterySetting 同串） */
        private const val KEY_TEMPERATURE_NOTIFY_ENABLED = "flutter.temperature_notify_enabled"
        private const val KEY_DEVICE_STATE_NOTIFY_ENABLED = "flutter.device_state_notify_enabled"
        private const val KEY_BATTERY_NOTIFY_ENABLED = "flutter.battery_notify_enabled"
        private const val KEY_NOTIFICATION_RULES = "flutter.notification_rules"
        private const val KEY_SMS_MONITOR_ENABLED = "flutter.sms_monitor_enabled"
        private const val KEY_SMS_SIM_FILTER = "flutter.sms_sim_filter"
        private const val KEY_SMS_CODE_MONITOR_ENABLED = "flutter.sms_code_monitor_enabled"
        // T23：设备态告警（电量/温度）要不要也过一遍关键词约束。**唯一写入者是 Dart**
        // （BatteryService.saveDeviceAlertsRespectConstraints 走 setBatterySetting 那枚通用布尔写）。
        private const val KEY_DEVICE_ALERT_CONSTRAINT = "flutter.device_alert_constraint_enabled"
    }

    private val prefs: SharedPreferences by lazy {
        context.getSharedPreferences(FLUTTER_PREFS_NAME, Context.MODE_PRIVATE)
    }

    /**
     * 完整的 webhook 通道配置（含 secret / type / 模板，用于签名、送达校验与自定义模板）
     */
    data class WebhookChannelConfig(
        val url: String,
        /** 可用性记账与主备路由的键（与 Dart 侧 `channel_health_webhook_<id>` 同源）。
         *  老配置没带 id 时用 url 兜底：同一 URL 的多份配置共享可用性，可接受。 */
        val id: String = "",
        val secret: String?,
        val type: WebhookPayloadBuilder.WebhookType,
        val messageFormat: String = "default",
        val messageTemplate: String? = null,
        // T12：主备角色。`getWebhookChannelConfigs()` 只返回**要推的**通道
        // （role=NONE 已被排除），所以发送层不需要再判一次。
        val role: ChannelRole = ChannelRole.PRIMARY,
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
                val rawId = obj.optString("id", "")
                val role = ChannelRole.parse(obj.optString("role", ""))
                // 「不参与」：保留配置但一条都不推（与"关掉启用开关"的区别是随时可归队）
                if (role == ChannelRole.NONE) continue
                // extra_config 不再解析（roadmap D4 / ㊷），见 WebhookChannelConfig 上的说明
                list.add(
                    WebhookChannelConfig(
                        url = url,
                        id = rawId.ifEmpty { url },
                        secret = secret,
                        type = type,
                        messageFormat = messageFormat,
                        messageTemplate = messageTemplate,
                        role = role,
                    )
                )
            }
            list
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse webhook channel configs", e)
            // 兜底：用 URL 列表，无签名
            getWebhookUrls().map {
                // 兜底路径没有 id 可用：用 URL 自己当键（与上面 ifEmpty 同一条规则）
                WebhookChannelConfig(
                    url = it, id = it, secret = null,
                    type = WebhookPayloadBuilder.detectType(it),
                )
            }
        }
    }

    /**
     * 自建应用通道完整配置读取（应用通道体系，与 webhook 通道分离存储）。
     * 返回 AppChannelSpec.kt 定义的 AppChannelConfig（未启用的通道被过滤）。
     */
    /**
     * **要推的**应用通道：已启用且角色不是 `NONE`（T12）。
     * 需要"包含不参与"的全量视图时用 [parseAppChannelConfigs]（例如「测试」按 id 找通道）。
     */
    fun getAppChannelConfigs(): List<AppChannelConfig> =
        parseAppChannelConfigs().filter { it.role != ChannelRole.NONE }

    /** 全量解析（不按角色过滤）：读不到 / 解析失败时返回空表。 */
    private fun parseAppChannelConfigs(): List<AppChannelConfig> {
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
                    role = ChannelRole.parse(obj.optString("role", "")),
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse app channel configs", e)
            emptyList()
        }
    }

    /** 按 id 找通道（「测试」按钮走这里）：**含**角色为 NONE 的通道 ——
     *  不参与推送不该连手动测试都不让做，所以这里用全量视图而不是 [getAppChannelConfigs]。 */
    fun findAppChannelById(id: String): AppChannelConfig? =
        parseAppChannelConfigs().firstOrNull { it.id == id }

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

    /** T24：亮度/网络规则（唯一写入者是 Dart 的 `EngineRuleRepository`，原生只读） */
    fun getDeviceStateRules(): String {
        return prefs.getString(KEY_DEVICE_STATE_RULES, "[]") ?: "[]"
    }

    fun getBatteryRules(): String {
        return prefs.getString(KEY_BATTERY_RULES, "[]") ?: "[]"
    }

    fun getBatteryNotifyEnabled(): Boolean {
        return prefs.getBoolean(KEY_BATTERY_NOTIFY_ENABLED, true)
    }

    /**
     * T24：温度族与设备状态族（亮度/网络）各自的总开关。
     *
     * ⚠ 温度这一枚是**修 bug**：`TemperatureService` 一直在写 `flutter.temperature_notify_enabled`，
     * 而原生从没有人读它 ⇒ 用户在页面上关掉开关，温度告警照旧推。默认 true 保证
     * 没动过这枚开关的老用户行为不变（"升级不改用户设置"）。
     */
    fun getTemperatureNotifyEnabled(): Boolean {
        return prefs.getBoolean(KEY_TEMPERATURE_NOTIFY_ENABLED, true)
    }

    fun getDeviceStateNotifyEnabled(): Boolean {
        return prefs.getBoolean(KEY_DEVICE_STATE_NOTIFY_ENABLED, true)
    }

    /**
     * T23：设备态告警是否也接受关键词约束。**默认关** —— 开了会改变已有设备的告警行为，
     * 所以只有用户明确勾选才生效（"升级不改用户设置"这条不变量在这里的字面意思）。
     */
    fun getDeviceAlertConstraintEnabled(): Boolean {
        return prefs.getBoolean(KEY_DEVICE_ALERT_CONSTRAINT, false)
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
