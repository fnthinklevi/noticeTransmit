package com.fnthink.notice

import android.util.Log
import io.flutter.plugin.common.MethodChannel

/**
 * 白名单通知触发的那一路：原生把「这条通知的正文像一条远程指令」交给 Dart 的那一格。
 *
 * ## 这一路开的是什么
 * 契约 `remoteExecution.sources.L1` 有两条来源，`localNotificationWhitelist` 是其中一条：
 * 白名单命中的通知，正文以指令信封开头 ⇒ 当成一条 L1 远程指令走**同一条**判定与执行链
 * （Dart 侧 `RemoteCommandRecognizer.judge(source:)`，不重写判定）。
 *
 * ## ⚠ 这是**无凭据**的 L1 入口 —— 威胁模型如实写在这
 * 这一路上没有 key、没有 TOTP（契约 `auth.l2Requires:false` / L1 更不要求）。能被它执行的动作
 * 按 `sources` 只到 L1，而 L1 的 item 表是 L2∪L3 的并集（`itemRequiredFromLevel = L2`），
 * 实际可做的是 `listener:start/stop`、`channel:toggle`、L3 设置项的翻转。
 *
 * 三层收窄，缺任何一层都会让"外部内容"直接变成"这台设备上的动作"：
 *  1. **来源**：只有用户自己在白名单里配过关键词的应用/通知才走到这里（`FilterEngine`）；
 *     Android 的渠道名+包名匹配又保证第三方应用**发不进本应用自己的渠道**。
 *  2. **前缀**：正文必须以 `FRX1:` 开头（见 [offer]）。用**开头**而不是"包含"是刻意的：
 *     会话类通知里别人**引用**一条指令（转发、贴代码块）不该被执行，自动化类应用
 *     自己发出的通知正文才是指令本身。
 *  3. **级别**：`sources.L2/L3` 只含 `fnthink` ⇒ 载荷写 L2/L3 会拿到
 *     `source-not-allowed:L2/L3` 并被拒。这一道在 Dart 的判定层，不在这侧。
 *
 * 剩下的真实窄路是「某个会把外部内容转发进通知正文的自动化类应用」—— 那必须先被用户
 * 放进白名单关键词、且自己把外部内容拼成一条 `FRX1:` 开头的通知。
 *
 * ## 为什么需要 TTL（[FRESH_SECONDS]）
 * Dart 引擎不一定在跑：这条通知可以由 [NotificationMonitorService] 在**没有界面**时收到
 * （它自己会把进程拉起来）。若无条件攒着，用户半小时后第一次打开应用，一批"半小时前的
 * 指令"会接连动手 —— 而那半小时里他没看见任何横幅，也**没有人能按下撤销**（撤销要靠
 * 状态栏那枚通知，而那条通知是 Dart 起来之后才发的）。
 *
 * 所以：**过期即作废，判在原生侧**（[take]）。这是 fail-safe 方向 ——
 * 宁可"通知发了但没执行"，也不能"用户没察觉时执行了"。
 *
 * ## 为什么不落盘（对照 `RemoteExecutionCancelStore`）
 * 那一份必须活过"Receiver 被单独拉起"的那一刻，所以落 SharedPreferences。
 * 这一份不需要：进程被回收 = Dart 也不在 = 那条指令**作废**（这正是 [FRESH_SECONDS]
 * 想保证的方向），落盘只会把一条过期的指令复活。
 */
object LocalRemoteCommandInbox {
    private const val TAG = "LocalRemoteCommandInbox"

    /**
     * 指令信封前缀。
     *
     * ⚠ 与 `packages/fnthink_push` 的 `RemoteCommandEnvelope` 是同一个值 ——
     *   **本仓已有一处跨语言守卫钉住它**（把两边改歪的那一发会红），此处不再复述判据。
     */
    private const val PREFIX = "FRX1:"

    /** 60 秒。理由见类注释「为什么需要 TTL」。 */
    private const val FRESH_MS = 60_000L

    /** 攒着等 Dart 来取的条数上限。满了丢**最老**的 —— 丢最老的那条最可能已过期。 */
    private const val MAX_PENDING = 8

    data class Item(val body: String, val atMs: Long)

    private val queue = ArrayDeque<Item>()
    private var channel: MethodChannel? = null

    /** `configureFlutterEngine` 登记、`cleanUpFlutterEngine` 注销。 */
    fun attach(ch: MethodChannel?) {
        synchronized(this) { channel = ch }
    }

    /**
     * 白名单命中后把正文交出来。回 true = 这一条被收下了（**不是**"这是一条指令"——
     * 拆信封、判级别、判 item 全在 Dart 侧那一层，不重写）。
     *
     * ⚠ 前缀判定**收在这里**而不是调用方：`NotificationMonitorService` 那一格只管
     * "白名单命中了，把正文交出去"，认不认得由这一个类说了算 ⇒ `FRX1:` 这个字面量
     * 在原生侧只有这一处。
     */
    fun offer(content: String?, nowMs: Long = System.currentTimeMillis()): Boolean {
        val body = content?.trim().orEmpty()
        if (!body.startsWith(PREFIX)) return false
        var dropped = false
        synchronized(this) {
            if (queue.size >= MAX_PENDING) {
                queue.removeFirst()
                dropped = true
            }
            queue.addLast(Item(body, nowMs))
        }
        if (dropped) Log.w(TAG, "local trigger inbox full, dropped the oldest")
        pingDart()
        return true
    }

    /**
     * 取一条**未过期**的（问一次即清）。
     *
     * ⚠ 过期的那几条在这里被丢掉而不是留着等：留着等于给它们一条"用户下次开应用时
     *   会执行"的活路，而撤销机会在那时不存在（见类注释 TTL 那一段）。
     * ⚠ **consume 而不是 peek**：同 `RemoteExecutionCancelStore` 的理由 —— 若留着，
     *   下一轮 drain 会把它再读一遍，同一条指令被执行两次。
     */
    fun take(nowMs: Long = System.currentTimeMillis()): Item? {
        val expired = mutableListOf<Int>()
        val found: Item?
        synchronized(this) {
            // ⚠ 全扫而不是"扫到第一个没过期就停"：队列按到达时间递增是**通常**情形，
            //   而 `offer` 的时钟来自 `System.currentTimeMillis()`（会因用户改系统时间而后退）。
            //   一次后退就变成"后面那条比前面那条旧"，前缀扫描会把旧的留在队列里，
            //   而它的表现是**一条过期指令被当成新鲜的执行了**。
            for (i in queue.indices) {
                if (nowMs - queue[i].atMs > FRESH_MS) expired += i
            }
            // 降序删，否则删掉前面的会让后面的索引前移。
            for (idx in expired.reversed()) if (idx < queue.size) queue.removeAt(idx)
            found = if (queue.isEmpty()) null else queue.removeFirst()
        }
        if (expired.isNotEmpty()) {
            Log.i(TAG, "dropped ${expired.size} stale local trigger(s)")
        }
        return found
    }

    /** 仅供测试与「有没有攒着的东西」这类读口。 */
    fun pendingCount(): Int = synchronized(this) { queue.size }

    /**
     * 引擎在的时候**推一个讯号**（T83 / #176 那一路的形状：原生只交"去问一次"，
     * 取的动作只从 [take] 一个出口走）。引擎不在时静默 —— 那条已经躺在队列里，
     * 等 Dart 装配好时取走。
     */
    private fun pingDart() {
        val ch = synchronized(this) { channel } ?: return
        try {
            ch.invokeMethod("onLocalRemoteCommand", null)
        } catch (e: Exception) {
            Log.d(TAG, "ping Dart skipped: ${e.message}")
        }
    }
}