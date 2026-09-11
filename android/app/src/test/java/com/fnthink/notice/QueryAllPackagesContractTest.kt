package com.fnthink.notice

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * `canQueryAllPackages` 权限判定的静态源码守卫（JVM 直测，无需 Android 运行时）。
 *
 * **背景（v1.5.68 缺陷）**：原「无副作用探测」`hasQueryAllPackagesEffective()` 查的是
 * **应用自身**的包信息——该查询在任何权限状态下都恒成功，构成**假阳性**：
 * AppOps 返回 `MODE_DEFAULT`（部分国产 ROM 的开关关闭态也返回 DEFAULT）时，探测恒返回
 * true → 未授权被误判为已授权 → 应用筛选页 / 规则适用应用选择页跳过授权引导、
 * 拿到空列表（原生 `getInstalledApps` 无权限时静默返回空）。
 *
 * **修复后的结构性约束（本类锁定的契约）**：
 * 1. 探测**不得**只查自身包（不得出现 `setPackage(`）——必须查全量桌面 Activity 可见数量，
 *    并与阈值比较（未授权时包可见性过滤生效，可见数通常 < 10；已授予时 100+）；
 * 2. `canQueryAllPackages` 的 AppOps 分派必须保守：
 *    `MODE_ALLOWED -> true`、`MODE_DEFAULT -> 交由探测裁决`、**其余模式（IGNORED/ERRORED/DENIED）
 *    一律 `else -> false`**（修复前的旧代码是 `else -> 探测`，把明确的拒绝信号也误判为已授予）。
 *
 * ⚠⚠ 改动 `canQueryAllPackages` / `hasQueryAllPackagesEffective` 的结构时必须同步更新本文件 ⚠⚠
 * ⚠ 断言前剥离注释（stripComments）——注释里的同名字样会误伤守卫（历史教训，见
 * MergePushLockContractTest 头注释）。
 */
class QueryAllPackagesContractTest {

    private val repoRoot: File = run {
        // Gradle 测试工作目录随 AGP/启动方式变化，逐个探测而不猜路径
        val candidates = listOf(File("../.."), File("."), File(".."))
        candidates.firstOrNull { File(it, "android/app/src/main/kotlin/com/fnthink/notice").isDirectory }
            ?: error("无法定位仓库根目录（cwd=${File(".").absolutePath}）")
    }

    private fun kotlinSource(name: String): String {
        val f = File(
            repoRoot,
            "android/app/src/main/kotlin/com/fnthink/notice/$name"
        )
        assertTrue("源文件不存在: ${f.absolutePath}", f.isFile)
        return f.readText()
    }

    /** 按函数名提取函数体（大括号配平），并剥离注释——断言只看可执行代码 */
    private fun functionBody(source: String, funName: String): String {
        val marker = "fun $funName"
        val idx = source.indexOf(marker)
        assertTrue("未找到函数 $funName", idx >= 0)
        val bodyStart = source.indexOf('{', idx)
        assertTrue("函数 $funName 缺少函数体", bodyStart >= 0)
        var depth = 0
        var i = bodyStart
        while (i < source.length) {
            when (source[i]) {
                '{' -> depth++
                '}' -> {
                    depth--
                    if (depth == 0) break
                }
            }
            i++
        }
        return stripComments(source.substring(bodyStart, i + 1))
    }

    private fun stripComments(code: String): String {
        val noBlock = Regex("""/\*[\s\S]*?\*/""").replace(code, " ")
        return noBlock.lineSequence()
            .joinToString("\n") { line ->
                val idx = line.indexOf("//")
                if (idx >= 0) line.substring(0, idx) else line
            }
    }

    // ===== 约束 1：探测不得只查自身包（假阳性根因），且必须有可见数量阈值 =====

    @Test
    fun probeQueriesLauncherVisibilityWithThreshold_notSelfPackage() {
        val body = functionBody(
            kotlinSource("MainActivity.kt"),
            "hasQueryAllPackagesEffective"
        )
        assertFalse(
            "探测函数出现 `setPackage(` —— 只查自身包的探测在任何权限状态下都恒成功" +
                "（假阳性：未授权也返回 true，授权引导被跳过、列表加载为空）。" +
                "必须探测全量桌面 Activity 可见数量。",
            body.contains("setPackage(")
        )
        assertTrue(
            "探测函数应调用 queryIntentActivities 统计可见桌面 Activity",
            body.contains("queryIntentActivities")
        )
        assertTrue(
            "探测函数缺少可见数量阈值判定（如 list.size >= 20）——" +
                "没有阈值就无法区分「未授权的少量可见」与「已授权的全量可见」",
            Regex("""\.size\s*>=\s*\d+""").containsMatchIn(body)
        )
    }

    // ===== 约束 2：AppOps 分派必须保守 —— 明确的拒绝信号不得交给探测 =====

    @Test
    fun appOpsModesAreJudgedConservatively() {
        val body = functionBody(
            kotlinSource("MainActivity.kt"),
            "canQueryAllPackages"
        )
        assertTrue(
            "MODE_ALLOWED 应直接判 true（快速路径）",
            Regex("""MODE_ALLOWED\s*->\s*true""").containsMatchIn(body)
        )
        assertTrue(
            "MODE_DEFAULT 应交由非自身包探测裁决（ROM 语义不明）",
            Regex("""MODE_DEFAULT\s*->\s*hasQueryAllPackagesEffective\(\)""")
                .containsMatchIn(body)
        )
        assertTrue(
            "其余 AppOps 模式（IGNORED/ERRORED/DENIED，明确的拒绝信号）必须 `else -> false`。" +
                "修复前的旧代码是 `else -> 探测`，把拒绝态也误判为已授予",
            Regex("""else\s*->\s*false""").containsMatchIn(body)
        )
        assertFalse(
            "canQueryAllPackages 不得把探测函数用于非 DEFAULT 分支（拒绝态必须直接 false）",
            Regex("""else\s*->\s*hasQueryAllPackagesEffective\(\)""")
                .containsMatchIn(body)
        )
    }
}
