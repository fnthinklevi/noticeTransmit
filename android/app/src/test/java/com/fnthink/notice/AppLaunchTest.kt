package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 「打开本机登记过的一条入口」（T124 片B 的 `app:launch`）里**能在 JVM 上断的那一半**：解析。
 *
 * 为什么这一半要紧：真机上"打开得开不开"一眼看得见，而**解析错了**（把一条不该认的串认成
 * 目标）的后果是"点下去系统不认"—— 一条已经执行过的指令换来一个什么都没发生。
 * 维护者裁定过合法路只有两条（App 自己公开的 deeplink / 本机登记的组件名），这组用例
 * 就是把"只有这两条"钉在解析层。
 */
class AppLaunchTest {

    @Test
    fun `组件形态 pkg 斜杠 cls 认得出来`() {
        val t = AppLaunch.parseTarget("com.tencent.mm/.ui.LauncherUI")
        assertTrue(t is AppLaunch.Target.Component)
        assertEquals("com.tencent.mm", (t as AppLaunch.Target.Component).pkg)
        assertEquals(".ui.LauncherUI", t.cls)
    }

    @Test
    fun `URI 形态要带 scheme（冒号在前）`() {
        val t = AppLaunch.parseTarget("weixin://dl/scan")
        assertTrue(t is AppLaunch.Target.Uri)
        assertEquals("weixin://dl/scan", (t as AppLaunch.Target.Uri).uri)
    }

    @Test
    fun `分不清的一律回 null（不猜、不补全）`() {
        assertNull("空串", AppLaunch.parseTarget(""))
        assertNull("裸包名（没有斜杠也没有 scheme）", AppLaunch.parseTarget("com.tencent.mm"))
        assertNull("没有点的包名", AppLaunch.parseTarget("weixin/Scan"))
        assertNull("斜杠在头", AppLaunch.parseTarget("/Scan"))
        assertNull("斜杠后为空", AppLaunch.parseTarget("com.tencent.mm/"))
        assertNull("带空白", AppLaunch.parseTarget("com.tencent.mm / .A"))
        assertNull("控制字符", AppLaunch.parseTarget("com.tencent.mm/.A\nb"))
        assertNull("数字开头的 scheme", AppLaunch.parseTarget("1abc://x"))
    }

    @Test
    fun `超长一律不认（总得有个头）`() {
        val long = "https://example.com/" + "a".repeat(AppLaunch.MAX_TARGET_CHARS)
        assertNull(AppLaunch.parseTarget(long))
    }
}
