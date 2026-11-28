package com.fnthink.notice

/**
 * MessagingStyle 多条消息的**唯一拼接作者**（P2-2）。
 *
 * 为什么需要它：`NotificationProcessor` 此前只取 `messages.last()`。微信/QQ 把
 * 多条消息合并成一个通知时，前面几条既不进转发内容、也不进历史 —— 用户看到的是
 * "只推送了最后一句"，而通知栏里明明有几条。审计（2026-11-27）把它记成
 * "内容级遗漏"。
 *
 * 为什么抽成纯函数：`Notification.MessagingStyle.Message` 属 Android 框架类，
 * JVM 单测拿不到实例；而拼接/去重/截断这三条判据本身与 Android 无关。抽出来之后
 * 用例直接喂 [Entry]，不必为了测一句 join 去搭 Robolectric。
 *
 * 两条刻意的取舍：
 *  - **相邻同文不重复展开**：同一应用连续 repost 时会把上一条原样再报一次，
 *    拼成两行会让用户以为对方说了两遍。
 *  - **超长保最新**：装不下时从最早的那条开始省略，并在开头注明"更早的 N 条未展开"
 *    —— 最新一句才是有时效的那一句；反过来截尾等于把刚收到的内容丢掉。
 */
object MessagingDigest {
    /**
     * 拼接后的正文上限（字符数）。
     *
     * 取 2000：微信/QQ 一次合并通知常见 3–10 条、每条几十字，正常远低于这个数；
     * 而企业微信 text 类型正文上限 2048 字节、Telegram 单条 4096 字符 —— 超过
     * 2000 的正文在部分通道上会被服务端截断或整条拒收，那时用户拿到的是一条
     * "发送失败"，比少几句更糟。上限不是"尽量多塞"，是"保证这一条发得出去"。
     */
    const val DEFAULT_MAX_CHARS = 2000

    /** 一条待拼接的消息：发送者（可空串）与正文。 */
    data class Entry(val sender: String, val text: String)

    /**
     * 按时间顺序（旧→新）拼接成一段正文。
     *
     * @param entries 消息列表，调用方保证顺序是旧→新（MessagingStyle 本身如此）。
     * @param maxChars 正文上限；结果长度不会超过它（单条超长时也会先截断再拼省略号）。
     * @param omittedNote 省略提示的唯一作者；参数是被省略的条数。生产传 I18n，
     *   用例传固定串 —— 这样拼接逻辑不必依赖全局 locale 才能断言。
     */
    fun format(
        entries: List<Entry>,
        maxChars: Int = DEFAULT_MAX_CHARS,
        omittedNote: (Int) -> String = { "…" },
    ): String {
        require(maxChars > 0) { "maxChars 必须为正数（0 会让每一条都被截成省略号）" }
        val lines = ArrayList<String>()
        for (entry in entries) {
            val text = entry.text.trim()
            if (text.isEmpty()) continue
            val sender = entry.sender.trim()
            val line = if (sender.isEmpty()) text else "$sender: $text"
            // 相邻同文才去重（不能全局去重：同一句话隔几条再出现是真实对话）。
            if (lines.isNotEmpty() && lines.last() == line) continue
            lines.add(line)
        }
        if (lines.isEmpty()) return ""

        val joined = lines.joinToString("\n")
        if (joined.length <= maxChars) return joined

        // 从末尾往前装：先试"省略 1 条"，装不下再省 2 条……直到连最新一条都装不下。
        for (kept in lines.size - 1 downTo 1) {
            val note = omittedNote(lines.size - kept)
            val body = lines.subList(lines.size - kept, lines.size).joinToString("\n")
            val candidate = if (note.isEmpty()) body else "$note\n$body"
            if (candidate.length <= maxChars) return candidate
        }

        // 连最新一条本身就超长：保尾部（最新那句话的结尾），开头一枚省略号说明被截断。
        val keep = (maxChars - 1).coerceAtLeast(0)
        return "…" + lines.last().takeLast(keep)
    }
}
