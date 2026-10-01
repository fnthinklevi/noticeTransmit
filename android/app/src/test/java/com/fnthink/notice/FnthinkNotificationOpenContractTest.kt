package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * 点通知 → 跳到那一条：那条链在两个语言里的**接线形状**（T83）。
 *
 * 为什么是源码契约而不是 JVM 行为用例：这一片的风险全在"哪一处调用了一次"上 ——
 * Intent 在 JVM 上造不出来（`getStringExtra` 是 not mocked），而 Dart 侧那一半有 widget 用例在跑。
 * 于是这里钉的是"三种进入形状都真的接上了、且只有一个出口"，那些地方一旦改回去，
 * 表现恰好是维护者报的原文：**点了通知只打开软件**。
 *
 * 五个方向：
 *  ① 读的是 `FnthinkInboxDisplay.EXTRA_MESSAGE_ID` 那一个常量，MainActivity 里不许出现键名字面量
 *     （两份字面量可以朝同一个方向写错，而那时两侧编译与测试都仍然绿）；
 *  ② 冷启动（onCreate）与热恢复（onNewIntent）两处都要接住 —— 只接冷启动的话"第二次点通知"
 *     还是只打开软件，而那正是这条判据点名的形状；
 *  ③ `onNewIntent` 里 `setIntent` 必须在前面：不设的话 `getIntent()` 永远停在第一条上，
 *     之后任何一次 recreate 都会重新记下**旧的那一枚**；
 *  ④ 读了就要 `removeExtra`：Intent 跟着 Activity 实例留下，不清就会让"从桌面图标进来"
 *     也跳到某条通知；
 *  ⑤ 冷启动**只拉不推**：configureFlutterEngine 早于 Dart 侧装 handler，那一刻推出去会静默丢。
 */
class FnthinkNotificationOpenContractTest {

    private val activity = stripComments(appFile(SRC + "MainActivity.kt").readText())
    private val handler = stripComments(appFile(CH + "FnthinkChannelHandler.kt").readText())
    private val openTarget = stripComments(appFile(SRC + "FnthinkOpenTarget.kt").readText())
    private val display = stripComments(appFile(SRC + "FnthinkInboxDisplay.kt").readText())

    @Test
    fun `extra 的键名只有一个作者`() {
        assertTrue(
            "MainActivity 必须读 FnthinkInboxDisplay.EXTRA_MESSAGE_ID 那一个常量",
            activity.contains("FnthinkInboxDisplay.EXTRA_MESSAGE_ID"),
        )
        assertFalse(
            "MainActivity 里重打了一遍键名字面量 ⇒ 改一边另一边不报错，" +
                "而表现是\"点了通知什么都不发生\"",
            activity.contains(EXTRA_LITERAL),
        )
        assertFalse(
            "通道 handler 也不许重打键名（它只该读那份已接进来的账）",
            handler.contains(EXTRA_LITERAL),
        )
        assertEquals(
            "键名的作者仍是收件显示那一处（写进 Intent 的就是它）",
            EXTRA_LITERAL.trim('"'),
            Regex("EXTRA_MESSAGE_ID\\s*=\\s*\"([^\"]+)\"").find(display)?.groupValues?.get(1),
        )
    }

    @Test
    fun `三种进入形状里原生负责的那两种都接住了`() {
        val onCreate = bodyOf(activity, "override fun onCreate(")
        val onNewIntent = bodyOf(activity, "override fun onNewIntent(")
        assertTrue(
            "冷启动没接：进程被杀之后从通知进来，那枚 id 到不了 Dart —— 就是\"只打开软件\"",
            onCreate.contains("consumeOpenTargetFrom("),
        )
        assertTrue(
            "后台热恢复没接：singleTask 下这一发走 onNewIntent 而不是新的 onCreate，" +
                "漏了它，用户第二次点通知还是\"只打开软件\"",
            onNewIntent.contains("consumeOpenTargetFrom("),
        )
        assertTrue(
            "onNewIntent 必须 setIntent：不设，getIntent() 一直停在第一条上，" +
                "之后一次 recreate 就会重新记下旧的那一枚",
            onNewIntent.contains("setIntent(intent)"),
        )
        assertTrue(
            "setIntent 要在接住那枚 id 之前（顺序错了就是把旧的那条再记一遍）",
            onNewIntent.indexOf("setIntent(intent)") <
                onNewIntent.indexOf("consumeOpenTargetFrom("),
        )
    }

    @Test
    fun `接住就清：同一枚 id 不会被 recreate 再记一遍`() {
        val consume = bodyOf(activity, "private fun consumeOpenTargetFrom(")
        assertTrue(
            "读不到 removeExtra ⇒ Intent 上的那枚一直留着，" +
                "配置变化重建时会把\"已经跳过的那一条\"再交出去一次",
            consume.contains("removeExtra("),
        )
        assertTrue(
            "接进来的账只能是 FnthinkOpenTarget —— 它才是那个「取走即清」的唯一落点",
            consume.contains("FnthinkOpenTarget.record("),
        )
    }

    @Test
    fun `冷启动只拉不推，热恢复才推`() {
        val configure = bodyOf(activity, "override fun configureFlutterEngine(")
        val onNewIntent = bodyOf(activity, "override fun onNewIntent(")
        assertTrue(
            "热恢复要推这一发讯号：App 活着时 Dart 不会主动来问，没人喊它就永远不跳",
            onNewIntent.contains("invokeMethod(\"$WAKE_METHOD\""),
        )
        assertFalse(
            "configureFlutterEngine 里推 ⇒ Dart 侧的 handler 还没装上，这一发静默丢掉，" +
                "而那正是本片要修的缺陷的形状。冷启动必须由 Dart 来拉",
            configure.contains("invokeMethod(\"$WAKE_METHOD\""),
        )
    }

    @Test
    fun `id 的唯一出口是 take，且那一枚不落地`() {
        assertTrue(
            "通道必须交的是 take()：换成 peek() 就成了第二个读者，同一条会跳两遍",
            handler.contains("\"$PULL_METHOD\" -> result.success(FnthinkOpenTarget.take())"),
        )
        assertFalse(
            "生产路径不许出现 peek（那是测试与日志用的读法，它不清账）",
            handler.contains("FnthinkOpenTarget.peek()") ||
                activity.contains("FnthinkOpenTarget.peek()"),
        )
        assertFalse(
            "把这一枚写进 prefs ⇒ 下次冷启动跳去一条三天前的通知，" +
                "比\"点了没反应\"更难向用户解释",
            openTarget.contains("SharedPreferences") || openTarget.contains("apply()"),
        )
    }

    /** 取一个函数从签名那一行到下一个同缩进 `}` 的正文（够钉住调用点顺序，不引解析器）。 */
    private fun bodyOf(source: String, signaturePrefix: String): String {
        val start = source.indexOf(signaturePrefix)
        assertTrue("源码里找不到 $signaturePrefix —— 它被改名或删掉了？", start >= 0)
        val bodyStart = source.indexOf("{", start)
        var depth = 0
        var i = bodyStart
        while (i < source.length) {
            when (source[i]) {
                '{' -> depth++
                '}' -> {
                    depth--
                    if (depth == 0) return source.substring(bodyStart, i + 1)
                }
            }
            i++
        }
        throw IllegalStateException("$signaturePrefix 的正文没有闭合")
    }

    /** 见 [FnthinkInboxDisplayTest] 里同一段注释：cwd 可能是模块根，也可能是仓库根的上一层。 */
    private fun appFile(rel: String): File {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            val candidate = File(dir, rel)
            if (candidate.exists()) return candidate
            dir = dir.parentFile
        }
        throw IllegalStateException("未找到 $rel（cwd=${File("").absolutePath}）")
    }

    private companion object {
        const val SRC = "src/main/kotlin/com/fnthink/notice/"
        const val CH = SRC + "channels/"
        const val EXTRA_LITERAL = "\"extra_fnthink_message_id\""
        const val WAKE_METHOD = "onFnthinkNotificationOpened"
        const val PULL_METHOD = "takeFnthinkOpenTarget"
    }
}
