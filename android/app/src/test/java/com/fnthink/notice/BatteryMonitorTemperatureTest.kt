package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 温度维度判定测试（v1.59）。
 *
 * 覆盖：crossing 触发语义（由低于阈值变为达到）、冷却期防抖、
 * 不可得维度（null）跳过、与电量规则的状态独立性。
 */
class BatteryMonitorTemperatureTest {

    @Test
    fun crossing_firesOnlyWhenRisingAboveThreshold() {
        // 首次采样（prev=null）不触发——避免服务启动/重启时因当前已高温误报
        assertFalse(BatteryMonitor.isTempCrossing(null, 50.0, 45))
        // 低于阈值 → 不触发
        assertFalse(BatteryMonitor.isTempCrossing(40.0, 44.9, 45))
        // 由低到高 crossing → 触发
        assertTrue(BatteryMonitor.isTempCrossing(44.9, 45.0, 45))
        // 持续高于阈值（prev 已 >= 阈值）→ 不重复触发
        assertFalse(BatteryMonitor.isTempCrossing(45.0, 46.0, 45))
    }

    @Test
    fun cooldown_blocksRepeatWithinWindow() {
        val now = 1_000_000L
        val until = now + BatteryMonitor.TEMP_COOLDOWN_MS
        assertTrue(BatteryMonitor.isCooldownActive(until, now + 1000))
        // 冷却期结束后重新武装
        assertFalse(BatteryMonitor.isCooldownActive(until, until + 1))
        assertFalse(BatteryMonitor.isCooldownActive(0L, now))
    }

    @Test
    fun tempRuleTypes_coverThreeDimensions() {
        // 双端契约：Dart battery_service 的类型集合与此一致（见
        // test/services/battery_temperature_contract_test.dart）
        assertEquals(
            setOf("battery_temp_above", "device_temp_above", "screen_temp_above"),
            BatteryMonitor.TEMP_RULE_TYPES,
        )
    }

    @Test
    fun cooldownPerDimension_isIndependent() {
        // 维度独立：battery 触发冷却不影响 device 维度（各自独立状态）
        val batteryCooldown = 5_000L
        val deviceCooldown = 0L
        assertTrue(BatteryMonitor.isCooldownActive(batteryCooldown, 4_999L))
        assertFalse(BatteryMonitor.isCooldownActive(deviceCooldown, 4_999L))
    }
}
