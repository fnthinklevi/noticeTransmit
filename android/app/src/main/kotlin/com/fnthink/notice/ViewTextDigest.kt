package com.fnthink.notice

/**
 * RemoteViews 里 `TextView` 文本的**唯一整理作者**（P2-3）。
 *
 * 背景：纯 Custom RemoteViews 的通知（进度条、音乐卡片、部分 ROM 的 group summary）
 * 在 `EXTRA_TITLE/TEXT/BIG_TEXT/SUMMARY_TEXT/TEXT_LINES/ticker/subText` 里一个字段都
 * 没有，旧兜底链走到最后就是"标题+正文都空 ⇒ 丢弃"。审计（2026-11-27）要求对
 * `contentView` / `bigContentView` 做**有限**提取：只读 `TextView` 的文本，不执行
 * 任意逻辑；提取不到就按"无内容"处理，但必须留一条诊断。
 *
 * 为什么整理逻辑抽成纯函数：`View` / `RemoteViews` 都是 Android 框架类，JVM 单测
 * 拿不到实例；而"哪些文本要、重复的怎么并、超长截哪头"与框架无关。遍历那一步
 * （`NotificationProcessor.collectTextViewTexts`）由源码守卫钉住：只认 `TextView`。
 *
 * 与 [MessagingDigest] 的差别（不是重复实现）：
 *  - 会话消息有发送者、按行拼接、超长保**最新**；
 *  - 布局文本没有发送者、同一句常在标题与展开区各出现一次（必须去重）、
 *    超长保**开头**（布局是从上到下的，先出现的是标题与主内容）。
 */
object ViewTextDigest {
    /**
     * 布局文本上限。
     *
     * 比 [MessagingDigest.DEFAULT_MAX_CHARS] 小：RemoteViews 是"最后一道兜底"，
     * 它的文本通常只有标题/副标题/按钮几段；再长基本是把整个列表塞进了布局，
     * 此时全量转发只会把正文淹掉。1200 字符足够覆盖常见卡片。
     */
    const val DEFAULT_MAX_CHARS = 1200

    /**
     * 把若干段布局文本整理成一段正文。
     *
     * @param lines 遍历 `TextView` 得到的原始文本（顺序＝布局顺序）。
     * @param maxChars 上限；超长时保留开头并补一枚省略号（长度仍不超过上限）。
     */
    fun format(lines: List<String>, maxChars: Int = DEFAULT_MAX_CHARS): String {
        require(maxChars > 0) { "maxChars 必须为正数（0 会让每一条都被截成省略号）" }
        val kept = ArrayList<String>()
        for (raw in lines) {
            val text = raw.trim()
            if (text.isEmpty()) continue
            // 布局里同一句常出现两次（折叠态标题 + 展开态标题）；全局去重是安全的：
            // 这里不是对话，重复的 TextView 文本没有"说了两遍"的语义。
            if (kept.contains(text)) continue
            kept.add(text)
        }
        if (kept.isEmpty()) return ""
        val joined = kept.joinToString("\n")
        if (joined.length <= maxChars) return joined
        if (maxChars == 1) return "…"
        return joined.take(maxChars - 1) + "…"
    }
}
