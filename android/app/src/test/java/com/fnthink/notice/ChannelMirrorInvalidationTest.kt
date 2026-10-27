package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ChannelMirrorInvalidationTest {
    @Test
    fun `成功时先阻断再清理验证最后撤闸`() {
        val events = mutableListOf<String>()

        val result = ChannelMirrorInvalidation.run(
            setPending = { pending -> events += "pending:$pending"; true },
            clear = { events += "clear"; true },
            verify = { events += "verify"; true },
        )

        assertTrue(result)
        assertEquals(listOf("pending:true", "clear", "verify", "pending:false"), events)
    }

    @Test
    fun `清理或验证失败都保留阻断且可幂等重试`() {
        for (clearSucceeds in listOf(false, true)) {
            var pending = false
            var attempts = 0
            val run = {
                attempts += 1
                ChannelMirrorInvalidation.run(
                    setPending = { pending = it; true },
                    clear = { clearSucceeds },
                    verify = { false },
                )
            }

            assertFalse(run())
            assertTrue(pending)
            assertFalse(run())
            assertTrue(pending)
            assertEquals(2, attempts)
        }
    }

    @Test
    fun `撤闸失败要重新阻断并返回失败`() {
        var pending = true

        val result = ChannelMirrorInvalidation.run(
            setPending = { value ->
                pending = value
                value
            },
            clear = { true },
            verify = { true },
        )

        assertFalse(result)
        assertTrue(pending)
    }
}
