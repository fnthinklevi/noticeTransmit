package com.fnthink.notice

import android.content.Context
import android.util.Log
import java.io.File
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * 「引擎未就绪」那一支的离线队列（T133 量级②的尾巴，与 [HistoryCache] 同一口径）。
 *
 * 来历：`MainActivity.cacheNotificationRecord` 原先把未送达的记录塞在一份
 * SharedPreferences 数组里（键 `flutter.notification_cache/pending_records`），
 * **上限 200、满了丢最旧、每条通知全量重写整根数组** —— 与 T133 量级②拆掉之前的
 * [HistoryCache] 是同一族的两个毛病。队列里躺的是这些记录的唯一副本（原生没有写
 * `notifications` 表的路），"满了丢最旧"就是静默销毁还没交付的历史。
 *
 * 所以这一份的口径与片5 之后的那份完全一致：
 *  - **没有条数上限**。记录的家是数据库，队列只负责"引擎没起来的这段时间别弄丢"；
 *  - 唯一的闸是 [HistoryCache.MAX_QUEUE_BYTES] 那枚**资源**闸（两条队列同一枚常量），
 *    触发的丢弃**并进同一枚溢出计数**（[HistoryCache.noteOverflowDropped]），
 *    照旧经下一次 `drainOfflineCache` 的 `dropped` 从 #94-A 那条横幅报出来 —— 两个口
 *    各报各的，用户就会看到两条互相都说不全的"丢了多少条"；
 *  - 载体是追加式行文件（一行一条，临时件 + rename 换文件），坏行只跳过自己那一行
 *    （复用 [HistoryCache.resolve] 的读盘语义）；
 *  - 升级搬家：旧 SP 数组在任何读写之前一次搬进行文件，**先落文件、再清旧键**
 *    （反过来崩一次就两边都没了；重复 id 由 resolve 就地并掉 ⇒ 这个方向的重试安全）。
 *
 * 与 [HistoryCache] 的分工：那边是"sendBroadcast 之后等 Flutter 批量拉走"的交接队列
 * （drain 分批协议）；这边是"引擎没就绪时逐条 invokeMethod 推过去"的待发队列
 * （[MainActivity.flushCachedNotificationRecords]）。投递失败留在队里这条语义不变。
 */
object PendingRecordCache {
    private const val TAG = "PendingRecordCache"

    private const val LEGACY_PREFS_NAME = "flutter.notification_cache"
    private const val LEGACY_KEY = "pending_records"
    private const val QUEUE_FILE = "notification_pending_queue.jsonl"

    private val lock = ReentrantLock()

    // ── 纯函数（JVM 可测）───────────────────────────────────────────────

    /**
     * 旧 SP 数组 → 行文件的内容。返回 `(要写的行, 是否清旧键)`：
     *  - 键不存在 ⇒ `(null, false)`；
     *  - 解析失败（整串坏掉）⇒ `(null, false)` 并保留原键 —— 与旧 flush 的
     *    「整体解析失败不清空，留待人工排查」同一条语义，搬家不替人销毁证据；
     *  - 解析成功（哪怕空数组）⇒ `(行, true)`：空数组也清，否则每次读写都要白搬一遍。
     */
    internal fun migrateLegacyArray(raw: String?): Pair<List<String>?, Boolean> {
        if (raw == null) return null to false
        val arr = try {
            org.json.JSONArray(raw)
        } catch (e: Exception) {
            Log.w(TAG, "legacy pending_records 解析失败，保留原键待人工排查", e)
            return null to false
        }
        val lines = mutableListOf<String>()
        for (i in 0 until arr.length()) {
            val obj = arr.optJSONObject(i) ?: continue
            lines.add(HistoryCache.recordLine(obj))
        }
        return lines to true
    }

    // ── 磁盘（薄层；语义都在 HistoryCache 的纯函数里）────────────────────

    private fun legacyPrefs(context: Context) =
        context.getSharedPreferences(LEGACY_PREFS_NAME, Context.MODE_PRIVATE)

    private fun queueFile(context: Context): File = File(context.filesDir, QUEUE_FILE)

    /**
     * 一次性搬家。⚠ 次序是「先落文件、再清旧键」，反过来就是丢数据（同
     * [HistoryCache.importLegacyArrayIfNeeded] 那段理由）；重复 id 由 resolve 并掉，
     * 所以"两边各留一份"这个最坏情况是安全的。
     */
    private fun importLegacyIfNeeded(context: Context) {
        val raw = legacyPrefs(context).getString(LEGACY_KEY, null) ?: return
        val (lines, clearKey) = migrateLegacyArray(raw)
        if (lines != null && lines.isNotEmpty()) {
            queueFile(context).appendText(
                lines.joinToString(separator = "\n", postfix = "\n"),
            )
            Log.i(TAG, "Imported ${lines.size} legacy pending records into the queue file")
        }
        if (clearKey) {
            legacyPrefs(context).edit().remove(LEGACY_KEY).commit()
        }
    }

    private fun readLines(context: Context): List<String> {
        val file = queueFile(context)
        if (!file.exists()) return emptyList()
        return try {
            file.readLines()
        } catch (e: Exception) {
            Log.e(TAG, "read queue failed", e)
            emptyList()
        }
    }

    /** 原子换文件：先写临时件再 rename（半截文件会让整条兜底读成空）。 */
    private fun writeLines(context: Context, lines: List<String>) {
        val file = queueFile(context)
        val tmp = File(file.parentFile, "$QUEUE_FILE.tmp")
        tmp.bufferedWriter().use { writer ->
            for (line in lines) {
                writer.write(line)
                writer.newLine()
            }
        }
        if (tmp.renameTo(file)) return
        tmp.copyTo(file, overwrite = true)
        tmp.delete()
    }

    /** 超预算时重解一遍并挤位。丢的条数并进 HistoryCache 那枚共享溢出计数（#94-A 同一条出口）。 */
    private fun compactAndEvict(context: Context) {
        val records = HistoryCache.resolve(readLines(context))
        val (kept, dropped) = HistoryCache.evictToBudget(records, HistoryCache.MAX_QUEUE_BYTES)
        writeLines(context, kept.map { HistoryCache.recordLine(it) })
        HistoryCache.noteOverflowDropped(context, dropped)
        if (dropped > 0) {
            Log.w(TAG, "待发队列超过预算，丢弃最旧 $dropped 条（未交付 Flutter）")
        }
    }

    /** 追加一条入队。同步落盘：即使进程被杀也不丢。 */
    fun append(context: Context, data: org.json.JSONObject) {
        lock.withLock {
            try {
                importLegacyIfNeeded(context)
                queueFile(context).appendText(HistoryCache.recordLine(data) + "\n")
                if (queueFile(context).length() > HistoryCache.MAX_QUEUE_BYTES) {
                    compactAndEvict(context)
                }
            } catch (e: Exception) {
                Log.e(TAG, "append failed", e)
            }
        }
    }

    /** 读全队（解析失败的行只跳过自己那一行）。flush 与将来的读口都走这一条。 */
    fun readAll(context: Context): List<org.json.JSONObject> {
        lock.withLock {
            return try {
                importLegacyIfNeeded(context)
                HistoryCache.resolve(readLines(context))
            } catch (e: Exception) {
                Log.e(TAG, "readAll failed", e)
                emptyList()
            }
        }
    }

    /**
     * flush 收尾：把**已交付**的那些从队里精确排除（按 id），其余原样留下。
     *
     * ⚠ 为什么不是"把 remaining 写回去"：交付循环在锁外进行（invokeMethod 可能很慢），
     * 期间新通知完全可以 append 进队 —— 整表重写会把那条新的连同旧的一起抹掉，
     * 症状是"刚到的通知丢了，而且没有任何日志"。锁内**重读一遍**再按 id 排除，
     * 交付期间入队的记录自然保留；锁让重读与写盘之间不再有缝。
     *
     * 无 id 的记录（正常链路不会出现）排除不了 ⇒ 留在队里、下次 flush 再投一次 ——
     * 与"投递失败留在队里"同一形状，看得见，不静默。
     */
    fun writeBack(context: Context, deliveredIds: Collection<String>) {
        val gone = deliveredIds.filter { it.isNotEmpty() }.toSet()
        lock.withLock {
            try {
                val records = HistoryCache.resolve(readLines(context))
                val kept = records.filter { it.optString("id") !in gone }
                writeLines(context, kept.map { HistoryCache.recordLine(it) })
            } catch (e: Exception) {
                Log.e(TAG, "writeBack failed", e)
            }
        }
    }
}
