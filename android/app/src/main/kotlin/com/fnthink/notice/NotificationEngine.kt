package com.fnthink.notice

/**
 * 一次采样喂给引擎的全部读数。
 *
 * ⚠ `temperatures` 的**缺键表示"这个维度本机读不到"**，不是 0、也不是"没超阈值"：
 * 屏幕/设备温区在多数机型上拿不到，拿不到就不判定，绝不能把缺失当低值参与比较
 * （与 `DeviceSnapshot` 的"读不到 = 缺字段，绝不是 0"是同一条不变量）。
 *
 * T24 起 `brightnessPercent` / `networkType` 同理用 **null 表达读不到**（亮度在部分 ROM
 * 的自动模式下拿不到；ConnectivityManager 不可用时没有网络类型可谈）。
 * 两者都有默认值 ⇒ 老的调用点（T25 的试跑）不会因为没有这两个维度就改变结论。
 */
data class EngineReading(
    val level: Int,
    val charging: Boolean,
    val temperatures: Map<String, Double>,
    val brightnessPercent: Int? = null,
    val networkType: String? = null,
)

/** 判定结论。`Silent` 也带原因，为的是 T21 的影子求值能逐条比对，而不是只比"推/没推"。 */
sealed class EngineDecision {
    data class BatteryFire(val rule: BatteryRule, val level: Int, val charging: Boolean) : EngineDecision()

    data class TemperatureFire(val rule: BatteryRule, val temperatureC: Double) : EngineDecision()

    /**
     * T24：亮度 / 网络触发。两个字段按类型只有一个非空 —— 渲染方不需要再判一次 type
     * 去猜"该把哪个值写进正文"，缺失的那一项就是这一族没有的那个维度。
     */
    data class DeviceStateFire(
        val rule: BatteryRule,
        val brightnessPercent: Int?,
        val networkType: String?,
    ) : EngineDecision()

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
 * T25 试跑结果（[NotificationEngine.previewTemperature] 的返回）。
 *
 * [steps] 逐步回传而不是只回最终结论：用户问的经常是"我配了 45℃ 为什么现在 50℃ 还不响"，
 * 答案在**过程**里（首轮基准 / 没有跨越 / 读不到该维度），只回"不响"就等于让人去猜。
 */
data class TemperaturePreview(
    val rule: BatteryRule?,
    val temperatureC: Double?,
    val silence: Silence?,
    val steps: List<Pair<String, String>>,
)

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

        /**
         * T24：亮度与网络触发源。**路由只看 type**，所以两族可以放在同一条规则列表里
         * （存储侧就是一个 `device_state` 族，不再为"两个族还是一族"多开一份表与一份镜像键）。
         */
        val BRIGHTNESS_RULE_TYPES = setOf("brightness_below", "brightness_above")
        val NETWORK_RULE_TYPES = setOf("network_connected", "network_disconnected")
        val DEVICE_STATE_RULE_TYPES = BRIGHTNESS_RULE_TYPES + NETWORK_RULE_TYPES

        /**
         * 亮度"向下跨越"：上一次还在阈值之上、这次掉到阈值之下才算一次事件。
         * 与温度的 crossing 同一条理由 —— 只要"满足就推"会让用户每 60s 被吵一次。
         */
        fun isBrightnessDownCrossing(
            prev: Int?,
            current: Int?,
            threshold: Int,
        ): Boolean = prev != null && current != null && prev >= threshold && current < threshold

        /** 亮度"向上跨越"（上一次不高于阈值，这次高于） */
        fun isBrightnessUpCrossing(
            prev: Int?,
            current: Int?,
            threshold: Int,
        ): Boolean = prev != null && current != null && prev <= threshold && current > threshold

        /**
         * 网络"断网"事件：上一次还有网、这次没了。
         *
         * ⚠ 只看"当前没网"不判"跨过去"是刻意的错法：断网期间每轮采样都会再推一次，
         * 而"没网"恰恰是用户最不需要被反复告知的那件事。
         */
        fun isNetworkLost(prev: String?, current: String?): Boolean =
            prev != null && current != null && prev != "none" && current == "none"

        /** 网络"恢复"事件：上一次没网、这次有了（恢复到哪种网络写进正文） */
        fun isNetworkRestored(prev: String?, current: String?): Boolean =
            prev != null && current != null && prev == "none" && current != "none"

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
         * 试跑第二步用的"压到阈值之下"的哨兵温度：滑块范围 30–90℃，任何合理阈值都不命中。
         * 它**不是**一次真实读数，只出现在 [previewTemperature] 里。
         */
        const val BELOW_ANY_THRESHOLD_C = -100.0

        /**
         * T25：温度规则的**只读试跑**（页右上与规则动作菜单的「试一次」）。
         *
         * 为什么在引擎这边而不是 Dart 那边：阈值/迟滞/冷却的判据只有一份，在 Dart 再实现
         * 一遍"会不会响"就是 T21 花一整批清掉的那种抄本（表现是测试器说不响、设备照样推）。
         *
         * 为什么必须走**三步**：引擎只认跨越（上一次还在阈值下、这次到阈值上），而一个全新
         * 实例第一次调用必定返回 `BASELINE` 且不播种温度 ⇒ 单喂一次真实读数永远得不到答案。
         * 于是 ① 真实读数建立基线 → ② 各维度压到阈值之下（播种"还没到"）→ ③ 再喂真实读数，
         * **第三步才是用户要的答案**。三步的判定都回传，界面才能说清"为什么没响"。
         *
         * 求值用的是**新建的引擎实例**：借服务那份试跑一次，就会真的吃掉 30 分钟冷却或挪动
         * baseline，表现成"我试了一下，之后真告警反而不响了"。
         */
        fun previewTemperature(
            rules: List<BatteryRule>,
            temps: Map<String, Double>,
            now: Long = System.currentTimeMillis(),
        ): TemperaturePreview {
            val previewEngine = NotificationEngine()
            val below = temps.keys.associateWith { BELOW_ANY_THRESHOLD_C }
            val steps = mutableListOf<Pair<String, String>>()
            var last: EngineDecision = EngineDecision.Silent(Silence.NO_RULES)
            for ((phase, reading) in listOf(
                "baseline" to temps,
                "below" to below,
                "current" to temps,
            )) {
                last = previewEngine.evaluate(
                    enabled = true,
                    batteryRules = emptyList(),
                    temperatureRules = rules,
                    reading = EngineReading(
                        level = 50,
                        charging = false,
                        temperatures = reading,
                    ),
                    now = now,
                )
                steps.add(
                    phase to when (last) {
                        is EngineDecision.TemperatureFire -> "FIRE"
                        is EngineDecision.BatteryFire -> "FIRE"
                        is EngineDecision.DeviceStateFire -> "FIRE"
                        is EngineDecision.Silent -> last.reason.name
                    },
                )
            }
            val fire = last as? EngineDecision.TemperatureFire
            val reason = (last as? EngineDecision.Silent)?.reason
            return TemperaturePreview(
                rule = fire?.rule,
                temperatureC = fire?.temperatureC,
                silence = reason?.let {
                    // 引擎里"这台设备没有这个温区"会落成 NOT_TRIGGERED（不判定就等于没满足）。
                    // 真实告警那条路不区分（都不推，行为不变），但**试跑要给用户看**：
                    // 读不到该去查传感器，没到阈值该去调阈值 —— 混成一句会把人支使去改配置。
                    if (it == Silence.NOT_TRIGGERED && rules.none { r -> r.type in temps }) {
                        Silence.NO_READING
                    } else {
                        it
                    }
                },
                steps = steps,
            )
        }

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

    /**
     * 冷却截止，按 `rule.type` 分格。原先叫 `tempCooldownUntil`（只有温度用），
     * T24 起亮度/网络也走同一张表：**冷却是"每条规则类型一份"的语义，与族无关**，
     * 再开一张新表就会有两套"多久之内不重复吵"各自漂移。
     */
    private val cooldownUntil = mutableMapOf<String, Long>()

    /** T24：亮度与网络的"上一次"。null = 还没有上一次（首轮不判定） */
    private var prevBrightness: Int? = null
    private var prevNetwork: String? = null

    /**
     * 各族规则是否至少配了一条（调用方据此省掉一次电池 syscall，见 `BatteryMonitor`）。
     *
     * ⚠ 每加一族都必须加进来：T19 修的就是"只看电量规则 ⇒ 只配温度的用户永远不响"，
     * 漏掉一族就是同一个缺陷换个族重演一次。
     */
    fun hasRules(
        batteryRules: List<BatteryRule>,
        temperatureRules: List<BatteryRule>,
        deviceStateRules: List<BatteryRule> = emptyList(),
    ): Boolean = batteryRules.isNotEmpty() || temperatureRules.isNotEmpty() ||
        deviceStateRules.isNotEmpty()

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
        deviceStateRules: List<BatteryRule> = emptyList(),
    ): EngineDecision {
        if (!enabled) return EngineDecision.Silent(Silence.DISABLED)
        // ⚠ 本行是 T19 唯一的行为修复：原先只看 batteryRules，只配温度规则的用户永远不响。
        // 同一件事对 T24 的亮度/网络族也必须成立 ⇒ 三族一起判。
        if (!hasRules(batteryRules, temperatureRules, deviceStateRules)) {
            return EngineDecision.Silent(Silence.NO_RULES)
        }
        if (reading == null) return EngineDecision.Silent(Silence.NO_READING)

        // 上一轮的读数先取出来（判定要用"上一次"），随后立刻更新 —— 与温度的
        // "判定之前就更新"同一条顺序：不管是触发还是各种不满足提前 return，
        // 这一轮的观测都必须留下一例，否则"断网"会在下一轮又被当成新事件。
        val prevBrightness = this.prevBrightness
        val prevNetwork = this.prevNetwork
        this.prevBrightness = reading.brightnessPercent
        this.prevNetwork = reading.networkType

        if (!initialized) {
            // 首轮只记基准：服务启动/重启时当前往往已满足条件，直接推就是"开机即告警"。
            prevLevel = reading.level
            prevCharging = reading.charging
            initialized = true
            return EngineDecision.Silent(Silence.BASELINE)
        }

        // 记录"本轮最接近触发"的阻塞原因，供影子比对与日志（不影响是否推送）
        var closest = Silence.NOT_TRIGGERED

        for (rule in batteryRules + temperatureRules + deviceStateRules) {
            if (rule.type in TEMP_RULE_TYPES) {
                val value = reading.temperatures[rule.type] ?: continue // 读不到 → 不判定
                val prev = prevTemps[rule.type]
                prevTemps[rule.type] = value // 判定之前就更新（与 v1.59 一致）

                if (value < rule.threshold) continue
                if (!isTempCrossing(prev, value, rule.threshold)) {
                    closest = worse(closest, Silence.NOT_CROSSING)
                    continue
                }
                if (isCooldownActive(cooldownUntil[rule.type] ?: 0L, now)) {
                    closest = worse(closest, Silence.IN_COOLDOWN)
                    continue
                }
                cooldownUntil[rule.type] = now + cooldownMs
                return EngineDecision.TemperatureFire(rule, value)
            }

            if (rule.type in BRIGHTNESS_RULE_TYPES) {
                val value = reading.brightnessPercent ?: continue // 读不到 → 不判定
                val crossed = if (rule.type == "brightness_below") {
                    isBrightnessDownCrossing(prevBrightness, value, rule.threshold)
                } else {
                    isBrightnessUpCrossing(prevBrightness, value, rule.threshold)
                }
                if (!crossed) continue
                if (isCooldownActive(cooldownUntil[rule.type] ?: 0L, now)) {
                    closest = worse(closest, Silence.IN_COOLDOWN)
                    continue
                }
                cooldownUntil[rule.type] = now + cooldownMs
                return EngineDecision.DeviceStateFire(rule, value, null)
            }

            if (rule.type in NETWORK_RULE_TYPES) {
                val value = reading.networkType ?: continue
                val crossed = if (rule.type == "network_disconnected") {
                    isNetworkLost(prevNetwork, value)
                } else {
                    isNetworkRestored(prevNetwork, value)
                }
                if (!crossed) continue
                if (isCooldownActive(cooldownUntil[rule.type] ?: 0L, now)) {
                    closest = worse(closest, Silence.IN_COOLDOWN)
                    continue
                }
                cooldownUntil[rule.type] = now + cooldownMs
                return EngineDecision.DeviceStateFire(rule, null, value)
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
