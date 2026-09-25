package com.fnthink.notice

/**
 * 一次采样喂给引擎的全部读数。
 *
 * ⚠ `temperatures` 的**缺键表示"这个维度本机读不到"**，不是 0、也不是"没超阈值"：
 * 屏幕/设备温区在多数机型上拿不到，拿不到就不判定，绝不能把缺失当低值参与比较
 * （与 `DeviceSnapshot` 的"读不到 = 缺字段，绝不是 0"是同一条不变量）。
 */
data class EngineReading(
    val level: Int,
    val charging: Boolean,
    val temperatures: Map<String, Double>,
)

/** 判定结论。`Silent` 也带原因，为的是 T21 的影子求值能逐条比对，而不是只比"推/没推"。 */
sealed class EngineDecision {
    data class BatteryFire(val rule: BatteryRule, val level: Int, val charging: Boolean) : EngineDecision()

    data class TemperatureFire(val rule: BatteryRule, val temperatureC: Double) : EngineDecision()

    data class Silent(val reason: Silence) : EngineDecision()
}

enum class Silence {
    DISABLED, // 用户关了总开关

    /** 两族规则都没配（注意：只看电量规则会漏掉"只配了温度"的用户，见 evaluate 注释） */
    NO_RULES,
    NO_READING, // 本机读不到电量（registerReceiver 返回 null）

    BASELINE, // 首轮只记基准，不推送
    NOT_TRIGGERED,
    NOT_CROSSING,
    IN_COOLDOWN,
}

/**
 * 通知引擎（roadmap T19）：**阈值 / 迟滞(crossing) / 冷却 / 去重**的唯一判据处。
 *
 * 为什么值得单独一个类：这两条判定链原先逐条写死在 `BatteryMonitor.checkBatteryAndNotify`
 * 里，一半在电量循环、一半在温度循环，两套状态字段、两套冷却与去重口径。T20 要把规则
 * 搬进 DB、T21 要让"旧链路 + 新引擎"影子并行比对、T24 要加亮度/网络触发源 —— 没有这个
 * 接缝，后面每一步都得再把那 60 行抄一遍；抄第二份必然分叉，而分叉的表现是
 * "某类告警永远不来"（用户在界面上看到规则在，只是不响）。
 *
 * 所以本类刻意做成**纯 Kotlin + 显式注入时钟 + 状态自持**：全部语义能在 JVM 上钉死
 * （见 `NotificationEngineTest`），不需要 Robolectric、不需要真机。
 *
 * ⚠ 语义与 v1.59 逐条等价，**本批只搬移判据不改判据**。三处值得写下来的既有语义：
 *  * 温度维度的 `prevTemps` 在**判定之前**就被本轮读数覆盖（先记基准再比 crossing）；
 *  * 一轮最多产出一条：命中即 return（`prevLevel` 在电量命中时被同步更新，而温度命中时
 *    不更新 —— 于是"同一轮里排在后面的电量规则"会错过它的 crossing 瞬间。这是既有缺陷，
 *    记进 base.md 与任务队列，修它要单独一批：改的是**推送条数**，属用户可见行为变化）；
 *  * 冷却只在温度维度存在（默认 30 分钟，等于现状 `TEMP_COOLDOWN_MS`）。
 *
 * 唯一的行为修复：**只看"电量规则非空"当总闸门，会让只配了温度规则的用户永远收不到
 * 温度告警**（`checkBatteryAndNotify` 原先 `batteryRules.isEmpty()` 就直接 return，
 * 而温度规则是另一页、另一套 prefs）。现在两族任一非空即参与判定。
 *
 * ⚠ 非线程安全：与现状一致，只在主线程（轮询 Handler 与电量广播都在主 Looper）调用。
 */
class NotificationEngine(private val cooldownMs: Long = DEFAULT_COOLDOWN_MS) {

    companion object {
        /**
         * 温度规则触发后的冷却期。**必须等于 v1.59 的 30 分钟**：
         * 用户已依赖"触发一次后半小时不再吵"，改这个数就是改行为（T19 任务书原文要求）。
         */
        const val DEFAULT_COOLDOWN_MS = 30 * 60 * 1000L

        /** 温度规则类型集合（与 Dart `TemperatureService.tempRuleTypes` 的跨端契约同源） */
        val TEMP_RULE_TYPES = setOf(
            "battery_temp_above", // 电池温度（BatteryManager，最可靠）
            "device_temp_above", // 设备整体温度（thermal_zone 最热温区）
            "screen_temp_above", // 屏幕温度（display/lcd 温区，部分机型不可得）
        )

        /** 判定用的电量规则类型（`level_equals` 之外都带充电态语义，见 [batteryMatches]） */
        val BATTERY_RULE_TYPES = setOf(
            "level_below",
            "level_above",
            "level_equals",
            "charging",
            "discharging",
        )

        /** 温度 crossing：由低于阈值变为达到阈值（首次读数 prev=null 不算 crossing） */
        fun isTempCrossing(prev: Double?, current: Double, threshold: Int): Boolean =
            prev != null && prev < threshold && current >= threshold

        /** 冷却期是否仍在生效 */
        fun isCooldownActive(cooldownUntil: Long, now: Long): Boolean = cooldownUntil > now

        /**
         * 文案模板的选择：**用户写了标题就用他的，没写才用该类型的默认模板**。
         *
         * 抽成纯函数是因为这条判据此前在电量与温度两处各写一遍
         * （`if (rule.title.isNotBlank()) …`）—— 两份抄本迟早一份松一份紧，
         * 表现是"同一个自定义标题在电量页生效、在温度页被忽略"。
         * 这里刻意不做 `trim()`：那是用户可见的字符串行为变化，不在搬移范围内。
         */
        fun titleOf(rule: BatteryRule, defaultTitle: String): String =
            if (rule.title.isNotBlank()) rule.title else defaultTitle

        /**
         * 单条电量规则"此刻是否满足条件"（不含 crossing）。
         * `level_below` 额外要求**未在充电**：插电时电量在涨，"电量低"对用户不是事件。
         */
        fun batteryMatches(
            rule: BatteryRule,
            level: Int,
            charging: Boolean,
            prevCharging: Boolean,
        ): Boolean = when (rule.type) {
            "level_below" -> level <= rule.threshold && !charging
            "level_above" -> level >= rule.threshold && charging
            "level_equals" -> level == rule.threshold
            "charging" -> charging && !prevCharging
            "discharging" -> !charging && prevCharging
            else -> false
        }

        /**
         * 同一条件"由不满足变为满足"的瞬间才算数（轮询与广播两条入口共用一条判据，
         * 否则一次充电过程会被推两三遍）。充电状态类规则本身就以"翻转"为条件，恒为真。
         */
        fun batteryCrosses(rule: BatteryRule, prevLevel: Int): Boolean =
            when (rule.type) {
                "level_below" -> prevLevel > rule.threshold
                "level_above" -> prevLevel < rule.threshold
                "level_equals" -> prevLevel != rule.threshold
                "charging", "discharging" -> true
                else -> false
            }
    }

    private var initialized = false
    private var prevLevel = -1
    private var prevCharging = false
    private val prevTemps = mutableMapOf<String, Double>()
    private val tempCooldownUntil = mutableMapOf<String, Long>()

    /** 两族规则是否至少配了一条（调用方据此省掉一次电池 syscall，见 `BatteryMonitor`）。 */
    fun hasRules(
        batteryRules: List<BatteryRule>,
        temperatureRules: List<BatteryRule>,
    ): Boolean = batteryRules.isNotEmpty() || temperatureRules.isNotEmpty()

    /**
     * 一次求值。[now] 显式注入（不读墙上时钟），这样冷却期/crossing 能在 JVM 上逐条钉测。
     *
     * 规则顺序 = 电量规则在前、温度规则在后（与 v1.59 的 `batteryRules + temperatureRules`
     * 一致）：一轮只出一条，所以顺序决定"同时满足时先推哪条"，改动它会改变用户已看到的行为。
     */
    fun evaluate(
        enabled: Boolean,
        batteryRules: List<BatteryRule>,
        temperatureRules: List<BatteryRule>,
        reading: EngineReading?,
        now: Long,
    ): EngineDecision {
        if (!enabled) return EngineDecision.Silent(Silence.DISABLED)
        // ⚠ 本行是 T19 唯一的行为修复：原先只看 batteryRules，只配温度规则的用户永远不响。
        if (!hasRules(batteryRules, temperatureRules)) {
            return EngineDecision.Silent(Silence.NO_RULES)
        }
        if (reading == null) return EngineDecision.Silent(Silence.NO_READING)

        if (!initialized) {
            // 首轮只记基准：服务启动/重启时当前往往已满足条件，直接推就是"开机即告警"。
            prevLevel = reading.level
            prevCharging = reading.charging
            initialized = true
            return EngineDecision.Silent(Silence.BASELINE)
        }

        // 记录"本轮最接近触发"的阻塞原因，供影子比对与日志（不影响是否推送）
        var closest = Silence.NOT_TRIGGERED

        for (rule in batteryRules + temperatureRules) {
            if (rule.type in TEMP_RULE_TYPES) {
                val value = reading.temperatures[rule.type] ?: continue // 读不到 → 不判定
                val prev = prevTemps[rule.type]
                prevTemps[rule.type] = value // 判定之前就更新（与 v1.59 一致）

                if (value < rule.threshold) continue
                if (!isTempCrossing(prev, value, rule.threshold)) {
                    closest = worse(closest, Silence.NOT_CROSSING)
                    continue
                }
                if (isCooldownActive(tempCooldownUntil[rule.type] ?: 0L, now)) {
                    closest = worse(closest, Silence.IN_COOLDOWN)
                    continue
                }
                tempCooldownUntil[rule.type] = now + cooldownMs
                return EngineDecision.TemperatureFire(rule, value)
            }

            if (!batteryMatches(rule, reading.level, reading.charging, prevCharging)) {
                continue
            }
            if (!batteryCrosses(rule, prevLevel)) {
                closest = worse(closest, Silence.NOT_CROSSING)
                continue
            }
            prevLevel = reading.level
            prevCharging = reading.charging
            return EngineDecision.BatteryFire(rule, reading.level, reading.charging)
        }

        prevLevel = reading.level
        prevCharging = reading.charging
        return EngineDecision.Silent(closest)
    }

    /** 阻塞原因 informative 程度排序：冷却 > 未 crossing > 未满足（只影响日志与影子比对）。 */
    private fun worse(current: Silence, candidate: Silence): Silence {
        val rank = mapOf(
            Silence.NOT_TRIGGERED to 0,
            Silence.NOT_CROSSING to 1,
            Silence.IN_COOLDOWN to 2,
        )
        return if ((rank[candidate] ?: 0) > (rank[current] ?: 0)) candidate else current
    }
}

/**
 * 一条引擎规则（电量与温度共用同一形状）。
 *
 * `enabled=false` 的规则在解析处就被滤掉（见 `BatteryMonitor.parseBatteryRules`），
 * 所以引擎拿到的列表**只含启用规则** —— 这里不再判 enabled，避免两处各判一次
 * （两处判据迟早一份松一份紧）。
 */
data class BatteryRule(
    val id: String,
    val type: String,
    val threshold: Int,
    val enabled: Boolean,
    val title: String = "",
)
