package com.fnthink.notice

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * 「读取应用列表」权限链路的静态源码守卫（JVM 直测，无需 Android 运行时）。
 *
 * **本类在 2026-09-23 被整体重写**，因为真机探针把旧契约的前提证伪了。
 * 旧版本（v1.5.68 立）钉的是：
 *   - `MODE_ALLOWED -> true`、`MODE_DEFAULT -> hasQueryAllPackagesEffective()`、`else -> false`；
 *   - 探测必须用"桌面 Activity 可见数 ≥ 阈值"。
 * 而 MEIZU 21（Android 16 / Flyme）实测（`AppListPermissionProbeTest`）：
 *   `permissionToOp=NULL`、`getInstalledApplications=0`、`queryIntentActivities(LAUNCHER)=121`
 *   ⇒ ① AOSP 根本没给 `QUERY_ALL_PACKAGES` 建 appop 映射，旧代码在此 `?: return true`，
 *      所以权限页在**所有** Android 11+ 设备上恒显"已授予"；
 *   ② "桌面可见数 ≥ 20"这个探测在拒绝态下给出 121 → 判"已授予"，
 *      而 `getInstalledApps()` 还把同一批桌面结果 merge 回来当列表 ⇒ 系统明确拒绝、应用照样列出。
 * 因此新契约改成下面这几条（语义本体在 [AppListVisibility]，由 `AppListVisibilityTest` 穷举锁）。
 *
 * ⚠ 断言前一律剥离注释：注释里的同名字样会误伤守卫（历史教训见 MergePushLockContractTest 头注释）。
 */
class QueryAllPackagesContractTest {

    private val repoRoot: File = run {
        val candidates = listOf(File("../.."), File("."), File(".."))
        candidates.firstOrNull { File(it, "android/app/src/main/kotlin/com/fnthink/notice").isDirectory }
            ?: error("无法定位仓库根目录（cwd=${File(".").absolutePath}")
    }

    private fun kotlinSource(name: String): String {
        val f = File(repoRoot, "android/app/src/main/kotlin/com/fnthink/notice/$name")
        assertTrue("源文件不存在: ${f.absolutePath}", f.isFile)
        return stripComments(f.readText())
    }

    /**
     * 取某个函数从声明处到**下一个成员声明**之间的片段。
     *
     * ⚠ 不能按大括号配平取：`canQueryAllPackages` 是表达式体（`= AppListVisibility.shouldScan(...)`），
     * 找 `\{` 会一路滑到后面某个无关函数的大括号里，断言退化成"签名字符串里有没有 X"且常绿
     * —— 这一族陷阱在 blockAfter 上踩过（见 base.md §12.3 静态守卫工具行）。
     */
    private fun functionRegion(source: String, funName: String): String {
        val marker = "fun $funName"
        val idx = source.indexOf(marker)
        assertTrue("未找到函数 $funName", idx >= 0)
        val boundaries = listOf(
            "\n    internal fun ",
            "\n    private fun ",
            "\n    internal var ",
            "\n    private var ",
            "\n    @Volatile",
            "\n    companion object",
            "\n    override fun ",
        )
        val next = boundaries.mapNotNull { source.indexOf(it, idx + marker.length) }
            .filter { it > 0 }
            .minOrNull()
        return if (next == null) source.substring(idx) else source.substring(idx, next)
    }

    // ===== 1. 旧的错误探测必须消失 =====

    @Test
    fun launcherCountProbe_isGone_becauseItSaysGrantedWhileDenied() {
        val src = kotlinSource("MainActivity.kt")
        assertFalse(
            "`hasQueryAllPackagesEffective` 必须已删除：它以「桌面 Activity 数 ≥ 20」判可读，" +
                "而真机拒绝态实测该数为 121（getInstalledApplications 才是 0）。" +
                "可读与否一律由 AppListVisibility.fromScan(枚举计数) 定。",
            src.contains("hasQueryAllPackagesEffective"),
        )
    }

    // ===== 2. 状态判定不得有任何 fail-open =====

    @Test
    fun stateComputationHasNoFailOpenFallbacks() {
        val body = functionRegion(kotlinSource("MainActivity.kt"), "appListPermissionState")
        assertFalse(
            "出现 `?: return true` = 拿不到读数就当已授予（旧假阳性根因，" +
                "AOSP 对 QUERY_ALL_PACKAGES 的 permissionToOp 就是 null）。必须退回 UNKNOWN。",
            Regex("""\?:\s*return\s+true""").containsMatchIn(body),
        )
        assertFalse(
            "状态函数里不得直接 return true —— 布尔结论只能来自 AppListVisibility 的裁决",
            Regex("""return\s+true""").containsMatchIn(body),
        )
        assertTrue(
            "必须把 declared / appOpMode 交给 AppListVisibility.fromAppOp 裁决",
            body.contains("AppListVisibility.fromAppOp"),
        )
    }

    @Test
    fun canQueryAllPackagesDelegatesToShouldScan() {
        val body = functionRegion(kotlinSource("MainActivity.kt"), "canQueryAllPackages")
        assertTrue(
            "`canQueryAllPackages` 的语义是「允许去枚举」（只有明确拒绝才拦），" +
                "必须转发 AppListVisibility.shouldScan，不得自己读 AppOps",
            body.contains("AppListVisibility.shouldScan"),
        )
        assertFalse(
            "canQueryAllPackages 不得再直接查 AppOps（判定已集中到 appListPermissionState）",
            body.contains("checkOpNoThrow"),
        )
    }

    // ===== 3. 扫描路径：先拦明确拒绝，再用枚举计数定论，且拒绝态不得 merge =====

    @Test
    fun scanGatesOnStateAndSettlesByEnumerationCount() {
        val body = functionRegion(kotlinSource("MainActivity.kt"), "getInstalledApps")
        assertTrue(
            "扫描前必须判 shouldScan：明确拒绝时不得再枚举（国产 ROM 会在首次枚举时弹系统框）",
            body.contains("AppListVisibility.shouldScan"),
        )
        assertTrue(
            "扫描后必须以枚举计数定论（fromScan），否则拒绝态下桌面查询会冒充「读到了列表」。",
            body.contains("AppListVisibility.fromScan"),
        )
        assertTrue(
            "判定为 DENIED 时必须返回空列表",
            Regex("""return\s+emptyList\(\)""").containsMatchIn(body),
        )
        // merge 只能出现在 fromScan 之后：桌面查询不得成为拒绝态的兜底数据源
        val mergeAt = body.indexOf("InstalledAppsMerger.merge")
        val scanAt = body.indexOf("AppListVisibility.fromScan")
        assertTrue(
            "InstalledAppsMerger.merge 必须排在 fromScan 之后（先定论、再决定要不要补标签）",
            mergeAt in 0 until Int.MAX_VALUE && scanAt in 0 until mergeAt,
        )
    }

    // ===== 4. 缓存：拒绝态不得复用、且要抹掉拒前数据 =====

    @Test
    fun deniedStateClearsCacheAndNeverServesStaleCache() {
        val src = kotlinSource("channels/StatsChannelHandler.kt")
        assertTrue(
            "权限被拒时必须在 lastAppListScanDenied 分支里清缓存（里面可能留着拒前采到的全量清单）。" +
                "⚠ 这里刻意用结构式正则而不是 contains(\"clearInstalledAppsCache\")：" +
                "反证植入 `if (false) { …clearInstalledAppsCache()… }` 时字面量仍在，" +
                "contains 型断言会假绿 —— 那是「测试通过 ≠ 有保护」的又一实例。",
            Regex(
                """lastAppListScanDenied\s*\)\s*\{[^}]*clearInstalledAppsCache\(\)""",
                RegexOption.DOT_MATCHES_ALL,
            ).containsMatchIn(src),
        )
        assertTrue(
            "复用缓存前必须过 canQueryAllPackages，否则拒绝态仍会吐出旧清单",
            Regex("""canQueryAllPackages\(\)\s*&&\s*activity\.isInstalledAppsCacheFresh""")
                .containsMatchIn(src),
        )
    }

    // ===== 5. 跨端契约：三态字符串取代布尔（布尔必然说谎） =====

    @Test
    fun channelExposesTriStateAndOldBoolIsGone() {
        val handler = kotlinSource("channels/PermissionChannelHandler.kt")
        assertTrue(
            "必须暴露 getAppListPermissionState（granted/denied/unknown）给权限页显示",
            handler.contains("getAppListPermissionState"),
        )
        assertFalse(
            "`isAppListPermissionGranted` 必须删除：布尔把「系统不给状态」压成了「已授予」。",
            handler.contains("isAppListPermissionGranted"),
        )
        val main = kotlinSource("MainActivity.kt")
        assertTrue(
            "MainActivity 必须提供 wire 出口，值域由 AppListState.wire() 单点定义",
            main.contains("appListPermissionState().wire()"),
        )
    }
}
