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
 * 注：深度 Doze 下非精确闹钟只在维护窗口投递（约 9~15 分钟一次），到点可能有分钟级延迟；
 * 系统已授权精确闹钟时走 setExactAndAllowWhileIdle（准点），未授权才降级 ——
 * 判定只有一个作者 [ExactAlarmPolicy]，App 内不再有第二枚开关（T140 走 (c)）。
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

    /**
     * 入队：追加一条延迟推送并重新调度最近一次触发。
     *
     * @return 因超出队列上限被挤出的条目 —— 调用方**必须把它们补推出去**（走与到点同一条
     *   推送路径）。挤出与丢弃是两件事：每条都已在历史里占了一行、送达列停在 `pending`，
     *   没有下一发回执它就永远说「发送中」（T150 片2，维护者 2026-10-12 第 6 条）。
     */
    @Synchronized
    fun enqueue(info: NotificationInfo, fireAt: Long): List<NotificationInfo> {
        val queue = readQueue()
        val item = JSONObject().apply {
            put("key", "${info.packageName}:${info.id}:${info.postTime}")
            put("fireAt", fireAt)
            put("info", info.toJson())
        }
        // 同 key 已存在则覆盖（避免同一通知重复入队）
        val filtered = ArrayList(queue.filter { it.optString("key", "") != item.optString("key", "") })
        filtered.add(item)
        // 上限挤出来的是**最早要到点**的那几条（见 [DelayedPushLogic.splitByCap]），
        // 它们不是垃圾：交回调用方补推，一条都不许凭空消失。
        val (kept, spilled) = DelayedPushLogic.splitByCap(filtered, MAX_QUEUE_SIZE)
        writeQueue(kept)
        // 隐私：不记录通知标题（可能含验证码/余额等敏感内容）
        Log.d(TAG, "延迟推送入队 fireAt=$fireAt, 队列=${kept.size}, 挤出=${spilled.size}")
        scheduleNext()
        return readInfos(spilled)
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
        // ⚠ 载荷解析不出来的条目**不能静默消失**（旧写法 `mapNotNull` 就是那样把通知丢掉的：
        // 那一行的送达列停在 pending，界面上一直说「发送中」，而它再也不会被发）。
        // 这里丢不掉就把它喊出来 —— 解析失败是数据问题，不是"少一条也算正常"。
        // ⚠ 这一发**今天仍拿不到送达说法**：`info` 坏掉就连 recordId 都取不出（队列项的
        // `key` 是 `pkg:id:postTime`，而 id 自己含冒号，拆不得）。登记成已知欠账，不假装覆盖。
        val out = readInfos(due)
        if (out.size != due.size) {
            Log.e(
                TAG,
                "延迟推送有 ${due.size - out.size} 条载荷解析失败，本轮补推不了（历史会停在发送中）",
            )
        }
        return out
    }

    /** 队列项 → 通知（解析不出的跳过，由调用方按数量差喊出来；见 [drainDue] 那条注释）。 */
    private fun readInfos(items: List<JSONObject>): List<NotificationInfo> {
        val out = ArrayList<NotificationInfo>(items.size)
        for (item in items) {
            try {
                out.add(NotificationInfo.fromJson(item.getJSONObject("info")))
            } catch (e: Exception) {
                Log.w(TAG, "延迟推送数据解析失败: ${e.message}")
            }
        }
        return out
    }

    /** 服务启动/配置刷新时重排闹钟（覆盖进程被杀后 START_STICKY 重启的场景） */
    @Synchronized
    fun rescheduleAll() {
        val queue = readQueue()
        if (queue.isEmpty()) {
            cancelAlarm()
            return
        }
        // ⚠ 过期条目**一律保留**：延迟队列里躺着的是"还没推送出去的通知"，不是日志。
        // 旧写法在这里把 `fireAt <= now` 的全筛掉，等于闹钟没赶上就永久不发，而那一行的
        // 送达列一直停在 `pending` —— 界面替本机说「发送中」（T150 片2）。留着它们，
        // [scheduleNext] 取到的最早 to 点已是过去时刻，AlarmManager 会尽快触发补推。
        // 与 `MergePushManager.rescheduleAll` 同一条策略（那边早已写成约束，见 MergeFailureContractTest）。
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
            // 精确与否只由系统授权决定（T140 走 (c)：App 内那枚开关已删，见 [ExactAlarmPolicy]）。
            // 已授权 → setExactAndAllowWhileIdle，到点分秒不差（Doze 下也准点）；
            // 未授权 → setAndAllowWhileIdle（深度 Doze 下分钟级延迟）。
            // 那一枚 SecurityException 兜底留着：授权状态可能在排程这一刻刚被用户在系统里收回。
            if (ExactAlarmPolicy.allowed(context)) {
                try {
                    am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAt, pi)
                    Log.d(TAG, "延迟推送精确闹钟已排程 fireAt=$fireAt")
                    return
                } catch (e: SecurityException) {
                    Log.w(TAG, "精确闹钟未授权，降级非精确闹钟", e)
                }
            }
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
            val arr = JSONArray()
            for (item in queue) arr.put(item)
            // commit()：延迟队列必须跨进程被杀存活（apply() 丢写 = 到点的推送永不补发）
            prefs.edit().putString(KEY_QUEUE, arr.toString()).commit()
        } catch (e: Exception) {
            Log.e(TAG, "延迟推送队列写入失败", e)
        }
    }
}

/**
 * 延迟队列的纯算术（无 Android 依赖，JVM 可测）。
 *
 * 抽出来不是为了"好看"：上限那一发在旧写法里是**静默丢**——被丢的那条已经在历史里占了一行、
 * 送达列停在 `pending`，从此再没有回执会来推离它，界面就永远替本机说「发送中」（T150 片2，
 * 维护者 2026-10-12 第 6 条）。现在上限的语义改成"挤出来的交回调用方补推"，而"分成两堆"
 * 这一步必须与 SharedPreferences 无关才谈得上逐条断言。
 */
object DelayedPushLogic {
    /**
     * 按 `fireAt` 升序保留 [max] 条（留下还要往后排的那些），返回 `保留到 挤出`。
     *
     * ⚠ 挤出的是**最早要到点**的那几条 —— 它们最该发，所以必须由调用方立刻推出去，
     * 不是"最没用的"。队列里原本的留法（`takeLast`）一字没改，改的只是被挤出的那一部分的去向。
     */
    fun splitByCap(
        queue: List<JSONObject>,
        max: Int,
    ): Pair<List<JSONObject>, List<JSONObject>> {
        if (max <= 0 || queue.size <= max) return queue to emptyList()
        val sorted = queue.sortedBy { it.optLong("fireAt", Long.MAX_VALUE) }
        return sorted.takeLast(max) to sorted.take(queue.size - max)
    }
}
