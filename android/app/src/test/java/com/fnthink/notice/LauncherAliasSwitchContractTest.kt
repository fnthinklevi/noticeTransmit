package com.fnthink.notice

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * P1-2 后续：首启别名切换的装配守卫。
 *
 * 行为判据在 [LauncherAliasPolicyTest]（纯字符串）；这里钉的是 MainActivity 有没有
 * 真的按那条判据走：
 *  - `changeLauncherIcon` / `switchLocaleAlias` 不许再直接调全量收敛；
 *  - 延迟收敛必须在 `onStop`（应用已不可见）里做，不能在 `onResume` 当场做；
 *  - 安全切换在延迟分支里只启用目标，不遍历禁用其它 alias。
 */
class LauncherAliasSwitchContractTest {

    private val repoRoot: File = run {
        val candidates = listOf(File("../.."), File("."), File(".."))
        candidates.firstOrNull {
            File(it, "android/app/src/main/kotlin/com/fnthink/notice").isDirectory
        } ?: error("无法定位仓库根目录（cwd=${File(".").absolutePath}）")
    }

    private fun mainActivity(): String {
        val f = File(
            repoRoot,
            "android/app/src/main/kotlin/com/fnthink/notice/MainActivity.kt",
        )
        assertTrue("源文件不存在: ${f.absolutePath}", f.isFile)
        return stripComments(f.readText())
    }

    private fun bodyOf(src: String, signature: String): String {
        val start = src.indexOf(signature)
        assertTrue("未找到 $signature", start >= 0)
        val brace = src.indexOf('{', start)
        var depth = 0
        for (i in brace until src.length) {
            when (src[i]) {
                '{' -> depth++
                '}' -> {
                    depth--
                    if (depth == 0) return src.substring(brace, i + 1)
                }
            }
        }
        error("函数体大括号不配对：$signature")
    }

    @Test
    fun `首启切换走安全入口，延迟到 onStop 收敛`() {
        val src = mainActivity()
        assertTrue(
            "switchLocaleAlias 没走 applyLauncherAliasSafely",
            bodyOf(src, "internal fun switchLocaleAlias()").contains("applyLauncherAliasSafely("),
        )
        assertTrue(
            "changeLauncherIcon 没走 applyLauncherAliasSafely",
            bodyOf(src, "internal fun changeLauncherIcon(").contains("applyLauncherAliasSafely("),
        )
        assertTrue(
            "安全切换没问 LauncherAliasPolicy",
            bodyOf(src, "private fun applyLauncherAliasSafely(")
                .contains("LauncherAliasPolicy.mustDeferDisable("),
        )
        assertTrue("缺少 pendingAliasSweep 标记", src.contains("pendingAliasSweep"))
        val onStop = bodyOf(src, "override fun onStop()")
        assertTrue(
            "onStop 没有做延迟收敛",
            onStop.contains("pendingAliasSweep") && onStop.contains("applyLauncherAlias("),
        )
    }

    @Test
    fun `延迟分支只启用目标，不遍历禁用其它 alias`() {
        val body = bodyOf(mainActivity(), "private fun applyLauncherAliasSafely(")
        assertTrue(
            "延迟分支没有启用目标 alias",
            body.contains("PackageManager.COMPONENT_ENABLED_STATE_ENABLED"),
        )
        assertFalse(
            "延迟分支里出现 COMPONENT_ENABLED_STATE_DISABLED ⇒ 又会在前台禁用旧 alias",
            body.contains("PackageManager.COMPONENT_ENABLED_STATE_DISABLED"),
        )
        assertTrue(
            "延迟分支没有置 pendingAliasSweep",
            body.contains("pendingAliasSweep = true"),
        )
    }
}
