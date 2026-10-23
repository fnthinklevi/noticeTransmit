import '../l10n/app_localizations.dart';
import 'fnthink_receive_coordinator.dart';

/// 「改权限」那一发的结论 → 界面那一句（T174，**唯一作者**）。
///
/// 四种来路各说各的，因为用户下一步动作不同：
///  - 成功 ⇒ 已保存；
///  - `pair-grant-update-not-found` ⇒ 服务端没有这条关系（对面撤了 / 这台重建过）⇒ 重新配对；
///  - 404/405 ⇒ 服务器版本旧、没有这扇门 ⇒ 升级服务端；
///  - 服务端认了但本机没写成 ⇒ 服务端已按新清单执行，本机那份要重开确认；
///  - 其余 ⇒ 原话（与别处同一纪律：不把"网络不通"翻译成"没保存"）。
String fnthinkPeerGrantOutcomeText(
  AppLocalizations l10n,
  FnthinkPeerGrantChange change,
) {
  if (change.ok) return l10n.fnthinkPeerGrantSaved;
  final reason = change.reason ?? 'unknown';
  if (reason == 'pair-grant-update-not-found') {
    return l10n.fnthinkPeerGrantNoRelationship;
  }
  if (reason.startsWith('pair-grant-update-http:404') ||
      reason.startsWith('pair-grant-update-http:405')) {
    return l10n.fnthinkPeerGrantMissingRoute;
  }
  if (change.result.ok) return l10n.fnthinkPeerGrantLocalNotWritten;
  return l10n.fnthinkPeerGrantFailed(reason);
}
