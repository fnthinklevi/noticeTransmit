package com.fnthink.notice

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.provider.CallLog
import androidx.core.content.ContextCompat

/**
 * 「按关键词搜本机通话记录」（T124 片C 的 `calls:search`，只在远端发起时用；本机界面不碰它）。
 *
 * 与 [SmsSearch] 逐条同源的三件取舍：
 *  ① **不落任何新库**：直查系统通话记录（`CallLog.Calls.CONTENT_URI`），命中就交回、不存副本；
 *  ② **`%` 与 `_` 必须转义**：LIKE 的通配符出现在关键词里会让"搜 50%"变成"搜 5 开头的任意串"，
 *     而多带出去的每一条都是一次**静默多带**。用 `ESCAPE '\'`；
 *  ③ **没权限回 null，不是空表**：空表的含义是"搜了、没有"，与"没查成"在对面读起来完全不同。
 *
 * ⚠ **本机开关不在这里判**：那是 Dart 侧的 [kFnthinkReadCallsKey] 那枚（默认关），
 * 它关着时连这个方法都不会被调到 —— 默认值只有一个家，原生这边不抄第二份。
 */
object CallLogSearch {
    private const val TAG = "CallLogSearch"

    /** 一次最多带几条回去（Dart 侧报告另有总预算：单条截断 + 整体上限）。 */
    const val LIMIT = 20

    /** LIKE 的转义字符（与 [escapeLike] 同源；改一处必须改两处，JVM 用例钉着）。 */
    const val LIKE_ESCAPE = "\\"

    /**
     * 把用户输入的词变成 LIKE 的**字面量**：`\` `%` `_` 三个字符各加一个转义前缀。
     * ⚠ 顺序必须是"先转 `\` 本身"——反过来会把刚加上的转义符再转一遍（`%` 变成 `\\%`，
     * 匹配的是"反斜杠开头的串"）。
     */
    fun escapeLike(keyword: String): String =
        keyword
            .replace("\\", "\\\\")
            .replace("%", "\\%")
            .replace("_", "\\_")

    /**
     * 选择串与参数（纯函数，JVM 可测）：
     * 号码或本机缓存的姓名任一命中即算（对面手里可能只有半个号码、也可能只有名字）。
     */
    fun selectionFor(keyword: String): Pair<String, Array<String>> {
        val like = "%${escapeLike(keyword)}%"
        return (
            "${CallLog.Calls.NUMBER} LIKE ? ESCAPE '$LIKE_ESCAPE'" +
                " OR ${CallLog.Calls.CACHED_NAME} LIKE ? ESCAPE '$LIKE_ESCAPE'"
            ) to arrayOf(like, like)
    }

    /**
     * 查一次。回 null = **没查成**（没给 READ_CALL_LOG / 查询被系统拒），回空表 = 查成了但没命中。
     * 不抛：一次查询失败不该让整轮收货崩在半路（与 [SmsSearch.search] 同一纪律）。
     */
    fun search(context: Context, keyword: String): List<Map<String, Any?>>? {
        val granted = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.READ_CALL_LOG,
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) return null
        val (selection, args) = selectionFor(keyword)
        return try {
            val out = mutableListOf<Map<String, Any?>>()
            context.contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                arrayOf(
                    CallLog.Calls.NUMBER,
                    CallLog.Calls.CACHED_NAME,
                    CallLog.Calls.TYPE,
                    CallLog.Calls.DATE,
                    CallLog.Calls.DURATION,
                ),
                selection,
                args,
                "${CallLog.Calls.DATE} DESC",
            )?.use { cursor ->
                val iNumber = cursor.getColumnIndex(CallLog.Calls.NUMBER)
                val iName = cursor.getColumnIndex(CallLog.Calls.CACHED_NAME)
                val iType = cursor.getColumnIndex(CallLog.Calls.TYPE)
                val iDate = cursor.getColumnIndex(CallLog.Calls.DATE)
                val iDur = cursor.getColumnIndex(CallLog.Calls.DURATION)
                // ⚠ 同 SmsSearch：上限在**游标这一层**收（读满就停），不依赖 SQL 方言。
                while (cursor.moveToNext() && out.size < LIMIT) {
                    out.add(
                        mapOf(
                            "number" to (if (iNumber >= 0) cursor.getString(iNumber) else null),
                            "name" to (if (iName >= 0) cursor.getString(iName) else null),
                            "type" to (if (iType >= 0) cursor.getInt(iType) else 0),
                            "dateMillis" to (if (iDate >= 0) cursor.getLong(iDate) else 0L),
                            // DURATION 在系统库里是**秒**；Dart 侧那份组装按毫秒写，
                            // 所以在这里就换成毫秒（单位换算是"交给外面之前"的事，
                            // 出去之后再猜是秒还是毫秒，两条路迟早不一致）。
                            "durationMillis" to
                                (if (iDur >= 0) cursor.getLong(iDur) * 1000L else 0L),
                        ),
                    )
                }
            }
            out
        } catch (e: SecurityException) {
            android.util.Log.w(TAG, "通话记录查询权限被拒", e)
            null
        } catch (e: Exception) {
            android.util.Log.e(TAG, "通话记录查询失败", e)
            null
        }
    }
}
