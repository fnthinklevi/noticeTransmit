package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 远程「让这台响一条」（T124 片B 的 `alert:ring`）的形状判定。
 *
 * 能在 JVM 上断的是三类**静默会坏**的事：
 *  ① **渠道归属**：响铃必须与收件共用同一条 HIGH 渠道（另开一条＝把用户关掉的声音偷偷打开），
 *     而渠道 id 不许在这里重打一份（重打的那份在渠道改名后变成"响铃用了一条没人管的新渠道"）；
 *  ② **身份不撞**：tag 与收件不同名 ⇒ 连响两次是重弹、且与任何一条收件不互相顶掉；
 *  ③ **"没显示就回 false"**：权限/渠道被关时回 false（不抛）——回真 true 会让执行链记成
 *     done，而对面以为这台的用户被提醒过了。
 *
 * ⚠ 写没写这些形状用**读源文件**钉（与 `FnthinkInboxDisplayTest` 同一套手法）：
 * 真正的"响没响"只有真机能证，这里钉的是"代码里那一行还在不在"。机器相关的那一半
 * （真机上响不响、震不震）在 T124 片的真机验收里。
 */
class FnthinkAlertDisplayTest {

    private fun alertSource(): String =
        stripComments(
            appFile("src/main/kotlin/com/fnthink/notice/FnthinkAlertDisplay.kt").readText(),
        )

    private fun appFile(rel: String): java.io.File {
        var dir = java.io.File("").absoluteFile
        while (true) {
            val candidate = java.io.File(dir, rel)
            if (candidate.exists()) return candidate
            dir = dir.parentFile ?: throw IllegalStateException("未找到 $rel")
        }
    }

    @Test
    fun `与收件共用同一条渠道，且渠道 id 不在这里重打一份`() {
        val body = alertSource()
        assertTrue(
            "渠道要取自收件那一枚常量：另开一条渠道等于把用户关掉的声音在别处偷偷打开",
            body.contains("FnthinkInboxDisplay.CHANNEL_ID"),
        )
        assertTrue(
            "渠道的创建点也要共用（ensureChannel）——各建各的会在两处漂移",
            body.contains("FnthinkInboxDisplay.ensureChannel"),
        )
        assertTrue(
            "本文件不许自己写一个渠道 id 字面量（重打的那份在渠道改名后静默失配）",
            !Regex("\\\"fnthink_[a-z_]*\\\"").containsMatchIn(body),
        )
    }

    @Test
    fun `tag 与收件不撞：连响两次是重弹，不堆叠也不顶掉收件`() {
        assertEquals("fnthink-alert", FnthinkAlertDisplay.TAG)
        assertNotEquals(
            "三元组里的 id 也要和收件不同值：撞号的后果是一条把另一条顶掉",
            FnthinkInboxDisplay.NOTIFICATION_ID,
            FnthinkAlertDisplay.NOTIFICATION_ID,
        )
        assertTrue(
            "tag 与收件的 messageId 命名空间必须分得开（收件 tag 就是 messageId）",
            !FnthinkAlertDisplay.TAG.startsWith("m_"),
        )
    }

    @Test
    fun `响与震写在通知那一层（8 以下那条路；8+ 由渠道决定）`() {
        val body = alertSource()
        assertTrue(
            "老系统那一路的声音与震动只看这两行",
            body.contains("setDefaults(NotificationCompat.DEFAULT_ALL)") &&
                body.contains("setVibrate("),
        )
        assertTrue(
            "掉优先级会让它与普通通知同档：响铃得按闹钟类对待（勿扰例外档会放它进来）",
            body.contains("NotificationCompat.CATEGORY_ALARM") &&
                body.contains("NotificationCompat.PRIORITY_HIGH") &&
                body.contains("NotificationCompat.VISIBILITY_PUBLIC"),
        )
    }

    @Test
    fun `没显示就回 false（权限被关时不抛、不为真）`() {
        val body = alertSource()
        assertTrue(
            "权限没给时 notify() 不报错也不显示 —— 不问一句就会回一个假 true",
            body.contains("areNotificationsEnabled()"),
        )
        assertTrue(
            "厂商闸仍可能在 notify 处抛 SecurityException：要单独接住并回 false",
            body.contains("catch (e: SecurityException)"),
        )
    }

    @Test
    fun `全屏那半没做，而且没顺手加那份权限（片B 的前提是零新权限）`() {
        val alert = alertSource()
        val manifest = appFile("src/main/AndroidManifest.xml").readText()
        assertTrue(
            "片B 交付的是响铃＋震动＋高优先横幅：全屏意图要 USE_FULL_SCREEN_INTENT（14+ 还要特殊授权），" +
                "那是一次新的权限面决定 —— 要加得按片C 那套来，先改这条断言",
            !alert.contains("setFullScreenIntent"),
        )
        assertTrue(
            "清单里也不许出现 USE_FULL_SCREEN_INTENT（出现即意味着有人在没做隐私面时加了它）",
            !manifest.contains("USE_FULL_SCREEN_INTENT"),
        )
    }

    @Test
    fun `两条文案中英都在（通知栏上那句话不能只有一种语言）`() {
        val zhTitle = I18n.fnthinkAlertTitle()
        val zhText = I18n.fnthinkAlertText()
        I18n.setLocale("en")
        val enTitle: String
        val enText: String
        try {
            enTitle = I18n.fnthinkAlertTitle()
            enText = I18n.fnthinkAlertText()
        } finally {
            I18n.setLocale("zh")
        }
        assertTrue("中文两条都不许为空", zhTitle.isNotBlank() && zhText.isNotBlank())
        assertTrue("英文两条都不许为空", enTitle.isNotBlank() && enText.isNotBlank())
        assertNotEquals("标题必须有英文版", zhTitle, enTitle)
        assertEquals("locale 要还原（全局那一份别的用例也在用）", "zh", I18n.getLocale())
    }
}
