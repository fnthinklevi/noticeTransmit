package com.fnthink.notice

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * 点开配对链接 → 弹出预填的输入层：那条链在三个地方各存一份字面量时的**接线形状**（#176 片4）。
 *
 * 为什么这一族必须在 JVM 上钉源码而不是只写 Dart 用例：这一片的风险全在"哪一处只写了一遍"上 ——
 * `Intent` 造不出来、Manifest 不参与编译，而**三处字面量**（契约的 `pairing.qrPrefix`、
 * Kotlin 的那把前缀、清单里的 scheme+host）只要有一处朝同一个方向改错，两侧编译与全部 Dart
 * 用例仍然绿，而真机上的表现是"点了链接什么都没有"（前缀不认）或"别的链接也弹层"（筛松了）。
 *
 * 六个方向：
 *  ① 三处合成的是同一把前缀（改一边另一边当场红 —— 这是本片最值的一条）；
 *  ② 冷启动（onCreate）与热恢复（onNewIntent）两处都接住；
 *  ③ 只有**真的记了**才推那一发讯号，且推的是配对那一发，不是通知那一发；
 *  ④ 接住之后清 `intent.data`：Intent 跟着 Activity 留下，不清就是 recreate 再弹一次；
 *  ⑤ 通道交的是 `take()`（不是 `peek()`），且那一串不落盘、不进日志；
 *  ⑥ Kotlin 不判载荷：判据在包层那份契约读口里，抄一份就是第二个作者。
 */
class FnthinkPairLinkContractTest {

    private val activity = stripComments(appFile(SRC + "MainActivity.kt").readText())
    private val handler = stripComments(appFile(CH + "FnthinkChannelHandler.kt").readText())
    private val pairLink = stripComments(appFile(SRC + "FnthinkPairLink.kt").readText())
    private val manifest = stripXmlComments(appFile(MANIFEST).readText())
    private val contract = appFile(CONTRACT).readText()

    @Test
    fun `前缀三处合成的是同一把`() {
        val qrPrefix = Regex("\"qrPrefix\"\\s*:\\s*\"([^\"]+)\"")
            .find(contract)
            ?.groupValues
            ?.get(1)
            ?: error("契约里找不到 pairing.qrPrefix（这条断言就成了空转）")
        val kotlinPrefix = Regex("PREFIX\\s*=\\s*\"([^\"]+)\"")
            .find(pairLink)
            ?.groupValues
            ?.get(1)
            ?: error("FnthinkPairLink.kt 里找不到 PREFIX 字面量")
        val scheme = Regex("android:scheme=\"([^\"]+)\"")
            .find(manifest)
            ?.groupValues
            ?.get(1)
            ?: error("清单里找不到 android:scheme（那一枚 intent-filter 被删了？）")
        val host = Regex("android:host=\"([^\"]+)\"")
            .find(manifest)
            ?.groupValues
            ?.get(1)
            ?: error("清单里找不到 android:host")

        assertTrue(
            "Kotlin 认的那把前缀必须逐字等于契约的 qrPrefix + `?` —— 差一个字符的表现是" +
                "「点了链接什么都没有」，而 Dart 那边永远取不到东西，谁都不报错",
            kotlinPrefix == "$qrPrefix?",
        )
        assertTrue(
            "清单里的 scheme + host 也必须合成同一把：少了这一枚 filter，系统根本不会把链接交给这个 App",
            "$scheme://$host" == qrPrefix,
        )
    }

    @Test
    fun `冷启动与热恢复两处都接住了`() {
        val onCreate = bodyOf(activity, "override fun onCreate(")
        val onNewIntent = bodyOf(activity, "override fun onNewIntent(")
        assertTrue(
            "冷启动没接：从桌面/聊天里点开链接时进程还没起，那一条到不了 Dart",
            onCreate.contains("consumePairLinkFrom("),
        )
        assertTrue(
            "热恢复没接：launchMode=singleTask 下这一发走 onNewIntent，漏了它就只有第一次点得动",
            onNewIntent.contains("consumePairLinkFrom("),
        )
    }

    @Test
    fun `只有真的记了才推那一发，而且推的是配对那一发`() {
        val onNewIntent = bodyOf(activity, "override fun onNewIntent(")
        assertTrue(
            "推那一发必须挂在 record 的返回值上：不看返回值就是「没记也推」，" +
                "而 Dart 取到 null 时什么也不做 —— 于是这条链坏的时候是静默的",
            onNewIntent.contains("if (consumePairLinkFrom(intent))"),
        )
        assertTrue(
            "记成了要推配对那一发讯号",
            onNewIntent.contains("invokeMethod(\"$PAIR_WAKE\""),
        )
        assertTrue(
            "配对那一支要先 return：让它继续往下走，下面那一发通知讯号会让首页去取一枚" +
                "从不存在的 messageId，表现是\"点开配对链接却跳到收件列表\"",
            onNewIntent.indexOf("invokeMethod(\"$PAIR_WAKE\"") <
                onNewIntent.indexOf("invokeMethod(\"$NOTIFY_WAKE\""),
        )
        assertFalse(
            "configureFlutterEngine 里推 ⇒ Dart 的 handler 还没装上，这一发静默丢掉（冷启动必须由 Dart 拉）",
            bodyOf(activity, "override fun configureFlutterEngine(")
                .contains("invokeMethod(\"$PAIR_WAKE\""),
        )
    }

    @Test
    fun `接住就清 Intent：同一条链接不会被 recreate 再弹一遍`() {
        val consume = bodyOf(activity, "private fun consumePairLinkFrom(")
        assertTrue(
            "读不到 `intent.data = null` ⇒ Intent 跟着 Activity 实例留下，" +
                "配置变化重建时会把已经弹过的那条再记一遍，而那枚口令是一次性的",
            consume.contains("intent.data = null"),
        )
        assertTrue(
            "接进来的账只能是 FnthinkPairLink —— 它才是那个「取走即清」的唯一落点",
            consume.contains("FnthinkPairLink.record("),
        )
    }

    @Test
    fun `唯一出口是 take，且那一串不落盘、不进日志`() {
        assertTrue(
            "通道必须交的是 take()：换成 peek() 就成了第二个读者，同一条链接会弹两遍输入层",
            handler.contains("\"$PULL_METHOD\" -> result.success(FnthinkPairLink.take())"),
        )
        assertFalse(
            "生产路径不许出现 peek（那是测试用的读法，它不清账）",
            handler.contains("FnthinkPairLink.peek()") ||
                activity.contains("FnthinkPairLink.peek()"),
        )
        assertFalse(
            "把这一串写进 prefs ⇒ 一次性口令变长期凭证（它还带着 code= 那一段）",
            pairLink.contains("SharedPreferences") || pairLink.contains("apply()"),
        )
        assertFalse(
            "打进日志 ⇒ 口令进 logcat 与反代可达的每一份日志（本站 T89 的脱敏还没配）",
            pairLink.contains("Log.") || pairLink.contains("println"),
        )
    }

    @Test
    fun `Kotlin 不判载荷：判据只有包层那一份`() {
        for (forbidden in listOf("split(", "substringAfter", "urlDecode")) {
            assertFalse(
                "原生开始自己拆 query（$forbidden）⇒ 契约那份 parse 就有了第二个作者，" +
                    "而两份判据可以朝同一个方向写错",
                pairLink.contains(forbidden),
            )
        }
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

    /** 去掉 XML 注释：那几段说明里也写着 scheme/host 的字面量，不算数。 */
    private fun stripXmlComments(source: String): String {
        return Regex("<!--[\\s\\S]*?-->").replace(source, "")
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
        const val MANIFEST = "src/main/AndroidManifest.xml"
        const val CONTRACT = "protocol/fnthink-v1.json"
        const val PAIR_WAKE = "onFnthinkPairLinkReceived"
        const val NOTIFY_WAKE = "onFnthinkNotificationOpened"
        const val PULL_METHOD = "takeFnthinkPairLink"
    }
}
