package com.fnthink.notice

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 延迟推送队列「上限挤出」的纯算术测试（[DelayedPushLogic]，无 Android 依赖）。
 *
 * 为什么这一发值得单独钉（T150 片2，维护者 2026-10-12 第 6 条）：旧写法在写盘时把超出
 * `MAX_QUEUE_SIZE` 的条目**直接丢掉**，而被丢的那条已经在推送历史里占了一行、送达列停在
 * 初值 `pending`。没有任何回执会再来推离它 ⇒ 界面上那一格永远写着「发送中」，而本机
 * 再也不会发它。现在上限的语义改成"挤出来的交回调用方补推"，于是必须能逐条断言：
 * ① 留在队列里的还是原来那些（既有行为不动）；② 被挤出的**一条都不许凭空消失**。
 */
class DelayedPushQueueCapTest {

    private fun item(key: String, fireAt: Long?): JSONObject =
        JSONObject().apply {
            put("key", key)
            if (fireAt != null) put("fireAt", fireAt)
        }

    private fun keys(items: List<JSONObject>): List<String> = items.map { it.optString("key") }

    @Test
    fun splitByCap_noop_whenUnderLimit() {
        val queue = listOf(item("a", 10L), item("b", 20L), item("c", 30L))
        val (kept, spilled) = DelayedPushLogic.splitByCap(queue, max = 3)
        // 恰好等于上限不该动任何东西（棘轮边界：`size <= max` 而不是 `<`）
        assertEquals(queue, kept)
        assertTrue("没超限就不该有挤出条目", spilled.isEmpty())
    }

    @Test
    fun splitByCap_spillsEarliestFiring_keepsSameOnesAsBefore() {
        val queue = listOf(item("late", 300L), item("early", 100L), item("mid", 200L))
        val (kept, spilled) = DelayedPushLogic.splitByCap(queue, max = 2)
        // 旧实现是 `sortedBy{fireAt}.takeLast(2)` ⇒ mid + late，一字没改
        assertEquals(listOf("mid", "late"), keys(kept))
        // 挤出的正是最该发的那条（最早到点的）：调用方必须把它推出去，不是当垃圾
        assertEquals(listOf("early"), keys(spilled))
    }

    @Test
    fun splitByCap_neverLosesOrDuplicatesItems() {
        val queue = (1..7).map { item("k$it", it * 10L) }
        val (kept, spilled) = DelayedPushLogic.splitByCap(queue, max = 5)
        assertEquals("两堆数量之和必须等于进来时", 7, kept.size + spilled.size)
        assertEquals(
            "既不重复也不漏 —— 漏一条就是历史上多一行永远「发送中」",
            (1..7).map { "k$it" }.toSet(),
            keys(kept + spilled).toSet(),
        )
        assertEquals(
            "同一条不许出现在两堆里（那会被推两遍）",
            kept.size + spilled.size,
            keys(kept + spilled).toSet().size,
        )
    }

    @Test
    fun splitByCap_treatsMissingFireAtAsLatest_notAsExpired() {
        val queue = listOf(item("noFireAt", null), item("soon", 5L))
        val (kept, spilled) = DelayedPushLogic.splitByCap(queue, max = 1)
        assertEquals(listOf("noFireAt"), keys(kept))
        assertEquals(
            "没有 fireAt = 不知道它何时该发，宁可留着也别挤出去消失",
            listOf("soon"),
            keys(spilled),
        )
    }

    @Test
    fun splitByCap_keepsAll_whenCapDisabled() {
        val queue = listOf(item("a", 1L), item("b", 2L))
        for (max in listOf(0, -1)) {
            val (kept, spilled) = DelayedPushLogic.splitByCap(queue, max = max)
            assertEquals("max=$max 是「关掉上限」，不等于清空队列", queue, kept)
            assertTrue("max=$max 时不该有挤出", spilled.isEmpty())
        }
    }
}
