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
            "hasRules() 必须把各族规则都交给引擎判定；只回 batteryRules.isNotEmpty() 就是" +
                "「只配温度规则的用户永远不响」那条缺陷复活",
            Regex("""engine\.hasRules\(\s*batteryRules\s*,""").containsMatchIn(src),
        )
        assertFalse(
            "checkBatteryAndNotify 不得再自己数 batteryRules（判据归引擎）",
            Regex("""if \(!enabled \|\| batteryRules\.isEmpty\(\)\)|_enabled \|\| batteryRules\.isEmpty""")
                .containsMatchIn(src)
        )
    }

    /**
     * T24 修的第二个"会撒谎的开关"：`temperature_notify_enabled` 一直被 Dart 写进 prefs，
     * 而原生从没有人读它 —— 用户在温度页关掉开关，温度告警照旧推。
     * 这类缺陷静态看不见（页面、prefs、通道全都正常），只有"原生到底读不读这把键"一条能钉。
     */
    @Test
    fun `族开关必须真的改变送进引擎的规则列表`() {
        for ((setter, gate, list) in listOf(
            Triple("setTemperatureEnabled", "temperatureEnabled", "temperatureRules"),
            Triple("setDeviceStateEnabled", "deviceStateEnabled", "deviceStateRules"),
        )) {
            assertTrue("$setter 必须存在（服务在 loadConfig 里递开关）", src.contains("fun $setter("))
            assertTrue(
                "$list 必须按 $gate 收口成 effective*：只存 setter 而判定链不看它，" +
                    "等于又留一枚只会显示状态的开关",
                Regex("""if \($gate\) $list else emptyList\(\)""").containsMatchIn(src),
            )
            assertTrue(
                "evaluate 必须收 effective* 那份，收原始字段就是关不掉",
                Regex("""$list = effective""").containsMatchIn(src),
            )
        }
        val cm = stripComments(
            File("src/main/kotlin/com/fnthink/notice/ConfigManager.kt").readText(),
        )
        for (key in listOf(
            "flutter.temperature_notify_enabled",
            "flutter.device_state_notify_enabled",
        )) {
            assertTrue("ConfigManager 必须真读这把键：$key", cm.contains("\"$key\""))
        }
        // 默认 true：没动过开关的老用户行为不许变（"升级不改用户设置"）。
        assertEquals(
            "两枚族开关的默认值都必须是 true",
            2,
            Regex("""getBoolean\(KEY_(TEMPERATURE|DEVICE_STATE)_NOTIFY_ENABLED, true\)""")
                .findAll(cm).count(),
        )
    }

    @Test
    fun `读数与各族规则一起交给引擎，结论三条都渲染`() {
        for (fam in listOf("temperatureRules", "deviceStateRules")) {
            assertTrue(
                "引擎必须拿到 $fam 的**生效版**（族开关关掉时传空表）：漏一族就是" +
                    "「那一族永远不响」或「关不掉」的复活现场",
                Regex("""engine\.evaluate\([\s\S]{0,600}?$fam = effective""")
                    .containsMatchIn(src),
            )
        }
        for (branch in listOf(
            "EngineDecision.BatteryFire",
            "EngineDecision.TemperatureFire",
            "EngineDecision.DeviceStateFire",
        )) {
            assertTrue(
                "$branch 没有对应的渲染分支 ⇒ 判出来了却不发，等于没判",
                src.contains("is $branch"),
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
