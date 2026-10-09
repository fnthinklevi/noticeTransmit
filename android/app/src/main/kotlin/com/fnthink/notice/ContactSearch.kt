package com.fnthink.notice

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.provider.ContactsContract
import androidx.core.content.ContextCompat

/**
 * 「按关键词搜本机通讯录」（T124 片C-4 的 `contacts:search`，只在远端发起时用；本机界面不碰它）。
 *
 * 与 [SmsSearch] / [CallLogSearch] 逐条同源的三件取舍：
 *  ① **不落任何新库**：直查系统通讯录（`ContactsContract`），命中就交回、不存副本；
 *  ② **`%` 与 `_` 必须转义**：LIKE 的通配符出现在关键词里会让"搜 50%"变成"搜 5 开头的任意串"；
 *  ③ **没权限回 null，不是空表**：空表的含义是"搜了、没有"。
 *
 * ⚠ **只带两件**：姓名与号码。联系人 id、头像、备注都不进 —— 通讯录比短信更宽，
 * 多带的每个字段都是一次新的对外披露面（与 Dart 侧那份组装同一条纪律）。
 * ⚠ **本机开关不在这里判**：那是 Dart 侧那一枚（默认关），关着时连这个方法都不会被调到。
 */
object ContactSearch {
    private const val TAG = "ContactSearch"

    /** 一次最多带几条回去（Dart 侧报告另有总预算）。 */
    const val LIMIT = 20

    /** LIKE 的转义字符（与另两份同源；改一处必须改三处，JVM 用例钉着）。 */
    const val LIKE_ESCAPE = "\\"

    /**
     * 把用户输入的词变成 LIKE 的**字面量**：`\` `%` `_` 三个字符各加一个转义前缀。
     * ⚠ 顺序必须是"先转 `\` 本身"。
     */
    fun escapeLike(keyword: String): String =
        keyword
            .replace("\\", "\\\\")
            .replace("%", "\\%")
            .replace("_", "\\_")

    /** 选择串与参数（纯函数，JVM 可测）：姓名或号码任一命中即算。 */
    fun selectionFor(keyword: String): Pair<String, Array<String>> {
        val like = "%${escapeLike(keyword)}%"
        return (
            "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} LIKE ? ESCAPE '$LIKE_ESCAPE'" +
                " OR ${ContactsContract.CommonDataKinds.Phone.NUMBER} LIKE ? ESCAPE '$LIKE_ESCAPE'"
            ) to arrayOf(like, like)
    }

    /**
     * 查一次。回 null = **没查成**（没给 READ_CONTACTS / 查询被系统拒），回空表 = 查成了但没命中。
     * 不抛：一次查询失败不该让整轮收货崩在半路。
     */
    fun search(context: Context, keyword: String): List<Map<String, Any?>>? {
        val granted = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.READ_CONTACTS,
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) return null
        val (selection, args) = selectionFor(keyword)
        return try {
            val out = mutableListOf<Map<String, Any?>>()
            context.contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                arrayOf(
                    ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                    ContactsContract.CommonDataKinds.Phone.NUMBER,
                ),
                selection,
                args,
                "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} ASC",
            )?.use { cursor ->
                val iName = cursor.getColumnIndex(
                    ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                )
                val iNumber = cursor.getColumnIndex(
                    ContactsContract.CommonDataKinds.Phone.NUMBER,
                )
                // ⚠ 同另两份：上限在**游标这一层**收（读满就停），不依赖 SQL 方言。
                while (cursor.moveToNext() && out.size < LIMIT) {
                    out.add(
                        mapOf(
                            "name" to (if (iName >= 0) cursor.getString(iName) else null),
                            "number" to (if (iNumber >= 0) cursor.getString(iNumber) else null),
                        ),
                    )
                }
            }
            out
        } catch (e: SecurityException) {
            android.util.Log.w(TAG, "通讯录查询权限被拒", e)
            null
        } catch (e: Exception) {
            android.util.Log.e(TAG, "通讯录查询失败", e)
            null
        }
    }
}
