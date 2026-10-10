package com.fnthink.notice

/**
 * 「这一发只给哪几族」的范围判定（T133 片4，原生侧唯一作者）。
 *
 * 手动补推原先总是**重置全部启用通道**：一条只有钉钉失败、邮件成功的通知，点一下会把邮件
 * 再发一遍 —— 收件端多出的是重复消息，不是补发。Dart 侧算出「该再发的那几把」
 * （`lib/services/repush_eligibility.dart`），把送达键的 slug 段沿
 * `pushRecordNow` → [NotificationMonitorService.ACTION_PUSH_RECORD_NOW] →
 * [NotificationMonitorService.dispatchToChannels] 传到四族扇出口。这里只回答一问：
 * **眼前这一个通道配置在不在范围内**。
 *
 * ⚠ 三档语义，少一档就退化成"全部重发"：
 * - `null` = 不限定。刚落库就要发出去那一条（设备快照、测试发送）用这一档：它欠的是
 *   全部启用通道各一发，没有"哪一族失败了"可言。
 * - **空集合 = 谁都不发**，这一档必须与 `null` 分开。把空集读成"不限定"，表现就是
 *   "这一条没有可再发的通道"却把全部通道重发一遍 —— 正是本片要修的行为。
 *   fail-closed 的另一半理由：范围是 Dart 算的，若两侧判据漂开，什么都不发才是可解释的。
 * - 非空 = 只放行 slug 落在集合里的那些。
 *
 * ⚠ **族粒度**是刻意的：送达键 `chan:<slug>` 本来就按族塌缩（两条钉钉共用一格，见 Dart 侧
 * `channelDeliveryKey`），所以重推 `dingtalk` 会把两条钉钉都发一遍。改成实例级要动存量
 * 数据迁移，维护者 2026-10-10 拍了"先不动键粒度"。
 */
internal object RepushScope {
    fun accepts(onlySlugs: List<String>?, slug: String): Boolean {
        if (onlySlugs == null) return true
        if (onlySlugs.isEmpty()) return false
        val want = slug.trim().lowercase()
        return onlySlugs.any { it.trim().lowercase() == want }
    }
}
