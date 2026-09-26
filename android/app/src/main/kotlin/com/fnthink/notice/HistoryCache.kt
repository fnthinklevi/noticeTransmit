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

    /**
     * 累计"因缓存满而丢弃最旧"的条数（#94-A）。它是一次性的：`drainAll` 把它随记录一起交给
     * Flutter 之后就清零 —— 提示过一次就不该每次开机再提示一遍。
     */
    private const val KEY_DROPPED = "dropped_total"
    private const val MAX_RECORDS = 500

    private val lock = ReentrantLock()

    /**
     * 追加一条缓存。同步写盘，确保即使进程被杀也不丢数据。
     * 同 id 重复追加会去重（更新而非插入），避免 MainActivity 在线时缓存重复。
     */
    /**
     * 把一条记录并进缓存数组 —— **纯函数，不碰磁盘**（#94 的取证入口）。
     *
     * 规则：同 id 就地更新（不追加），无 id 或新 id 追加到尾部；超过 [maxRecords] 从**头部**
     * 丢最旧。返回本次丢弃的条数 —— 这个数字此前根本拿不到（`while` 里悄悄 remove），
     * 而"离线缓存满过没有、丢了几条"正是 #94 三种改法共同需要的量。
     */
    internal fun mergeIntoArray(arr: JSONArray, data: JSONObject, maxRecords: Int): Int {
        val id = data.optString("id", "")
        if (id.isNotEmpty()) {
            for (i in 0 until arr.length()) {
                val existing = arr.optJSONObject(i)
                if (existing != null && existing.optString("id", "") == id) {
                    arr.put(i, data)
                    return 0
                }
            }
        }
        arr.put(data)
        var dropped = 0
        while (arr.length() > maxRecords) {
            arr.remove(0)
            dropped++
        }
        return dropped
    }

    /** 读缓存数组；坏 JSON / 缺键一律退化成空数组（不抛，因为抛在这里等于离线兜底整个失效）。 */
    internal fun parseArray(raw: String?): JSONArray = try {
        JSONArray(raw ?: "[]")
    } catch (_: Exception) {
        JSONArray()
    }

    fun append(context: Context, data: JSONObject) {
        lock.lock()
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val arr = readArray(prefs)
            val dropped = mergeIntoArray(arr, data, MAX_RECORDS)
            // 溢出计数与数组**同一次 commit 落盘**：分两次写就会出现"数组写成功、计数没写"
            // 的那种半状态，而 #94 要的正是一条都不能记漏。
            var total = prefs.getInt(KEY_DROPPED, 0)
            if (dropped > 0) {
                total += dropped
                Log.w(TAG, "离线缓存已满 $MAX_RECORDS 条，丢弃最旧 $dropped 条（未送达 Flutter）")
            }
            writeArray(prefs, arr, total)
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
            // 确认送达只动记录，**不动溢出计数** ⇒ 原值带回。否则"消费掉一条离线通知"
            // 会顺手把还没报给用户的"期间丢了 N 条"清零，那条提示就永远不出现了。
            if (changed) writeArray(prefs, arr, prefs.getInt(KEY_DROPPED, 0))
        } catch (e: Exception) {
            Log.e(TAG, "remove failed", e)
        } finally {
            lock.unlock()
        }
    }

    /**
     * 拉取全部缓存并清空（Flutter 启动时调用）。
     *
     * 返回 [OfflineDrain]：记录 + **本次一并交付的丢弃条数**（#94-A）。两个键必须一起清：
     * 记录清了而计数没清，下次启动就会把同一批"丢了 N 条"再报一遍。
     */
    fun drainAll(context: Context): OfflineDrain {
        lock.lock()
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val arr = readArray(prefs)
            val dropped = prefs.getInt(KEY_DROPPED, 0)
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
            // 清空缓存与计数：同步 commit —— 异步清会在进程被杀时留下"记录已空、计数还在"，
            // 于是那句提示每次冷启动都重复出现一遍。
            prefs.edit().remove(KEY_RECORDS).remove(KEY_DROPPED).commit()
            Log.i(TAG, "Drained ${list.size} cached records, dropped=$dropped")
            return OfflineDrain(list, dropped)
        } catch (e: Exception) {
            Log.e(TAG, "drainAll failed", e)
            return OfflineDrain(emptyList(), 0)
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

    private fun readArray(prefs: android.content.SharedPreferences): JSONArray =
        // 解析逻辑只留 parseArray 一份（两处各写一个 try/catch 迟早漂出"一处退化成空数组、
        // 另一处抛出去"）
        parseArray(prefs.getString(KEY_RECORDS, "[]"))

    private fun writeArray(
        prefs: android.content.SharedPreferences,
        arr: JSONArray,
        droppedTotal: Int,
    ) {
        // 记录与溢出计数**同一次 commit**：分两次写就会漂出"数组落了、计数没落"的半状态
        prefs.edit()
            .putString(KEY_RECORDS, arr.toString())
            .putInt(KEY_DROPPED, droppedTotal)
            .commit()
    }
}

/**
 * `drainAll` 的一次性交付：缓存里的记录 + 此前累计因满而丢弃的条数（#94-A）。
 *
 * 为什么不新开一个"读丢弃数"的方法：那样要么多一个 MethodChannel 方法（本仓库的规矩是
 * 方法数只降不升），要么让 Flutter 分两次读 —— 两次读之间原生可能又丢了新的，计数就漏了。
 */
data class OfflineDrain(val records: List<Map<String, Any?>>, val dropped: Int)
