package com.fnthink.notice

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `HistoryCache` 的行为锁（纯 JVM，不碰磁盘）。
 *
 * 触发原因（#94）：离线缓存在超过 500 条时**静默丢最旧**，而此前 `HistoryCache` 只有源码契约
 * （`MergeFailureContractTest` 读文本），"去重 / 顺序 / 裁剪"这三件真正决定
 * "用户会不会少收到一条推送历史"的行为没有任何用例钉着。
 *
 * 测的是抽出来的纯函数 [HistoryCache.mergeIntoArray] / [HistoryCache.parseArray] ——
 * SharedPreferences 与 commit 仍留在 `append` 里（JVM 里不伪造 Context，那是 Robolectric 的活）。
 */
class HistoryCacheTest {

    private fun rec(
        id: String,
        title: String = "标题",
        content: String = "正文",
    ) = JSONObject().apply {
        put("id", id)
        put("title", title)
        put("content", content)
        put("packageName", "com.example.app")
        put("appName", "示例应用")
        put("postTime", 1_700_000_000_000L)
        put("time", "2026-09-26 19:00:00")
        put("type", "normal")
        put("deviceName", "MEIZU 21")
    }

    private fun ids(arr: JSONArray): List<String> =
        (0 until arr.length()).map { arr.getJSONObject(it).getString("id") }

    // ===== 去重：同 id 必须就地更新，不许追加成两条 =====

    @Test
    fun sameId_updatesInPlace_notAppended() {
        val arr = JSONArray()
        HistoryCache.mergeIntoArray(arr, rec("a", title = "第一版"), maxRecords = 500)
        HistoryCache.mergeIntoArray(arr, rec("a", title = "第二版"), maxRecords = 500)

        assertEquals("同 id 追加成两条 ⇒ 历史页会看见重复记录", 1, arr.length())
        assertEquals("a", ids(arr).single())
        assertEquals(
            "就地更新没生效（还是旧内容）⇒ Flutter 上线后拉到的是过期的一条",
            "第二版",
            arr.getJSONObject(0).getString("title"),
        )
    }

    @Test
    fun sameId_keepsOriginalPosition() {
        val arr = JSONArray()
        listOf("a", "b", "c").forEach { HistoryCache.mergeIntoArray(arr, rec(it), maxRecords = 500) }
        HistoryCache.mergeIntoArray(arr, rec("a", title = "又更新"), maxRecords = 500)

        // 顺序 = 到达顺序：把更新的这条挪到尾部，等于把离线期间的时序打乱
        assertEquals(listOf("a", "b", "c"), ids(arr))
    }

    @Test
    fun emptyId_isNeverDeduped() {
        val arr = JSONArray()
        val noId = JSONObject().put("id", "").put("title", "无 id 的通知")
        HistoryCache.mergeIntoArray(arr, noId, maxRecords = 500)
        HistoryCache.mergeIntoArray(arr, noId, maxRecords = 500)

        // 无 id（原生没给）时按 id 去重会把两条不同的通知并成一条 ⇒ 真丢内容
        assertEquals(2, arr.length())
    }

    // ===== 裁剪：丢的特别必须是"最旧"，且丢多少要说得出来 =====

    @Test
    fun overCap_dropsOldestAndKeepsArrivalOrder() {
        val arr = JSONArray()
        var dropped = 0
        listOf("a", "b", "c", "d", "e").forEach {
            dropped += HistoryCache.mergeIntoArray(arr, rec(it), maxRecords = 3)
        }

        assertEquals("裁剪方向错了：留下的不是最新的三条", listOf("c", "d", "e"), ids(arr))
        assertEquals(2, dropped)
    }

    @Test
    fun exactlyAtCap_dropsNothing() {
        val arr = JSONArray()
        var dropped = 0
        listOf("a", "b", "c").forEach {
            dropped += HistoryCache.mergeIntoArray(arr, rec(it), maxRecords = 3)
        }
        assertEquals("刚好到上限就丢 ⇒ 边界写成 >= 了，会少留一条", 0, dropped)
        assertEquals(3, arr.length())
    }

    @Test
    fun sameIdUpdateAtCap_doesNotEvictAnything() {
        val arr = JSONArray()
        listOf("a", "b", "c").forEach { HistoryCache.mergeIntoArray(arr, rec(it), maxRecords = 3) }
        val dropped = HistoryCache.mergeIntoArray(arr, rec("b", title = "更新"), maxRecords = 3)

        // 更新一条已有记录不该触发淘汰 —— 那是"改一下就把最旧的踢掉"
        assertEquals(0, dropped)
        assertEquals(listOf("a", "b", "c"), ids(arr))
    }

    // ===== 读盘退化：坏 JSON 不许抛（抛在这里 = 离线兜底整个失效）=====

    @Test
    fun corruptStoredJson_degradesToEmptyArray() {
        for (raw in listOf("not json", "", "{不是数组", "[1,2", "null")) {
            val arr = HistoryCache.parseArray(raw)
            assertTrue("坏载荷 $raw 应退化成空数组", arr.length() == 0)
        }
        assertEquals(0, HistoryCache.parseArray(null).length())
    }

    // ===== 满仓体积：#94 三个方向共同需要的量（不是凭感觉决定）=====

    @Test
    fun fullCachePayloadSize_isMeasurable() {
        val arr = JSONArray()
        repeat(500) { HistoryCache.mergeIntoArray(arr, rec("id-$it", content = "正文".repeat(20)), maxRecords = 500) }
        val bytes = arr.toString().toByteArray(Charsets.UTF_8).size

        // 实测（2026-09-26 JVM）：500 条 ×（正文 60 汉字 + 8 个字段）= **158,391 字节 ≈ 每条 317 字节**。
        // 这条断言只钉量级（不是精确值 —— 精确值随字段长度浮动，钉死它只会让人改文案时来拆测试）：
        // 满仓的那根 String 是 **100KB 级、不是 MB 级** ⇒ `#94` 的代价重心在"每条通知都全量重写 +
        // 同步 commit 一整份"，而不在"缓存把存储吃了"。三个候选方向都按这个量级重估。
        assertTrue(
            "满仓体积 $bytes 字节不在 50KB–1MB 区间 ⇒ 载荷形状变了，#94 的成本估算要重来",
            bytes in 50_000..1_000_000,
        )
    }
}
