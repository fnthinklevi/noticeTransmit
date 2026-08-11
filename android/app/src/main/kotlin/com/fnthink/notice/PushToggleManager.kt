package com.fnthink.notice

import android.content.Context
import android.content.SharedPreferences
import android.util.Log

/**
 * 推送启停状态管理器
 *
 * 三级状态机：
 * - RUNNING：监听 + 推送（默认）
 * - PAUSED：监听但不推送（通知仍会被记录到历史，但不发 webhook）
 * - STOPPED：停止服务（由 NotificationMonitorService.stopSelf 处理，本类不涉及）
 *
 * 状态持久化到 SharedPreferences，服务重启后恢复。
 * NetworkClient 通过 [isPushActive] 决定是否真正发送 webhook。
 */
object PushToggleManager {
    private const val TAG = "PushToggleManager"
    private const val PREFS_NAME = "push_toggle_state"
    private const val KEY_PUSH_ACTIVE = "push_active"

    @Volatile
    private var cachedActive: Boolean = true

    @Volatile
    private var initialized: Boolean = false

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /**
     * 初始化缓存（服务启动时调用一次）
     */
    fun init(context: Context) {
        cachedActive = prefs(context).getBoolean(KEY_PUSH_ACTIVE, true)
        initialized = true
        Log.i(TAG, "PushToggleManager initialized: pushActive=$cachedActive")
    }

    /**
     * 推送是否激活（NetworkClient 调用此方法判断是否真正发送）
     */
    fun isPushActive(): Boolean {
        if (!initialized) return true
        return cachedActive
    }

    /**
     * 暂停推送（监听继续，仅不发送 webhook）
     */
    fun pause(context: Context) {
        cachedActive = false
        prefs(context).edit().putBoolean(KEY_PUSH_ACTIVE, false).apply()
        Log.i(TAG, "Push paused")
    }

    /**
     * 恢复推送
     */
    fun resume(context: Context) {
        cachedActive = true
        prefs(context).edit().putBoolean(KEY_PUSH_ACTIVE, true).apply()
        Log.i(TAG, "Push resumed")
    }

    /**
     * 切换状态，返回切换后的状态（true=推送激活）
     */
    fun toggle(context: Context): Boolean {
        return if (cachedActive) {
            pause(context)
            false
        } else {
            resume(context)
            true
        }
    }
}
