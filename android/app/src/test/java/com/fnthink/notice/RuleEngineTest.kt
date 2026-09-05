package com.fnthink.notice

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * RuleEngine.evaluate 双端黄金用例（原生侧）。
 *
 * fixture 与 test/fixtures/rule_engine_golden.json 为同步副本（Flutter 侧由
 * filter_service_golden_test.dart 消费），保证同一 rule+输入 双端匹配结果一致。
 * 修改用例必须同步两份 fixture。
 */
class RuleEngineTest {

    private data class Case(
        val name: String,
        val rule: JSONObject,
        val notification: JSONObject,
        val expected: Boolean,
    )

    private fun loadCases(): List<Case> {
        val stream = javaClass.getResourceAsStream("/rule_engine_golden.json")
            ?: error("缺少测试资源 rule_engine_golden.json，请与 test/fixtures/ 同步")
        val root = JSONObject(stream.bufferedReader().readText())
        val cases = root.getJSONArray("cases")
        return (0 until cases.length()).map { i ->
            val obj = cases.getJSONObject(i)
            Case(
                name = obj.getString("name"),
                rule = obj.getJSONObject("rule"),
                notification = obj.getJSONObject("notification"),
                expected = obj.getBoolean("expected"),
            )
        }
    }

    private fun info(n: JSONObject): NotificationInfo = NotificationInfo(
        id = "n1",
        title = n.optString("title"),
        content = n.optString("content"),
        subText = "",
        packageName = n.optString("packageName"),
        appName = "Test",
        postTime = 0L,
        time = n.optString("time"),
        type = "notification",
        deviceName = "dev",
        priority = n.optInt("priority", 1),
    )

    @Test
    fun goldenCases_matchFlutterFilterService() {
        val cases = loadCases()
        assertEquals("黄金用例数为双端同步的硬约定", 34, cases.size)
        for (c in cases) {
            assertEquals(
                "case: ${c.name}",
                c.expected,
                RuleEngine.evaluate(c.rule, info(c.notification)),
            )
        }
    }
}
