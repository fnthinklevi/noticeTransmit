package com.fnthink.notice

import android.net.NetworkCapabilities
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * T17 设备快照的**纯函数**契约（`DeviceSnapshot.normalize` 与几个换算函数）。
 *
 * 这里锁的全是"错了不会崩、只会显示成一个看起来很合理的错数字"的地方：Long 整除截断、
 * 亮度值域 0-255 还是 0-100、电池温度的十分之一度，以及最重要的 —— **读不到必须显式为
 * null 并进 `unavailable`，不能伪装成 0**。换算集中在纯函数里，正是为了能在 JVM 里钉住
 * （Android API 那半边只能靠人工/仪器，见 base.md 的"必须真机验证"清单）。
 *
 * ⚠ 网络类型用例传的是 `NetworkCapabilities.TRANSPORT_*` 本身，不在测试里另抄一份数字：
 * 自己定义常量再跟它比，就是把值改了两次也照样绿（本项目踩过这种空守卫）。
 */
class DeviceSnapshotTest {

    private fun normalize(raw: Map<String, Any?>): Map<String, Any?> =
        DeviceSnapshot.normalize(raw, 1770000000000L)

    @Suppress("UNCHECKED_CAST")
    private fun unavailableOf(out: Map<String, Any?>): List<String> =
        out["unavailable"] as List<String>

    // ── 单位换算 ────────────────────────────────────────────────────────────

    @Test
    fun bytesToMbKeepsTheFractionInsteadOfTruncating() {
        // 1_677_722 B ≈ 1.6 MB。写成 bytes/1024/1024（Long 整除）会得到 1.0 ——
        // 屏幕上就是一个安静少报了的存储数字。
        assertEquals(1.6, DeviceSnapshot.toMb(1_677_722L)!!, 0.001)
        assertEquals(1536.0, DeviceSnapshot.toMb(1_610_612_736L)!!, 0.001)
    }

    @Test
    fun zeroAndNegativeAndNullBytesAreAllUnread_notZero() {
        // 0 字节的分区不是"存储剩 0MB"，是读不到（StatFs 失败时也可能给 0）
        assertNull("0 必须按未读到处理", DeviceSnapshot.toMb(0L))
        assertNull(DeviceSnapshot.toMb(-1L))
        assertNull(DeviceSnapshot.toMb(null))
    }

    @Test
    fun batteryTemperatureIsTenthsOfACelsius() {
        assertEquals(31.5, DeviceSnapshot.temperatureC(315)!!, 0.0001)
        assertEquals(45.0, DeviceSnapshot.temperatureC(450)!!, 0.0001)
        // 读不到时系统给 -1；0 及以下不可能是传感器读数，一律按未读到
        assertNull(DeviceSnapshot.temperatureC(-1))
        assertNull(DeviceSnapshot.temperatureC(0))
        assertNull(DeviceSnapshot.temperatureC(null))
    }

    @Test
    fun brightnessHandlesBothValueRangesAndKeepsZeroValid() {
        // 0 是合法值（最暗），不能与"读不到"混为一谈 ⇒ 判负数，不是判 <=0
        assertEquals(0, DeviceSnapshot.brightnessPercent(0))
        assertEquals(100, DeviceSnapshot.brightnessPercent(255))
        assertEquals(50, DeviceSnapshot.brightnessPercent(128))
        // 部分 ROM（含模拟器）直接给 0-100：>100 才按 255 换算
        assertEquals(76, DeviceSnapshot.brightnessPercent(76))
        assertNull(DeviceSnapshot.brightnessPercent(-1))
        assertNull(DeviceSnapshot.brightnessPercent(null))
    }

    @Test
    fun networkPreferenceIsVpnThenWifiThenEthernetThenCellular() {
        assertEquals("none", DeviceSnapshot.networkTypeOf(false, emptySet()))
        // VPN 之下跑什么不重要：用户关心的事实是"走了 VPN" ⇒ VPN 优先级最高
        assertEquals(
            "vpn",
            DeviceSnapshot.networkTypeOf(
                true,
                setOf(NetworkCapabilities.TRANSPORT_WIFI, NetworkCapabilities.TRANSPORT_VPN),
            ),
        )
        assertEquals(
            "wifi",
            DeviceSnapshot.networkTypeOf(
                true,
                setOf(NetworkCapabilities.TRANSPORT_WIFI, NetworkCapabilities.TRANSPORT_CELLULAR),
            ),
        )
        assertEquals(
            "ethernet",
            DeviceSnapshot.networkTypeOf(
                true,
                setOf(
                    NetworkCapabilities.TRANSPORT_ETHERNET,
                    NetworkCapabilities.TRANSPORT_CELLULAR,
                ),
            ),
        )
        assertEquals(
            "cellular",
            DeviceSnapshot.networkTypeOf(true, setOf(NetworkCapabilities.TRANSPORT_CELLULAR)),
        )
        assertEquals("other", DeviceSnapshot.networkTypeOf(true, emptySet()))
    }

    // ── normalize 的"未知"账 ────────────────────────────────────────────────

    @Test
    fun emptySnapshotMarksEveryFieldUnavailableInsteadOfInventingValues() {
        val out = normalize(emptyMap())
        val unavailable = unavailableOf(out)
        assertTrue("全空快照必须记账，不能静默", unavailable.isNotEmpty())
        for (key in listOf(
            "model", "brand", "manufacturer", "osVersion", "sdkInt", "network",
            "batteryLevel", "batteryCharging", "batteryTemperatureC",
            "storageTotalMb", "storageFreeMb", "memoryTotalMb", "memoryAvailableMb",
            "brightnessPercent", "brightnessMode", "uptimeSeconds",
        )) {
            assertTrue("$key 应记为未读到：$unavailable", unavailable.contains(key))
            assertFalse("$key 不该出现在结果里（未知≠0）", out.containsKey(key))
        }
        assertEquals(1770000000000L, out["capturedAtMs"])
    }

    /**
     * 输出字段名 = 跨端契约（Dart 的 `DeviceSnapshot.fromMap` 逐名读同一批键）。
     * 两端各写字符串、改名不会有任何编译期报错 —— 这里钉 Kotlin 侧，
     * `test/services/device_snapshot_test.dart` 钉 Dart 侧读的名字都在这份里。
     */
    @Test
    fun outputFieldNamesAreTheCrossLanguageContract() {
        val out = normalize(
            mapOf(
                "model" to "M", "brand" to "B", "manufacturer" to "MF",
                "osVersion" to "14", "sdkInt" to 34, "network" to "wifi",
                "batteryLevel" to 50, "batteryCharging" to true,
                "batteryTemperatureC" to 300, "storageTotalMb" to 1_000_000_000L,
                "storageFreeMb" to 500_000_000L, "memoryTotalMb" to 8_000_000_000L,
                "memoryAvailableMb" to 2_000_000_000L, "brightnessPercent" to 100,
                "brightnessMode" to 1, "uptimeSeconds" to 1000L,
            )
        )
        assertEquals(
            setOf(
                "model", "brand", "manufacturer", "osVersion", "sdkInt", "network",
                "batteryLevel", "batteryCharging", "batteryTemperatureC",
                "storageTotalMb", "storageFreeMb", "memoryTotalMb", "memoryAvailableMb",
                "brightnessPercent", "brightnessMode", "uptimeSeconds",
                "capturedAtMs", "unavailable",
            ),
            out.keys,
        )
    }

    @Test
    fun fullSnapshotConvertsEveryUnitAndRecordsNothingAsUnavailable() {
        val out = normalize(
            mapOf(
                "model" to "MEIZU 21",
                "brand" to "MEIZU",
                "manufacturer" to "Meizu",
                "osVersion" to "14",
                "sdkInt" to 34,
                "network" to "wifi",
                "batteryLevel" to 82,
                "batteryCharging" to false,
                "batteryTemperatureC" to 315,
                "storageTotalMb" to 128_000_000_000L,
                "storageFreeMb" to 30_000_000_000L,
                "memoryTotalMb" to 12_000_000_000L,
                "memoryAvailableMb" to 4_500_000_000L,
                "brightnessPercent" to 128,
                "brightnessMode" to 0,
                "uptimeSeconds" to 7_200_000L,
            )
        )
        val unavailable = unavailableOf(out)
        assertEquals("完整输入不该有未读到项：$unavailable", emptyList<String>(), unavailable)
        assertEquals("MEIZU 21", out["model"])
        assertEquals(34, out["sdkInt"])
        assertEquals(82, out["batteryLevel"])
        assertEquals(false, out["batteryCharging"])
        assertEquals(31.5, out["batteryTemperatureC"] as Double, 0.0001)
        assertEquals(122070.3, out["storageTotalMb"] as Double, 0.2)
        assertEquals(4291.5, out["memoryAvailableMb"] as Double, 0.2)
        assertEquals(50, out["brightnessPercent"])
        assertEquals("manual", out["brightnessMode"])
        assertEquals(7200L, out["uptimeSeconds"])
    }

    @Test
    fun blankStringsAndOutOfRangeNumbersAreTreatedAsUnread() {
        // Build.MODEL 在个别 ROM 上是 ""；空串进快照会渲染成一个空白行而不是"读不到"
        val out = normalize(mapOf("model" to "   ", "batteryLevel" to 101, "sdkInt" to 0))
        val unavailable = unavailableOf(out)
        assertTrue(unavailable.contains("model"))
        assertTrue("电量 101 是非法读数，不能当成有效值：$unavailable", unavailable.contains("batteryLevel"))
        assertTrue("sdkInt=0 是哨兵值：$unavailable", unavailable.contains("sdkInt"))
    }

    @Test
    fun batteryLevelZeroIsValidButMinusOneIsNot() {
        val zero = normalize(mapOf("batteryLevel" to 0))
        assertFalse("电量为 0 是有效读数", unavailableOf(zero).contains("batteryLevel"))
        assertEquals(0, zero["batteryLevel"])

        val minus = normalize(mapOf("batteryLevel" to -1))
        assertTrue(unavailableOf(minus).contains("batteryLevel"))
    }
}
