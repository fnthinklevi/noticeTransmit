package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * 「点开的那条配对链接」那本交接账的判定（#176 片4）。
 *
 * 这一族钉的是**只交付一次 + 只认这把前缀**，两件错了都是静默的：
 *  ① 不筛前缀 ⇒ 任何一次带 data 的 Intent（别的 App 分享、浏览器"用其他应用打开"）都会让
 *    幻念推送页凭空弹出一个配对输入层，而用户不知道那两格为什么已经填好了；
 *  ② 取走不清 ⇒ 冷启动那一发与热恢复那一发各弹一次，而链接里那枚口令是 singleUse 的；
 *  ③ 排队不覆盖 ⇒ 连点两条链接时，用户要配的是最后点的那台。
 *
 * `Intent` 在 JVM 上造不出来（`dataString` 是"not mocked"），所以这里只测状态机；
 * "从 Intent 读、读了就清 Intent"那一半由 [FnthinkPairLinkContractTest] 在源码层面钉住。
 */
class FnthinkPairLinkTest {

    @Before
    fun clearBetweenCases() {
        // 进程内的单例：不清就会让上一条用例的余温决定下一条的结论。
        FnthinkPairLink.clear()
    }

    @Test
    fun `不是这把前缀的一条都不进账`() {
        assertFalse(FnthinkPairLink.record(null))
        assertFalse(FnthinkPairLink.record(""))
        assertFalse(FnthinkPairLink.record("   "))
        assertFalse(FnthinkPairLink.record("https://push.fnthink.top/pair?to=A"))
        assertFalse(FnthinkPairLink.record("fnthink-push://pairArm?v=1"))
        assertNull("上面那些都不该进账 —— 否则随便一个带 data 的 Intent 都会弹配对输入层", FnthinkPairLink.peek())
    }

    @Test
    fun `记成了会回 true，MainActivity 据此才推那一发讯号`() {
        assertTrue(FnthinkPairLink.record(PREFIX + "v=1&to=AAAAAAAAAAAAAAAAAAAA&code=BBBB2345678901234567&level=L1"))
        assertEquals(
            "返回值是「要不要推」的唯一依据：不判它就成了「没记也推了」，而 Dart 那边取到 null 什么也不做",
            true,
            FnthinkPairLink.record(PREFIX + "v=1"),
        )
    }

    @Test
    fun `take 是唯一出口：取走即清`() {
        FnthinkPairLink.record(PREFIX + "v=1&to=A&code=B&level=L1")
        assertEquals(PREFIX + "v=1&to=A&code=B&level=L1", FnthinkPairLink.take())
        assertNull(
            "第二次必须是空 —— 否则冷启动那一发与热恢复那一发各弹一次输入层，" +
                "而那一枚口令按契约是一次性的",
            FnthinkPairLink.take(),
        )
    }

    @Test
    fun `后到的覆盖先到的，不排队`() {
        FnthinkPairLink.record(PREFIX + "v=1&to=OLD&code=X&level=L1")
        FnthinkPairLink.record(PREFIX + "v=1&to=NEW&code=Y&level=L1")
        assertTrue(
            "连点两条链接时用户要配的是最后点的那台；排队会让页面逐条弹旧的输入层",
            FnthinkPairLink.take()!!.contains("to=NEW"),
        )
    }

    @Test
    fun `前后空格不影响识别`() {
        val raw = "  " + PREFIX + "v=1&to=A&code=B&level=L1  "
        assertTrue(FnthinkPairLink.record(raw))
        assertEquals("记下来的是去过分隔空格的那一串", raw.trim(), FnthinkPairLink.peek())
    }

    private companion object {
        const val PREFIX = "fnthink-push://pair?"
    }
}
