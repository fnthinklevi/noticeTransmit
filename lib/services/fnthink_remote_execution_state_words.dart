import '../l10n/app_localizations.dart';
import 'fnthink_remote_execution.dart';

/// 远程执行**状态词**的唯一作者（T141① 从 `remote_history_page` 抽出来的那一把）。
///
/// 为什么值得一个文件：收件历史页要把指令行显示成「一条远程指令（状态/原因）」
/// （维护者 2026-10-17 拍板），而状态词此前只住在远程历史页的一个私有 switch 里。
/// 收件行直接再写一份 switch，就是同一张词表的两处抄本 —— 契约加一档时
/// 两处迟早各改一半，屏上同时出现人话与机器词。
///
/// [knownStates] 传契约的 `remoteExecutionStates`：**存量出现词表外的状态时显示
/// "不认得"**，不当它等于某个已知状态 —— 那是这一格最容易犯的错：把"读不出来"
/// 说成"执行完毕"。传 null（读不到契约的地方）跳过这道漂移检查，
/// 词表外的状态仍由 `_` 臂兜回"不认得"，两种入口的输出一致。
String fnthinkRemoteExecutionStateWord(
  AppLocalizations l10n,
  String state, {
  List<String>? knownStates,
}) {
  if (knownStates != null && !knownStates.contains(state)) {
    return l10n.remoteHistoryStateUnknown(state);
  }
  return switch (state) {
    RemoteExecutionStates.pending => l10n.remoteHistoryPending,
    RemoteExecutionStates.executing => l10n.remoteHistoryExecuting,
    RemoteExecutionStates.done => l10n.remoteHistoryDone,
    RemoteExecutionStates.failed => l10n.remoteHistoryFailed,
    RemoteExecutionStates.cancelled => l10n.remoteHistoryCancelled,
    _ => l10n.remoteHistoryStateUnknown(state),
  };
}
