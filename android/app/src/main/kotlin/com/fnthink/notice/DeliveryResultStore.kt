package com.fnthink.notice

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

/**
 * 送达结果持久化队列（补偿机制）。
 *
 * 背景：送达结果链路为「ACTION_DELIVERY_RESULT 广播 → MainActivity.deliveryReceiver → MethodChannel」，
 * 依赖 MainActivity 存活。当用户在通知到达后滑掉最近任务 / 系统回收 Activity 时，
 * 结果广播无人接收，Flutter 端记录会永远停在「发送中」。
 *
 * 解决：DeliveryNotifier 广播的同时把结果写入本队列（SharedPreferences 持久化）；
 * Flutter 启动 loadRecords() 与页面 resume 时调用 drainDeliveryResults() 拉取并逐条补更新。
 * 与实时广播路径互不冲突（Flutter updateDelivery 幂等，重复写入同状态无害）。
 */
object DeliveryResultStore {
    private const val PREFS_NAME = "delivery_result_store"
    private const val KEY_PENDING = "pending_results"
    private const val MAX_ITEMS = 200

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** 入队：同 notificationId + type 去重更新（保留最新结果） */
    @Synchronized
    fun push(
        context: Context,
        notificationId: String,
        type: String,
        status: String,
        message: String,
        httpCode: Int
    ) {
        if (notificationId.isEmpty() || type.isEmpty()) return
        val p = prefs(context)
        val arr = JSONArray(p.getString(KEY_PENDING, "[]") ?: "[]")
        val newItem = JSONObject().apply {
            put("notificationId", notificationId)
            put("type", type)
            put("status", status)
            put("message", message)
            put("httpCode", httpCode)
        }
        var replaced = false
        for (i in 0 until arr.length()) {
            val item = arr.optJSONObject(i) ?: continue
            if (item.optString("notificationId") == notificationId &&
                item.optString("type") == type
            ) {
                arr.put(i, newItem)
                replaced = true
                break
            }
        }
        if (!replaced) arr.put(newItem)
        // 容量上限：保留最新 MAX_ITEMS 条
        while (arr.length() > MAX_ITEMS) arr.remove(0)
        p.edit().putString(KEY_PENDING, arr.toString()).apply()
    }

    /** 返回全部未消费结果并清空队列（Flutter 端 updateDelivery 幂等，无需逐条 ack） */
    @Synchronized
    fun drain(context: Context): List<Map<String, Any>> {
        val p = prefs(context)
        val arr = JSONArray(p.getString(KEY_PENDING, "[]") ?: "[]")
        p.edit().remove(KEY_PENDING).apply()
        val list = mutableListOf<Map<String, Any>>()
        for (i in 0 until arr.length()) {
            val item = arr.optJSONObject(i) ?: continue
            list.add(
                mapOf(
                    "notificationId" to item.optString("notificationId"),
                    "webhookType" to item.optString("type"),
                    "status" to item.optString("status"),
                    "message" to item.optString("message"),
                    "httpCode" to item.optInt("httpCode", 0),
                )
            )
        }
        return list
    }
}
