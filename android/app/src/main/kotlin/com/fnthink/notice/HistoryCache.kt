package com.fnthink.notice

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.locks.ReentrantLock

/**
 * 离线通知**交接队列**（不是历史存储）
 *
 * 解决问题：Flutter 引擎被杀或 MainActivity 销毁后，sendBroadcast 投递失败导致推送历史丢失。
 *
 * 工作机制：
 * - WebhookSender.sendBroadcast 之后，同步调用 [append] 入队
 * - Flutter 在线时，MainActivity.notificationReceiver 成功 invokeMethod 后调用 [remove]
 * - Flutter 启动时通过 MethodChannel 调用 [drainAll]，**按批**拉走已交接的部分
 *
 * ⚠ 关于上限（T133 量级②，2026-10-11）：这里原来有一道 `MAX_RECORDS = 500`。它名义上是队列的
 * 容量，实际上是一道**存储闸** —— 队里留下的全是「还没交给 Flutter」的记录，也就是那些记录的
 * **唯一副本**，满了丢最旧 = 静默销毁还没落库的历史。记录的家是数据库，而数据库不设上限（T133①）。
 * 现在剩下的只有 [MAX_QUEUE_BYTES] 这一枚**资源**闸门（磁盘），它触发的丢弃照旧计数、照旧经
 * [OfflineDrain.dropped] 交给 Flutter 报给用户（#94-A），不再是一个没人知道的数。
 *
 * ⚠ 为什么不是「原生直接写数据库」：生产库是 `sqflite_sqlcipher` 建的加密库
 * （`notice_transmit_encrypted.db`，口令在 `SecureStorageService`），`android.database.sqlite`
 * 打不开它；就算打得开，那也是同一张 `notifications` 表的第二个写入者（T20 那条纪律）。
 * 所以"塞进数据库"这一发能做的、也只剩做的是：**别让队列替数据库行使存储上限**。
 *
 * 载体从"SharedPreferences 里的一整根 JSON 数组"换成**追加式行文件**：一条记录一行，入队是
 * append（不再每条通知都全量重写 + 同步 commit 一整份 —— 那正是 500 条这条上限当初显得"不得不有"
 * 的理由）。确认送达写一行墓碑，攒够了再压实一次。
 *
 * 与 MainActivity.cacheNotificationRecord 兜底机制并存（互不干扰，使用不同载体）。
 */
object HistoryCache {
    private const val TAG = "HistoryCache"

    /** 只剩计数与「旧载体」的迁移源；记录本体不住这里了。 */
    private const val PREFS_NAME = "notification_offline_cache"

    private const val KEY_RECORDS = "records"
    private const val KEY_DROPPED = "dropped_total"
    private const val KEY_LIVE = "live_lines"
    private const val KEY_TOMBSTONES = "tombstone_lines"

    private const val QUEUE_FILE = "notification_offline_queue.jsonl"

    /** 墓碑行的键名：与通知载荷同形（一行一个 JSON 对象），所以它必须是一个不会撞上的键。 */
    internal const val TOMBSTONE_KEY = "tombstone"

    /**
     * 资源闸门，不是容量闸门。按 [HistoryCacheTest] 实测的每条 ≈317 字节折算，4 MB ≈ 一万三千条
     * 尚未交接的记录 —— 那个量级上「满了」意味着软件几个月没打开，而不是"历史页存不下"。
     */
    internal const val MAX_QUEUE_BYTES = 4 * 1024 * 1024

    /** 一次 MethodChannel 交付多少条 —— 载荷形状的上限，与保留多少条无关。 */
    internal const val DEFAULT_DRAIN_LIMIT = 500

    private val lock = ReentrantLock()

    // ── 纯函数：队列的语义全在这里，磁盘只在下面那几个 fun 里 ──────────────

    /** 一行 = 一个 JSON 对象。载荷里的换行在 `toString()` 里已被转义，所以"一行一条"成立。 */
    internal fun recordLine(data: JSONObject): String = data.toString()

    internal fun tombstoneLine(id: String): String =
        JSONObject().put(TOMBSTONE_KEY, id).toString()

    /** 坏行退化成 null 并跳过 —— 抛在这里等于整条离线兜底失效，也等于一次坏字节让后面所有行读不到。 */
    internal fun parseLine(raw: String?): JSONObject? {
        val text = raw?.trim() ?: return null
        if (text.isEmpty()) return null
        return try {
            JSONObject(text)
        } catch (_: Exception) {
            null
        }
    }

    /**
     * 行序列 → 在案记录。规则（与旧的 `mergeIntoArray` 逐条对齐，只是不再按条数裁）：
     *  - 同 id 就地更新并**保留原位置**：把更新的那条挪到尾部，等于把离线期间的时序打乱；
     *  - 墓碑行杀掉它**之前**同 id 的那条（此后再来同 id 是新通知，照旧留）；
     *  - 无 id 的记录不参与去重 —— 按 id 去重会把两条不同的通知并成一条，那是真丢内容。
     */
    internal fun resolve(lines: List<String>): List<JSONObject> {
        val out = mutableListOf<JSONObject>()
        val liveIndex = mutableMapOf<String, Int>()
        val dead = mutableSetOf<Int>()
        for (raw in lines) {
            val obj = parseLine(raw) ?: continue
            val tombstone = obj.opt(TOMBSTONE_KEY)
            if (tombstone != null) {
                val id = tombstone.toString()
                val index = if (id.isEmpty()) null else liveIndex.remove(id)
                if (index != null) dead.add(index)
                continue
            }
            val id = obj.optString("id", "")
            if (id.isEmpty()) {
                out.add(obj)
                continue
            }
            val existing = liveIndex[id]
            if (existing != null && existing !in dead) {
                out[existing] = obj
            } else {
                liveIndex[id] = out.size
                out.add(obj)
            }
        }
        return out.filterIndexed { index, _ -> index !in dead }
    }

    /** 一行的字节数（含行尾换行 —— 与文件里真正占的地方一致）。 */
    internal fun lineBytes(obj: JSONObject): Int =
        obj.toString().toByteArray(Charsets.UTF_8).size + 1

    /**
     * 按**字节**预算从头部挤位：丢的必须是最旧的，且丢多少要说得出来。
     *
     * 返回 Pair(留下的, 丢掉的条数)。留下的按原顺序；一条都放不下时全部丢掉（调用处照旧计数并
     * 打日志 —— 单条就撑爆预算的载荷属于坏数据，留着它只会让每次入队都重写整个文件）。
     */
    internal fun evictToBudget(records: List<JSONObject>, maxBytes: Int): Pair<List<JSONObject>, Int> {
        val sizes = records.map { lineBytes(it) }
        var total = sizes.sum()
        var dropped = 0
        while (total > maxBytes && dropped < sizes.size) {
            total -= sizes[dropped]
            dropped++
        }
        return if (dropped == 0) {
            records to 0
        } else {
            records.subList(dropped, records.size).toList() to dropped
        }
    }

    /** 读旧载体（SharedPreferences 里那根数组）；坏 JSON / 缺键一律退化成空数组。 */
    internal fun parseArray(raw: String?): JSONArray = try {
        JSONArray(raw ?: "[]")
    } catch (_: Exception) {
        JSONArray()
    }

    // ── 磁盘 ─────────────────────────────────────────────────────────────

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun queueFile(context: Context): File = File(context.filesDir, QUEUE_FILE)

    /**
     * 一次性搬家：升级前那根躺在 SharedPreferences 里的数组。
     *
     * 必须在**任何**读写队列之前发生：不搬，老用户离线期间那批"还没交接"的记录就凭空蒸发，
     * 而它们正是这个队列存在的全部理由。
     *
     * ⚠ 次序是「先落文件、再清旧键」，反过来就是丢数据：清键之后崩在落盘前面，那批记录两边都没了。
     * 先落文件最坏是两边各留一份，而重复的 id 由 [resolve] 并成一条（就地更新、保留原位置）——
     * 所以这一个方向的重试是安全的，另一个方向不是。
     */
    private fun importLegacyArrayIfNeeded(context: Context, prefs: SharedPreferences) {
        val raw = prefs.getString(KEY_RECORDS, null) ?: return
        val arr = parseArray(raw)
        val lines = mutableListOf<String>()
        for (i in 0 until arr.length()) {
            val obj = arr.optJSONObject(i) ?: continue
            lines.add(recordLine(obj))
        }
        val editor = prefs.edit()
        if (lines.isNotEmpty()) {
            queueFile(context).appendText(lines.joinToString(separator = "\n", postfix = "\n"))
            editor.putInt(KEY_LIVE, prefs.getInt(KEY_LIVE, 0) + lines.size)
            Log.i(TAG, "Imported ${lines.size} legacy cached records into the queue file")
        }
        // 计数与清键同一笔：分成两次就会出现"旧键清了、条数没加"——压实那一句据此决定要不要动文件
        editor.remove(KEY_RECORDS).commit()
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

    /** 原子换文件：先写临时文件，再 rename 覆盖。中途被杀留下的是上一份完整队列，不是半截文件。 */
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
        // rename 失败（跨文件系统 / 厂商定制）时退化成"拷过去再删临时件"，顺序不能反
        tmp.copyTo(file, overwrite = true)
        tmp.delete()
    }

    /**
     * 重解一遍队列并按资源预算挤位，然后落盘。返回本次丢掉的条数。
     *
     * 压实与挤位是同一次写盘：分开写就会出现"墓碑清了、字节还在超"或反之的那种半状态。
     *
     * ⚠ 计数那一笔必须 `commit()`（同步）。旧写法把「数组 + 溢出计数」装在同一个 `commit()` 里，
     * 换行文件之后两者不在一个载体了，只能把这唯一一笔跨载体的写钉成同步：计数丢了不要紧，
     * 丢的是"有 N 条没交接出去"这件事本身 —— 那正是 #94-A 那条横幅存在的全部理由。
     * （残余窗口：文件已换、计数未落 —— 那条最坏结果是少报一次，不是静默多丢。）
     */
    private fun compactAndEvict(context: Context, prefs: SharedPreferences): Int {
        val records = resolve(readLines(context))
        val (kept, dropped) = evictToBudget(records, MAX_QUEUE_BYTES)
        writeLines(context, kept.map { recordLine(it) })
        prefs.edit()
            .putInt(KEY_LIVE, kept.size)
            .putInt(KEY_TOMBSTONES, 0)
            .putInt(KEY_DROPPED, prefs.getInt(KEY_DROPPED, 0) + dropped)
            .commit()
        if (dropped > 0) {
            Log.w(TAG, "离线队列超过 ${MAX_QUEUE_BYTES / 1024 / 1024}MB，丢弃最旧 $dropped 条（未送达 Flutter）")
        }
        return dropped
    }

    /**
     * 追加一条入队。同步落盘，确保即使进程被杀也不丢。
     */
    fun append(context: Context, data: JSONObject) {
        lock.lock()
        try {
            val prefs = prefs(context)
            importLegacyArrayIfNeeded(context, prefs)
            queueFile(context).appendText(recordLine(data) + "\n")
            prefs.edit().putInt(KEY_LIVE, prefs.getInt(KEY_LIVE, 0) + 1).apply()
            if (queueFile(context).length() > MAX_QUEUE_BYTES) {
                compactAndEvict(context, prefs)
            } else if (prefs.getInt(KEY_TOMBSTONES, 0) >= prefs.getInt(KEY_LIVE, 0)) {
                // 墓碑不比在案的少 ⇒ 文件里一半以上是废行，顺手压实一次（不挤位）
                compactAndEvict(context, prefs)
            }
        } catch (e: Exception) {
            Log.e(TAG, "append failed", e)
        } finally {
            lock.unlock()
        }
    }

    /**
     * 记一笔"Flutter 已收到"：追加一行墓碑，不动已有行。
     *
     * 为什么不是原地删：原地删等于每条成功交接都要全量重写整份队列 —— 那正是旧载体把每条通知
     * 都写成 O(n) 的地方。墓碑是 O(1)，攒够了由 [append] 或 [drainAll] 压实。
     */
    fun remove(context: Context, id: String) {
        if (id.isEmpty()) return
        lock.lock()
        try {
            val prefs = prefs(context)
            importLegacyArrayIfNeeded(context, prefs)
            queueFile(context).appendText(tombstoneLine(id) + "\n")
            prefs.edit().putInt(KEY_TOMBSTONES, prefs.getInt(KEY_TOMBSTONES, 0) + 1).apply()
        } catch (e: Exception) {
            Log.e(TAG, "remove failed", e)
        } finally {
            lock.unlock()
        }
    }

    /**
     * 按批拉走已交接的记录：取最旧的 [limit] 条，**剩下的留在队里**（下次再拉）。
     *
     * ⚠ 这里改的不只是批大小。旧写法一次拉完并清空 ⇒ 一次交付的载荷大小、以及"清空之后、入库
     * 之前进程被杀"的丢失面都随队列长度线性增长。现在拉走的只是一批，未交付的那部分根本不会被
     * 清掉，所以队列不设条数上限也不会有一次交付打满内存。
     *
     * 溢出计数与第一批**一起交付**（分开读会漏计）；两个键必须一起清：记录清了而计数没清，
     * 下次启动就会把同一批"丢了 N 条"再报一遍。
     */
    fun drainAll(
        context: Context,
        limit: Int = DEFAULT_DRAIN_LIMIT,
    ): OfflineDrain {
        lock.lock()
        try {
            val prefs = prefs(context)
            importLegacyArrayIfNeeded(context, prefs)
            val records = resolve(readLines(context))
            val take = if (limit <= 0) records else records.take(limit)
            val truncated = take.size < records.size
            val dropped = prefs.getInt(KEY_DROPPED, 0)
            val remaining = records.subList(take.size, records.size).map { recordLine(it) }
            writeLines(context, remaining)
            prefs.edit()
                .putInt(KEY_LIVE, remaining.size)
                .putInt(KEY_TOMBSTONES, 0)
                .remove(KEY_DROPPED)
                .commit()
            Log.i(TAG, "Drained ${take.size} cached records, remaining=${remaining.size}, dropped=$dropped")
            return OfflineDrain(take.map { it.toMap() }, dropped, truncated)
        } catch (e: Exception) {
            Log.e(TAG, "drainAll failed", e)
            return OfflineDrain(emptyList(), 0, false)
        } finally {
            lock.unlock()
        }
    }

    private fun JSONObject.toMap(): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>()
        val keys = keys()
        while (keys.hasNext()) {
            val k = keys.next()
            map[k] = get(k)
        }
        return map
    }
}

/**
 * [HistoryCache.drainAll] 的一次交付：本批记录 + 此前累计因资源预算而丢弃的条数（#94-A）
 * + 队列里还有没有（截断标记）。
 *
 * 为什么不新开一个"读丢弃数"的方法：那样要么多一个 MethodChannel 方法（本仓库的规矩是方法数
 * 只降不升），要么让 Flutter 分两次读 —— 两次读之间原生可能又丢了新的，计数就漏了。
 * `truncated` 走同一份载荷也是同一个理由：Flutter 要靠它决定"还要不要再拉一批"。
 */
data class OfflineDrain(
    val records: List<Map<String, Any?>>,
    val dropped: Int,
    val truncated: Boolean,
)
