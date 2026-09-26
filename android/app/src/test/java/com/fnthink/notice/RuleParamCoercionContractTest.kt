package com.fnthink.notice

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 原生读规则 params 的口径（T23-B）。
 *
 * `RuleEngine` 用 `optInt("windowSeconds", -1)` / `optBoolean("groupByTitle", false)` 取值，
 * 而这些值可能来自**用户手上编辑过的备份/模板文件** —— `30.0`、`"30"`、`"true"` 都是真实形状。
 * Dart 侧原先写 `v is int`，同一份文件于是变成"界面上没配、设备上却生效"，最坏的一条是
 * 规则编辑页取不到值 ⇒ 输入框是空的 ⇒ 用户打开看一眼再保存，配置被抹掉。
 *
 * 本类**实测**出原生这份读数（不是凭 API 文档的记忆），Dart 侧
 * `test/models/rule_param_contract_test.dart` 用同一张表逐条对齐。
 *
 * ⚠ 覆盖边界：JVM 单测用的是 org.json 参考实现（`testImplementation("org.json:json:…")`），
 * 设备上跑的是 Android libcore 那份。两者对「Number 一律截断」与「"true"/"false" 字符串算布尔」
 * 一致，对「数字当布尔」都不认（都退回默认值）；剩下的未知数是 libcore 是否把 `"30"` 认作 30。
 * Dart 侧按"认"实现 —— 选这个方向是因为两边的失败不对称：读出一个生效值，用户在界面上看得见、
 * 可以再改；读成"没配"，配置会在下一次保存时被静默抹掉。这一条登记为真机待复核。
 */
class RuleParamCoercionContractTest {

    /** 用一个键造一份只含该值的 JSON，避免各用例互相污染。 */
    private fun jsonWith(key: String, value: Any?): JSONObject =
        JSONObject().apply { put(key, value) }

    @Test
    fun numbersAreTruncatedNotRounded() {
        // 截断（Number.intValue() 的语义），不是四舍五入。
        assertEquals(30, jsonWith("windowSeconds", 30).optInt("windowSeconds", -1))
        assertEquals(30, jsonWith("windowSeconds", 30.0).optInt("windowSeconds", -1))
        assertEquals(
            "5.999 必须读成 5（若实现改成 round，这条会红，Dart 侧同步改）",
            5,
            jsonWith("maxItems", 5.999).optInt("maxItems", -1),
        )
        assertEquals(-3, jsonWith("delaySeconds", -3.5).optInt("delaySeconds", -1))
        assertFalse(
            "round 语义的哨兵：5.5 四舍五入会是 6",
            6 == jsonWith("maxItems", 5.5).optInt("maxItems", -1),
        )
    }

    @Test
    fun numericStringsAreCoerced() {
        assertEquals(30, jsonWith("windowSeconds", "30").optInt("windowSeconds", -1))
        assertEquals(
            "实数字符串同样落回整数（截断）",
            5,
            jsonWith("maxItems", "5.7").optInt("maxItems", -1),
        )
    }

    @Test
    fun unusableValuesFallBackToDefault() {
        assertEquals(-1, jsonWith("windowSeconds", "abc").optInt("windowSeconds", -1))
        assertEquals(-1, jsonWith("windowSeconds", true).optInt("windowSeconds", -1))
        assertEquals(
            "键不存在 ⇒ 用调用方给的默认值（这里 60 = 原生 DEFAULT_MERGE_WINDOW 的来源）",
            -1,
            JSONObject().optInt("windowSeconds", -1),
        )
        assertEquals(0, jsonWith("priority", 0).optInt("priority", 60))
    }

    @Test
    fun booleansAcceptTrueFalseStringsAndRejectNumbers() {
        assertTrue(jsonWith("groupByTitle", true).optBoolean("groupByTitle", false))
        assertTrue(jsonWith("groupByTitle", "true").optBoolean("groupByTitle", false))
        assertFalse(jsonWith("groupByTitle", "FALSE").optBoolean("groupByTitle", true))
        // 数字**不**被当成布尔：1/0 都退回默认值。Dart 的 ruleParamBool 同一条。
        assertTrue(jsonWith("groupByTitle", 1).optBoolean("groupByTitle", true))
        assertTrue(jsonWith("groupByTitle", 0).optBoolean("groupByTitle", true))
        assertFalse(jsonWith("groupByTitle", 1).optBoolean("groupByTitle", false))
        assertFalse(
            "键不存在 ⇒ 默认值",
            JSONObject().optBoolean("groupByTitle", false),
        )
        assertTrue(
            "optBoolean(\"enabled\", true)：没有键时是启用（这就是为什么 Dart 侧不许照抄这条默认）",
            JSONObject().optBoolean("enabled", true),
        )
    }
}
