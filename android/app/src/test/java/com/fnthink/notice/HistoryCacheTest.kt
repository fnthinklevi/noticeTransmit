package com.fnthink.notice

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 离线交接队列的行为锁（纯 JVM，不碰磁盘）。
 *
 * 触发原因（#94）：这条队列曾经**静默丢最旧**，而当时 `HistoryCache` 只有源码契约
 * （`MergeFailureContractTest` 读文本），"去重 / 顺序 / 裁剪"这三件真正决定
 * "用户会不会少收到一条推送历史"的行为没有任何用例钉着。
 *
 * T133 量级②之后：按**条数**裁的那道闸没了（记录的家是数据库），剩下的形状是
 * 「一行一条 + 墓碑 + 按字节挤位」。所以这里钉的是这三件事：
 *  1. 读盘语义 —— 同 id 就地更新且保留原位置、墓碑只杀它之前那条、无 id 永不参与去重、坏行只跳过自己；
 *  2. 挤位方向与计数 —— 丢的必须是最旧的，且丢多少要说得出来（那条横幅据此生成）；
 *  3. 预算是不是**资源**闸 —— 按实测的每条字节数折算，它必须对应几千条以上；
 *     若哪天折算出"预算只够装几百条"，那它就已重新变成一道存储闸，这条用例当场红。
 *
 * 测的是抽出来的纯函数 —— 文件与 SharedPreferences 仍留在 `append`/`drainAll` 里
 * （JVM 里不伪造 Context，那是 Robolectric 的活）。
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

    private fun linesOf(vararg records: JSONObject): List<String> = records.map { HistoryCache.recordLine(it) }

    private fun ids(records: List<JSONObject>): List<String> = records.map { it.getString("id") }

    // ===== 去重与墓碑：读盘语义 =====

    @Test
    fun sameId_updatesInPlace_notAppended() {
        val kept = HistoryCache.resolve(
            linesOf(rec("a", title = "第一版"), rec("a", title = "第二版")),
        )

        assertEquals("同 id 变成两条 ⇒ 历史页会看见重复记录", 1, kept.size)
        assertEquals("a", ids(kept).single())
        assertEquals(
            "就地更新没生效（还是旧内容）⇒ Flutter 上线后拉到的是过期的一条",
            "第二版",
            kept[0].getString("title"),
        )
    }

    @Test
    fun sameId_keepsOriginalPosition() {
        val kept = HistoryCache.resolve(
            linesOf(rec("a"), rec("b"), rec("c"), rec("a", title = "又更新")),
        )

        // 顺序 = 到达顺序：把更新的这条挪到尾部，等于把离线期间的时序打乱
        assertEquals(listOf("a", "b", "c"), ids(kept))
        assertEquals("又更新", kept[0].getString("title"))
    }

    @Test
    fun emptyId_isNeverDeduped() {
        val noId = JSONObject().put("id", "").put("title", "无 id 的通知")
        val kept = HistoryCache.resolve(linesOf(noId, noId))

        // 无 id（原生没给）时按 id 去重会把两条不同的通知并成一条 ⇒ 真丢内容
        assertEquals(2, kept.size)
    }

    @Test
    fun tombstone_killsOnlyThatRecordAndKeepsOrder() {
        val kept = HistoryCache.resolve(
            linesOf(rec("a"), rec("b"), rec("c")) + HistoryCache.tombstoneLine("b") + linesOf(rec("d")),
        )

        assertEquals("墓碑没生效或多杀了别条", listOf("a", "c", "d"), ids(kept))
    }

    @Test
    fun tombstone_doesNotKillALaterRecordWithTheSameId() {
        // 交接确认（墓碑）之后同 id 再来一条，是**新一次**通知：它没被交接过，必须留在队里
        val kept = HistoryCache.resolve(
            linesOf(rec("a", title = "旧的"), rec("b")) +
                HistoryCache.tombstoneLine("a") +
                linesOf(rec("a", title = "新的")),
        )

        assertEquals(listOf("b", "a"), ids(kept))
        assertEquals("新的", kept[1].getString("title"))
    }

    @Test
    fun corruptLine_skipsItselfNotTheRestOfTheQueue() {
        val kept = HistoryCache.resolve(
            listOf(
                HistoryCache.recordLine(rec("a")),
                "not json",
                "",
                "{不是对象",
                "[1,2",
                "null",
                HistoryCache.recordLine(rec("b")),
            ),
        )

        // 旧写法是整根数组退化成一个空数组：一行坏字节让整条离线兜底失效。
        // 行文件必须只丢掉那一行 —— 这一条是载体换形的**理由**，不只是副产品。
        assertEquals(listOf("a", "b"), ids(kept))
    }

    @Test
    fun recordLine_neverContainsANewline() {
        val line = HistoryCache.recordLine(rec("a", content = "第一行\n第二行\r\n尾"))
        assertTrue("载荷里的换行没被转义 ⇒ 一条记录占两行，读回来就是两条坏行", !line.contains('\n'))
    }

    // ===== 挤位：按字节，丢的必须是最旧，且丢多少要说得出来 =====

    @Test
    fun overBudget_dropsOldestAndKeepsArrivalOrder() {
        val records = listOf("a", "b", "c", "d", "e").map { rec(it) }
        // 预算正好等于「最后三条」的字节数：挤位到刚好放下为止
        val budget = records.takeLast(3).sumOf { HistoryCache.lineBytes(it) }
        val (kept, dropped) = HistoryCache.evictToBudget(records, budget)

        assertEquals("挤位方向错了：留下的不是最新的三条", listOf("c", "d", "e"), ids(kept))
        assertEquals(2, dropped)
    }

    @Test
    fun exactlyAtBudget_dropsNothing() {
        val records = listOf("a", "b", "c").map { rec(it) }
        val (kept, dropped) = HistoryCache.evictToBudget(records, records.sumOf { HistoryCache.lineBytes(it) })

        assertEquals("刚好到预算就丢 ⇒ 边界写成 >= 了，会少留一条", 0, dropped)
        assertEquals(3, kept.size)
    }

    @Test
    fun inPlaceUpdateAtBudget_doesNotEvictAnything() {
        val records = listOf("a", "b", "c").map { rec(it) }
        val lines = records.map { HistoryCache.recordLine(it) }.toMutableList()
        // 更新一条已有记录不该触发挤位 —— 那是"改一下就把最旧的踢掉"
        lines[1] = HistoryCache.recordLine(rec("b", title = "更新", content = "正文".repeat(200)))
        val resolved = HistoryCache.resolve(lines)
        val (kept, dropped) = HistoryCache.evictToBudget(resolved, 5_000)

        assertEquals(3, kept.size)
        assertEquals(0, dropped)
        assertEquals(listOf("a", "b", "c"), ids(kept))
    }

    @Test
    fun emptyQueue_evictsNothingAndDropsNothing() {
        val (kept, dropped) = HistoryCache.evictToBudget(emptyList(), 1)
        assertEquals(0, kept.size)
        assertEquals("空队列被算成丢了几条", 0, dropped)
    }

    // ===== 旧载体（升级）：坏 JSON / 缺键一律退化成空数组，不许抛 =====

    @Test
    fun corruptStoredJson_degradesToEmptyArray() {
        for (raw in listOf("not json", "", "{不是数组", "[1,2", "null")) {
            val arr = HistoryCache.parseArray(raw)
            assertTrue("坏载荷 $raw 应退化成空数组", arr.length() == 0)
        }
        assertEquals(0, HistoryCache.parseArray(null).length())
    }

    @Test
    fun legacyArray_stillParsesRecordsForTheOneTimeImport() {
        val arr = JSONArray()
        arr.put(rec("a"))
        arr.put(rec("b"))
        val parsed = HistoryCache.parseArray(arr.toString())
        assertEquals("旧载体读不回来 ⇒ 升级那批还没交接的记录凭空蒸发", 2, parsed.length())
        assertEquals("a", parsed.getJSONObject(0).getString("id"))
    }

    // ===== 预算的口径：它得真的是资源闸，不是换了个写法的存储闸 =====

    @Test
    fun fullQueuePayloadSize_isMeasuredAndBudgetIsResourceSized() {
        val arr = JSONArray()
        repeat(500) {
            arr.put(rec("id-$it", content = "正文".repeat(20)))
        }
        val bytes = arr.toString().toByteArray(Charsets.UTF_8).size
        val perRecord = bytes / 500

        // 实测（2026-09-26 JVM，2026-10-11 复核）：500 条 ×（正文 60 汉字 + 8 个字段）≈ 158KB
        // ⇒ 每条 ≈317 字节。这条断言只钉量级（不是精确值 —— 精确值随字段长度浮动）。
        assertTrue(
            "满仓体积 $bytes 字节不在 50KB–1MB 区间 ⇒ 载荷形状变了，预算的折算要重来",
            bytes in 50_000..1_000_000,
        )
        assertTrue("单条字节数 $perRecord 不在 100–2000 区间 ⇒ 折算出的容量不可信", perRecord in 100..2_000)

        // ⚠ 这一条是"那道 500 不是被换成另一个数字"的证据：预算折算出的容量必须远在几百条之上。
        // 若哪天载荷涨到只装得下一两千条，它就已重新变成存储闸 —— 当场红，而不是等用户发现历史少了。
        val implied = HistoryCache.MAX_QUEUE_BYTES / perRecord
        assertTrue(
            "预算折算只够 $implied 条 ⇒ MAX_QUEUE_BYTES 已退化成一道存储闸（T133 量级②禁止的形状）",
            implied >= 5_000,
        )
    }

    @Test
    fun drainBatchSizeIsNotAStorageGate() {
        // 一批交付多少条是**载荷形状**的上限（MethodChannel 一次回一整份会卡），与"保留多少条"无关。
        // 两者一旦混用，"批大小"就会重新变成当年那道 500 —— 所以这里按实测的单条字节数折算出
        // 队列真正装得下多少条，再要求一批不超过它的十分之一。
        val perRecord = HistoryCache.lineBytes(rec("id-x", content = "正文".repeat(20)))
        val capacity = HistoryCache.MAX_QUEUE_BYTES / perRecord

        assertTrue(
            "单条 $perRecord 字节折算出队列容量 $capacity 条，一批 ${HistoryCache.DEFAULT_DRAIN_LIMIT} 条" +
                "已经不止它的十分之一 ⇒ 批大小在事实上又变成了存储上限",
            HistoryCache.DEFAULT_DRAIN_LIMIT * 10 <= capacity,
        )
    }
}
