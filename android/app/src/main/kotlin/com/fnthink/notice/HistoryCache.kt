package com.fnthink.notice

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.locks.ReentrantLock

/**
 * 离线通知缓存
 *
 * 解决问题：Flutter 引擎被杀或 MainActivity 销毁后，sendBroadcast 投递失败导致推送历史丢失。
 *
 * 工作机制：
 * - WebhookSender.sendBroadcast 之后，同步调用 [append] 写入本缓存（持久化到 SP）
 * - Flutter 在线时，MainActivity.notificationReceiver 成功 invokeMethod 后调用 [remove]
 * - Flutter 启动时通过 MethodChannel 调用 [drainAll]，拉取离线期间缓存并清空
 * - 上限 [MAX_RECORDS] 条，超出时丢弃最旧记录
 *
 * 与 MainActivity.cacheNotificationRecord 兜底机制并存（互不干扰，使用不同 SP 文件）。
 */
object HistoryCache {
    private const val TAG = "HistoryCache"
    private const val PREFS_NAME = "notification_offline_cache"
    private const val KEY_RECORDS = "records"
    private const val MAX_RECORDS = 500

    private val lock = ReentrantLock()

    /**
     * 追加一条缓存。同步写盘，确保即使进程被杀也不丢数据。
     * 同 id 重复追加会去重（更新而非插入），避免 MainActivity 在线时缓存重复。
     */
    fun append(context: Context, data: JSONObject) {
        lock.lock()
        try {
            val id = data.optString("id", "")
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val arr = readArray(prefs)

            // id 去重：已存在则更新原位置
            if (id.isNotEmpty()) {
                for (i in 0 until arr.length()) {
                    val existing = arr.optJSONObject(i)
                    if (existing != null && existing.optString("id", "") == id) {
                        arr.put(i, data)
                        writeArray(prefs, arr)
                        return
                    }
                }
            }

            arr.put(data)
            // 上限保护：丢弃最旧
            while (arr.length() > MAX_RECORDS) {
                arr.remove(0)
            }
            writeArray(prefs, arr)
        } catch (e: Exception) {
            Log.e(TAG, "append failed", e)
        } finally {
            lock.unlock()
        }
    }

    /**
     * 移除指定 id 的缓存（Flutter 已成功接收后调用）。
     */
    fun remove(context: Context, id: String) {
        if (id.isEmpty()) return
        lock.lock()
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val arr = readArray(prefs)
            var changed = false
            for (i in arr.length() - 1 downTo 0) {
                val obj = arr.optJSONObject(i)
                if (obj != null && obj.optString("id", "") == id) {
                    arr.remove(i)
                    changed = true
                }
            }
            if (changed) writeArray(prefs, arr)
        } catch (e: Exception) {
            Log.e(TAG, "remove failed", e)
        } finally {
            lock.unlock()
        }
    }

    /**
     * 拉取全部缓存并清空（Flutter 启动时调用）。
     * 返回 List<Map<String, Any?>>，每个元素是一条通知 JSON。
     */
    fun drainAll(context: Context): List<Map<String, Any?>> {
        lock.lock()
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val arr = readArray(prefs)
            val list = mutableListOf<Map<String, Any?>>()
            for (i in 0 until arr.length()) {
                try {
                    val obj = arr.optJSONObject(i) ?: continue
                    val map = mutableMapOf<String, Any?>()
                    val keys = obj.keys()
                    while (keys.hasNext()) {
                        val k = keys.next()
                        map[k] = obj.get(k)
                    }
                    list.add(map)
                } catch (_: Exception) {}
            }
            // 清空缓存
            prefs.edit().remove(KEY_RECORDS).apply()
            Log.i(TAG, "Drained ${list.size} cached records")
            return list
        } catch (e: Exception) {
            Log.e(TAG, "drainAll failed", e)
            return emptyList()
        } finally {
            lock.unlock()
        }
    }

    /**
     * 获取当前缓存数量（用于诊断）
     */
    fun size(context: Context): Int {
        lock.lock()
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            return readArray(prefs).length()
        } catch (_: Exception) {
            return 0
        } finally {
            lock.unlock()
        }
    }

    private fun readArray(prefs: android.content.SharedPreferences): JSONArray {
        return try {
            val json = prefs.getString(KEY_RECORDS, "[]") ?: "[]"
            JSONArray(json)
        } catch (e: Exception) {
            JSONArray()
        }
    }

    private fun writeArray(prefs: android.content.SharedPreferences, arr: JSONArray) {
        prefs.edit().putString(KEY_RECORDS, arr.toString()).commit()
    }
}
