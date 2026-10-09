package com.fnthink.notice

import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 「点通知跳收件页」那条链在 **T125** 修好之后的两条形状纪律（JVM 上按源码形状钉）。
 *
 * ## 那一条缺陷的因果链（两处各自都对、接起来就错）
 * ① `launchMode="singleTask"` ⇒ 系统把新 Intent 交给存活的 Activity，全走 `onNewIntent`；
 * ② 旧的 `onNewIntent` 在 `consumeOpenTargetFrom(intent)` 之后**无条件**推
 *    `onFnthinkNotificationOpened` —— 于是"从最近任务恢复""点桌面图标""点任何一条通知"
 *    全被 Dart 那侧当成"他点了一条收件通知"，每次进入都被送进收件历史页。
 *
 * ## 三条进入路（软件侧钉形状，真机各走一次另记）
 * | 进入形状 | Intent 里有什么 | 期望 |
 * |---|---|---|
 * | 从最近任务恢复 | 没有 EXTRA_MESSAGE_ID | **不**进收件页 |
 * | 点桌面图标 | 没有 EXTRA_MESSAGE_ID | **不**进收件页 |
 * | 点状态栏一条非收件类通知 | 没有 EXTRA_MESSAGE_ID | **不**进收件页 |
 * | （对照）点幻念收件通知（App 活着） | 带 EXTRA_MESSAGE_ID | 进收件页并展开那一条 |
 *
 * ## 为什么是源码形状而不是行为
 * `onNewIntent` 的行为要真机重投 Intent 才谈得上（厂商 ROM 的进入形状软件侧判不了）；
 * 本机能钉住的是"推的时机由哪一个条件决定"这个形状。行为面另有 Dart 双向用例与真机走查。
 *
 * ⚠ **不许反过来改成"Dart 侧取不到 id 就不跳"**：那会把 T83 判据③（点了收件通知、
 * id 拿不到也要打开列表）原样放回来，只是换了个方向错。
 */
class FnthinkNotificationOpenGuardTest {

    /** 剥掉块注释与整行注释（源码守卫的标配件，与 CameraSnapTest 同源）。 */
    private fun stripComments(src: String): String =
        src
            .replace(Regex("(?s)/\\*.*?\\*/"), "")
            .lines()
            .filterNot { it.trimStart().startsWith("//") }
            .joinToString("\n")

    /** 取一个方法体：从签名到下一个 4 空格缩进的 `}`（与仓库里各 Kotlin 源码守卫同一口径）。 */
    private fun methodBody(src: String, signature: String): String {
        val start = src.indexOf(signature)
        assertTrue("找不到方法：$signature（签名改了 ⇒ 这条守卫要跟着改口径）", start >= 0)
        val end = src.indexOf("\n    }", start)
        assertTrue("读不到方法体结尾：$signature", end > start)
        return src.substring(start, end)
    }

    @Test
    fun `onNewIntent 不许无条件推那一发讯号`() {
        val src = stripComments(
            appFile("src/main/kotlin/com/fnthink/notice/MainActivity.kt").readText(),
        )
        val body = methodBody(src, "override fun onNewIntent(intent: Intent)")
        val pushIdx = body.indexOf("onFnthinkNotificationOpened")
        assertTrue(
            "onNewIntent 里没有那一发讯号了 ⇒ 热恢复点通知没人跳（T83 的原始缺陷）",
            pushIdx >= 0,
        )
        val condIdx = body.indexOf("if (consumeOpenTargetFrom(intent))")
        assertTrue(
            "推那一发没有挂在 `consumeOpenTargetFrom(intent)` 的条件里 —— " +
                "每一种进入形状都会走到 onNewIntent，无条件推 = 没有新通知也进收件页（T125）",
            condIdx in 0 until pushIdx,
        )
        assertTrue(
            "条件与推送之间没有左花括号 ⇒ 那不是一个 if 块在包着它",
            body.substring(condIdx, pushIdx).contains("{"),
        )
    }

    @Test
    fun `consumeOpenTargetFrom 回布尔：记到了才算`() {
        val src = stripComments(
            appFile("src/main/kotlin/com/fnthink/notice/MainActivity.kt").readText(),
        )
        val body = methodBody(src, "private fun consumeOpenTargetFrom(intent: Intent?)")
        assertTrue(
            "签名必须是 Boolean：否则\"这一次进入到底有没有一枚要跳的 id\"没人说得清（T125）",
            body.contains("consumeOpenTargetFrom(intent: Intent?): Boolean"),
        )
        assertTrue("拿不到 id 要回 false（不是继续往下推）", body.contains("?: return false"))
        val recordIdx = body.indexOf("FnthinkOpenTarget.record(messageId)")
        val retIdx = body.indexOf("return true")
        assertTrue("记了那枚 id 才回 true（record 要在 return true 之前）", recordIdx in 0 until retIdx)
    }

    /** 从测试工作目录往上找到仓库根，再拼 android/app 下的相对路径。 */
    private fun appFile(rel: String): java.io.File {
        var dir = java.io.File("").absoluteFile
        while (true) {
            val f = java.io.File(dir, "android/app/$rel")
            if (f.exists()) return f
            dir = dir.parentFile ?: break
        }
        throw AssertionError("找不到 $rel")
    }
}
