package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * T245 电源态取证位的纯判据测试。
 *
 * 背景：E3 真机实证（2026-11-07）——NETWORK_FAIL 的日志形态无法区分
 * 「教科书 Doze 挂起 / Flyme 叠加限制 / 普通网络抖动」，只能靠猜。失败消息追加
 * 电源态标签后，真机一条失败即可定位归属。
 */
class PowerStateTagsTest {

    @Test
    fun cleanState_emptySuffix() {
        // 亮屏、已豁免：一个标签都不附（普通网络抖动）
        assertEquals("", PowerStateTags.suffix(deviceIdle = false, batteryExempt = true))
    }

    @Test
    fun deepIdle_tagged() {
        assertEquals("[idle]", PowerStateTags.suffix(deviceIdle = true, batteryExempt = true))
    }

    @Test
    fun noExempt_tagged() {
        assertEquals("[no-exempt]", PowerStateTags.suffix(deviceIdle = false, batteryExempt = false))
    }

    @Test
    fun textbookDoze_combinesTags() {
        // 深睡 + 未豁免 = 教科书 Doze 形态（E3 里 devtest 的那个窗口）
        assertEquals(
            "[idle][no-exempt]",
            PowerStateTags.suffix(deviceIdle = true, batteryExempt = false),
        )
    }
}
