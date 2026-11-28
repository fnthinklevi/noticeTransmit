package com.fnthink.notice

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * `BatteryMonitor` 轮询准入守卫（后台空闲降 CPU 第 3 项）。
 *
 * 旧实现只要 `monitoringEnabled` 就无条件 `startPolling()`；`pollingRunnable` 虽然每轮
 * 先看 `hasRules()`，但**零规则也照旧 `postDelayed(60s)`**。于是三族规则全空时，服务
 * 仍每分钟醒一次、进一次引擎方法 —— 不推送、不读电池，但会阻止 CPU 深睡。
 *
 * 这类缺陷在行为测试里很难抓：没有通知、没有异常、界面完全正常；只有"队列里还有没有
 * 下一发"能说明它在空转。因此这里钉住三件事：谁决定轮询、规则变时谁重算、停掉后还会不会
 * 自己把自己排回去。
 */
class BatteryPollingContractTest {

    private val src: String by lazy {
        stripComments(File("src/main/kotlin/com/fnthink/notice/BatteryMonitor.kt").readText())
    }

    private val service: String by lazy {
        stripComments(
            File("src/main/kotlin/com/fnthink/notice/NotificationMonitorService.kt").readText(),
        )
    }

    @Test
    fun `轮询只在总开关开且真有规则时启动`() {
        val sync = blockAfter(src, "fun syncPolling()")
        assertTrue(
            "syncPolling 必须同时看总开关与三族规则；只看其中一边就会" +
                "「零规则仍空转」或「有规则却不轮询」",
            Regex("""if \(_enabled && hasRules\(\)\) startPolling\(\) else stopPolling\(\)""")
                .containsMatchIn(sync),
        )
        for (trigger in listOf(
            "fun setEnabled(",
            "fun updateRules(",
            "fun updateTemperatureRules(",
            "fun updateDeviceStateRules(",
            "fun setTemperatureEnabled(",
            "fun setDeviceStateEnabled(",
        )) {
            assertTrue(
                "$trigger 变更后必须重算轮询准入：漏一处就是规则恢复后永远不响",
                Regex(
                    Regex.escape(trigger) + """[\s\S]{0,900}?syncPolling\(\)""",
                ).containsMatchIn(src),
            )
        }
    }

    @Test
    fun `服务启动路径不再无条件 startPolling`() {
        assertFalse(
            "服务里直接 startPolling 会绕过零规则闸门，重新引入每分钟空转",
            Regex("""batteryMonitor\.startPolling\(""").containsMatchIn(service),
        )
        assertTrue(
            "服务启动/重载必须走 syncPolling",
            service.contains("batteryMonitor.syncPolling()"),
        )
    }

    @Test
    fun `停掉之后 runnable 不许把自己排回去`() {
        val runnable = blockAfter(src, "private val pollingRunnable")
        assertTrue(
            "runnable 开头必须看 polling：stopPolling 只 removeCallbacks 时，正在执行的那一轮" +
                "仍会把下一发排进队列，停轮询就变成「下一次才停」",
            Regex("""if \(!polling\) return""").containsMatchIn(runnable),
        )
        assertTrue(
            "重排也必须受 polling 管",
            Regex("""if \(polling\) handler\.postDelayed\(""").containsMatchIn(runnable),
        )
        assertTrue(
            "startPolling 必须幂等：重复 sync 不许叠出两条 60 秒链",
            Regex("""if \(polling\) return""").containsMatchIn(blockAfter(src, "fun startPolling()")),
        )
    }
}

private fun blockAfter(source: String, anchor: String): String {
    val start = source.indexOf(anchor)
    if (start < 0) return ""
    val end = source.indexOf("\n    }", start)
    return source.substring(start, if (end < 0) source.length else end)
}
