package com.fnthink.notice

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * T137 验收①的守卫：**本包名下只许有一条收件渠道**。
 *
 * 真机取证（Xiaomi d78f2b5b，2026-10-11）看到的是旧渠道不删的下场：MIUI 设置页出现
 * 两行一模一样的「幻念推送 · 收件」、连描述都同一句 ⇒ 用户根本不知道自己在调哪一行。
 * 这里守三件接线：
 *  1. `ensureChannel` 必须删旧渠道（`deleteNotificationChannel(LEGACY_CHANNEL_ID)`）；
 *  2. 删除必须发生在**新建/确认新渠道的那条路径上**（升级用户不进新渠道那段代码就清不到旧渠道）；
 *  3. 渠道创建时必须显式给震动与声音 —— 真机上 `mVibrationPattern=null` 是"我们没配"，
 *     不是 ROM 关的；显式写出来才少给用户留一个"你什么都没设"的把柄。
 * 全类读源码不跑设备：行为那一半（渠道真删了）在真机/仪器测试里，这里钉的是"代码说没说"。
 */
class FnthinkInboxChannelGuardTest {

    private companion object {
        const val SRC = "src/main/kotlin/com/fnthink/notice/"
    }

    private val displaySource: String by lazy {
        stripComments(File(SRC + "FnthinkInboxDisplay.kt").readText())
    }

    @Test
    fun ensureChannelDeletesLegacyChannel() {
        val ensure = extractFunction(displaySource, "internal fun ensureChannel(")
        assertTrue(
            "没找到 ensureChannel 函数体 —— 守卫本身失效了",
            ensure.isNotEmpty(),
        )
        assertTrue(
            "旧渠道 fnthink_inbox 必须在 ensureChannel 里清掉（deleteNotificationChannel）—— " +
                "MIUI 设置页两行同名「幻念推送 · 收件」就是这么来的",
            ensure.contains("deleteNotificationChannel(LEGACY_CHANNEL_ID)"),
        )
        // 删除要在"见到新渠道就 return"那一句**之前**：提前 return 的老设备永远清不到旧渠道
        val deleteAt = ensure.indexOf("deleteNotificationChannel(LEGACY_CHANNEL_ID)")
        val earlyReturnAt = ensure.indexOf("if (manager.getNotificationChannel(id) != null) return")
        assertTrue(
            "守卫锚点丢了（ensureChannel 的结构变了）—— 本守卫需要按新结构重排",
            deleteAt >= 0 && earlyReturnAt >= 0,
        )
        assertTrue(
            "删除旧渠道必须发生在「新渠道已存在就 return」之前，否则老设备永远清不到它",
            deleteAt < earlyReturnAt,
        )
        assertTrue(
            "ensureChannel 必须把建渠道交给 createHighChannel（T173 起重建也走同一条）",
            ensure.contains("createHighChannel(manager, id)"),
        )
    }

    @Test
    fun channelCreationSetsVibrationAndSoundExplicitly() {
        // T173：建渠道那段挪进了 `createHighChannel`（重建也走它），断言跟着去那儿读。
        val create = extractFunction(displaySource, "private fun createHighChannel(")
        assertTrue(
            "没找到 createHighChannel 函数体 —— 守卫本身失效了",
            create.isNotEmpty(),
        )
        assertTrue(
            "渠道创建必须显式给震动模板（真机取证：mVibrationPattern=null 是我们没配，不是 ROM 关的）",
            create.contains("vibrationPattern = longArrayOf(") && create.contains("enableVibration(true)"),
        )
        assertTrue(
            "渠道创建必须显式给声音（setSound + 系统默认通知音）—— 声音只在创建那一刻绑定",
            create.contains("setSound(") &&
                create.contains("DEFAULT_NOTIFICATION_URI"),
        )
    }

    @Test
    fun notificationBodyKeepsChannelLevelSilenceDiscipline() {
        // 渠道管声音/震动，通知本体**不带音模**（sound=null defaults=0 是对的写法）——
        // 通知级 setSound 会把"用户在渠道上关掉的声音"偷偷打开。
        val showFn = extractFunction(displaySource, "fun show(")
        if (showFn.isEmpty()) {
            // show 的构造若挪走，specFor/渠道段仍在；此守卫只钉"别长出通知级音模"
            assertFalse(
                "本包不许出现 Notification.DEFAULT_SOUND / setSound 在通知构建器上（声音归渠道）",
                displaySource.contains("DEFAULT_SOUND") &&
                    displaySource.contains("setContentTitle") &&
                    Regex("builder\\.setSound|notification\\.setSound").containsMatchIn(displaySource),
            )
            return
        }
        assertFalse(
            "通知构建器上不许 setSound/DEFAULT_SOUND：声音归渠道，通知级音模会绕开用户的渠道设置",
            Regex("\\.setSound\\(|DEFAULT_SOUND").containsMatchIn(showFn),
        )
    }

    private fun stripComments(src: String): String =
        src.replace(Regex("/\\*.*?\\*/", RegexOption.DOT_MATCHES_ALL), "")
            .replace(Regex("//.*"), "")

    private fun extractFunction(src: String, signature: String): String {
        val start = src.indexOf(signature)
        if (start < 0) return ""
        val candidates = listOf("\n    fun ", "\n    internal fun ", "\n    private fun ", "\n}")
            .mapNotNull { anchor ->
                val at = src.indexOf(anchor, start + 1)
                if (at > start) at else null
            }
        val end = candidates.minOrNull() ?: src.length
        return src.substring(start, end)
    }
}
