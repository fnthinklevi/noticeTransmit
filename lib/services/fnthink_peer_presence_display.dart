import 'package:fnthink_push/fnthink_push.dart';

import '../l10n/app_localizations.dart';
import '../widgets/channel_health_badge.dart';

/// 对端状态的**显示档**（T156 片2）。
///
/// 三态来自服务端（契约 `presence.states`），这里**不判**在线/离线；只把"这一行该画哪一档"
/// 分成六种可画的东西。其中两种不是三态：`notShared`（读到了，但这一台没把状态共享给本机）
/// 与 `unavailable`（这次没读到）。把它们并进 `offline` 就是本片要治的那句不实陈述。
enum FnthinkPeerPresenceKind {
  online,
  offline,
  unknown,
  notShared,
  loading,
  unavailable,
}

/// 这一台现在该画哪一档。`loading` / `unavailable` 是**整张名单**的状态，
/// 不是某一台的结论 —— 调用方在加载/失败时只画卡片级那一句，不给每行编一个状态。
({FnthinkPeerPresenceKind kind, int? ageSeconds}) fnthinkPeerPresenceView({
  required FnthinkContract contract,
  required FnthinkPeerPresenceResult? result,
  required bool loading,
  required String peerAddress,
}) {
  if (loading) {
    return (kind: FnthinkPeerPresenceKind.loading, ageSeconds: null);
  }
  if (result == null || !result.ok) {
    return (kind: FnthinkPeerPresenceKind.unavailable, ageSeconds: null);
  }
  final row = result.peerOf(peerAddress);
  if (row == null) {
    // 读到了，但这一台不在返回的集合里：对端没有把状态共享给本机（契约 absentMeans=notShared）。
    return (kind: FnthinkPeerPresenceKind.notShared, ageSeconds: null);
  }
  if (row.presence == contract.presenceOnlineState) {
    return (kind: FnthinkPeerPresenceKind.online, ageSeconds: row.ageSeconds);
  }
  if (row.presence == contract.presenceOfflineState) {
    return (kind: FnthinkPeerPresenceKind.offline, ageSeconds: row.ageSeconds);
  }
  if (row.presence == contract.presenceUnknownState) {
    return (kind: FnthinkPeerPresenceKind.unknown, ageSeconds: null);
  }
  // 词表外的值内核已经整读拒收；走到这里仍按 unknown 画，不猜成离线。
  return (kind: FnthinkPeerPresenceKind.unknown, ageSeconds: null);
}

/// 「正在读取」那一句的唯一作者。
String fnthinkPeerPresenceLoadingLine(AppLocalizations l10n) =>
    l10n.fnthinkPeerPresenceLoading;

/// T177：把内核给的机器理由翻成用户能照着办的话。
///
/// `peer-presence-http:404` 不是网络故障，是**服务器没有这条读口**（部署版本旧）。
/// 原样摊给用户只会得到一句「HTTP 404」，而下一步该做的是重传新版 `server/`。
/// 其余理由仍原样带出：它们是传输/签名/限流各自的机器码，翻成一句通用话会丢掉线索。
String fnthinkPeerPresenceReasonText(AppLocalizations l10n, String reason) {
  if (reason.contains('peer-presence-http:404')) {
    return l10n.fnthinkPeerPresenceMissingRoute;
  }
  return reason;
}

/// 「这次没拿到」那一句的唯一作者。原因原话来自内核，界面不另编一个。
String fnthinkPeerPresenceFailedLine(AppLocalizations l10n, String reason) =>
    l10n.fnthinkPeerPresenceFailed(fnthinkPeerPresenceReasonText(l10n, reason));

/// 离线那一档下面那句：**离线不等于发不出去**（T176）。
///
/// 服务端把 `offline` 判成"超过阈值没 poll"，而收单会照收并排队等它上线。
/// 旧界面只写「离线」，用户读成"现在发不了"；这一句把"到达时间会晚"与"发不出去"
/// 分开说。其余五档回 null：在线不需要这句，unknown/notShared 说"排队"是替人家作保。
String? fnthinkPeerPresenceDeliveryNote(
  AppLocalizations l10n,
  FnthinkPeerPresenceKind kind,
) => kind == FnthinkPeerPresenceKind.offline
    ? l10n.fnthinkPeerPresenceOfflineQueued
    : null;

/// 一台对端那一行的状态句（null = 不画；失败那句在卡片级，由
/// [fnthinkPeerPresenceFailedLine] 负责）。
String? fnthinkPeerPresenceLine(
  AppLocalizations l10n,
  ({FnthinkPeerPresenceKind kind, int? ageSeconds}) view,
) {
  switch (view.kind) {
    case FnthinkPeerPresenceKind.loading:
      return l10n.fnthinkPeerPresenceLoading;
    case FnthinkPeerPresenceKind.unavailable:
      return null;
    case FnthinkPeerPresenceKind.notShared:
      return l10n.fnthinkPeerPresenceNotShared;
    case FnthinkPeerPresenceKind.unknown:
      return l10n.fnthinkPeerPresenceUnknown;
    case FnthinkPeerPresenceKind.online:
      return l10n.fnthinkPeerPresenceOnline(
        fnthinkAgoLabelFromSeconds(l10n, view.ageSeconds ?? 0),
      );
    case FnthinkPeerPresenceKind.offline:
      return l10n.fnthinkPeerPresenceOffline(
        fnthinkAgoLabelFromSeconds(l10n, view.ageSeconds ?? 0),
      );
  }
}
