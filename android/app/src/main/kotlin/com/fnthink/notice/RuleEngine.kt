package com.fnthink.notice

import android.util.Log
import com.fnthink.notice.BuildConfig
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * 通知规则引擎（原生端）
 *
 * 与 Flutter 端 FilterService.evaluateRule 语义保持一致，供前台通知服务在收到通知时
 * 实时评估规则并决定动作（推送 / 延迟推送 / 仅记录 / 静默忽略）。
 *
 * 规则 JSON 结构与 Flutter 端 NotificationRule.toMap() 一致：
 * [{
 *   "id", "name", "enabled", "priority"（规则优先级，高者先匹配）,
 *   "conditions": [{"id","type","value","logic"}],
 *   "actions": [{"id","type","params"}]
 * }]
 *
 * 动作语义：
 * - push   → 立即推送（默认）
 * - delay  → 延迟/定时推送（params.delaySeconds 延迟秒数；params.scheduleTime "HH:mm" 定时）
 * - merge  → 聚合推送（params.windowSeconds 聚合窗口秒数，默认 60）：同应用通知在窗口内
 *            先记录历史，窗口结束时合并为一条聚合推送（详见 MergePushManager 的交互风险标注）
 * - record → 仅记录到历史，不推送
 * - silent → 静默忽略（不推送也不记录）
 */
object RuleEngine {
    private const val TAG = "RuleEngine"

    /** 延迟动作未配置参数时的兜底延迟（60 秒） */
    const val DEFAULT_DELAY_MS = 60_000L

    /** 聚合窗口未配置/非法时的兜底窗口（60 秒），下限 5 秒 */
    const val DEFAULT_MERGE_WINDOW_MS = 60_000L
    const val MIN_MERGE_WINDOW_MS = 5_000L

    sealed class Decision {
        /** 静默忽略：不推送、不记录 */
        object Block : Decision()

        /** 仅记录到历史，不推送 */
        object Record : Decision()

        /** 立即推送 + 记录 */
        object Push : Decision()

        /** 延迟/定时推送：立即记录，到 fireAt 再推送 */
        data class Delay(val fireAt: Long) : Decision()

        /**
         * 聚合推送：立即记录，窗口期内同应用通知追加进同一聚合组，
         * 窗口结束时合并为一条推送。
         *
         * ⚠ 与延迟队列/去重键的交互风险（详见 MergePushManager 头注释）：
         * - 决策在命中规则时一次性产生，同一条通知不会同时进入 Delay 队列与 Merge 窗口
         *  （decide 命中第一条规则即停，动作取第一个有效项）；
         * - 聚合组 id 为 "{pkg}:merge:{windowEnd}"，与去重键 "{pkg}:{tag}:{id}" 体系独立；
         * - 窗口到期推送使用聚合 id，成员记录的送达结果以 MERGE 伪通道逐条回传补标。
         */
        data class Merge(
            val windowMs: Long,
            /** F3：满 N 条提前触发窗口（0 = 关闭，等窗口到点）；由规则 params.maxItems 配置 */
            val maxItems: Int = 0,
            /** F3：按会话分组（true 时聚合组 key = 包名|标题，同应用不同联系人分开聚合） */
            val groupByTitle: Boolean = false,
        ) : Decision()
    }

    /** 归一化文本（复用过滤引擎：trim + 全角转半角 + 折叠空白 + 小写） */
    private fun normalize(raw: String): String = FilterEngine.normalize(raw)

    /**
     * 对单条通知做规则匹配，返回决策。
     * 规则按优先级（大 → 小）排序，命中第一条即停止；未命中任何规则时默认立即推送。
     */
    fun decide(info: NotificationInfo, rulesJson: String): Decision {
        if (rulesJson.isBlank()) {
            DiagLog.w(TAG, "诊断·规则表为空(blank) → 全部默认推送")
            return Decision.Push
        }

        val rules = try {
            JSONArray(rulesJson)
        } catch (e: Exception) {
            Log.w(TAG, "规则 JSON 解析失败，按默认推送处理: ${e.message}")
            return Decision.Push
        }

        DiagLog.w(TAG, "诊断·规则表载入: ${rules.length()} 条 (jsonLen=${rulesJson.length})")

        val sorted = (0 until rules.length())
            .map { rules.getJSONObject(it) }
            .sortedByDescending { it.optInt("priority", 0) }

        return decideAmong(sorted, info, Decision.Push) ?: Decision.Push
    }

    /**
     * T186 片1：**设备状态翻转**路径的决策（没有通知到达）。
     *
     * 与 [decide] 的差别只有一处，但那一处是这条路径的全部安全边界：**只评估含设备态条件
     * （`charging_state` / `network_type`）的规则**。不过滤的话，一条"什么都不填"的规则
     * （`conditions` 为空时 [evaluate] 返回 false，但只配了一条 `package_name: "*"` 的规则
     * 会匹配）会在每次充电/断网时凭空推一条 —— 那是把"通知规则"变成"状态广播"。
     *
     * 返回 null = 这一次没有任何设备态规则命中（**不**回落 `Push`）：状态翻转不是通知，
     * 没有"默认推送"这回事。
     */
    fun decideDeviceState(info: NotificationInfo, rulesJson: String): Decision? {
        if (rulesJson.isBlank()) return null
        val rules = try {
            JSONArray(rulesJson)
        } catch (e: Exception) {
            Log.w(TAG, "设备态规则 JSON 解析失败，本次不评估: ${e.message}")
            return null
        }
        val sorted = (0 until rules.length())
            .map { rules.getJSONObject(it) }
            .filter { it.optBoolean("enabled", true) && hasDeviceStateCondition(it) }
            .sortedByDescending { it.optInt("priority", 0) }
        if (sorted.isEmpty()) return null
        return decideAmong(sorted, info, null)
    }

    /**
     * 规则表里是否至少有一条**启用中**的设备态规则。
     *
     * 给触发源做「要不要为此读一次连通性」的闸：没有这条规则时，电池广播不该为此
     * 多花一次 `ConnectivityManager` 调用（每 60s／每次电量变化都读）。
     */
    fun hasAnyDeviceStateRule(rulesJson: String): Boolean {
        if (rulesJson.isBlank()) return false
        val rules = try {
            JSONArray(rulesJson)
        } catch (e: Exception) {
            Log.w(TAG, "设备态规则 JSON 解析失败，按没有规则处理: ${e.message}")
            return false
        }
        for (i in 0 until rules.length()) {
            val rule = rules.optJSONObject(i) ?: continue
            if (rule.optBoolean("enabled", true) && hasDeviceStateCondition(rule)) return true
        }
        return false
    }

    /**
     * T186 片1：设备态翻转判据（纯函数，状态触发路径对「事件」的定义）。
     *
     * 只有**至少一枚**读数相对基准真的变了才算事件。两处细节都是刻意的：
     * - [previous] 为 null（还没有基准）⇒ **不是**翻转：服务刚起来／规则刚变更时先立基准，
     *   不把「当前状态」当成一次刚发生的变化；
     * - 空串 = 读不到，**不参与比较**：读不到不是某一档，拿它当一次翻转会凭空推一条
     *   （与条件求值「未知一律不匹配」同一条保守口径）。
     */
    fun isDeviceStateFlip(previous: DeviceStateReading?, current: DeviceStateReading): Boolean {
        if (previous == null) return false

        fun changed(before: String, now: String): Boolean =
            before.isNotEmpty() && now.isNotEmpty() && before != now

        return changed(previous.chargingState, current.chargingState) ||
            changed(previous.networkType, current.networkType)
    }

    /** 一次设备态读数（两枚原值；空串 = 读不到）。 */
    data class DeviceStateReading(val chargingState: String, val networkType: String)

    /** 这条规则是否含设备态条件（`charging_state` / `network_type`）。两型词表只在 [evaluateCondition] 一处。 */
    fun hasDeviceStateCondition(rule: JSONObject): Boolean {
        val conditions = rule.optJSONArray("conditions") ?: return false
        for (i in 0 until conditions.length()) {
            when (conditions.getJSONObject(i).optString("type", "")) {
                "charging_state", "network_type" -> return true
            }
        }
        return false
    }

    /// 命中第一条即停；[fallback] = 一条都没命中时的结论（通知路径是 Push，状态路径是 null）。
    private fun decideAmong(
        sorted: List<JSONObject>,
        info: NotificationInfo,
        fallback: Decision?
    ): Decision? {
        for (rule in sorted) {
            if (!rule.optBoolean("enabled", true)) {
                DiagLog.w(TAG, "诊断·规则跳过(禁用): ${rule.optString("name")}(${rule.optString("id")})")
                continue
            }
            val matched = evaluate(rule, info)
            if (DiagLog.enabled) {
                // 诊断明细含条件遍历，仅在诊断开启时构建（其余诊断点为轻量插值，非惰性足够）
                val conds = rule.optJSONArray("conditions")
                val condDesc = if (conds == null) "null" else
                    (0 until conds.length()).joinToString(",") { i ->
                        val c = conds.getJSONObject(i)
                        "${c.optString("type")}='${c.optString("value")}'"
                    }
                DiagLog.w(
                    TAG,
                    "诊断·规则评估: ${rule.optString("name")}(${rule.optString("id")}) " +
                        "pri=${rule.optInt("priority", 0)} 条件[$condDesc] 匹配=$matched"
                )
            }
            if (!matched) continue
            DiagLog.w(
                TAG,
                // 隐私：不记录通知标题（可能含验证码/余额等敏感内容）
                "规则命中: ${rule.optString("name", "")} (${rule.optString("id", "")}) " +
                    "pkg=${info.packageName}"
            )
            return decideAction(rule, info)
        }
        return fallback
    }

    /** 由命中规则的 actions 计算最终动作 */
    private fun decideAction(rule: JSONObject, info: NotificationInfo): Decision {
        val actions = rule.optJSONArray("actions") ?: return Decision.Push
        var recordOnly = false
        var delayFireAt: Long? = null
        var mergeWindowMs: Long? = null
        // F3 聚合深化：满 N 条提前触发 + 按会话分组（取首个 merge 动作的参数）
        var mergeMaxItems = 0
        var mergeGroupByTitle = false

        for (i in 0 until actions.length()) {
            val action = actions.getJSONObject(i)
            when (action.optString("type", "push")) {
                "silent" -> return Decision.Block
                "record" -> recordOnly = true
                "delay" -> {
                    val params = action.optJSONObject("params")
                    val t = computeFireAt(params)
                    delayFireAt = if (t != null && t > System.currentTimeMillis()) {
                        t
                    } else {
                        System.currentTimeMillis() + DEFAULT_DELAY_MS
                    }
                }
                "merge" -> {
                    if (mergeWindowMs == null) {
                        val params = action.optJSONObject("params")
                        val seconds = params?.optInt("windowSeconds", -1) ?: -1
                        mergeWindowMs = if (seconds > 0) {
                            maxOf(
                                seconds * 1000L,
                                MIN_MERGE_WINDOW_MS
                            )
                        } else {
                            DEFAULT_MERGE_WINDOW_MS
                        }
                        // F3：满 N 条提前触发（0/缺失 = 关闭）
                        val maxItems = params?.optInt("maxItems", -1) ?: -1
                        mergeMaxItems = if (maxItems > 0) maxItems else 0
                        // F3：按会话分组（同应用不同标题分开聚合）
                        mergeGroupByTitle = params?.optBoolean("groupByTitle", false) ?: false
                    }
                }
                // push：按立即推送处理
                else -> Unit
            }
        }

        // 动作同时配置时的优先级：delay > merge > record（与 Flutter 端首次出现的
        // 有效动作语义一致；delay/merge 都是"延后推送"，delay 定时点更明确故优先）
        if (delayFireAt != null) {
            Log.d(TAG, "延迟推送 fireAt=$delayFireAt")
            return Decision.Delay(delayFireAt)
        }
        if (mergeWindowMs != null) {
            Log.d(TAG, "聚合推送 windowMs=$mergeWindowMs maxItems=$mergeMaxItems groupByTitle=$mergeGroupByTitle")
            return Decision.Merge(mergeWindowMs, mergeMaxItems, mergeGroupByTitle)
        }
        if (recordOnly) return Decision.Record
        return Decision.Push
    }

    /**
     * 计算延迟动作的触发时间：
     * - params.delaySeconds > 0  → 当前时间 + 延迟秒数
     * - params.scheduleTime "HH:mm" → 当日该时刻（已过则顺延至次日）
     * - 均未配置 → null（由调用方兜底）
     */
    private fun computeFireAt(params: JSONObject?): Long? {
        if (params == null) return null
        val now = System.currentTimeMillis()

        val delaySeconds = params.optInt("delaySeconds", -1)
        if (delaySeconds > 0) {
            return now + delaySeconds * 1000L
        }

        val scheduleTime = params.optString("scheduleTime", "").trim()
        if (scheduleTime.isNotEmpty()) {
            val parts = scheduleTime.split(":")
            if (parts.size == 2) {
                val hour = parts[0].toIntOrNull()
                val minute = parts[1].toIntOrNull()
                if (hour != null && minute != null && hour in 0..23 && minute in 0..59) {
                    val cal = Calendar.getInstance().apply {
                        set(Calendar.HOUR_OF_DAY, hour)
                        set(Calendar.MINUTE, minute)
                        set(Calendar.SECOND, 0)
                        set(Calendar.MILLISECOND, 0)
                    }
                    var t = cal.timeInMillis
                    if (t <= now) t += 24 * 60 * 60 * 1000L
                    return t
                }
            }
        }
        return null
    }

    /** 评估单条规则：conditions 按 logic（and/or）分组，组内 AND、组间 OR */
    fun evaluate(rule: JSONObject, info: NotificationInfo): Boolean {
        // P1-4 规则级适用应用（排除制）：excludedPackages 非空且包含通知来源应用
        // → 本规则对该通知不适用。与 Dart 侧 FilterService.evaluateRule 语义一致；
        // 字段缺省 = 不排除任何应用（兼容旧版本存量规则数据）。
        val excluded = rule.optJSONArray("excludedPackages")
        if (excluded != null) {
            for (i in 0 until excluded.length()) {
                if (excluded.optString(i) == info.packageName) return false
            }
        }

        val conditions = rule.optJSONArray("conditions") ?: return false
        if (conditions.length() == 0) return false
        val normTitle = normalize(info.title)
        val normContent = normalize(info.content)

        val groups = ArrayList<Boolean>()
        var groupResult = true
        var isFirst = true

        for (i in 0 until conditions.length()) {
            val cond = conditions.getJSONObject(i)
            val match = evaluateCondition(cond, info, normTitle, normContent)
            val logic = cond.optString("logic", "and")

            if (isFirst) {
                groupResult = match
                isFirst = false
            } else if (logic == "and") {
                groupResult = groupResult && match
            } else {
                groups.add(groupResult)
                groupResult = match
            }
        }
        groups.add(groupResult)
        return groups.any { it }
    }

    private fun evaluateCondition(
        cond: JSONObject,
        info: NotificationInfo,
        normTitle: String,
        normContent: String
    ): Boolean {
        val type = cond.optString("type", "")
        val rawValue = cond.optString("value", "")
        val value = rawValue.trim()
        if (value.isEmpty() && type != "package_name") return false

        return when (type) {
            // "*" 表示「任意应用」：用于聚合推送等不区分应用的规则（与 Dart 侧语义一致）
            "package_name" -> value == "*" || info.packageName == value
            "title_contains" -> normTitle.contains(normalize(value))
            "title_not_contains" -> !normTitle.contains(normalize(value))
            "content_contains" -> normContent.contains(normalize(value))
            "content_not_contains" -> !normContent.contains(normalize(value))
            "priority" -> evaluatePriority(value.lowercase(), info.priority)
            "time_range" -> evaluateTimeRange(value)
            "regex_match" -> evaluateRegex(value, info.title, info.content)
            // T186 片1 设备态两型：与**通知到达那一刻**的读数逐字相等（大小写不敏感，与 Dart 侧同口径）。
            // 读不到 = 空串 ⇒ 与非空条件值都不相等 ⇒ 不匹配（不把未知伪装成某一档）。
            // 值域不在这里再校验：词表由 `DeviceSnapshot.chargingStateOf`／`networkTypeOf` 那两处负责，
            // 拼错的值（`ful`）自然匹配不上 —— 与"认不出的类型判不匹配"是同一条保守口径。
            "charging_state" -> info.chargingState.equals(value, ignoreCase = true)
            "network_type" -> info.networkType.equals(value, ignoreCase = true)
            else -> false
        }
    }

    /** 与 Flutter 端 _evaluatePriorityCondition 保持一致：高>=2、中=1、低<1 */
    private fun evaluatePriority(value: String, priority: Int): Boolean {
        return when (value) {
            "high" -> priority >= 2
            "medium" -> priority == 1
            "low" -> priority < 1
            else -> false
        }
    }

    /** 时间范围 "HH:mm-HH:mm"，支持跨天（start > end 表示跨零点） */
    private fun evaluateTimeRange(value: String): Boolean {
        val parts = value.split("-")
        if (parts.size != 2) return false
        val start = parseMinutes(parts[0]) ?: return false
        val end = parseMinutes(parts[1]) ?: return false
        val now = Calendar.getInstance()
        val current = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        return if (start <= end) {
            current >= start && current <= end
        } else {
            current >= start || current <= end
        }
    }

    private fun parseMinutes(s: String): Int? {
        val parts = s.trim().split(":")
        if (parts.size != 2) return null
        val hour = parts[0].toIntOrNull() ?: return null
        val minute = parts[1].toIntOrNull() ?: return null
        if (hour !in 0..23 || minute !in 0..59) return null
        return hour * 60 + minute
    }

    /** 正则匹配：命中标题或内容（与 Flutter 端一致，大小写敏感）。E1：超长 pattern 直接拒绝，防灾难性回溯阻塞 */
    private fun evaluateRegex(pattern: String, title: String, content: String): Boolean {
        if (pattern.length > 200) {
            Log.w(TAG, "正则超长拒绝（>200 字符）: ${pattern.take(30)}...")
            return false
        }
        return try {
            val regex = Regex(pattern)
            regex.containsMatchIn(title) || regex.containsMatchIn(content)
        } catch (e: Exception) {
            Log.w(TAG, "非法正则 '${pattern.take(30)}': ${e.message}")
            false
        }
    }
}
