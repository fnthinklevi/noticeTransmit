package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 「读本机最近一次定位」（T124 片C-2 的 `location:get`）里**能在 JVM 上断的那一半**：
 * 候选里挑"最新"的那一条（各 provider 的近况各自新旧不一，挑错就是把一条几小时前的
 * 座标当"最近"发出去）。
 *
 * 真机上"读到的是不是这台的位置"只有真机+真定位能证，这里钉的是挑选规则本身。
 */
class LocationFixTest {

    private fun row(provider: String, time: Long, accuracy: Float = 10f) =
        LocationFix.FixRow(provider = provider, timeMillis = time, accuracyMeters = accuracy)

    @Test
    fun `空表回 null，不编一条出来`() {
        assertNull(LocationFix.freshest(emptyList()))
        assertEquals(-1, LocationFix.freshestIndex(emptyList()))
    }

    @Test
    fun `单条就选它`() {
        val only = row("gps", 1000L)
        assertEquals(only, LocationFix.freshest(listOf(only)))
    }

    @Test
    fun `多条挑时间最大的那一条（不是第一条、也不是精度最好的）`() {
        val old = row("gps", 100L, accuracy = 5f)
        val fresh = row("network", 900L, accuracy = 500f)
        val middle = row("passive", 500L)
        assertEquals(
            "挑的是**最新**而不是第一条/最准的 —— 读的人要的是「现在大概在哪」",
            fresh,
            LocationFix.freshest(listOf(old, fresh, middle)),
        )
        assertEquals(1, LocationFix.freshestIndex(listOf(old, fresh, middle)))
    }

    @Test
    fun `时间全为 0（有些 ROM 的 last-known 不给时间）也回一条，而不是装作没有`() {
        val a = row("gps", 0L)
        val b = row("network", 0L)
        assertEquals(a, LocationFix.freshest(listOf(a, b)))
    }

    @Test
    fun `FINE 或 COARSE 任一给了就算给了这一条在源码里（判据不在这里，读法钉在别处）`() {
        // 权限判据要真 Context，JVM 上断不了；这里钉的是"两枚权限名都在文件里"——
        // 只判 FINE 的话，Android 12+ 选了"大致位置"的人会被读成"没给"。
        // ⚠ 先剥注释再判：文件头那段说明**点了"不用的那两个方法"的名**，不剥就会把
        //   注释里的字面量当成真代码（本仓在 Dart 侧为这个栽过几次，同一口坑）。
        val source = stripComments(
            appFile("src/main/kotlin/com/fnthink/notice/LocationFix.kt").readText(),
        )
        assertTrue(
            "FINE 与 COARSE 都要读",
            source.contains("ACCESS_FINE_LOCATION") && source.contains("ACCESS_COARSE_LOCATION"),
        )
        assertTrue(
            "两枚之间是 ||（任一给了就算给了）",
            source.contains("fine || coarse"),
        )
        assertTrue(
            "只读最近一次、不主动发起定位（不出现主动采集那类调用）",
            !source.contains("requestLocationUpdates") &&
                !source.contains("getCurrentLocation"),
        )
    }

    /** 剥掉块注释与整行注释（源码守卫的标配件，见上面那条用例的注释）。 */
    private fun stripComments(src: String): String =
        src
            .replace(Regex("(?s)/\\*.*?\\*/"), "")
            .lines()
            .filterNot { it.trimStart().startsWith("//") }
            .joinToString("\n")

    private fun appFile(rel: String): java.io.File {
        var dir = java.io.File("").absoluteFile
        while (true) {
            val f = java.io.File(dir, "android/app/$rel")
            if (f.exists()) return f
            dir = dir.parentFile ?: break
        }
        throw AssertionError("找不到 $rel")
    }
}
