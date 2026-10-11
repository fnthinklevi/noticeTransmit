package com.fnthink.notice

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * 「引擎未就绪」那支待发队列（T133 量级②尾巴）的行为锁（纯 JVM，不碰磁盘）。
 *
 * 它与 [HistoryCache] 同族同口径，那边的行为锁已经钉过 resolve / 挤位 / 预算折算；
 * 这里钉的是这一支**自己**的两件事：
 *  1. 升级搬家的语义 —— 老键里是什么就搬什么（顺序不动）、坏串不清键（留待人工排查）、
 *     空数组也清键（否则每次读写都白搬一遍）；"先落文件再清键"的次序在磁盘层，
 *     源码守卫（本文件下半）钉住它不被人反着写；
 *  2. 源码守卫 —— `cacheNotificationRecord` 必须委托出去、旧的「满 200 丢最旧」
 *     那一行不许长回来：那是这条队列存在史里真正丢过数据的一行。
 */
class PendingRecordCacheTest {

    private fun legacyJson(vararg ids: String): String {
        val arr = org.json.JSONArray()
        for (id in ids) {
            arr.put(
                JSONObject()
                    .put("id", id)
                    .put("title", "标题$id")
                    .put("content", "正文")
                    .put("packageName", "com.example.app")
                    .put("appName", "示例应用")
                    .put("postTime", 1_700_000_000_000L)
                    .put("time", "2026-10-11 10:00:00")
                    .put("type", "normal")
                    .put("deviceName", "本机"),
            )
        }
        return arr.toString()
    }

    private fun ids(lines: List<String>): List<String> =
        HistoryCache.resolve(lines).map { it.getString("id") }

    // ===== 搬家语义（migrateLegacyArray）=====

    @Test
    fun legacyArray_migratesInOrder() {
        val (lines, clearKey) = PendingRecordCache.migrateLegacyArray(
            legacyJson("a", "b", "c"),
        )

        assertTrue("搬完家不清旧键 ⇒ 下一次读写再搬一遍（两边各一份）", clearKey)
        assertEquals("搬家打乱顺序 ⇒ 离线期间的历史时间线是假的", listOf("a", "b", "c"), ids(lines!!))
    }

    @Test
    fun legacyCorruptString_keepsKeyForManualInspection() {
        val (lines, clearKey) = PendingRecordCache.migrateLegacyArray("{不是json")

        assertNull("坏串搬不出行", lines)
        assertFalse(
            "整串坏掉不清键：与旧 flush 的「留待人工排查」同一条语义，搬家不替人销毁证据",
            clearKey,
        )
    }

    @Test
    fun legacyEmptyArray_clearsKey() {
        val (lines, clearKey) = PendingRecordCache.migrateLegacyArray("[]")

        assertEquals(0, lines!!.size)
        assertTrue("空数组不清键 ⇒ 每次读写都要白搬一遍", clearKey)
    }

    @Test
    fun legacyMissingKey_isNoop() {
        val (lines, clearKey) = PendingRecordCache.migrateLegacyArray(null)

        assertNull(lines)
        assertFalse(clearKey)
    }

    @Test
    fun migratedLines_reuseHistoryCacheResolve() {
        // 搬出来的行必须是 HistoryCache 认的那一种行：坏行只跳自己、重复 id 就地并 ——
        // 两条队列共用一套读盘语义，谁也不许自己发明第二种。
        val raw = org.json.JSONArray()
            .put(JSONObject().put("id", "dup").put("title", "第一版"))
            .put(JSONObject().put("id", "dup").put("title", "第二版"))
            .toString()
        val (lines, _) = PendingRecordCache.migrateLegacyArray(raw)

        val kept = HistoryCache.resolve(lines!!)
        assertEquals(1, kept.size)
        assertEquals("第二版", kept.single().getString("title"))
    }

    // ===== 源码守卫：老的那一行不许回来 =====

    private companion object {
        const val SRC = "src/main/kotlin/com/fnthink/notice/"
    }

    private val mainSource: String by lazy {
        stripComments(
            File(SRC + "MainActivity.kt").readText(),
        )
    }
    private val queueSource: String by lazy {
        stripComments(File(SRC + "PendingRecordCache.kt").readText())
    }

    @Test
    fun cacheAndFlushDelegateToPendingRecordCache() {
        val cacheFn = extractFunction(mainSource, "fun cacheNotificationRecord(")
        assertTrue(
            "没找到 cacheNotificationRecord 函数体 —— 守卫本身失效了",
            cacheFn.isNotEmpty(),
        )
        assertTrue(
            "cacheNotificationRecord 必须委托 PendingRecordCache.append（队列的语义只此一份）",
            cacheFn.contains("PendingRecordCache.append"),
        )
        val flushFn = extractFunction(mainSource, "fun flushCachedNotificationRecords(")
        assertTrue(
            "flush 必须读 PendingRecordCache（readAll）并写回（writeBack）—— 自建 SP 数组就是两条读盘语义的开始",
            flushFn.contains("PendingRecordCache.readAll") &&
                flushFn.contains("PendingRecordCache.writeBack"),
        )
    }

    @Test
    fun countBasedCapMustNotComeBack() {
        assertFalse(
            "「满 200 丢最旧」那行是这条队列真正丢过数据的地方 —— 条数闸不许长回来（唯一的闸是字节资源闸）",
            mainSource.contains("arr.length() > 200") || queueSource.contains(Regex("""length\(\)\s*>\s*\d+""")),
        )
        assertTrue(
            "PendingRecordCache 必须用 HistoryCache.MAX_QUEUE_BYTES 当资源闸 —— 另立一枚常量就是第二本预算账",
            queueSource.contains("HistoryCache.MAX_QUEUE_BYTES"),
        )
        assertTrue(
            "挤位丢掉的条数必须并进共享溢出计数（HistoryCache.noteOverflowDropped）—— 两条队列的「丢了 N 条」从同一个口出，各报各的就是两条都说不全",
            extractFunction(queueSource, "private fun compactAndEvict(").contains("HistoryCache.noteOverflowDropped"),
        )
        assertFalse(
            "待发队列不许自带第二套挤位/读盘实现（resolve/evictToBudget 只此一份作者）",
            queueSource.contains("fun resolve(") || queueSource.contains("fun evictToBudget("),
        )
    }

    @Test
    fun legacyImportOrderIsFileFirstThenKey() {
        val importFn = extractFunction(queueSource, "private fun importLegacyIfNeeded(")
        assertTrue(
            "没找到 importLegacyIfNeeded —— 搬家入口没了",
            importFn.isNotEmpty(),
        )
        val appendAt = importFn.indexOf("appendText(")
        val removeAt = importFn.indexOf(".remove(LEGACY_KEY)")
        assertTrue(
            "搬家必须先落文件（appendText）再清旧键（remove）—— 反过来崩一次就两边都没了",
            appendAt in 0 until removeAt,
        )
    }

    private fun stripComments(src: String): String =
        src.replace(Regex("/\\*.*?\\*/", RegexOption.DOT_MATCHES_ALL), "")
            .replace(Regex("//.*"), "")

    /** 取 `fun 名字(` 起到下一个顶级 `fun `/对象结尾的近似函数体（守卫用，不必完美）。 */
    private fun extractFunction(src: String, signature: String): String {
        val start = src.indexOf(signature)
        if (start < 0) return ""
        val next = src.indexOf("\n    fun ", start + 1).let {
            if (it < 0) src.indexOf("\n    internal fun ", start + 1) else it
        }
        val nextPrivate = src.indexOf("\n    private fun ", start + 1)
        val candidates = listOf(next, nextPrivate).filter { it > start }
        val end = candidates.minOrNull() ?: src.length
        return src.substring(start, end)
    }
}
