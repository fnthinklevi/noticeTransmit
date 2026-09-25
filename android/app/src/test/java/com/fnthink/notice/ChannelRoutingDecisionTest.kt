package com.fnthink.notice

import com.fnthink.notice.ChannelAvailability.HealthRecord
import com.fnthink.notice.ChannelAvailability.Reason
import com.fnthink.notice.ChannelRouting.Member
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * T12 B 的路由与可用性判定（纯函数，JVM 直测）。
 *
 * 这里锁的是"通知到底发给谁"，错一格的后果是用户静默收不到通知，
 * 所以每条规则都要有一条用例，尤其是**兜底方向**：判据说"全部不可用"时
 * 也绝不能返回空集合（那等于把通知丢掉）。
 */
class ChannelRoutingDecisionTest {

    private val now = 1_700_000_000_000L
    private val fresh = HealthRecord(reachable = true, probedAt = now - 60_000L)
    private val staleOk = HealthRecord(reachable = true, probedAt = now - 7L * 60 * 60 * 1000)
    private val failed = HealthRecord(reachable = false, probedAt = now - 60_000L)

    private fun m(key: String, role: ChannelRole, ok: Boolean) = Member(key, role, ok)

    // ── 可用性判定 ────────────────────────────────────────────────────

    @Test
    fun `可用性：只有新鲜成功算可用`() {
        assertEquals(Reason.FRESH_SUCCESS, ChannelAvailability.reasonOf(0, fresh, now))
        assertEquals(Reason.FRESH_FAILURE, ChannelAvailability.reasonOf(0, failed, now))
        // 旧的成功证明不了现在通 —— 但也不能当失败，判据里它是"不可用"的一档
        assertEquals(Reason.STALE_SUCCESS, ChannelAvailability.reasonOf(0, staleOk, now))
        assertEquals(Reason.NEVER_PROBED, ChannelAvailability.reasonOf(0, null, now))
        assertFalse(Reason.STALE_SUCCESS.isAvailable)
        assertTrue(Reason.FRESH_SUCCESS.isAvailable)
    }

    @Test
    fun `连续失败优先于成功记录，阈值前后一格分明`() {
        val t = ChannelAvailability.FAILURE_THRESHOLD
        assertEquals(Reason.FRESH_SUCCESS, ChannelAvailability.reasonOf(t - 1, fresh, now))
        assertEquals(Reason.CONSECUTIVE_FAILURES, ChannelAvailability.reasonOf(t, fresh, now))
        // 失败计数压过"根本没记录"，方向必须是"更保守地认为不可用"
        assertEquals(Reason.CONSECUTIVE_FAILURES, ChannelAvailability.reasonOf(t + 5, null, now))
    }

    // ── 路由 ─────────────────────────────────────────────────────────

    @Test
    fun `有可用主通道时只推主通道`() {
        val d = ChannelRouting.route(
            listOf(
                m("webhook:wh-1", ChannelRole.PRIMARY, true),
                m("webhook:wh-2", ChannelRole.PRIMARY, false),
                m("app:app-1", ChannelRole.BACKUP, true),
            ),
            backupEngaged = false,
        )
        assertEquals(listOf("webhook:wh-1"), d.keys)
        assertFalse("没降级就不该锁存", d.engagedBackup)
    }

    @Test
    fun `主通道全不可用且有可用备用时降级并锁存`() {
        val d = ChannelRouting.route(
            listOf(
                m("webhook:wh-1", ChannelRole.PRIMARY, false),
                m("app:app-1", ChannelRole.BACKUP, true),
            ),
            backupEngaged = false,
        )
        assertEquals(listOf("app:app-1"), d.keys)
        assertTrue("真降级要锁存（不自动切回，防抖动）", d.engagedBackup)
    }

    @Test
    fun `锁存期间主通道恢复也不自动切回`() {
        val d = ChannelRouting.route(
            listOf(
                m("webhook:wh-1", ChannelRole.PRIMARY, true),
                m("app:app-1", ChannelRole.BACKUP, true),
            ),
            backupEngaged = true,
        )
        assertEquals(listOf("app:app-1"), d.keys)
        assertTrue(d.engagedBackup)
    }

    @Test
    fun `锁存期间备用全不可用则退回可用主通道，绝不空转`() {
        val d = ChannelRouting.route(
            listOf(
                m("webhook:wh-1", ChannelRole.PRIMARY, true),
                m("app:app-1", ChannelRole.BACKUP, false),
            ),
            backupEngaged = true,
        )
        assertEquals(listOf("webhook:wh-1"), d.keys)

        // 两边都不行 → 全推（不静默丢失优先于严格判据）
        val worst = ChannelRouting.route(
            listOf(
                m("webhook:wh-1", ChannelRole.PRIMARY, false),
                m("app:app-1", ChannelRole.BACKUP, false),
            ),
            backupEngaged = true,
        )
        assertEquals(listOf("webhook:wh-1", "app:app-1"), worst.keys)
    }

    @Test
    fun `没配主通道不算降级，不锁存`() {
        val d = ChannelRouting.route(
            listOf(
                m("app:app-1", ChannelRole.BACKUP, true),
                m("webhook:wh-9", ChannelRole.NONE, true),
            ),
            backupEngaged = false,
        )
        assertEquals(listOf("app:app-1"), d.keys)
        assertFalse("全设成备用的人不该被记成「已切到备用」", d.engagedBackup)
    }

    @Test
    fun `新装后谁都没探测过时照推，一条都不能少`() {
        // 判据会把"从未探测"归为不可用；此时若严格照判据就是一条都不推 = 丢通知
        val d = ChannelRouting.route(
            listOf(
                m("webhook:wh-1", ChannelRole.PRIMARY, false),
                m("app:app-1", ChannelRole.BACKUP, false),
            ),
            backupEngaged = false,
        )
        assertEquals(listOf("webhook:wh-1", "app:app-1"), d.keys)
        assertFalse(d.engagedBackup)
    }

    @Test
    fun `不参与推送的通道任何一档都不出现`() {
        val d = ChannelRouting.route(
            listOf(
                m("webhook:wh-1", ChannelRole.NONE, true),
                m("webhook:wh-2", ChannelRole.PRIMARY, true),
            ),
            backupEngaged = false,
        )
        assertFalse(d.keys.contains("webhook:wh-1"))
        assertEquals(listOf("webhook:wh-2"), d.keys)

        val allNone = ChannelRouting.route(
            listOf(m("webhook:wh-1", ChannelRole.NONE, true)),
            backupEngaged = false,
        )
        assertTrue("全都不参与时返回空是正确行为（用户就是这么设的）", allNone.keys.isEmpty())
    }
}
