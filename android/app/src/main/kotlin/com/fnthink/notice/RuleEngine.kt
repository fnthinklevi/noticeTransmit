package com.fnthink.notice

import android.util.Log
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
 * - push   → 立即推送（默认，含 merge 动作暂按 push 处理）
 * - delay  → 延迟/定时推送（params.delaySeconds 延迟秒数；params.scheduleTime "HH:mm" 定时）
 * - record → 仅记录到历史，不推送
 * - silent → 静默忽略（不推送也不记录）
 */
object RuleEngine {
    private const val TAG = "RuleEngine"

    /** 延迟动作未配置参数时的兜底延迟（60 秒） */
    const val DEFAULT_DELAY_MS = 60_000L

    sealed class Decision {
        /** 静默忽略：不推送、不记录 */
        object Block : Decision()

        /** 仅记录到历史，不推送 */
        object Record : Decision()

        /** 立即推送 + 记录 */
        object Push : Decision()

        /** 延迟/定时推送：立即记录，到 fireAt 再推送 */
        data class Delay(val fireAt: Long) : Decision()
    }

    /** 归一化文本（复用过滤引擎：trim + 全角转半角 + 折叠空白 + 小写） */
    private fun normalize(raw: String): String = FilterEngine.normalize(raw)

    /**
     * 对单条通知做规则匹配，返回决策。
     * 规则按优先级（大 → 小）排序，命中第一条即停止；未命中任何规则时默认立即推送。
     */
    fun decide(info: NotificationInfo, rulesJson: String): Decision {
        if (rulesJson.isBlank()) return Decision.Push

        val rules = try {
            JSONArray(rulesJson)
        } catch (e: Exception) {
            Log.w(TAG, "规则 JSON 解析失败，按默认推送处理: ${e.message}")
            return Decision.Push
        }

        val sorted = (0 until rules.length())
            .map { rules.getJSONObject(it) }
            .sortedByDescending { it.optInt("priority", 0) }

        for (rule in sorted) {
            if (!rule.optBoolean("enabled", true)) continue
            if (!evaluate(rule, info)) continue
            Log.d(
                TAG,
                "规则命中: ${rule.optString("name", "")} (${rule.optString("id", "")}) " +
                    "pkg=${info.packageName} title=${info.title}"
            )
            return decideAction(rule, info)
        }
        return Decision.Push
    }

    /** 由命中规则的 actions 计算最终动作 */
    private fun decideAction(rule: JSONObject, info: NotificationInfo): Decision {
        val actions = rule.optJSONArray("actions") ?: return Decision.Push
        var recordOnly = false
        var delayFireAt: Long? = null

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
                // push / merge：按立即推送处理
                else -> Unit
            }
        }

        if (delayFireAt != null) {
            Log.d(TAG, "延迟推送 fireAt=${delayFireAt} (${info.title})")
            return Decision.Delay(delayFireAt)
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
            "package_name" -> info.packageName == value
            "title_contains" -> normTitle.contains(normalize(value))
            "title_not_contains" -> !normTitle.contains(normalize(value))
            "content_contains" -> normContent.contains(normalize(value))
            "content_not_contains" -> !normContent.contains(normalize(value))
            "priority" -> evaluatePriority(value.lowercase(), info.priority)
            "time_range" -> evaluateTimeRange(value)
            "regex_match" -> evaluateRegex(value, info.title, info.content)
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

    /** 正则匹配：命中标题或内容（与 Flutter 端一致，大小写敏感） */
    private fun evaluateRegex(pattern: String, title: String, content: String): Boolean {
        return try {
            val regex = Regex(pattern)
            regex.containsMatchIn(title) || regex.containsMatchIn(content)
        } catch (e: Exception) {
            Log.w(TAG, "非法正则 '${pattern.take(30)}': ${e.message}")
            false
        }
    }
}
