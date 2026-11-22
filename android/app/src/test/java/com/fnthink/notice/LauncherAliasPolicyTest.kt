package com.fnthink.notice

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * P1-2 后续：首启别名切换不能把任务送回桌面。
 *
 * 判据本身是纯字符串，行为测试直接穷举三种形状；MainActivity 的装配由
 * [LauncherAliasSwitchContractTest] 钉。
 */
class LauncherAliasPolicyTest {

    private val zh = "com.fnthink.notice/.LauncherDefaultZh"
    private val en = "com.fnthink.notice/.LauncherDefaultEn"

    @Test
    fun `不是从 alias 启动时可以直接全量收敛`() {
        assertFalse(LauncherAliasPolicy.mustDeferDisable(null, en))
    }

    @Test
    fun `目标与启动组件相同时可以直接全量收敛`() {
        assertFalse(LauncherAliasPolicy.mustDeferDisable(en, en))
    }

    @Test
    fun `从旧 alias 启动时要延迟禁用`() {
        assertTrue(LauncherAliasPolicy.mustDeferDisable(zh, en))
        assertTrue(LauncherAliasPolicy.mustDeferDisable(en, zh))
    }
}
