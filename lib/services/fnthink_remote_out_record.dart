/// 发起端那一发的 out 行（T143 片1，维护者 2026-10-12 裁定 2）。
///
/// ## 为什么这一行此前根本不存在
/// `fnthink_remote_executions` 的**四个生产写入点全是 in 方向**（被拒档、pending、终态、
/// sweep 沿用原行方向），而历史页默认档是 `in` ⇒「发」那一档点进去**恒空**：
/// 从按下到 send 返回，本机一个字都没记，而界面上那句"这一发已经交出去了"是当场说给用户听的。
/// 说的和记的不是同一件事，回头就没法查。
///
/// ## 这一层只管发起端自己知道的那两件事
/// ① 我发了什么（对端 / 级别 / 项 / 参数），② 有没有交出去（send 的结论）。
/// ⚠ **不含对面执行到哪一步**：回执载荷里没有关联键（`execId` 与原 `messageId` 都不在），
///   同一枚指令连发两次时分不清哪一发被确认 —— 那是片2，且它有一拍等维护者定（加键＝协议变更）。
///   所以 send 成功之后这一行**停在 `pending`**：界面那句话只能是"已交出去、等对面回执"，
///   不许提前写成"做完了"。
library;

import '../database/database_helper.dart';
import '../models/fnthink_remote_execution_record.dart';
import 'fnthink_remote_execution.dart';

/// 生产那一份写口（四个装配点共用一份，别各抄一遍 lambda）。
///
/// 走的是 `DatabaseHelper().saveRemoteExecutionRecord` —— 与 in 方向那两枚 `saveRecord`
/// （`service_locator.dart` 里逐字同一个实现）**同一个方法**：一张表两个写入者各写一份 SQL
/// 是另一族坑（T20 那条纪律）。
Future<void> saveRemoteExecutionRow(FnthinkRemoteExecutionRecord record) =>
    DatabaseHelper().saveRemoteExecutionRecord(record);

/// 这一行的来源那一维（契约 `remoteExecution.sources` 是封闭两档）。
///
/// 发起端是自己按下的，走的是幻念那条路 ⇒ 只有 `fnthink` 说得通；
/// `localNotificationWhitelist` 说的是"本机通知触发执行"那一路（in 方向），不是这一路。
const String kFnthinkRemoteOutSource = 'fnthink';

/// 按下那一发时造的那一行（`pending`）。
///
/// ⚠ `at` 用**这一次按下**的时刻，不是 send 返回的时刻：这一行要回答的第一件事是
///   "我什么时候按的"，而那一发可能在网络路上停几秒。
FnthinkRemoteExecutionRecord remoteOutRow({
  required String execId,
  required String peer,
  required String level,
  required String item,
  required String argument,
  required DateTime at,
}) => FnthinkRemoteExecutionRecord(
  execId: execId,
  direction: kFnthinkRemoteDirectionOut,
  peerAddress: peer,
  level: level,
  item: item,
  argument: argument,
  state: RemoteExecutionStates.pending,
  source: kFnthinkRemoteOutSource,
  createdAt: at.millisecondsSinceEpoch,
);

/// send 那一发回来之后这一行长什么样（**覆盖同一行**，`execId` 不变）。
///
/// 交出去 ⇒ 原样留着 `pending`（对面还没回执，这里不许替它编一个终态）；
/// 没交出去 ⇒ `failed` + 理由。[reason] 传的是 send 结果里那枚机器词
/// （`network` / `notFound` / `locked` 之类），界面按词表翻成人话。
FnthinkRemoteExecutionRecord remoteOutRowAfterSend(
  FnthinkRemoteExecutionRecord row, {
  required bool accepted,
  String reason = '',
}) {
  if (accepted) return row;
  return FnthinkRemoteExecutionRecord(
    execId: row.execId,
    direction: row.direction,
    peerAddress: row.peerAddress,
    level: row.level,
    item: row.item,
    argument: row.argument,
    state: RemoteExecutionStates.failed,
    source: row.source,
    createdAt: row.createdAt,
    result: row.result,
    reason: reason,
  );
}
