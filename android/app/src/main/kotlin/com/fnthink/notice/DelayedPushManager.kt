package com.fnthink.notice

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * 延迟/定时推送队列（原生端）
 *
 * 命中规则「延迟推送」动作的通知会写入本队列（SharedPreferences 持久化，服务被杀/重启不丢失），
 * 到点后由 AlarmManager（setAndAllowWhileIdle，Doze 下也可触发）广播 ACTION_PUSH_DUE，
 * 由 NotificationMonitorService 注册的接收器统一取出并推送。
 *
 * 队列项：{"key": "pkg:id:postTime", "fireAt": 毫秒时间戳, "info": {NotificationInfo JSON}}
 */
class DelayedPushManager(private val context: Context) {
    companion object {
        private const val TAG = "DelayedPushManager"
        const val ACTION_PUSH_DUE = "com.fnthink.notice.PUSH_DUE"
        private const val PREFS_NAME = "delayed_push_queue"
        private const val KEY_QUEUE = "queue"
        private const val REQUEST_CODE = 3001
        private const val MAX_QUEUE_SIZE = 200
    }

    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager

    /** 入队：追加一条延迟推送并重新调度最近一次触发 */
    @Synchronized
    fun enqueue(info: NotificationInfo, fireAt: Long) {
        val queue = readQueue()
        val item = JSONObject().apply {
            put("key", "${info.packageName}:${info.id}:${info.postTime}")
            put("fireAt", fireAt)
            put("info", info.toJson())
        }
        // 同 key 已存在则覆盖（避免同一通知重复入队）
        val filtered = ArrayList(queue.filter { it.optString("key", "") != item.optString("key", "") })
        filtered.add(item)
        writeQueue(filtered)
        Log.d(TAG, "延迟推送入队 fireAt=$fireAt (${info.title}), 队列=${filtered.size}")
        scheduleNext()
    }

    /** 取出所有已到期的推送并持久化剩余队列；返回到期的通知列表 */
    @Synchronized
    fun drainDue(): List<NotificationInfo> {
        val queue = readQueue()
        if (queue.isEmpty()) return emptyList()
        val now = System.currentTimeMillis()
        val due = queue.filter { it.optLong("fireAt", 0L) <= now }
        if (due.isEmpty()) return emptyList()
        val remaining = queue.filter { it.optLong("fireAt", 0L) > now }
        writeQueue(remaining)
        Log.d(TAG, "延迟推送到期 ${due.size} 条，剩余 ${remaining.size}")
        return due.mapNotNull { item ->
            try {
                NotificationInfo.fromJson(item.getJSONObject("info"))
            } catch (e: Exception) {
                Log.w(TAG, "延迟推送数据解析失败: ${e.message}")
                null
            }
        }
    }

    /** 服务启动/配置刷新时重排闹钟（覆盖进程被杀后 START_STICKY 重启的场景） */
    @Synchronized
    fun rescheduleAll() {
        val queue = readQueue()
        if (queue.isEmpty()) {
            cancelAlarm()
            return
        }
        // 清掉已过期条目（服务长时间未运行的情况）
        val now = System.currentTimeMillis()
        val expired = queue.filter { it.optLong("fireAt", 0L) <= now }
        if (expired.isNotEmpty()) {
            writeQueue(queue.filter { it.optLong("fireAt", 0L) > now })
        }
        scheduleNext()
    }

    /** 清空队列（规则全部删除等场景可调用） */
    @Synchronized
    fun clear() {
        writeQueue(ArrayList())
        cancelAlarm()
    }

    private fun scheduleNext() {
        val queue = readQueue()
        if (queue.isEmpty()) {
            cancelAlarm()
            return
        }
        val next = queue.minByOrNull { it.optLong("fireAt", Long.MAX_VALUE) } ?: return
        val fireAt = next.optLong("fireAt", 0L)
        if (fireAt <= 0L) return
        val am = alarmManager ?: return
        try {
            val intent = Intent(ACTION_PUSH_DUE).apply { setPackage(context.packageName) }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            val pi = PendingIntent.getBroadcast(context, REQUEST_CODE, intent, flags)
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAt, pi)
            Log.d(TAG, "延迟推送闹钟已排程 fireAt=$fireAt")
        } catch (e: Exception) {
            Log.e(TAG, "延迟推送闹钟排程失败", e)
        }
    }

    private fun cancelAlarm() {
        try {
            val am = alarmManager ?: return
            val intent = Intent(ACTION_PUSH_DUE).apply { setPackage(context.packageName) }
            val pi = PendingIntent.getBroadcast(
                context,
                REQUEST_CODE,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            am.cancel(pi)
        } catch (e: Exception) {
            Log.e(TAG, "取消延迟推送闹钟失败", e)
        }
    }

    private fun readQueue(): ArrayList<JSONObject> {
        val json = prefs.getString(KEY_QUEUE, "[]") ?: "[]"
        return try {
            val arr = JSONArray(json)
            val list = ArrayList<JSONObject>(arr.length())
            for (i in 0 until arr.length()) {
                try {
                    list.add(arr.getJSONObject(i))
                } catch (_: Exception) {}
            }
            list
        } catch (e: Exception) {
            Log.e(TAG, "延迟推送队列读取失败", e)
            ArrayList()
        }
    }

    private fun writeQueue(queue: List<JSONObject>) {
        try {
            val capped = if (queue.size > MAX_QUEUE_SIZE) {
                // 保留 fireAt 最近的 MAX 条（丢弃最久远的）
                queue.sortedBy { it.optLong("fireAt", Long.MAX_VALUE) }
                    .takeLast(MAX_QUEUE_SIZE)
            } else {
                queue
            }
            val arr = JSONArray()
            for (item in capped) arr.put(item)
            prefs.edit().putString(KEY_QUEUE, arr.toString()).apply()
        } catch (e: Exception) {
            Log.e(TAG, "延迟推送队列写入失败", e)
        }
    }
}
