package com.fnthink.notice

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import androidx.core.content.ContextCompat

/**
 * 「按关键词搜本机短信」（T124 片B 的 `sms:search`，只在远端发起时用；本机界面不碰它）。
 *
 * 三件写在这里的取舍：
 *  ① **不落任何新库**：直查系统短信库（`content://sms`），命中就交回、不存副本 ——
 *     存一份等于新增一处短信正文的**留存点**，而那是隐私面的决定，不在这一片里顺手做。
 *  ② **`%` 与 `_` 必须转义**：LIKE 的通配符出现在关键词里会让"搜 50%"变成"搜 5 开头的任意串"，
 *     而多带出去的每一条都是一次**静默多带**（读的人以为匹配是字面的）。用 `ESCAPE '\'`。
 *  ③ **没权限回 null，不是空表**：空表的含义是"搜了、没有"（对面只该看到这句话）；
 *     两件事在对面读起来完全不同 —— 一个该去给权限，一个只是没命中。
 */
object SmsSearch {
    private const val TAG = "SmsSearch"

    /** 一次最多带几条回去（Dart 侧报告另有总预算：单条截断 + 整体上限）。 */
    const val LIMIT = 20

    const val COLUMN_ID = "_id"
    const val COLUMN_ADDRESS = "address"
    const val COLUMN_BODY = "body"
    const val COLUMN_DATE = "date"

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

    /** 选择串与参数（纯函数，JVM 可测）。 */
    fun selectionFor(keyword: String): Pair<String, Array<String>> =
        "$COLUMN_BODY LIKE ? ESCAPE '$LIKE_ESCAPE'" to arrayOf("%${escapeLike(keyword)}%")

    /**
     * 查一次。回 null = **没查成**（没给 READ_SMS / 查询被系统拒），回空表 = 查成了但没命中。
     * 不抛：一次查询失败不该让整轮收货崩在半路（与显示那几发的纪律同源）。
     */
    fun search(context: Context, keyword: String): List<Map<String, Any?>>? {
        val granted = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.READ_SMS,
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) return null
        val (selection, args) = selectionFor(keyword)
        return try {
            val out = mutableListOf<Map<String, Any?>>()
            context.contentResolver.query(
                Uri.parse("content://sms"),
                arrayOf(COLUMN_ID, COLUMN_ADDRESS, COLUMN_BODY, COLUMN_DATE),
                selection,
                args,
                "$COLUMN_DATE DESC",
            )?.use { cursor ->
                val iAddr = cursor.getColumnIndex(COLUMN_ADDRESS)
                val iBody = cursor.getColumnIndex(COLUMN_BODY)
                val iDate = cursor.getColumnIndex(COLUMN_DATE)
                // ⚠ 有些 ROM 不给 sortOrder 里的 LIMIT（那是各家的老坑），
                //   所以上限在**游标这一层**收（读满就停），不依赖 SQL 方言。
                while (cursor.moveToNext() && out.size < LIMIT) {
                    out.add(
                        mapOf(
                            "address" to (if (iAddr >= 0) cursor.getString(iAddr) else null),
                            "body" to (if (iBody >= 0) cursor.getString(iBody) else null),
                            "dateMillis" to (if (iDate >= 0) cursor.getLong(iDate) else 0L),
                        ),
                    )
                }
            }
            out
        } catch (e: SecurityException) {
            android.util.Log.w(TAG, "短信查询权限被拒", e)
            null
        } catch (e: Exception) {
            android.util.Log.e(TAG, "短信查询失败", e)
            null
        }
    }
}
