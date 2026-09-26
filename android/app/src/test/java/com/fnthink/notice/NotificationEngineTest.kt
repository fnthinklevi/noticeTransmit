package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 通知引擎判定测试（roadmap T19）。
 *
 * 这里钉的是**用户已经依赖的语义**，不是实现细节：阈值、"由不满足变为满足"的迟滞、
 * 30 分钟冷却、维度独立、读不到就不判定、规则顺序。T20（规则入 DB）与 T21（影子求值）
 * 都以这份语义为基线比对，所以每条都写成"改动必红"的形式：
 * 把 crossing 改成"只要满足就推"，一次充电会推两三遍；
 * 把缺失维度当 0℃，拿不到温区的多数机型会凭空误报"温度过高"。
 */
class NotificationEngineTest {

    private val t0 = 1_700_000_000_000L
    private val minute = 60_000L

    private fun rule(
        type: String,
        threshold: Int,
        id: String = "r-$type-$threshold",
    ) = BatteryRule(id = id, type = type, threshold = threshold, enabled = true, title = "")

    private fun reading(
        level: Int,
        charging: Boolean = false,
        temps: Map<String, Double> = emptyMap(),
    ) = EngineReading(level = level, charging = charging, temperatures = temps)

    private val temp = rule("battery_temp_above", 40)

    private fun tempRound(
        engine: NotificationEngine,
        c: Double,
        at: Long,
        level: Int = 80,
    ): EngineDecision = engine.evaluate(
        enabled = true,
        batteryRules = emptyList(),
        temperatureRules = listOf(temp),
        reading = reading(level, temps = mapOf(temp.type to c)),
        now = at,
    )

    // ———— 电量维度 ————

    @Test
    fun `首轮只记基准，不因当前已满足条件就告警`() {
        val engine = NotificationEngine()
        val first = engine.evaluate(
            true, listOf(rule("level_below", 20)), emptyList(), reading(5), t0
        )
        assertTrue(
            "开机时电量已经很低是既有状态，不是刚发生的事件：推一条就是凭空告警",
            first is EngineDecision.Silent && first.reason == Silence.BASELINE,
        )
    }

    @Test
    fun `level_below 只在由高变低且未充电时触发`() {
        val r = rule("level_below", 20)
        val engine = NotificationEngine()
        engine.evaluate(true, listOf(r), emptyList(), reading(30), t0) // 基准
        val fire = engine.evaluate(true, listOf(r), emptyList(), reading(15), t0 + 1)
        assertTrue("由 30 掉到 15 必须触发", fire is EngineDecision.BatteryFire)

        // 已在阈值之下继续走低：不重复推（这就是 crossing 语义的全部意义）
        engine.evaluate(true, listOf(r), emptyList(), reading(14), t0 + 2)
        val again = engine.evaluate(true, listOf(r), emptyList(), reading(13), t0 + 3)
        assertTrue(again is EngineDecision.Silent && again.reason == Silence.NOT_CROSSING)

        // 充电中：电量在涨，"电量低"对用户不是事件
        val charging = engine.evaluate(
            true, listOf(r), emptyList(), reading(10, charging = true), t0 + 4
        )
        assertTrue("充电时的 level_below 必须不触发", charging is EngineDecision.Silent)
    }

    @Test
    fun `level_above 未充电时不算事件`() {
        val r = rule("level_above", 90)
        val engine = NotificationEngine()
        engine.evaluate(true, listOf(r), emptyList(), reading(50), t0) // 基准
        val notCharging = engine.evaluate(true, listOf(r), emptyList(), reading(95), t0 + 1)
        assertTrue(
            "没充电时「电量高于 90」不是用户要的事件（充满是常态，不是告警）",
            notCharging is EngineDecision.Silent,
        )
    }

    @Test
    fun `level_above 在充电中由低升高才触发`() {
        val r = rule("level_above", 90)
        val engine = NotificationEngine()
        engine.evaluate(true, listOf(r), emptyList(), reading(50), t0) // 基准
        engine.evaluate(true, listOf(r), emptyList(), reading(80), t0 + 1) // 仍未满足 ⇒ 基准 80
        val charging = engine.evaluate(
            true, listOf(r), emptyList(), reading(92, charging = true), t0 + 2
        )
        assertTrue(
            "80→92 且正在充电：这才是「快充满了」的那一刻",
            charging is EngineDecision.BatteryFire,
        )
    }

    @Test
    fun `充电状态翻转只推一次，状态不变就不重复`() {
        val on = rule("charging", 0)
        val engine = NotificationEngine()
        engine.evaluate(true, listOf(on), emptyList(), reading(50), t0) // 基准（未充电）
        val fire = engine.evaluate(
            true, listOf(on), emptyList(), reading(50, charging = true), t0 + 1
        )
        assertTrue(fire is EngineDecision.BatteryFire)
        val repeat = engine.evaluate(
            true, listOf(on), emptyList(), reading(52, charging = true), t0 + 2
        )
        assertTrue(
            "一直插着电却每 60s 推一条 = 把轮询当成了事件源",
            repeat is EngineDecision.Silent && repeat.reason == Silence.NOT_TRIGGERED,
        )
    }

    @Test
    fun `同一轮多条规则只推靠前的一条（已知限制，改推送条数要单开一批）`() {
        // 钉住现状而不是钉住"应该怎样"：有人改这条时会红，提醒他"一次采样推几条"
        // 是用户可见的行为变化（排在后面的规则会错过它的 crossing 瞬间）。
        val low = rule("level_below", 20)
        val critical = rule("level_below", 10)
        val engine = NotificationEngine()
        engine.evaluate(true, listOf(low, critical), emptyList(), reading(30), t0)
        val fired = engine.evaluate(
            true, listOf(low, critical), emptyList(), reading(5), t0 + 1
        )
        assertTrue(fired is EngineDecision.BatteryFire)
        assertEquals(low.id, (fired as EngineDecision.BatteryFire).rule.id)
    }

    @Test
    fun `引擎不替调用方过滤停用规则，过滤只许在解析处做`() {
        val disabled = BatteryRule(
            id = "off", type = "level_below", threshold = 20, enabled = false
        )
        val engine = NotificationEngine()
        engine.evaluate(true, listOf(disabled), emptyList(), reading(30), t0) // 基准
        val fired = engine.evaluate(true, listOf(disabled), emptyList(), reading(15), t0 + 1)
        assertTrue(
            "引擎拿到什么列表就判什么：enabled 的过滤在 parseBatteryRules。" +
                "两处都判一次的话，迟早一份松一份紧",
            fired is EngineDecision.BatteryFire,
        )
    }

    // ———— 温度维度 ————

    @Test
    fun crossing_firesOnlyWhenRisingAboveThreshold() {
        // 首次读数（prev=null）不算 crossing：避免服务启动/重启时因当前已高温而误报
        assertFalse(NotificationEngine.isTempCrossing(null, 50.0, 45))
        assertFalse(NotificationEngine.isTempCrossing(40.0, 44.9, 45))
        assertTrue(NotificationEngine.isTempCrossing(44.9, 45.0, 45))
        assertFalse(NotificationEngine.isTempCrossing(45.0, 46.0, 45)) // 持续高温不重复
    }

    @Test
    fun `冷却默认值必须等于现状的 30 分钟`() {
        // T19 任务书原文要求。用户已依赖"触发一次后半小时不再吵"，改这个数就是改行为。
        assertEquals(30 * 60 * 1000L, NotificationEngine.DEFAULT_COOLDOWN_MS)
    }

    @Test
    fun `温度触发后冷却期内不再重复，期满后重新 crossing 才算`() {
        val engine = NotificationEngine()
        assertTrue(tempRound(engine, 39.0, t0) is EngineDecision.Silent) // 基准
        assertTrue(tempRound(engine, 41.0, t0 + minute) is EngineDecision.Silent) // 无 prev
        assertTrue(tempRound(engine, 30.0, t0 + 2 * minute) is EngineDecision.Silent)
        val fired = tempRound(engine, 41.0, t0 + 3 * minute)
        assertTrue("30→41 是 crossing，必须推", fired is EngineDecision.TemperatureFire)

        tempRound(engine, 30.0, t0 + 10 * minute)
        val cooling = tempRound(engine, 45.0, t0 + 12 * minute)
        assertTrue(
            "冷却窗口内即使重新爬过阈值也不许再推（温度在阈值附近抖动属正常）",
            cooling is EngineDecision.Silent && cooling.reason == Silence.IN_COOLDOWN,
        )

        tempRound(engine, 30.0, t0 + 70 * minute)
        val after = tempRound(engine, 41.0, t0 + 75 * minute)
        assertTrue("冷却期满 + 新 crossing ⇒ 重新武装", after is EngineDecision.TemperatureFire)
    }

    @Test
    fun `冷却按维度独立记账，一个高温维度不会把另一个维度一起静音`() {
        val battery = rule("battery_temp_above", 40)
        val device = rule("device_temp_above", 45)
        val engine = NotificationEngine()
        engine.evaluate(
            true, emptyList(), listOf(battery, device),
            reading(80, temps = mapOf(battery.type to 39.0, device.type to 44.0)), t0
        ) // 基准

        engine.evaluate(
            true, emptyList(), listOf(battery, device),
            reading(80, temps = mapOf(battery.type to 30.0, device.type to 44.0)), t0 + minute
        )
        val first = engine.evaluate(
            true, emptyList(), listOf(battery, device),
            reading(80, temps = mapOf(battery.type to 41.0, device.type to 44.0)), t0 + 2 * minute
        )
        assertTrue(first is EngineDecision.TemperatureFire)
        assertEquals(battery.type, (first as EngineDecision.TemperatureFire).rule.type)

        engine.evaluate(
            true, emptyList(), listOf(battery, device),
            reading(80, temps = mapOf(battery.type to 30.0, device.type to 30.0)), t0 + 3 * minute
        )
        val deviceLater = engine.evaluate(
            true, emptyList(), listOf(battery, device),
            reading(80, temps = mapOf(battery.type to 30.0, device.type to 47.0)), t0 + 4 * minute
        )
        assertTrue(
            "battery 维度的冷却期不能把 device 维度一起静音",
            deviceLater is EngineDecision.TemperatureFire,
        )
    }

    @Test
    fun `读不到的维度不参与判定，也不被当成 0 度`() {
        val screen = rule("screen_temp_above", 35)
        val engine = NotificationEngine()
        // 本机拿不到屏幕温区 ⇒ temperatures 里连这个键都没有
        val out = engine.evaluate(true, emptyList(), listOf(screen), reading(80), t0)
        assertTrue(out is EngineDecision.Silent)
        val withReading = engine.evaluate(
            true, emptyList(), listOf(screen),
            reading(80, temps = mapOf(screen.type to 20.0)), t0 + 1
        )
        assertTrue(
            "读到值但仍在阈值下：只记基准，不触发",
            withReading is EngineDecision.Silent,
        )
        val second = engine.evaluate(
            true, emptyList(), listOf(screen),
            reading(80, temps = mapOf(screen.type to 40.0)), t0 + 2
        )
        assertTrue(
            "20→40 才是一次 crossing ⇒ 该维度确实能判定（不是被永久禁用）",
            second is EngineDecision.TemperatureFire,
        )
    }

    @Test
    fun `只配温度规则也必须能判定（T19 修掉的饿死缺陷）`() {
        // 修前的总闸门是"电量规则非空才走这一轮"，而温度规则是另一页、另一套存储 ⇒
        // 只配了温度规则的用户永远收不到温度告警，界面上还一切正常。
        val engine = NotificationEngine()
        tempRound(engine, 39.0, t0) // 基准
        tempRound(engine, 41.0, t0 + minute) // 记维度基准
        tempRound(engine, 30.0, t0 + 2 * minute)
        val fire = tempRound(engine, 45.0, t0 + 3 * minute)
        assertTrue("温度族必须独立可判定", fire is EngineDecision.TemperatureFire)
    }

    // ———— 一轮只出一条时的状态推进（T21 影子比对的前提） ————

    @Test
    fun `温度命中时不得顺手推进电量基准`() {
        // 构造：电量规则本轮"因充电而不满足"，温度规则本轮 crossing ⇒ 引擎提前返回。
        // 若提前返回前把 prevLevel 刷成本轮读数，下一条用例的 crossing 就不成立了。
        val low = rule("level_below", 35)
        val engine = NotificationEngine()
        engine.evaluate(
            true, listOf(low), listOf(temp),
            reading(60, temps = mapOf(temp.type to 39.0)), t0
        ) // 基准：prevLevel=60
        engine.evaluate(
            true, listOf(low), listOf(temp),
            reading(50, temps = mapOf(temp.type to 38.0)), t0 + minute
        ) // 50>35 电量不满足；温度 38 仍在阈值 40 之下 ⇒ 只记基准，整轮走完 ⇒ prevLevel=50

        val tempFire = engine.evaluate(
            true, listOf(low), listOf(temp),
            reading(33, charging = true, temps = mapOf(temp.type to 45.0)), t0 + 2 * minute
        )
        assertTrue(
            "充电时 level_below 不算事件，于是本轮由温度命中",
            tempFire is EngineDecision.TemperatureFire,
        )

        val batteryFire = engine.evaluate(
            true, listOf(low), listOf(temp),
            reading(30, temps = mapOf(temp.type to 20.0)), t0 + 3 * minute
        )
        assertTrue(
            "prevLevel 必须仍是 50（33 那次没被记成基准）⇒ 30 才算 crossing。" +
                "若命中时也推进基准，prevLevel 会是 33，33>35 不成立 ⇒ 本条红",
            batteryFire is EngineDecision.BatteryFire,
        )
    }

    @Test
    fun `维度读不到时不得写入基准，否则下一轮会凭空造出一次 crossing`() {
        // 温区可能只是那一轮没读到（休眠 / 权限），不是"温度掉到 0℃"。
        // 若把缺失记成 0，下一次读到 40℃ 就会被当成 0→40 的上升沿 ⇒ 凭空误报一次高温。
        val screen = rule("screen_temp_above", 35)
        val engine = NotificationEngine()
        engine.evaluate(true, emptyList(), listOf(screen), reading(80, temps = mapOf(screen.type to 40.0)), t0) // 基准
        engine.evaluate(true, emptyList(), listOf(screen), reading(80, temps = mapOf(screen.type to 40.0)), t0 + minute) // 持平：不触发
        engine.evaluate(true, emptyList(), listOf(screen), reading(80), t0 + 2 * minute) // 这一轮读不到
        val afterGap = engine.evaluate(
            true, emptyList(), listOf(screen),
            reading(80, temps = mapOf(screen.type to 40.0)), t0 + 3 * minute
        )
        assertTrue(
            "上一轮读不到不得被记成 0℃ ⇒ 40→40 不是上升沿，不该推",
            afterGap is EngineDecision.Silent,
        )
    }

    @Test
    fun `同一维度的两条规则共用一份基准与冷却，于是只有先注册的那条能响（已知限制）`() {
        // 状态按 rule.type 记账（v1.59 至今如此）：同维度两条规则 ⇒ 后一条每轮拿到的
        // "上次读数"其实是同一轮前一条刚写进去的值 ⇒ 它永远等不到自己的 crossing。
        // 钉住现状而非"应该怎样"：T20 规则入 DB 会有稳定 id，届时是否改成按规则记账
        // 属用户可见的行为变化（同一维度从"只响一条"变成"两条都响"），要单独决策。
        val low = rule("battery_temp_above", 40)
        val high = rule("battery_temp_above", 50)
        val engine = NotificationEngine()
        engine.evaluate(
            true, emptyList(), listOf(low, high),
            reading(80, temps = mapOf(low.type to 30.0)), t0
        ) // 首轮只记基准（prevTemps 都还没写）
        engine.evaluate(
            true, emptyList(), listOf(low, high),
            reading(80, temps = mapOf(low.type to 30.0)), t0 + minute
        ) // 这一轮把维度的"上次读数"写成 30
        val r3 = engine.evaluate(
            true, emptyList(), listOf(low, high),
            reading(80, temps = mapOf(low.type to 45.0)), t0 + 2 * minute
        )
        assertTrue("30→45：低阈值那条拿到这一轮", r3 is EngineDecision.TemperatureFire)
        assertEquals(low.threshold, (r3 as EngineDecision.TemperatureFire).rule.threshold)

        engine.evaluate(
            true, emptyList(), listOf(low, high),
            reading(80, temps = mapOf(low.type to 48.0)), t0 + 3 * minute
        ) // 45→48：谁都不算上升沿（低阈值那条已在本轮把维度读数写成 48）
        val r5 = engine.evaluate(
            true, emptyList(), listOf(low, high),
            reading(80, temps = mapOf(low.type to 55.0)), t0 + 4 * minute
        )
        assertTrue(
            "48→55 本该是**高阈值那条**的上升沿；但同维度共用一份读数，" +
                "低阈值那一条在本轮先把它写成了 55 ⇒ 高阈值那条永远等不到自己的 crossing",
            r5 is EngineDecision.Silent,
        )
    }

    // ———— 文案模板选择（原先电量/温度两处各抄一份） ————

    @Test
    fun `自定义标题优先，空白才回退默认模板`() {
        val custom = BatteryRule("c", "level_below", 20, true, title = "我的标题")
        assertEquals("我的标题", NotificationEngine.titleOf(custom, "默认"))
        val blank = BatteryRule("b", "level_below", 20, true, title = "")
        assertEquals("默认", NotificationEngine.titleOf(blank, "默认"))
        // 只有空白的标题才回退（isNotBlank 语义，与 v1.59 完全一致）：
        // 用户"只打了空格"按没写处理，比推一条只有空格的标题有用。
        val spaces = BatteryRule("s", "level_below", 20, true, title = "   ")
        assertEquals("默认", NotificationEngine.titleOf(spaces, "默认"))
    }

    // ———— 总开关与空集 ————

    @Test
    fun `总开关关闭、两族皆空、没有读数都沉默`() {
        val engine = NotificationEngine()
        val off = engine.evaluate(
            false, listOf(rule("level_below", 20)), emptyList(), reading(5), t0
        )
        assertTrue(off is EngineDecision.Silent && off.reason == Silence.DISABLED)
        val empty = engine.evaluate(true, emptyList(), emptyList(), reading(5), t0)
        assertTrue(empty is EngineDecision.Silent && empty.reason == Silence.NO_RULES)
        val noReading = engine.evaluate(
            true, listOf(rule("level_below", 20)), emptyList(), null, t0
        )
        assertTrue(noReading is EngineDecision.Silent && noReading.reason == Silence.NO_READING)
    }

    @Test
    fun `未知规则类型永不触发，两族类型集合就是引擎认识的全部`() {
        val engine = NotificationEngine()
        val unknown = rule("brightness_below", 10)
        engine.evaluate(true, listOf(unknown), emptyList(), reading(50), t0)
        val out = engine.evaluate(true, listOf(unknown), emptyList(), reading(5), t0 + 1)
        assertTrue(
            "引擎不认识的类型必须静默不触发：T24 加亮度/网络触发源时要在这里登记，" +
                "不能先让 Dart 页面能配、原生后认识",
            out is EngineDecision.Silent,
        )
        assertEquals(3, NotificationEngine.TEMP_RULE_TYPES.size)
        assertEquals(5, NotificationEngine.BATTERY_RULE_TYPES.size)
        assertTrue(
            NotificationEngine.TEMP_RULE_TYPES.intersect(NotificationEngine.BATTERY_RULE_TYPES)
                .isEmpty()
        )
    }

    // ── T25：只读试跑 ────────────────────────────────────────────────

    @Test
    fun `试跑必须走三步，第三步才是答案`() {
        val out = NotificationEngine.previewTemperature(
            listOf(temp),
            mapOf("battery_temp_above" to 50.0),
            now = t0,
        )
        assertEquals(
            "三步顺序变了就不是跨越（引擎只认 prev 在阈值下、这次在阈值上）",
            listOf("baseline", "below", "current"),
            out.steps.map { it.first },
        )
        assertEquals(listOf("BASELINE", "NOT_TRIGGERED", "FIRE"), out.steps.map { it.second })
        assertEquals(temp, out.rule)
        assertEquals(50.0, out.temperatureC!!, 0.0001)
        assertEquals(null, out.silence)
    }

    @Test
    fun `没到阈值不许谎报触发`() {
        val out = NotificationEngine.previewTemperature(
            listOf(temp),
            mapOf("battery_temp_above" to 30.0),
            now = t0,
        )
        assertEquals(null, out.rule)
        assertEquals(Silence.NOT_TRIGGERED, out.silence)
    }

    @Test
    fun `读不到温区必须说读不到，不许混成没到阈值`() {
        // 引擎本体里这两种都落 NOT_TRIGGERED（真实告警行为不变），但试跑要给用户分诊：
        // 前者该去查传感器，后者该去调阈值。
        val out = NotificationEngine.previewTemperature(
            listOf(temp),
            mapOf("device_temp_above" to 99.0), // 有读数，但不是这条规则的维度
            now = t0,
        )
        assertEquals(null, out.rule)
        assertEquals(Silence.NO_READING, out.silence)
    }

    @Test
    fun `试跑反复跑结果一致：它不吃真实冷却`() {
        // 借服务那份引擎试跑，第一次会把 tempCooldownUntil 写成 now+30min ⇒ 第二次就会是
        // IN_COOLDOWN。用户看到的是"我试了一下，之后真告警反而不响了"。
        val temps = mapOf("battery_temp_above" to 50.0)
        val first = NotificationEngine.previewTemperature(listOf(temp), temps, now = t0)
        val second = NotificationEngine.previewTemperature(listOf(temp), temps, now = t0 + 1000)
        assertEquals(first.rule, second.rule)
        assertEquals(first.steps.map { it.second }, second.steps.map { it.second })
        assertTrue("两次都必须仍然触发", second.rule != null)
    }

    @Test
    fun `没有启用规则时试跑答 NO_RULES 而不是崩溃`() {
        val out = NotificationEngine.previewTemperature(
            emptyList(),
            mapOf("battery_temp_above" to 50.0),
            now = t0,
        )
        assertEquals(null, out.rule)
        assertEquals(Silence.NO_RULES, out.silence)
    }
}
