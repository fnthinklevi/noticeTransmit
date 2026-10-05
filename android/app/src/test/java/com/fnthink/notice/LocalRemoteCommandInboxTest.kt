package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * 白名单通知触发那一路的**原生那一格**（交接 + 新鲜期 + 上限）。
 *
 * 钉的是三件 Dart 侧**看不到**的事：
 *  ① 前缀判定只认**开头**（会话通知里引用一条指令不该被执行）；
 *  ② 过期即作废，且判在**取**的那一侧（Dart 起来晚于通知时不能补执行）；
 *  ③ 取走即清（问一次不是看一眼，否则 drain 下一轮会把同一条执行两遍）。
 *
 * ⚠ 时刻一律**显式传** `nowMs`，不碰系统时钟：这些用例要能在"墙上时间不动"的前提下
 *   把 60 秒那一格推到过去，而真等 60 秒的用例永远不会被跑。
 */
class LocalRemoteCommandInboxTest {

    private val t0 = 1_700_000_000_000L
    private val fresh = 60_000L

    @Before
    fun setUp() {
        // 静态 object 的队列跨用例残留，测前清空（否则这条挂了下一条也挂，且症状难查）。
        while (LocalRemoteCommandInbox.take(t0) != null) { /* drain */ }
    }

    private fun offer(body: String, at: Long = t0) =
        LocalRemoteCommandInbox.offer(body, at)

    @Test
    fun offer_prefixAtStart_accepted() {
        assertTrue(offer("FRX1:L1 listener:start"))
        assertEquals(1, LocalRemoteCommandInbox.pendingCount())
    }

    @Test
    fun offer_prefixWithLeadingWhitespace_accepted() {
        // 通知正文常带前导空白（拼接模板/换行）—— trim 之后再判前缀。
        assertTrue(offer("  \n FRX1:L1 listener:stop"))
    }

    @Test
    fun offer_prefixAppearsMidText_rejected() {
        // ⚠ 这是这一格最要紧的一条：`contains` 会让聊天里**引用**一条指令就动手。
        assertFalse(offer("他说：FRX1:L1 listener:stop"))
        assertEquals(0, LocalRemoteCommandInbox.pendingCount())
    }

    @Test
    fun offer_otherPrefix_rejected() {
        // 回执信封 `FRR1:` 刻意与指令不同前缀；把它放进来是为了钉住"这两个不能混"。
        assertFalse(offer("FRR1:delivered L1 listener:stop"))
    }

    @Test
    fun take_returnsBody_thenEmpties() {
        offer("FRX1:L1 listener:start")
        assertEquals("FRX1:L1 listener:start", LocalRemoteCommandInbox.take(t0 + 1)?.body)
        assertNull("问一次即清：再问一次必须是 null", LocalRemoteCommandInbox.take(t0 + 1))
    }

    @Test
    fun take_staleEntry_droppedNotReturned() {
        offer("FRX1:L1 listener:start", at = t0)
        assertNull(
            "过了新鲜期的那一条必须作废 —— 那段时间里用户没看到任何横幅，也没人能按下撤销",
            LocalRemoteCommandInbox.take(t0 + fresh + 1)
        )
        assertEquals(0, LocalRemoteCommandInbox.pendingCount())
    }

    @Test
    fun take_justInsideWindow_returned() {
        offer("FRX1:L1 listener:start", at = t0)
        assertNotNull("边界上之内仍算新鲜", LocalRemoteCommandInbox.take(t0 + fresh))
    }

    @Test
    fun take_staleBehindFresh_oneDroppedOtherReturned() {
        offer("FRX1:L1 listener:start", at = t0)
        offer("FRX1:L1 listener:stop", at = t0 + 30_000)
        // 取的时刻要让**队首**过期而第二条仍在窗口内（65s / 35s，窗口 60s）——
        // 这正是"队首过期"与"整堆作废"两种实现分道的地方。
        val got = LocalRemoteCommandInbox.take(t0 + 65_000)
        assertEquals("FRX1:L1 listener:stop", got?.body)
        assertEquals(0, LocalRemoteCommandInbox.pendingCount())
    }

    @Test
    fun take_newerThanNow_notDropped() {
        // 时钟被用户往回拨过：atMs 大于 nowMs 时差值为负，不该被判成过期。
        offer("FRX1:L1 listener:start", at = t0 + 120_000)
        assertNotNull(LocalRemoteCommandInbox.take(t0 + 1)?.body)
    }

    @Test
    fun take_outOfOrderArrival_staleStillDropped() {
        // ⚠ 单调假设的反例：系统时间往回拨，后到的那条反而更"旧"。
        //   前缀扫描会在这里漏掉第二条，于是**过期那条**在下一轮被当成新鲜的取走执行。
        offer("FRX1:L1 listener:start", at = t0 + 60_000)
        offer("FRX1:L1 listener:stop", at = t0)
        assertEquals(
            "先取到的必须是新鲜那条（队首）",
            "FRX1:L1 listener:start",
            LocalRemoteCommandInbox.take(t0 + 61_000)?.body
        )
        assertNull(
            "过期那条在同一次取里就被丢掉，不留到下一轮再执行",
            LocalRemoteCommandInbox.take(t0 + 61_000)
        )
    }

    @Test
    fun offer_overCapacity_dropsOldest() {
        for (i in 1..8) offer("FRX1:L1 listener:start#$i", at = t0 + i)
        assertEquals(8, LocalRemoteCommandInbox.pendingCount())
        offer("FRX1:L1 listener:start#9", at = t0 + 9)
        assertEquals("满了丢最老的那条（它最可能已过期），总数不涨", 8, LocalRemoteCommandInbox.pendingCount())
        val first = LocalRemoteCommandInbox.take(t0 + 9)
        assertEquals("FRX1:L1 listener:start#2", first?.body)
    }
}
