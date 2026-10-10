/// 「这一通道能不能再发一次」的判据（T133 片1，**唯一作者**）。
///
/// 这里回答的是一个问题，而它常被和另一个问题混起来 —— 混起来就是那条缺陷：
///
/// | 问题 | 谁回答 | 含 `intercepted` 吗 |
/// |---|---|---|
/// | 这条**送达了吗**（筛选、状态词、计数） | DB 侧 `buildSearchSql` 的粗筛 + `NotificationService.matchDeliveryFilter` 的精筛 | **含** —— 被拦截的确实没送达 |
/// | 这条**可以再发一次吗**（批量池、勾选框、单条「现在推送」） | 本文件 | **不含** —— 那是用户自己定的过滤规则，替他推翻它不是"重推" |
///
/// 改之前两件事共用一个 `hasFailedChannel`（只认 `failed`），于是"筛选筛得出 intercepted、
/// 批量却选不中"这一类自相矛盾出现在界面上（维护者 2026-10-10 第 7 条点名的形状之一）。
///
/// ⚠ 另外三条不进重推池，各有一句理由：
/// - `success`：再发一遍 = 同一条通知推两次。收件端那条消息不会因为"重推"而消失。
/// - `pending`：还在途。重推就是拿"再发一次"去和"这一次可能正在发"抢，at-least-once 之上再叠一层。
/// - 空 / 异形：这一条从来没有送达记录 —— 典型是"仅记录不推送"与规则 `Record` 那一档，
///   那是用户明说"这条别发"。把"没有记录"读成"失败了"会静默扩张推送范围。
library;

/// 一个通道条目该不该被再发一次。[info] 是送达 map 里那一格（正常是 `Map`，也可能是异形值）。
bool channelNeedsRepush(Object? info) {
  if (info is! Map) return false;
  final status = info['status']?.toString() ?? '';
  return status == 'failed' || status == 'paused';
}

/// 一条记录要不要进重推池（= 至少一个通道该再发一次）。
bool recordNeedsRepush(Map<String, dynamic> deliveryStatus) {
  return deliveryStatus.values.any(channelNeedsRepush);
}

/// 这一条里该再发的那几把（保持记录里的原顺序，界面按它列明细）。
List<String> repushableChannels(Map<String, dynamic> deliveryStatus) {
  return deliveryStatus.entries
      .where((e) => channelNeedsRepush(e.value))
      .map((e) => e.key)
      .toList();
}
