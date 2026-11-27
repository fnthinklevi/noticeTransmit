package com.fnthink.notice

/**
 * 启动补扫水位（纯逻辑，JVM 可测）。
 *
 * **背景（漏通知根因）**：Android 的 `onNotificationPosted` 是**非持久化事件**——
 * 系统未及时绑定监听器（Doze / 长时间后台驻留 / 进程被回收后 ROM 延迟重新绑定）时，
 * 该通知的事件永久丢失，但通知本身仍驻留在通知栏。原实现只在
 * `onListenerDisconnected → onListenerConnected` 路径补扫，而**进程被回收时
 * 该回调不会触发、`disconnectedAt` 随进程消失**（重建后为 0）→ 冷启动永不补扫 → 静默漏读。
 *
 * **解法**：把「服务存活心跳」持久化（`flutter.notif_last_alive_at`），服务启动时比较
 * `now - lastAliveAt`：
 * - 首次安装（无心跳）→ 不补扫（避免把通知栏既有历史通知全部回放）；
 * - 心跳新鲜（服务始终存活）→ 无需补扫（事件未丢）；
 * - 心跳陈旧（服务中断过）→ 以「心跳时刻」为下界补扫活跃通知。
 *
 * 三重下界保障不重复补扫：`max(心跳时刻, 上次补扫水位, now - 最大回溯)`。
 */
internal object RecoveryWatermark {

    /** 心跳距今小于此值视为「服务未中断」（正常重启/配置刷新不触发补扫） */
    const val MIN_GAP_MS = 30_000L

    /** 最大回溯：即便中断很久，也只回放最近 6 小时，避免冷启动回放大量陈旧通知 */
    const val MAX_LOOKBACK_MS = 6 * 60 * 60 * 1000L

    /**
     * 计算启动补扫的时间下界（含）。
     *
     * @param lastAliveAt 上次服务存活心跳（0 = 从未记录，即首次安装）
     * @param lastScanAt 上次补扫水位（0 = 从未补扫）
     * @param now 当前时间
     * @return 需补扫的 postTime 下界；返回 null 表示**无需补扫**
     */
    fun scanSinceOrNull(lastAliveAt: Long, lastScanAt: Long, now: Long): Long? {
        if (lastAliveAt <= 0L) return null
        // 服务从未中断（心跳新鲜）：事件不会丢，不补扫
        if (now - lastAliveAt < MIN_GAP_MS) return null
        return maxOf(lastAliveAt, lastScanAt, now - MAX_LOOKBACK_MS)
    }

    /**
     * 一次冷启动补扫的收尾决策（P1-3）。
     *
     * 背景：原实现**先**把 `LAST_SCAN` / `LAST_ALIVE` 推进到 `now`、**再**去扫，而
     * 扫描在 `activeNotifications` 还是 null（监听器尚未接上）时静默 return ——
     * 那一段通知就永远补不回来了：水位已经跨过去，下一次启动算出的下界比它们新。
     *
     * @param since 补扫下界（null = 不需要补扫）
     * @param snapshotReadable 这一次是否真的拿到了活跃通知快照并扫完
     */
    fun settleStartupScan(since: Long?, snapshotReadable: Boolean): StartupScanSettle {
        // 不需要补扫：照常推进水位（否则每次启动都重算同一段，而那段本来就没漏）
        if (since == null) {
            return StartupScanSettle(advanceWatermark = true, pendingSince = null)
        }
        // 需要补扫且真的扫完了：推进水位
        if (snapshotReadable) {
            return StartupScanSettle(advanceWatermark = true, pendingSince = null)
        }
        // 需要补扫但没拿到快照：**不推进**，把这一段挂成 pending 等监听器接上再补
        return StartupScanSettle(advanceWatermark = false, pendingSince = since)
    }
}

/**
 * 冷启动补扫的收尾结论（见 [RecoveryWatermark.settleStartupScan]）。
 *
 * @property advanceWatermark 要不要把 `LAST_SCAN` / `LAST_ALIVE` 推进到 now
 * @property pendingSince 非 null = 这一段还没扫，等 `onListenerConnected` 之后再补一次
 */
internal data class StartupScanSettle(
    val advanceWatermark: Boolean,
    val pendingSince: Long?,
)
