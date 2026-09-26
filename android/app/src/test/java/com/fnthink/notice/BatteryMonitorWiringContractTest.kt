package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * `BatteryMonitor` 的**接线**守卫（T19）。
 *
 * 判据本身在 `NotificationEngine` 里，JVM 能直测；但"读数有没有交给引擎、引擎结论有没有
 * 被渲染"这几条住在需要 Android `Context` 的类里，行为测试覆盖不到。这几处一旦接错，
 * 表现全都是**静默不推**（而不是崩溃），所以用源码形状钉住 —— 与
 * `MainThreadAndApiGuardContractTest` 同一手法（读源码后先剥注释，见 `SourceGuards.kt`：
 * 一句提到旧写法的注释能让守卫为反而绿）。
 *
 * 每条都对应一个真实存在过的缺陷形状：算出来没塞进去、总闸门只看一族、
 * 模板判据在两个渲染函数里各抄一份、状态被复制成两份。
 */
class BatteryMonitorWiringContractTest {

    private val src: String by lazy {
        stripComments(File("src/main/kotlin/com/fnthink/notice/BatteryMonitor.kt").readText())
    }

    @Test
    fun `总闸门看两族规则，不再只系数电量规则`() {
        assertTrue(
            "hasRules() 必须把两族规则都交给引擎判定；只回 batteryRules.isNotEmpty() 就是" +
                "「只配温度规则的用户永远不响」那条缺陷复活",
            Regex("""engine\.hasRules\(\s*batteryRules\s*,\s*temperatureRules""").containsMatchIn(src)
        )
        assertFalse(
            "checkBatteryAndNotify 不得再自己数 batteryRules（判据归引擎）",
            Regex("""if \(!enabled \|\| batteryRules\.isEmpty\(\)\)|_enabled \|\| batteryRules\.isEmpty""")
                .containsMatchIn(src)
        )
    }

    @Test
    fun `读数与两族规则一起交给引擎，结论两条都渲染`() {
        assertTrue(
            "引擎必须同时拿到温度规则，否则温度族又被漏在接缝外",
            Regex("""engine\.evaluate\([\s\S]{0,400}?temperatureRules = temperatureRules""")
                .containsMatchIn(src)
        )
        for (branch in listOf("EngineDecision.BatteryFire", "EngineDecision.TemperatureFire")) {
            assertTrue(
                "$branch 没有对应的渲染分支 ⇒ 判出来了却不发，等于没判",
                src.contains("is $branch")
            )
        }
    }

    @Test
    fun `电池温度必须真的塞进 BatteryInfo`() {
        // T19 修掉的缺陷：算出了 temperatureC 却没写进构造参数 ⇒ battery_temp_above
        // 永远读不到，用户配的「电池温度高于 X」永远不响，而界面一切正常。
        val start = src.indexOf("private fun parseBatteryIntent(")
        assertTrue("parseBatteryIntent 不见了/改名：接缝守卫要跟", start >= 0)
        val end = src.indexOf("\n    }\n", start)
        val body = src.substring(start, if (end < 0) src.length else end)
        assertTrue(
            "没截到函数体 ⇒ 下面几条断言会对空串永远成立",
            body.isNotEmpty()
        )
        assertTrue(
            "BatteryInfo 构造必须带 temperatureC = …（少了这一行就是静默丢数据）",
            Regex("""temperatureC\s*=\s*temperatureC""").containsMatchIn(body)
        )
        // 换算规则只此一份：不得再自己写 `/ 10.0`
        assertFalse(
            "0.1℃ 的换算必须复用 DeviceSnapshot.temperatureC（两处各写一份迟早不一致）",
            Regex("""/\s*10\.0""").containsMatchIn(body)
        )
        assertTrue(
            "换算没走 DeviceSnapshot.temperatureC ⇒ 与设备快照那条链口径分叉",
            body.contains("DeviceSnapshot.temperatureC(")
        )
    }

    @Test
    fun `标题模板判据不在渲染函数里各抄一份`() {
        val copies = Regex("""rule\.title\.isNotBlank\(\)""").findAll(src).count()
        assertEquals(
            "「用户写了就用他的」这条判据只能在引擎里出现一次（BatteryMonitor 两处都调 titleOf）",
            0,
            copies
        )
        val uses = Regex("""NotificationEngine\.titleOf\(""").findAll(src).count()
        assertEquals(
            "电量、温度、设备状态（T24 亮度/网络）三个渲染函数都要走 titleOf ⇒ " +
                "多一个渲染函数而没走它，就是给「用户写了标题却被忽略」开出第三个现场",
            3,
            uses,
        )
    }

    @Test
    fun `引擎是唯一的判据持有者，BatteryMonitor 不再存状态`() {
        for (state in listOf(
            "prevLevel",
            "prevIsCharging",
            "prevTemps",
            "tempCooldownUntil",
            "initialized",
        )) {
            assertFalse(
                "$state 又回到 BatteryMonitor ⇒ 两处状态迟早不一致（引擎已有自己的一份）",
                Regex("""(@Volatile\s+)?private\s+(var|val)\s+$state""").containsMatchIn(src)
            )
        }
        assertTrue(
            "BatteryMonitor 必须持有一个引擎实例",
            src.contains("NotificationEngine()")
        )
    }
}
