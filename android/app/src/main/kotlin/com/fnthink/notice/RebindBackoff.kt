package com.fnthink.notice

/**
 * 监听器重绑的退避档位（纯逻辑，JVM 可测）。
 *
 * **背景（漏读，P1-2）**：`onListenerDisconnected` 之后调
 * `NotificationListenerService.requestRebind(...)` 是官方文档里唯一安全的恢复调用，
 * 但它**可能被系统节流或直接静默忽略**。原实现只在 15 秒后再试一次就收手 ——
 * 若系统那两次都没答应（国产 ROM 上很常见：后台被限制、权限页还开着、
 * Doze 里刚醒），监听器就一直不回来，而 `onNotificationPosted` 不再回调 ⇒
 * 那段时间的通知全部静默漏读，界面上却只有一行"监听已断开"永远挂着。
 *
 * **解法**：改成持续退避，一直试到 `onListenerConnected` 或服务被销毁为止。
 * 档位 15s → 30s → 60s → 120s → 300s，之后**封顶在 5 分钟**（不再加长）：
 * - 上限 5 分钟是刻意的：再长就会让"用户手动去权限页开回来"这件事在恢复后
 *   仍要等一个很长的间隔才被注意到；而 5 分钟对一台在充电的常驻机是可接受的对账粒度。
 * - 首次仍然 15 秒：刚断开那一刻系统最常见的行为是"马上就好"，等长反而拖慢恢复。
 *
 * ⚠ 这个退避只覆盖"重绑请求"这一条路，它不改变补扫（[RecoveryWatermark]）——
 * 补扫判的是"服务中断过多久"，与重试了几次无关。
 */
internal object RebindBackoff {

    /** 五档退避（毫秒）。最后一档即封顶值。 */
    val DELAYS_MS = longArrayOf(15_000L, 30_000L, 60_000L, 120_000L, 300_000L)

    /** 封顶间隔：一直连不上时按这个粒度继续试，不再加长。 */
    const val MAX_DELAY_MS = 300_000L

    /**
     * 第 [attempt] 次重试之后该等多久（attempt 从 0 开始：0 = 断开后的第一次等待）。
     *
     * 负数按首次处理；超出档位表的按封顶值。**不许返回 0** —— 返回 0 会让
     * `postDelayed` 变成同步递归，在整个 Doze 期间打满主线程。
     */
    fun delayFor(attempt: Int): Long {
        if (attempt < 0) return DELAYS_MS[0]
        if (attempt >= DELAYS_MS.size) return MAX_DELAY_MS
        return DELAYS_MS[attempt]
    }
}
