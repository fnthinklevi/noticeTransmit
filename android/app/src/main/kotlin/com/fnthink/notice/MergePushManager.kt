package com.fnthink.notice

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log
import com.fnthink.notice.BuildConfig
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.LinkedHashSet
import java.util.Locale

/**
 * 聚合推送管理器（P2：规则引擎 merge 动作落地）
 *
 * 命中规则「合并推送」动作的通知按 packageName 聚合：首条通知开启固定窗口
 * （windowEnd = now + windowMs），窗口内同应用后续通知追加进同一组（窗口结束点不延长），
 * 到点后由 AlarmManager 广播 ACTION_MERGE_DUE，由 NotificationMonitorService 的接收器
 * 取出各组、合并为一条聚合 NotificationInfo 统一推送，并对成员逐条回传 MERGE 伪通道
 * 送达结果补标历史。
 *
 * ⚠⚠ 与延迟队列 / 去重键的交互风险（重要，改动前必读）⚠⚠
 *
 * 1. **与 DelayedPushManager 完全隔离**：本管理器使用独立的 SP 文件（merge_push_queue）、
 *    独立的 PendingIntent requestCode（3002）、独立的广播 action（MERGE_DUE），
 *    与延迟队列（3001/PUSH_DUE）互不干扰。同一通知不会同时进入两个队列——
 *    RuleEngine.decide 命中第一条规则即停，且 delay 与 merge 同时配置时 delay 优先，
 *    不存在"聚合组到点后又进延迟队列"的路径。
 *
 * 2. **去重键体系**：聚合组 id = "{packageName}:merge:{windowEnd}"，独立于通知去重键
 *    "{pkg}:{tag}:{notificationId}"。成员通知仍以真实 id 各自写入 HistoryCache / DB
 *    （dispatchPosted 先 sendBroadcast 记录单条），聚合推送本身再以聚合 id 记录一条汇总；
 *    ⚠ 注意：聚合 id 中包含 windowEnd（开窗时间 + 窗口时长），同一应用每次开窗产生的
 *    聚合记录 id 不同，不会互相覆盖；但若窗口秒数与开窗时刻完全一致（重启后 SP 残留 +
 *    恰好同毫秒开窗，概率极低）才会触发 HistoryCache/DB 主键替换——可接受的幂等行为。
 *
 * 3. **送达回传按单条 id 运作**：聚合推送只有一条 HTTP 结果，无法逐成员映射回
 *    webhook_delivery_log。方案：聚合推送完成后对每个成员以 MERGE 伪通道
 *    （DeliveryNotifier.notify(type="MERGE", …)）逐条回传，Flutter 端 updateDelivery
 *    把成员记录的全部真实通道置为终态。
 *    ⚠⚠ 必须回传**聚合推送的真实结果**，不能无条件 SUCCESS：
 *    历史缺陷是无论 webhook 是否成功都把成员标成 success("已合并推送")，
 *    于是推送失败时用户在历史里看到的是"已合并推送"——**内容丢失且无任何提示**。
 *    现改为按聚合 HTTP 结果回传（成功→success、失败→failed），
 *    Flutter 端 MERGE 分支按真实 status 映射。
 *    ⚠ 成员记录在窗口期内历史页会显示"发送中"（pending），到点批量转终态——
 *    窗口设置过长（>10 分钟）时用户会长时间看到"发送中"，属预期行为。
 *
 * 4. **计数语义变化**：pushCount / WidgetDailyCounter 在聚合组推送时 +1（按组计），
 *    不再按成员逐条 +N。桌面小部件"今日推送数"与成员条数不再一一对应。
 *
 * 5. **配置快照窗口**：append 捕获的是入队时的规则窗口参数；用户在窗口期内删除 merge
 *    规则或调整窗口，已开启的聚合组仍会按旧窗口到点推送（下一次决策才生效新配置）。
 *    rescheduleAll 在服务重启后按 SP 中的旧 windowEnd 重排，行为一致。
 *
 * 6. **闹钟精度**：与 DelayedPushManager 相同的 exact/非 exact 策略；非精确闹钟在
 *    深度 Doze 下有分钟级延迟 → 实际聚合窗口可能被拉长（窗口越长单次推送内容越多，
 *    但不会丢通知：SP 持久化，服务被杀重启后 rescheduleAll 恢复）。
 *
 * 队列项：{"key": "pkg", "windowEnd": 毫秒, "items": [{NotificationInfo}...]}
 */
class MergePushManager(private val context: Context) {
    companion object {
        private const val TAG = "MergePushManager"
        const val ACTION_MERGE_DUE = "com.fnthink.notice.MERGE_DUE"
        private const val PREFS_NAME = "merge_push_queue"
        private const val KEY_QUEUE = "groups"
        private const val REQUEST_CODE = 3002
        private const val MAX_GROUPS = 50
        private const val MAX_ITEMS_PER_GROUP = 50
    }

    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager

    /** 单条成员在聚合推送里的展示行 */
    data class MergeItem(val info: NotificationInfo)

    /** 到期的聚合组 */
    data class MergeGroup(
        val key: String,
        val windowEnd: Long,
        val items: List<NotificationInfo>
    ) {
        /** 聚合组 id（写入 HistoryCache/DB 的主键） */
        fun mergedId(): String = "$key:merge:$windowEnd"

        /**
         * F3：聚合成员标题摘要（供 %titles% 模板变量）。
         * 取各成员标题去重（标题与正文相同/为空时用正文首行兜底），
         * 最多 10 个、每个截断 30 字符，超出以「等」收尾——防模板变量无限膨胀。
         */
        private fun buildMergeTitles(): String {
            val seen = LinkedHashSet<String>()
            for (item in items) {
                val t = when {
                    item.title.isNotEmpty() && item.title != item.content -> item.title
                    item.content.isNotEmpty() -> item.content.lineSequence().firstOrNull() ?: ""
                    else -> ""
                }
                val trimmed = t.trim()
                if (trimmed.isNotEmpty()) seen.add(trimmed.take(30))
                if (seen.size >= 10) break
            }
            if (seen.isEmpty()) return ""
            val joined = seen.joinToString("、")
            return if (items.size > seen.size) "$joined 等" else joined
        }

        /** 合并后的聚合 NotificationInfo：title=摘要、content=逐行明细 */
        fun buildMergedInfo(): NotificationInfo {
            val first = items.first()
            val count = items.size
            val id = mergedId()
            val title = I18n.mergePushTitle(first.appName, count)
            val content = items.joinToString("\n") { item ->
                val line = if (item.title.isNotEmpty() && item.title != item.content) {
                    "${item.title}：${item.content}"
                } else {
                    item.content
                }
                "· " + line.take(200)
            }
            val timeStr = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
                .format(Date(windowEnd))
            return NotificationInfo(
                id = id,
                title = title,
                content = content,
                subText = "",
                packageName = first.packageName,
                appName = first.appName,
                postTime = windowEnd,
                time = timeStr,
                // type=merge：历史页以独立类型标识聚合记录（Flutter 端 channelTypeDisplayName
                // 无此值不影响送达标签；类型色走默认紫）
                type = "merge",
                deviceName = first.deviceName,
                priority = items.maxOf { it.priority },
                // F3：聚合模板变量（自定义模板可用 %count% / %titles%）
                mergeCount = count,
                mergeTitles = buildMergeTitles()
            )
        }
    }

    /**
     * 追加一条通知进聚合组：同应用已有活跃组 → 追加（窗口结束点不变）；
     * 无 → 开启新窗口。写入后调度最近的到期闹钟。
     *
     * ⚠ **本方法全程不执行任何网络 IO**（锁内不做推送）。历史上队列超限时在此直接
     * 触发兜底推送，把网络请求放进了 `@Synchronized` 临界区——而 `append` 处于
     * **每条命中 merge 规则的通知都会经过的热路径**上，后果是：
     * 1. 对象锁被网络 IO 长时间占用 → `drainDue` / `activeGroups` / `rescheduleAll`
     *    （前台通知 InboxStyle 刷新用）全部阻塞等待，前台通知刷新卡顿；
     * 2. 网络回调会链路到 `DeliveryNotifier.notify` → 发广播，若接收方同步回调进
     *    本类其他 `@Synchronized` 方法，形成跨线程等待死锁。
     *
     * 现改为「锁内取快照，锁外推送」：需立即推送的组在此只从队列移除并放入返回值，
     * 由调用方（`NotificationMonitorService`，持有共享且已配置通道的 `webhookSender`）
     * 在锁外执行推送。与 `DelayedPushManager` 的既有约定一致——管理器只负责
     * 队列与闹钟，推送交给 Service 执行。
     *
     * @param windowMs 聚合窗口（毫秒），开窗时确定后不延长
     * @param maxItems F3 满 N 条提前触发：>0 时该组达到 N 条立即移出队列交由调用方推送；
     *                 0 = 关闭（等窗口到点）
     * @param groupByTitle F3 按会话分组：true 时组 key = "包名|标题"
     *                     （同应用不同联系人分开聚合）；false = 按应用聚合（默认）
     *
     * @return 需要**立即推送**的聚合组：① 队列超限时移出的最旧组；
     *         ② 达到 maxItems 提前触发的当前组；无则空列表
     */
    @Synchronized
    fun append(
        info: NotificationInfo,
        windowMs: Long,
        maxItems: Int = 0,
        groupByTitle: Boolean = false,
    ): List<MergeGroup> {
        val queue = readQueue()
        val now = System.currentTimeMillis()
        // F3 按会话分组：key = 包名|标题（标题为空时退化为按应用聚合）
        val key = if (groupByTitle && info.title.isNotEmpty()) {
            "${info.packageName}|${info.title}"
        } else {
            info.packageName
        }
        // ⚠ 只匹配「未过期」的组：已过期但尚未被 drainDue（闹钟未触发 / 被系统杀进程
        // 错过唤醒）的僵尸组若仍被匹配到，后续通知会被并入该组并按旧的 windowEnd 排程，
        // 但 drainDue 只按 windowEnd 取组，僵尸组被取走后本应新开的通知就永久滞留；
        // 且多组同 key 时旧组会掩盖新组，表现为「不聚合、直接单条推送」。
        val existing = queue.firstOrNull {
            it.optString("key", "") == key && it.optLong("windowEnd", 0L) > now
        }
        val toFlush = ArrayList<MergeGroup>(1)
        if (existing != null) {
            // ⚠ 追加语义：窗口结束点不延长（固定窗口）。成员异常时 items 仍有
            // MAX_ITEMS_PER_GROUP 上限防 SP 无限膨胀（超限丢弃最旧的成员行）。
            val items = existing.optJSONArray("items") ?: JSONArray()
            if (items.length() >= MAX_ITEMS_PER_GROUP) {
                // 移除最旧一条（index 0）再追加
                val trimmed = JSONArray()
                for (i in 1 until items.length()) trimmed.put(items.getJSONObject(i))
                trimmed.put(info.toJson())
                existing.put("items", trimmed)
            } else {
                items.put(info.toJson())
                existing.put("items", items)
            }
            DiagLog.w(TAG, "聚合追加: $key, 窗口至 ${existing.optLong("windowEnd", 0L)}")
            // F3 满 N 条提前触发：达到上限则把该组移出队列，交由调用方在锁外立即推送
            // （不能留在队列——否则闹钟到点会二次推送同一组）
            if (maxItems > 0 && items.length() >= maxItems) {
                queue.remove(existing)
                groupFromJson(existing)?.let { toFlush.add(it) }
                DiagLog.w(TAG, "聚合组达上限提前触发: $key (${items.length()} 条 ≥ $maxItems)")
            }
        } else {
            val windowEnd = now + windowMs
            val group = JSONObject().apply {
                put("key", key)
                put("windowEnd", windowEnd)
                put("items", JSONArray().put(info.toJson()))
            }
            queue.add(group)
            // 组数上限：超出时把 windowEnd 最早的组移出队列，**交由调用方在锁外**立即推送
            // （防止 SP 无界增长；不能直接丢弃——聚合组里是尚未推送的通知）
            if (queue.size > MAX_GROUPS) {
                val oldest = queue.minByOrNull { it.optLong("windowEnd", Long.MAX_VALUE) }
                if (oldest != null) {
                    queue.remove(oldest)
                    groupFromJson(oldest)?.let { toFlush.add(it) }
                }
            }
            DiagLog.w(TAG, "聚合开窗: $key, 窗口至 $windowEnd")
        }
        writeQueue(queue)
        scheduleNext()
        return toFlush
    }

    /** 取出全部已到期的聚合组；返回空列表表示无可推送组 */
    @Synchronized
    fun drainDue(): List<MergeGroup> {
        val queue = readQueue()
        if (queue.isEmpty()) return emptyList()
        val now = System.currentTimeMillis()
        val due = queue.filter { it.optLong("windowEnd", 0L) <= now }
        if (due.isEmpty()) return emptyList()
        writeQueue(queue.filter { it.optLong("windowEnd", 0L) > now })
        DiagLog.w(TAG, "聚合组到期 ${due.size} 组，剩余 ${queue.size - due.size}")
        return due.mapNotNull { groupFromJson(it) }
    }

    /** 当前活跃的聚合组（前台通知 InboxStyle 预览用），按 windowEnd 升序 */
    @Synchronized
    fun activeGroups(): List<MergeGroup> {
        return readQueue().mapNotNull { groupFromJson(it) }.sortedBy { it.windowEnd }
    }

    /** 服务启动/配置刷新时重排闹钟（进程被杀 → START_STICKY 重建场景） */
    @Synchronized
    fun rescheduleAll() {
        val queue = readQueue()
        if (queue.isEmpty()) {
            cancelAlarm()
            return
        }
        // 服务长时间未运行：过期组保留，靠 immediately 触发的闹钟尽快补推
        // （不能用 DelayedPushManager 的"丢弃过期"策略——聚合组里是未推送的通知，不能丢）
        scheduleNext()
    }

    /** 清空全部聚合组（仅调试/重置用；正常到点走 drainDue） */
    @Synchronized
    fun clear() {
        writeQueue(ArrayList())
        cancelAlarm()
    }

    /**
     * 把聚合推送的送达结果按 MERGE 伪通道逐成员回传。
     *
     * 成功时把消息文案换成 [I18n.mergeDeliveredLabel]（"已合并推送"）——用户需要知道
     * 这条内容不是单独发的、而是聚合推送的一部分；失败时保留原生失败原因，
     * 否则用户看到"失败"却不知为何失败。
     *
     * 多通道时 [WebhookSender.sendWebhooksOnly] 已按「最差优先」汇总（任一通道失败即失败）——
     * 宁可多报一次失败，也不要让失败被某个成功通道掩盖、静默成"已合并推送"。
     */
    fun markMembersDelivered(
        group: MergeGroup,
        result: WebhookResponseParser.ParseResult
    ) {
        val success = result.status == WebhookResponseParser.DeliveryStatus.SUCCESS
        val forwarded = if (success) {
            result.copy(message = I18n.mergeDeliveredLabel())
        } else {
            result
        }
        for (member in group.items) {
            DeliveryNotifier.notify(context, member.id, "MERGE", forwarded)
        }
        DiagLog.w(
            TAG,
            "聚合组送达回传: ${group.key} (${group.items.size} 条) → " +
                if (success) "success" else "failed(${result.status})"
        )
    }

    private fun groupFromJson(json: JSONObject): MergeGroup? {
        return try {
            val key = json.optString("key", "")
            val windowEnd = json.optLong("windowEnd", 0L)
            val itemsJson = json.optJSONArray("items") ?: return null
            val items = ArrayList<NotificationInfo>(itemsJson.length())
            for (i in 0 until itemsJson.length()) {
                try {
                    items.add(NotificationInfo.fromJson(itemsJson.getJSONObject(i)))
                } catch (_: Exception) {}
            }
            if (key.isEmpty() || items.isEmpty()) return null
            MergeGroup(key, windowEnd, items)
        } catch (e: Exception) {
            Log.w(TAG, "聚合组解析失败: ${e.message}")
            null
        }
    }

    private fun scheduleNext() {
        val queue = readQueue()
        if (queue.isEmpty()) {
            cancelAlarm()
            return
        }
        val next = queue.minByOrNull { it.optLong("windowEnd", Long.MAX_VALUE) } ?: return
        val stored = next.optLong("windowEnd", 0L)
        // windowEnd 缺失/非法时不能静默 return（否则该组永远等不到闹钟、通知滞留）。
        // 兜底按「当前时间立即到期」排程，交给 drainDue 立即推送。
        val fireAt = if (stored > 0L) stored else System.currentTimeMillis()
        val am = alarmManager ?: return
        try {
            val intent = Intent(ACTION_MERGE_DUE).apply { setPackage(context.packageName) }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            val pi = PendingIntent.getBroadcast(context, REQUEST_CODE, intent, flags)
            // 精确闹钟策略与 DelayedPushManager 一致（共享 flutter.exact_alarm_enabled 开关）
            if (isExactAlarmEnabled()) {
                try {
                    am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAt, pi)
                    Log.d(TAG, "聚合推送精确闹钟已排程 fireAt=$fireAt")
                    return
                } catch (e: SecurityException) {
                    Log.w(TAG, "精确闹钟未授权，降级非精确闹钟", e)
                }
            }
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAt, pi)
            Log.d(TAG, "聚合推送闹钟已排程 fireAt=$fireAt")
        } catch (e: Exception) {
            Log.e(TAG, "聚合推送闹钟排程失败", e)
        }
    }

    /** 精确闹钟开关（与 DelayedPushManager 共用同一 Flutter 设置项） */
    private fun isExactAlarmEnabled(): Boolean {
        return try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.getBoolean("flutter.exact_alarm_enabled", false)
        } catch (e: Exception) {
            false
        }
    }

    private fun cancelAlarm() {
        try {
            val am = alarmManager ?: return
            val intent = Intent(ACTION_MERGE_DUE).apply { setPackage(context.packageName) }
            val pi = PendingIntent.getBroadcast(
                context,
                REQUEST_CODE,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            am.cancel(pi)
        } catch (e: Exception) {
            Log.e(TAG, "取消聚合推送闹钟失败", e)
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
            Log.e(TAG, "聚合队列读取失败", e)
            ArrayList()
        }
    }

    private fun writeQueue(queue: List<JSONObject>) {
        try {
            val arr = JSONArray()
            for (item in queue) arr.put(item)
            prefs.edit().putString(KEY_QUEUE, arr.toString()).apply()
        } catch (e: Exception) {
            Log.e(TAG, "聚合队列写入失败", e)
        }
    }
}
