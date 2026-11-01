import '../l10n/app_localizations.dart';

/// T220 片2b：一个通道「最近一次失败」怎么读 —— 分类词表与判据的**唯一作者**。
///
/// 为什么必须只有一个作者：同一条失败会同时出现在通道状态页、历史详情与导出里。
/// 三处各自拿 `httpCode` / `message` 猜一遍，用户就会看到"网络问题"和"平台拒绝"
/// 形容同一次投递 —— 而"偶发失败到底错在哪"正是这一片要回答的那个问题。
///
/// 判据输入只有送达日志里已有的三格（`http_code` / `message` / 归一化后的 `status`），
/// **不新开存储**：native 侧的 `DeliveryStatus` 早就把它分好了，只是没一路落下来；
/// 这里按它落到 Dart 之后剩下的痕迹重新归一次类，够回答"是哪一类"，且存量行也能读。
enum DeliveryFailureKind {
  /// 请求没到对面：DNS／连接超时／断网（`http_code = 0`）。
  network,

  /// 对面回了 4xx／5xx（具体码在送达记录里）。
  http,

  /// 平台限流（429）：自动等一会儿再试，不算配置错。
  rateLimited,

  /// HTTP 通了但平台业务拒绝（errcode 非 0 一族）：重试无用（T202 已拍不排队）。
  business,

  /// 这一条还没发出去就被本机停了（推送暂停／引擎不在）。
  interrupted,

  /// 有 HTTP 码却是 2xx／3xx，又没有任何业务拒绝的痕迹 —— 不猜。
  unknown,
}

/// 一个通道的失败读数。`consecutiveFailures` = 从最近一次成功之后连着失败了几次。
class ChannelFailureSummary {
  const ChannelFailureSummary({
    required this.lastFailedAt,
    required this.httpCode,
    required this.message,
    required this.kind,
    required this.consecutiveFailures,
  });

  final int lastFailedAt;
  final int httpCode;
  final String message;
  final DeliveryFailureKind kind;
  final int consecutiveFailures;

  ChannelFailureSummary _addOlderFailure() => ChannelFailureSummary(
    lastFailedAt: lastFailedAt,
    httpCode: httpCode,
    message: message,
    kind: kind,
    consecutiveFailures: consecutiveFailures + 1,
  );
}

/// 分类判据（顺序即优先级）。
///
/// ⚠ 429 必须排在 4xx 前面：它是"慢一点"，用户该做的事与"地址/权限错了"完全不同。
/// ⚠ 业务拒绝排在 `httpCode > 0` 前面：平台业务拒绝常常带 200，按码归就会读成"服务器出错"。
DeliveryFailureKind deliveryFailureKindOf({
  required int httpCode,
  required String message,
}) {
  if (httpCode == 429) return DeliveryFailureKind.rateLimited;
  if (httpCode >= 400) return DeliveryFailureKind.http;
  final lower = message.toLowerCase();
  if (message.contains('业务') ||
      lower.contains('errcode') ||
      lower.contains('business')) {
    return DeliveryFailureKind.business;
  }
  if (lower.contains('inactive') ||
      lower.contains('push paused') ||
      message.contains('暂停')) {
    return DeliveryFailureKind.interrupted;
  }
  if (httpCode > 0) return DeliveryFailureKind.unknown;
  return DeliveryFailureKind.network;
}

/// 人话（问号弹层与行内那一格共用同一份词）。
String channelFailureKindText(
  AppLocalizations l10n,
  DeliveryFailureKind kind,
) => switch (kind) {
  DeliveryFailureKind.network => l10n.channelFailureKindNetwork,
  DeliveryFailureKind.http => l10n.channelFailureKindHttp,
  DeliveryFailureKind.rateLimited => l10n.channelFailureKindRateLimited,
  DeliveryFailureKind.business => l10n.channelFailureKindBusiness,
  DeliveryFailureKind.interrupted => l10n.channelFailureKindInterrupted,
  DeliveryFailureKind.unknown => l10n.channelFailureKindUnknown,
};

/// 从送达日志（**按时间倒序**，即调用方的 `ORDER BY timestamp DESC`）汇总每个 tag 的失败读数。
///
/// 折叠规则：
///  - 「最近一次失败」= 这个 tag 在窗口内**最新的一条 `failed`**，即便它之后已经又成功了
///    （那正是要留的证据：通道恢复了，但上一次错在何时、错在哪一类仍要读得出来）。
///  - `consecutiveFailures` = 从那条失败往前数**相邻**的 `failed` 条数：遇到 `success`
///    或任何非失败终态（`queued` 等）就停 —— "连续"只数真正挨着的失败。
///  - 窗口内一条失败都没有的 tag **不出现**（调用方据此不画占位）。
///  - ⚠ 同一事件被广播与补拉双写时，`insertDeliveryLog` 已做幂等拦截；这里不再按内容去重
///    （按内容去重会把"同一轮里两条不同的失败"折成一次，那是另一种失真）。
Map<String, ChannelFailureSummary> summarizeChannelFailures(
  Iterable<Map<String, dynamic>> rows,
) {
  final out = <String, ChannelFailureSummary>{};
  final counting = <String>{};
  for (final row in rows) {
    final tag = row['tag']?.toString() ?? '';
    if (tag.isEmpty) continue;
    final status = row['status']?.toString() ?? '';
    final existing = out[tag];
    if (existing == null) {
      // 还没找到这个 tag 的最近一次失败：只有真失败才开账，成功/其它一律继续往前找。
      if (status != 'failed') continue;
      final httpCode = (row['http_code'] as num?)?.toInt() ?? 0;
      final message = row['message']?.toString() ?? '';
      out[tag] = ChannelFailureSummary(
        lastFailedAt: (row['timestamp'] as num?)?.toInt() ?? 0,
        httpCode: httpCode,
        message: message,
        kind: deliveryFailureKindOf(httpCode: httpCode, message: message),
        consecutiveFailures: 1,
      );
      counting.add(tag);
      continue;
    }
    if (!counting.contains(tag)) continue;
    if (status == 'failed') {
      out[tag] = existing._addOlderFailure();
    } else {
      // 连续链断开：保留已数到的次数，这个 tag 到此为止。
      counting.remove(tag);
    }
  }
  return out;
}
