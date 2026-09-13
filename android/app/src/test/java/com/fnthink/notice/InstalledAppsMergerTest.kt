package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 应用列表合并器测试（Flyme 扫描补足场景）。
 *
 * 行为：以 packageName 去重（首见优先）+ 按 appName 小写排序。
 * 主列表（getInstalledApplications，可能被 ROM 过滤为空/不完整）
 * + 补充列表（桌面 Activity 查询，与权限探测同源可见）。
 */
class InstalledAppsMergerTest {

    private fun app(pkg: String, name: String, system: Boolean = false) =
        mapOf("packageName" to pkg, "appName" to name, "isSystemApp" to system)

    @Test
    fun primaryEmpty_secondaryFills() {
        // Flyme 场景：getInstalledApplications 空，桌面查询补足
        val result = InstalledAppsMerger.merge(
            primary = emptyList(),
            secondary = listOf(app("com.b", "B"), app("com.a", "A")),
        )
        assertEquals(listOf("com.a", "com.b"), result.map { it["packageName"] })
    }

    @Test
    fun duplicatePackage_primaryWins() {
        // 同包名两处都有：保留主列表（首见）条目
        val result = InstalledAppsMerger.merge(
            primary = listOf(app("com.a", "主列表名称")),
            secondary = listOf(app("com.a", "桌面名称")),
        )
        assertEquals(1, result.size)
        assertEquals("主列表名称", result.first()["appName"])
    }

    @Test
    fun mergedSortedByAppNameLowercase() {
        val result = InstalledAppsMerger.merge(
            primary = listOf(app("com.b", "Beta")),
            secondary = listOf(app("com.a", "alpha"), app("com.c", "CHERRY")),
        )
        assertEquals(
            listOf("com.a", "com.b", "com.c"),
            result.map { it["packageName"] },
        )
    }

    @Test
    fun emptyPackageSkipped() {
        val result = InstalledAppsMerger.merge(
            primary = listOf(mapOf("packageName" to "", "appName" to "无包名")),
            secondary = listOf(app("com.a", "A")),
        )
        assertEquals(listOf("com.a"), result.map { it["packageName"] })
    }

    @Test
    fun bothEmpty_returnsEmpty() {
        assertTrue(InstalledAppsMerger.merge(emptyList(), emptyList()).isEmpty())
    }
}
