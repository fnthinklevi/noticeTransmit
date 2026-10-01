package com.fnthink.notice

/**
 * 「点开的那条配对链接」的交接处（#176 片4，T28-B 的最后一跳）。
 *
 * A 那台把 `配对链接`（契约 `pairing.qrPrefix` 那一把前缀 + `to`/`code`/`level`）显示在屏幕上，
 * B 这台要么用相机扫、要么把它复制过去点开。后一种从今天起有人接：系统的 VIEW intent 走到
 * [MainActivity]，这里记一次，Dart 取一次。
 *
 * 四条写在代码旁边的取舍：
 *  ① **只记不判**：这里唯一的判断是"这把前缀对不对"，剩下的一切（载荷名单、版本、地址码形状、
 *    口令形状、档位词表）都在 Dart 侧由 `FnthinkPairingRequest.parse(契约, …)` 判 —— 判据在契约层，
 *    Kotlin 抄一份就是第二个作者，而第二份判据可以朝同一个方向写错。
 *    前缀这一枚字面量无法从契约读（原生读不到那份 JSON），所以由
 *    `FnthinkPairLinkContractTest` 钉住"它逐字等于契约的 `pairing.qrPrefix` + `?`"。
 *  ② **只有一个出口：[take]，取走即清**（与 [FnthinkOpenTarget] 同一条纪律）。三种进入形状
 *    （冷启动、后台热恢复、前台再点一次）都往这里记，而只有 take 能出去 ⇒ "同一条链接弹两次
 *    输入弹层"在这套写法里没有落脚处。
 *  ③ **不匹配前缀就不记**（返回 false，MainActivity 据此**不推那一发讯号）。漏了这一步的表现是
 *    "从别的地方回到 App，屏幕上凭空跳出一个配对弹层"，而 [MainActivity] 的 onNewIntent
 *    对每一种 Intent 都会走。
 *  ④ **不落盘、不打日志**：那串 query 里带着一次性口令（契约 `pairing.codeMayAppearIn`
 *    允许它出现在二维码与一次性链接里，仅此两处）。写进 prefs 就等于把它变成长期凭证，
 *    而本站的反代日志脱敏（T89）还没配。
 *
 * ⚠ 覆盖而不是排队：连点两条配对链接时，用户要配的是最后点的那台。
 */
object FnthinkPairLink {

    /**
     * 认这一把前缀（契约 `pairing.qrPrefix` 加一个 `?`）。
     *
     * 为什么把 `?` 也算进来：载荷为空（`fnthink-push://pair?` 后面什么都没有）在 Dart 侧
     * 是一个明确的 `empty` 结论，而"前缀都不对"根本不该走到那一步 —— 两者要分得开。
     */
    const val PREFIX = "fnthink-push://pair?"

    @Volatile
    private var pending: String? = null

    /**
     * 记下来自 VIEW intent 的那一条。返回**是否真的记了** —— 调用方用它决定要不要推那一发讯号，
     * 于是"没记"与"推了但没人接"这两件事不会同时发生。
     */
    fun record(rawUri: String?): Boolean {
        val trimmed = rawUri?.trim()
        if (trimmed.isNullOrEmpty() || !trimmed.startsWith(PREFIX)) return false
        pending = trimmed
        return true
    }

    /** Dart 的唯一出口：取走并清空；没有待配的那条就回 null。 */
    fun take(): String? {
        val taken = pending
        pending = null
        return taken
    }

    /** 不清空的读法，只给测试用。生产路径一律走 [take]。 */
    fun peek(): String? = pending

    /** 让这一条作废（测试用）。 */
    fun clear() {
        pending = null
    }
}
