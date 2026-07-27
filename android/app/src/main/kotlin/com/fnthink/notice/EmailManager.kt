package com.fnthink.notice

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/// 邮件通道配置管理器（原生端）
///
/// 存储策略：
///   1. 密码 → 独立 SP key（email_channel_passwords），与元数据分离
///   2. 非敏感元数据 → SharedPreferences（email_channel_configs）
///   3. Flutter 端同步时由 MethodChannel 传入完整配置（含密码），此处持久化。
object EmailManager {

    private const val TAG = "EmailManager"
    private const val PREFS_NAME = "email_channel_configs"
    private const val PREFS_PASSWORDS = "email_channel_passwords"
    private const val KEY_CHANNELS = "channels"
    private const val KEY_PASSWORDS = "passwords"

    /** 保存邮件通道元数据 + 密码 */
    fun saveChannels(context: Context, channelsData: List<Map<String, Any?>>) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val pwdPrefs = context.getSharedPreferences(PREFS_PASSWORDS, Context.MODE_PRIVATE)

        val metaArray = JSONArray()
        val pwdObj = JSONObject()

        for (data in channelsData) {
            val id = data["id"]?.toString() ?: ""
            val obj = JSONObject()
            data.forEach { (k, v) ->
                if (k == "password") {
                    pwdObj.put(id, v?.toString() ?: "")
                } else {
                    obj.put(k, v?.toString() ?: "")
                }
            }
            metaArray.put(obj)
        }

        prefs.edit().putString(KEY_CHANNELS, metaArray.toString()).apply()
        pwdPrefs.edit().putString(KEY_PASSWORDS, pwdObj.toString()).apply()
        Log.d(TAG, "保存 ${channelsData.size} 个邮件通道配置")
    }

    /** 返回通道列表（Map 格式，供 Flutter MethodChannel 回传） */
    fun loadChannelsAsMap(context: Context): List<Map<String, String?>> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val json = prefs.getString(KEY_CHANNELS, "[]") ?: "[]"
        val result = mutableListOf<Map<String, String?>>()

        try {
            val jsonArray = JSONArray(json)
            for (i in 0 until jsonArray.length()) {
                val obj = jsonArray.getJSONObject(i)
                val map = mutableMapOf<String, String?>()
                obj.keys().forEach { key -> map[key] = obj.optString(key) }
                result.add(map)
            }
        } catch (e: Exception) {
            Log.e(TAG, "加载通道列表失败", e)
        }

        return result
    }

    /** 加载启用的通道配置（含密码），供通知分发使用 */
    fun getEnabledConfigs(context: Context): List<EmailSender.EmailConfig> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val pwdPrefs = context.getSharedPreferences(PREFS_PASSWORDS, Context.MODE_PRIVATE)

        val json = prefs.getString(KEY_CHANNELS, "[]") ?: "[]"
        val passwordsJson = pwdPrefs.getString(KEY_PASSWORDS, "{}") ?: "{}"

        val passwords = mutableMapOf<String, String>()
        try {
            val pwdObj = JSONObject(passwordsJson)
            pwdObj.keys().forEach { key -> passwords[key] = pwdObj.optString(key) }
        } catch (_: Exception) {}

        val configs = mutableListOf<EmailSender.EmailConfig>()

        try {
            val jsonArray = JSONArray(json)
            for (i in 0 until jsonArray.length()) {
                val obj = jsonArray.getJSONObject(i)
                val enabled = obj.optBoolean("enabled", true)
                if (!enabled) continue

                val id = obj.optString("id", "")
                configs.add(EmailSender.EmailConfig(
                    smtpHost = obj.optString("smtpHost", ""),
                    smtpPort = obj.optInt("smtpPort", 465),
                    username = obj.optString("username", ""),
                    password = passwords[id] ?: "",
                    fromEmail = obj.optString("fromEmail", ""),
                    toEmails = obj.optString("toEmail", "")
                        .split(",")
                        .map { it.trim() }
                        .filter { it.isNotEmpty() },
                    useSSL = obj.optBoolean("useSSL", true),
                    subjectTemplate = obj.optString("subjectTemplate", "").ifBlank { null },
                    bodyTemplate = obj.optString("bodyTemplate", "").ifBlank { null }
                ))
            }
        } catch (e: Exception) {
            Log.e(TAG, "获取启用通道失败", e)
        }

        return configs
    }
}
