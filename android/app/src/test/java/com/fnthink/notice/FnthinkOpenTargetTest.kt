package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

/**
 * 「点通知要跳去的那一条」那本交接账的判定（T83）。
 *
 * 这一页之所以值得在 JVM 上跑：它守的不是画面，而是**只交付一次**这件事 ——
 * 而这件事错的时候是静默的：
 *  ① 空白也照记 ⇒ Dart 那边要判"没记"与"记了个空串"两种空，漏一种就是
 *     "跳到历史页却展开了一条猜出来的行"（判据③明确不许猜）；
 *  ② 取走不清 ⇒ 每一次 `onResume` 都会再跳一次，表现是"这条详情关不掉"；
 *  ③ 排队不覆盖 ⇒ 用户连点两条通知，第二条早就把第一条划掉了，页面却逐条弹旧的那条。
 *
 * Intent 本身在 JVM 上造不出来（`getStringExtra` 是"not mocked"），所以这一族用例只测
 * 状态机的四条判据；"从 Intent 读、读罢就清"那一半由
 * [FnthinkNotificationOpenContractTest] 在源码层面钉住。
 */
class FnthinkOpenTargetTest {

    @Before
    fun clearBetweenCases() {
        // 这是进程内的单例：不清就会让上一条用例的余温决定下一条的结论。
        FnthinkOpenTarget.clear()
    }

    @Test
    fun `空白的那一枚根本不进账`() {
        FnthinkOpenTarget.record(null)
        FnthinkOpenTarget.record("")
        FnthinkOpenTarget.record("   ")
        assertNull("记了空串与没记必须是同一件事，否则 Dart 侧要判两种空", FnthinkOpenTarget.peek())
        assertNull(FnthinkOpenTarget.take())
    }

    @Test
    fun `take 是唯一出口：取走即清`() {
        FnthinkOpenTarget.record("m_0f48df96")
        assertEquals("第一次取到的是那一条", "m_0f48df96", FnthinkOpenTarget.take())
        assertNull(
            "第二次必须是空 —— 否则冷启动那一发与热恢复那一发会各跳一次，" +
                "而用户看到的就是同一条详情弹两遍",
            FnthinkOpenTarget.take(),
        )
    }

    @Test
    fun `连点两条通知：最新那一条赢`() {
        FnthinkOpenTarget.record("m_first")
        FnthinkOpenTarget.record("m_second")
        assertEquals(
            "覆盖而不是排队：第二条早就把第一条从通知栏划掉了",
            "m_second",
            FnthinkOpenTarget.take(),
        )
        assertNull("排队的另一半年就是留下一条点不开的旧消息", FnthinkOpenTarget.take())
    }

    @Test
    fun `peek 不兑现：读一眼不该把这次跳转花掉`() {
        FnthinkOpenTarget.record("m_look")
        assertEquals("m_look", FnthinkOpenTarget.peek())
        assertEquals("peek 之后仍能 take 到同一枚", "m_look", FnthinkOpenTarget.take())
    }

    @Test
    fun `记进去的是去掉两端空白的那一枚`() {
        FnthinkOpenTarget.record("  m_padded  ")
        assertEquals(
            "带着空白的 id 拿去和表里的 message_id 比，永远比不中 ⇒ 用户看到的会是" +
                "\"这一条已经不在历史里\"，而它明明在",
            "m_padded",
            FnthinkOpenTarget.take(),
        )
    }
}
