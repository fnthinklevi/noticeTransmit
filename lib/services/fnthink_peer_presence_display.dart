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

/// 「这次没拿到」那一句的唯一作者。原因原话来自内核，界面不另编一个。
String fnthinkPeerPresenceFailedLine(AppLocalizations l10n, String reason) =>
    l10n.fnthinkPeerPresenceFailed(reason);

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
