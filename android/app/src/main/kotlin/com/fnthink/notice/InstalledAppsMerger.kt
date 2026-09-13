package com.fnthink.notice

/**
 * 应用列表合并器（纯函数，JVM 可测）。
 *
 * 背景（Flyme 机型实测）：「读取应用列表」的 ROM 限制只过滤
 * `PackageManager.getInstalledApplications`，而桌面 Activity 查询
 * （`queryIntentActivities(ACTION_MAIN/LAUNCHER)`，与 N1 权限探测同源）仍可见——
 * 导致「权限判定已授权但扫描为空」的矛盾。扫描结果需与桌面查询结果合并补足。
 *
 * 合并规则：以 packageName 去重（首见优先）；按 appName 小写排序。
 */
internal object InstalledAppsMerger {

    fun merge(
        primary: List<Map<String, Any?>>,
        secondary: List<Map<String, Any?>>,
    ): List<Map<String, Any?>> {
        val merged = LinkedHashMap<String, Map<String, Any?>>()
        for (app in primary + secondary) {
            val pkg = app["packageName"]?.toString() ?: continue
            if (pkg.isEmpty() || merged.containsKey(pkg)) continue
            merged[pkg] = app
        }
        return merged.values.sortedBy {
            (it["appName"]?.toString() ?: "").lowercase()
        }
    }
}
