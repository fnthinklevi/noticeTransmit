package com.fnthink.notice

/**
 * 「点通知要跳去的那一条」的交接处（T83）。
 *
 * `FnthinkInboxDisplay.show` 早就把 `messageId` 放进了 tap Intent（`EXTRA_MESSAGE_ID`），
 * 但一直到这一片之前**没有任何人读它** —— 于是真机上的表现就是维护者报的那句"点了只打开软件"。
 * 这个对象就是那一枚 id 从 Intent 走到 Dart 手里的**唯一落点**。
 *
 * 四条写在代码旁边的取舍：
 *  ① **它是进程内的 `object`，不是挂在 Activity 上的字段**。Dart 侧读它要经过
 *    `FnthinkChannelHandler`，而那一族按 §4-9 片0 的守卫只许拿 `Context`（后台引擎没有
 *    Activity 可传）。把值存在 Activity 上，就等于把"后台装不出来"那个老坑再挖一遍。
 *  ② **只有一个出口：[take]，取走即清**。三个进入形状（冷启动、后台热恢复、前台再点）都往这里记，
 *    而只有 `take` 能把出去 ⇒ "同一条通知跳两次"在这套写法里没有落脚处。
 *    ⚠ 不把它做成 `var` 公开读写：那等于允许第二个读者出现，而第二个读者就是重复跳转的作者。
 *  ③ **空白一律不记**（[record] 拒绝 null/空串/全空格）。判据是"拿不到 messageId 就打开列表"
 *    （系统重放一条老通知、或厂商改了 extra 那一格），所以"没记"与"记了个空串"必须是同一件事 ——
 *    否则 Dart 那边要判两种空，漏一种就是"跳到历史页却展开了一条猜出来的行"。
 *  ④ **覆盖而不是排队**。连点两条通知时用户要看的是最后点的那条；排队会让页面逐条弹详情，
 *    而第二条早已把第一条划掉了。
 *
 * ⚠ 不落盘：这是"这一次点击进入"的意图，进程死了就该跟着死。写进 prefs 的后果是
 *    下次冷启动跳去一条三天前的通知 —— 那比"点了没反应"更难解释。
 */
object FnthinkOpenTarget {

    @Volatile
    private var pendingMessageId: String? = null

    /** 记下来自 Intent 的那一枚。空白不记，见类注释 ③。 */
    fun record(messageId: String?) {
        val trimmed = messageId?.trim()
        if (trimmed.isNullOrEmpty()) return
        pendingMessageId = trimmed
    }

    /** Dart 的唯一出口：取走并清空；没有待跳的就回 null（页面据此只打开列表）。 */
    fun take(): String? {
        val taken = pendingMessageId
        pendingMessageId = null
        return taken
    }

    /** 不清空的读法，只给测试与日志用。生产路径一律走 [take]。 */
    fun peek(): String? = pendingMessageId

    /** 让这一枚作废（测试与"跳转已经不需要它"的场合）。 */
    fun clear() {
        pendingMessageId = null
    }
}
