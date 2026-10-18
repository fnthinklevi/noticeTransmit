package com.fnthink.notice

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test

/**
 * 聚合组「成员达上限」的纯算术测试（[MergePushLogic]，无 Android 依赖）。
 *
 * T150 片2 之前这一步是在 `append` 里就地摘掉 index 0 然后继续走 —— 摘掉的那条**没人再管**：
 * 它早已写进推送历史、送达列停在初值 `pending`，而它不会随聚合发出去，于是那一行永远说
 * 「发送中」。现在这一步必须把被摘的那条交回调用方（`AppendResult.droppedMembers`），
 * 由 Service 逐条回传"未随聚合发出"。这里钉的是交回的形状：摘谁、剩谁、新增谁。
 */
class MergePushMemberCapTest {

    private fun itemsOf(vararg titles: String): JSONArray {
        val arr = JSONArray()
        for (t in titles) arr.put(JSONObject().put("title", t))
        return arr
    }

    private fun titlesOf(arr: JSONArray): List<String> =
        (0 until arr.length()).map { arr.getJSONObject(it).optString("title") }

    @Test
    fun memberGroupId_isTheOneShapeHistoryRowsRead() {
        assertEquals("com.a:merge:123", MergePushLogic.memberGroupId("com.a", 123))
        assertEquals(
            "groupByTitle 的 key 里可以有竖线，组 id 仍是 key + 固定尾段",
            "com.a|张三:merge:456",
            MergePushLogic.memberGroupId("com.a|张三", 456),
        )
    }

    @Test
    fun appendMember_appendsAndReturnsNoDropped_whenBelowCap() {
        val items = itemsOf("a", "b")
        val (next, dropped) = MergePushLogic.appendMember(items, JSONObject().put("title", "c"), max = 5)
        assertEquals("未达上限 ⇒ 顺序照旧追加在末尾", listOf("a", "b", "c"), titlesOf(next))
        assertNull("未达上限不该摘掉任何成员", dropped)
    }

    @Test
    fun appendMember_dropsOldest_andKeepsLength() {
        val items = itemsOf("a", "b", "c")
        val fresh = JSONObject().put("title", "d")
        val (next, dropped) = MergePushLogic.appendMember(items, fresh, max = 3)
        assertEquals("摘的是 index 0（最旧那条）", "a", dropped?.optString("title"))
        assertSame("交回的必须是输入里那条本体，不是复制品", items.getJSONObject(0), dropped)
        assertEquals("剩下的 + 新来的，长度仍受上限约束", listOf("b", "c", "d"), titlesOf(next))
    }

    @Test
    fun appendMember_dropsNothing_whenCapDisabled() {
        val items = itemsOf("a", "b")
        for (max in listOf(0, -1)) {
            val (next, dropped) = MergePushLogic.appendMember(items, JSONObject().put("title", "c"), max = max)
            assertNull("max=$max 是「关掉上限」，不该摘掉任何成员", dropped)
            assertEquals(listOf("a", "b", "c"), titlesOf(next))
        }
    }

    @Test
    fun appendMember_doesNotMutateInput() {
        // 纯算术的底线：不改调用方传进来的那个数组。旧写法在"未超限"分支里
        // `items.put(...)` 就地改了它，而 `existing` 还握着同一个对象 —— 同一份队列状态
        // 被两条路径以不同方式写过，重排或复用时就是隐形串味。
        val items = itemsOf("a", "b", "c")
        MergePushLogic.appendMember(items, JSONObject().put("title", "d"), max = 3)
        assertEquals("输入数组必须一字不动", listOf("a", "b", "c"), titlesOf(items))
    }
}
