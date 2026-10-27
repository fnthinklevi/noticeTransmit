package com.fnthink.notice

internal object ChannelMirrorInvalidation {
    fun run(
        setPending: (Boolean) -> Boolean,
        clear: () -> Boolean,
        verify: () -> Boolean,
    ): Boolean {
        if (!setPending(true)) return false
        val cleared = try {
            clear() && verify()
        } catch (_: Exception) {
            false
        }
        if (!cleared) return false
        if (setPending(false)) return true
        setPending(true)
        return false
    }
}
