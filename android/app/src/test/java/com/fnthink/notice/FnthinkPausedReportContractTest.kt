package com.fnthink.notice

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * T138 ①的接线守卫：**推送暂停时，幻念族必须落一个可判的档**。
 *
 * 三族发送口在暂停时的行为曾经各不一致：webhook 那支回 `PAUSED`（NetworkClient）、
 * 邮件那支回 `PAUSED`（dispatchEmail），而幻念那支**静默 return** —— 那一格没有
 * 任何新状态进来，只能停在「推送中」，直到 T112 那道 90 秒上限来收场。界面说的
 * 全是假话，而三族不一致这件事行为测试看不见（要真机 + 暂停态 + 真通道），
 * 所以按源码形状钉住 —— 与 [BatteryMonitorWiringContractTest] 同一手法。
 *
 * 判据两条：
 *  1. `dispatchFnthink` 的暂停分支必须 `DeliveryNotifier.notify(..., "fnthink", paused)`；
 *  2. 那一发**不带备用标记**（这条消息根本没投递出去，标"走了备用"只会误导 ——
 *     与邮件那条注释同一句理由）。
 */
class FnthinkPausedReportContractTest {

    private val src: String by lazy {
        stripComments(
            File("src/main/kotlin/com/fnthink/notice/NotificationMonitorService.kt").readText(),
        )
    }

    @Test
    fun `暂停时幻念族要回传 paused 而不是静默吞掉`() {
        val fn = functionBody(src, "private fun dispatchFnthink(")
        assertTrue(
            "没找到 dispatchFnthink 函数体 —— 守卫本身失效了",
            fn.isNotEmpty(),
        )
        assertTrue(
            "暂停分支必须 DeliveryNotifier.notify(..., \"fnthink\", paused)：" +
                "静默 return 让那一格永远停在「推送中」（T138 ① 的缺陷本体）",
            Regex("""DeliveryNotifier\.notify\(this,\s*info\.id,\s*"fnthink",\s*paused\)""")
                .containsMatchIn(fn),
        )
    }

    @Test
    fun `暂停那一发不带备用标记`() {
        val fn = functionBody(src, "private fun dispatchFnthink(")
        val pausedAt = fn.indexOf("DeliveryStatus.PAUSED")
        assertTrue(
            "守卫锚点丢了（dispatchFnthink 里没有 PAUSED 分支）—— 按新结构重排",
            pausedAt >= 0,
        )
        val tail = fn.substring(pausedAt, fn.indexOf("return", pausedAt))
        assertTrue(
            "暂停那一发不许带 viaBackup：没投递出去的消息标「走了备用」是把没发生的事写进历史",
            !tail.contains("viaBackup"),
        )
    }

    private fun functionBody(src: String, signature: String): String {
        val start = src.indexOf(signature)
        if (start < 0) return ""
        val anchors = listOf("\n    private fun ", "\n    internal fun ", "\n    fun ", "\n}")
            .mapNotNull { anchor ->
                val at = src.indexOf(anchor, start + 1)
                if (at > start) at else null
            }
        val end = anchors.minOrNull() ?: src.length
        return src.substring(start, end)
    }
}
