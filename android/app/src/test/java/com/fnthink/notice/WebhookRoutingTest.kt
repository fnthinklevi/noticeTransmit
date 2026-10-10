package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * T132 片1：主备判据对**三条链**都成立（以前只有通知转发那一条走判据）。
 *
 * ## 维护者要求（三个感叹号那一条）
 * 「默认只发主通道，主通道完全不可用才切备通道，不参与的通道永远不参与推送。」
 *
 * ## 现读到的三处不一致（本片的靶子）
 * | # | 位置 | 破的是哪一句 |
 * |---|---|---|
 * | ① | `SmsDispatcher` / `PhoneCallReceiver` 直接遍历全量 webhook | "只发主"——主＋备同发；且不读可用性、**不记失败** ⇒ "主完全不可用"这个判断对这两条链永不成立 |
 * | ③ | `ChannelRouting.route()` 那条兜底（主备都判成不可用 ⇒ 照推全部候选） | 推了却不标 `viaBackup` ⇒ 历史里写着"走的主通道"，而那次谁都不可用 |
 *
 * （②「设备状态快照按 peer 名单全发、不看角色」是**片2**：那条要先把 Dart 侧的选路并回原生
 * 那一个作者，不能在 Dart 里抄一份 `ChannelRouting` —— 那是本仓反复在治的第二份实现。）
 *
 * ## 为什么判据仍然只有一份
 * [WebhookRouting.select] 里只有 `ChannelRouting.route` 一个判断，没有第二个 `filter { role ... }`。
 * 本片新增的是"把这一份接到短信/来电两条链上"的装配，不是第二条判据。
 */
class WebhookRoutingTest {

    private fun cfg(
        id: String,
        role: ChannelRole,
        ok: Boolean,
        avail: MutableSet<String>,
    ): ConfigManager.WebhookChannelConfig {
        if (ok) avail.add(id)
        return ConfigManager.WebhookChannelConfig(
            url = "https://example.invalid/$id",
            id = id,
            secret = null,
            type = WebhookPayloadBuilder.WebhookType.GENERIC,
            role = role,
        )
    }

    private fun select(
        specs: List<Triple<String, ChannelRole, Boolean>>,
        backupEngaged: Boolean = false,
    ): Pair<WebhookRouting.Selection, Set<String>> {
        val avail = HashSet<String>()
        val configs = specs.map { (id, role, ok) -> cfg(id, role, ok, avail) }
        val s = WebhookRouting.select(configs, available = { id -> id in avail }, backupEngaged)
        return s to avail
    }

    private fun ids(s: WebhookRouting.Selection) = s.configs.map { it.id }

    // ── 判据（与 ChannelRoutingDecisionTest 同规，但对象是"接上短信/来电链之后的装配"）──

    @Test
    fun `有可用主通道时只推主，备用一把都不发`() {
        val (s, _) = select(
            listOf(
                Triple("p1", ChannelRole.PRIMARY, true),
                Triple("b1", ChannelRole.BACKUP, true),
            ),
        )
        assertEquals(listOf("p1"), ids(s))
        assertFalse("只推主时不许标备用", s.viaBackup)
        assertFalse(s.engagedBackup)
    }

    @Test
    fun `主全不可用且有可用备用时切备，并标也锁`() {
        val (s, _) = select(
            listOf(
                Triple("p1", ChannelRole.PRIMARY, false),
                Triple("b1", ChannelRole.BACKUP, true),
            ),
        )
        assertEquals(listOf("b1"), ids(s))
        assertTrue(s.viaBackup)
        assertTrue(s.engagedBackup)
    }

    @Test
    fun `锁存期间优先备用，绝不空转`() {
        val (s, _) = select(
            listOf(
                Triple("p1", ChannelRole.PRIMARY, true),
                Triple("b1", ChannelRole.BACKUP, true),
            ),
            backupEngaged = true,
        )
        assertEquals(listOf("b1"), ids(s))
        assertTrue("锁存期推的是备用，标记必须跟着走，否则历史会说谎", s.viaBackup)
    }

    @Test
    fun `兜底那一档照推全部候选，标备用但不锁存`() {
        // ③ 的靶子：这一档以前 viaBackup=false（"推了没标"）。标它 = 历史里那句"走了备用"是真的；
        // 不锁存 = 一次"谁都判成不可用"不该把这台设备永久按在备用档上。
        val (s, _) = select(
            listOf(
                Triple("p1", ChannelRole.PRIMARY, false),
                Triple("b1", ChannelRole.BACKUP, false),
            ),
        )
        assertEquals(listOf("p1", "b1"), ids(s))
        assertTrue("T132：兜底推了全部候选却不标 viaBackup ⇒ 历史写着走主通道，而那次主并不可用", s.viaBackup)
        assertFalse("但这一档不构成切换事实，不许写锁存", s.engagedBackup)
    }

    @Test
    fun `压根没配主通道时推可用备用，不算降级也不标`() {
        val (s, _) = select(listOf(Triple("b1", ChannelRole.BACKUP, true)))
        assertEquals(listOf("b1"), ids(s))
        assertFalse(s.viaBackup)
        assertFalse(s.engagedBackup)
    }

    @Test
    fun `不参与那一档任何一条链都不许看见它`() {
        val (s, _) = select(
            listOf(
                Triple("p1", ChannelRole.PRIMARY, true),
                Triple("n1", ChannelRole.NONE, true),
                Triple("b1", ChannelRole.BACKUP, true),
            ),
        )
        assertEquals(listOf("p1"), ids(s))
        assertFalse(
            "NONE 出现在结果里 = 用户在通道页明明选了「不参与」，短信却还往它推",
            ids(s).contains("n1"),
        )
    }

    // ── 形状：短信与来电两条链不许再各走各的 ──

    private fun strip(src: String): String =
        src
            .replace(Regex("(?s)/\\*.*?\\*/"), "")
            .lines()
            .filterNot { it.trimStart().startsWith("//") }
            .joinToString("\n")

    private fun appFile(rel: String): java.io.File {
        var dir = java.io.File("").absoluteFile
        while (true) {
            val f = java.io.File(dir, "android/app/$rel")
            if (f.exists()) return f
            dir = dir.parentFile ?: break
        }
        throw AssertionError("找不到 $rel")
    }

    private fun source(rel: String): String = strip(appFile(rel).readText())

    @Test
    fun `短信与来电都改走那一个决策，不许再遍历全量配置`() {
        for (rel in listOf(
            "src/main/kotlin/com/fnthink/notice/SmsDispatcher.kt",
            "src/main/kotlin/com/fnthink/notice/PhoneCallReceiver.kt",
        )) {
            val src = source(rel)
            assertFalse(
                "$rel 还在直接遍历 getWebhookChannelConfigs() 的全量结果 ⇒ 主＋备同发（T132）",
                src.contains("for (cfg in channelConfigs)"),
            )
            assertTrue(
                "$rel 没接上 WebhookRouting ⇒ 这条链不受主备判据约束",
                src.contains("WebhookRouting.routeWebhooks(context, channelConfigs)"),
            )
            assertTrue("$rel 没用路由出来的那一把", src.contains("routed.configs"))
        }
    }

    @Test
    fun `两条链把失败记进同一张可用性表并把备用标记传到底`() {
        for (rel in listOf(
            "src/main/kotlin/com/fnthink/notice/SmsDispatcher.kt",
            "src/main/kotlin/com/fnthink/notice/PhoneCallReceiver.kt",
        )) {
            val src = source(rel)
            assertTrue(
                "$rel 不记失败 ⇒ 「主通道完全不可用」对它永不成立，判据第 3 条形同虚设（T132）",
                src.contains("ChannelAvailability.noteResult("),
            )
            assertTrue(
                "$rel 的送达回传没带 viaBackup ⇒ 历史页看不见「本次走了备用」",
                src.contains("viaBackup = viaBackup,"),
            )
        }
    }

    @Test
    fun `转发链的备用标记取本轮事实，不取锁存位`() {
        val src = source("src/main/kotlin/com/fnthink/notice/NotificationMonitorService.kt")
        assertTrue(
            "viaBackup 又指回 engagedBackup ⇒ 兜底那一档重新变成「推了没标」（T132 ③）",
            src.contains("viaBackup = decision.viaBackup,"),
        )
        assertFalse(src.contains("viaBackup = decision.engagedBackup,"))
    }
}
