package com.fnthink.notice

import com.fnthink.notice.ChannelAvailability.HealthRecord
import com.fnthink.notice.ChannelAvailability.Reason
import com.fnthink.notice.ChannelRouting.Member
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
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
    fun `锁存期间主通道一次成功读数不切回`() {
        // 这条钉的是"一次就切"绝不允许回来：老写法根本不切（用户手动），
        // 而一次就切比老写法更吵 —— 用户至少只手动点过一次。
        val d = ChannelRouting.route(
            listOf(
                m("webhook:wh-1", ChannelRole.PRIMARY, true),
                m("app:app-1", ChannelRole.BACKUP, true),
            ),
            backupEngaged = true,
        )
        assertEquals(listOf("app:app-1"), d.keys)
        assertTrue(d.engagedBackup)
        assertFalse("没有探测读数就没有切回这回事", d.releasedBackup)
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

    // ── 「未设置」：新建通道的起点（1.5.76 反馈 #2）──────────────────────
    // 这条改动唯一会丢通知的方式，是把 UNSET 处理成"跟 none 一样被摘掉"或"谁都不推"。
    // 下面四条把它的三种落点全部钉住，`route()` 因此不需要为 UNSET 改一行代码。

    @Test
    fun `有可用主通道时，未设置的通道不跟着全量推`() {
        val d = ChannelRouting.route(
            listOf(
                m("webhook:wh-1", ChannelRole.PRIMARY, true),
                m("app:app-new", ChannelRole.UNSET, true),
            ),
            backupEngaged = false,
        )
        assertEquals(
            "新建那条不再默认算主 ⇒ 同一条通知不该再重复推两次",
            listOf("webhook:wh-1"),
            d.keys,
        )
        assertFalse(d.engagedBackup)
    }

    @Test
    fun `一条主都没设时，未设置的通道照推，绝不空转`() {
        val d = ChannelRouting.route(
            listOf(
                m("app:app-1", ChannelRole.UNSET, true),
                m("webhook:wh-2", ChannelRole.UNSET, true),
            ),
            backupEngaged = false,
        )
        assertEquals(
            "只有未设置的通道时一条都不发 = 静默丢失，这是最坏结果",
            listOf("app:app-1", "webhook:wh-2"),
            d.keys,
        )
        assertFalse("没人设主不构成「降级」，不该锁存备用模式", d.engagedBackup)
    }

    @Test
    fun `主与备都不可用时，未设置的通道随兜底一起接住`() {
        val d = ChannelRouting.route(
            listOf(
                m("webhook:wh-1", ChannelRole.PRIMARY, false),
                m("email:e-1", ChannelRole.BACKUP, false),
                m("app:app-new", ChannelRole.UNSET, true),
            ),
            backupEngaged = false,
        )
        assertTrue(
            "刚加的通道不该因为「还没设过角色」而在主备都不可用时被丢掉",
            d.keys.contains("app:app-new"),
        )
    }

    @Test
    fun `锁存期间未设置的通道既不被推，也不把锁存解除`() {
        val d = ChannelRouting.route(
            listOf(
                m("webhook:wh-1", ChannelRole.PRIMARY, true),
                m("app:app-new", ChannelRole.UNSET, true),
            ),
            backupEngaged = true,
        )
        assertEquals(listOf("webhook:wh-1"), d.keys)
        assertTrue("锁存只由调用方解除：本函数在锁存期绝不自己切回", d.engagedBackup)
    }

    // ── 自动切回（T135 ②）──────────────────────────────────────────────
    // 这一族只有一个危险：抖动。所以"该切回去了"这件事要同时满足三件，
    // 每一件一条用例 —— 合成一个条件就会有一种情况悄悄失效：
    //  ① 那份探测读数**新鲜**（过期读数证明不了现在通）
    //  ② 它是**降级之后**写的（降级之前就已经连着成功过，不是修好的证据）
    //  ③ 它自己是**连续第 N 次**成功
    // 而 N 这个数不写在下面任何一条用例里（抄一份就会在阈值改动时假装还成立）：
    // 每条都用 `RECOVERY_SUCCESS_COUNT` 表达"差一次 / 刚好 / 多一次"。

    /** 一小时前降级的 */
    private val latchAt = now - 3_600_000L

    /** 攒了 [okN] 次连续成功探测的那条主通道（默认：新鲜、降级之后写的） */
    private fun primaryRecovered(
        okN: Int,
        probedAt: Long = now - 60_000L,
        fresh: Boolean = true,
    ) = Member(
        key = "webhook:wh-1",
        role = ChannelRole.PRIMARY,
        available = true,
        recovery = ChannelRouting.Recovery(fresh, probedAt, okN),
    )

    private val backupOk = m("app:app-1", ChannelRole.BACKUP, true)

    @Test
    fun `锁存期：攒够连续成功探测就自动切回，切回那一轮推主通道且不标备用`() {
        val need = ChannelRouting.RECOVERY_SUCCESS_COUNT
        val d = ChannelRouting.route(
            listOf(primaryRecovered(need), backupOk),
            backupEngaged = true,
            engagedAtMs = latchAt,
        )
        assertTrue("证据够了就该把锁存交出去", d.releasedBackup)
        assertFalse("切回之后这台不再以备用为准", d.engagedBackup)
        assertEquals(listOf("webhook:wh-1"), d.keys)
        assertFalse("历史里那句「本次走了备用」必须跟着消失", d.viaBackup)
    }

    @Test
    fun `锁存期：差一次成功就不切（阈值前后一格分明）`() {
        val need = ChannelRouting.RECOVERY_SUCCESS_COUNT
        val d = ChannelRouting.route(
            listOf(primaryRecovered(need - 1), backupOk),
            backupEngaged = true,
            engagedAtMs = latchAt,
        )
        assertFalse("证据没攒够就还锁着", d.releasedBackup)
        assertEquals(listOf("app:app-1"), d.keys)
        assertTrue(d.engagedBackup)
    }

    @Test
    fun `锁存期：降级之前就已经连着的成功不算证据`() {
        // 这条是"刚降级就立刻切回去"那件事的唯一拦网：主通道时好时坏时，
        // 降级那一刻手上往往已经挂着三五次成功了 —— 那说的是降级**之前**的事。
        val need = ChannelRouting.RECOVERY_SUCCESS_COUNT
        val d = ChannelRouting.route(
            listOf(primaryRecovered(need, probedAt = latchAt - 60_000L), backupOk),
            backupEngaged = true,
            engagedAtMs = latchAt,
        )
        assertFalse(d.releasedBackup)
        assertEquals(listOf("app:app-1"), d.keys)
    }

    @Test
    fun `锁存期：过期的成功读数不算证据`() {
        val need = ChannelRouting.RECOVERY_SUCCESS_COUNT
        val d = ChannelRouting.route(
            listOf(primaryRecovered(need, fresh = false), backupOk),
            backupEngaged = true,
            engagedAtMs = latchAt,
        )
        assertFalse(d.releasedBackup)
    }

    @Test
    fun `锁存期：备用那一档攒再多成功也不把锁存解除`() {
        // 切回判据只管主通道：备用的成功是"降级之后一直在用"的常态，
        // 拿它当切回理由等于把这台设备从"能用的一侧"拽回"刚坏过的一侧"。
        val need = ChannelRouting.RECOVERY_SUCCESS_COUNT
        val d = ChannelRouting.route(
            listOf(
                m("webhook:wh-1", ChannelRole.PRIMARY, false),
                Member(
                    key = "app:app-1",
                    role = ChannelRole.BACKUP,
                    available = true,
                    recovery = ChannelRouting.Recovery(true, now - 60_000L, need + 2),
                ),
            ),
            backupEngaged = true,
            engagedAtMs = latchAt,
        )
        assertFalse(d.releasedBackup)
        assertEquals(listOf("app:app-1"), d.keys)
    }

    @Test
    fun `没有锁存时不产出切回（不许有无中生有的那一次）`() {
        val need = ChannelRouting.RECOVERY_SUCCESS_COUNT
        val d = ChannelRouting.route(
            listOf(primaryRecovered(need), backupOk),
            backupEngaged = false,
        )
        assertFalse("本来就没锁，谈不上解除", d.releasedBackup)
        assertEquals("没锁存时那一轮走的就是可用主通道那一档", listOf("webhook:wh-1"), d.keys)
    }

    @Test
    fun `切回的阈值与降级的阈值对称（出去与回来要一样多的证据）`() {
        // 不对称 = 抖动的那个缺口：降级要三次失败，切回只要一次成功的话，
        // 一条时好时坏的主通道就会推着用户在主备之间反复收。
        assertEquals(
            "两个阈值漂开的那一刻，防抖就没了",
            ChannelAvailability.FAILURE_THRESHOLD.toLong(),
            ChannelRouting.RECOVERY_SUCCESS_COUNT.toLong(),
        )
    }

    // ── 「主不可用时自动切备」那枚开关（T135 ③，默认开）──────────────────
    // 拍板的形状是「仍按当轮判据推，但不锁存」，所以这一档有三件事必须成立：
    // 绝不写 backup_engaged、已经锁着的那份要说解就解、兜底那一档一条都不能少。

    @Test
    fun `关掉自动切备：当轮仍推可用备用，但绝不锁存`() {
        val d = ChannelRouting.route(
            listOf(
                m("webhook:wh-1", ChannelRole.PRIMARY, false),
                backupOk,
            ),
            backupEngaged = false,
            autoBackup = false,
        )
        assertEquals(listOf("app:app-1"), d.keys)
        assertFalse("关掉的那一条绝不写 backup_engaged", d.engagedBackup)
        assertTrue("那一轮推的确实不是主档 ⇒ 送达记录该说真话", d.viaBackup)
    }

    @Test
    fun `关掉自动切备时，已经锁着的那份当轮就解除`() {
        // 不解除的话：路由已经不认这份锁存了，而状态页还写着"已切到备用"——
        // 屏幕上报的是这台设备已经不做的主张。
        val d = ChannelRouting.route(
            listOf(
                m("webhook:wh-1", ChannelRole.PRIMARY, true),
                backupOk,
            ),
            backupEngaged = true,
            autoBackup = false,
        )
        assertTrue(d.releasedBackup)
        assertFalse(d.engagedBackup)
        assertEquals(listOf("webhook:wh-1"), d.keys)
    }

    @Test
    fun `关掉自动切备也不丢通知：主备都不可用时照推全部候选`() {
        val d = ChannelRouting.route(
            listOf(
                m("webhook:wh-1", ChannelRole.PRIMARY, false),
                m("app:app-1", ChannelRole.BACKUP, false),
            ),
            backupEngaged = false,
            autoBackup = false,
        )
        assertEquals(listOf("webhook:wh-1", "app:app-1"), d.keys)
        assertFalse(d.engagedBackup)
        assertTrue(d.viaBackup)
    }

    @Test
    fun `关掉自动切备时不锁存也不产出切回（没锁过就谈不上解除）`() {
        val need = ChannelRouting.RECOVERY_SUCCESS_COUNT
        val d = ChannelRouting.route(
            listOf(primaryRecovered(need), backupOk),
            backupEngaged = false,
            autoBackup = false,
        )
        assertFalse(d.releasedBackup)
        assertFalse(d.engagedBackup)
    }

    @Test
    fun `锁存期攒够证据之前，任何一档能用就用（绝不空转）`() {
        val need = ChannelRouting.RECOVERY_SUCCESS_COUNT
        val noBackup = m("app:app-1", ChannelRole.BACKUP, false)
        val d = ChannelRouting.route(
            listOf(primaryRecovered(need - 1), noBackup),
            backupEngaged = true,
            engagedAtMs = latchAt,
        )
        assertFalse(d.releasedBackup)
        assertEquals(
            "备用不可用而主通道证据还不够 ⇒ 退回可用主通道，一条不推是最坏结果",
            listOf("webhook:wh-1"),
            d.keys,
        )
    }

    // ── 两把尺子的差（T135 那条死锁的唯一解）───────────────────────────────

    @Test
    fun `发送侧的失败计数压得住 available，压不掉切回的证据`() {
        val r = ChannelAvailability.readOf(
            fails = ChannelAvailability.FAILURE_THRESHOLD,
            record = HealthRecord(reachable = true, probedAt = now - 60_000L, okSuccesses = 3),
            nowMs = now,
        )
        assertFalse("计数还在 ⇒ 这一轮仍算不可用（降级那一侧的判据不许松）", r.available)
        assertTrue(
            "探测那一条尺子仍要说得出「这份读数是通的」——锁存期主通道不再被发送，" +
                "计数永远不会归零，跟着压掉就等于「锁上之后没有自动出口」",
            r.recovery!!.fresh,
        )
        assertEquals(3L, r.recovery!!.okSuccesses.toLong())
        assertEquals(now - 60_000L, r.recovery!!.probedAt)
    }

    @Test
    fun `没有探测记录时 recovery 是空，不是「零次成功」`() {
        val r = ChannelAvailability.readOf(fails = 0, record = null, nowMs = now)
        assertFalse(r.available)
        assertNull("凭空造出一份 Recovery 就等于替「从没探测过」编一个时刻", r.recovery)
    }

    // ── 落盘裁决（BackupModeStore.latchChange）─────────────────────────────

    private fun decision(engaged: Boolean = false, released: Boolean = false) =
        ChannelRouting.Decision(listOf("webhook:wh-1"), engaged, releasedBackup = released)

    @Test
    fun `真降级且还没锁 ⇒ 写锁存`() {
        assertEquals(
            BackupModeStore.LatchChange.Engage,
            BackupModeStore.latchChange(engaged = false, decision(engaged = true)),
        )
    }

    @Test
    fun `锁存期每轮都报 engagedBackup，不许每轮重复写盘`() {
        // 表现层面这条不成立就是"每条通知一次 prefs 写"，而 release 那一发更坏：
        // `backup_released_at` 会被一路刷成现在，用户读到的"什么时候回来的"永远是"刚刚"。
        assertEquals(
            BackupModeStore.LatchChange.None,
            BackupModeStore.latchChange(engaged = true, decision(engaged = true)),
        )
        assertEquals(
            BackupModeStore.LatchChange.None,
            BackupModeStore.latchChange(engaged = false, decision()),
        )
    }

    @Test
    fun `证据够了且确实锁着 ⇒ 解除；没锁着时不产出无中生有的解除`() {
        assertEquals(
            BackupModeStore.LatchChange.Release,
            BackupModeStore.latchChange(engaged = true, decision(released = true)),
        )
        assertEquals(
            BackupModeStore.LatchChange.None,
            BackupModeStore.latchChange(engaged = false, decision(released = true)),
        )
    }
}
