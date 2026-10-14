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
/// ⚠ **不含对面执行到哪一步**：对面做到哪一步是**回执**的事，而回执是收货循环送进来的，
///   它落这一行的那一格住在 `remoteOutRowForReceipt`（片2 已落：载荷带 `exec` 关联键，
///   值就是这里的 `execId` ⇒ 认领得到具体那一发）。这一层因此只在 send 没交出去时写 `failed`，
///   交出去就**停在 `pending`**：界面那句话是"已交出去、等对面回执"，不许提前写成"做完了"。
library;

import 'package:fnthink_push/fnthink_push.dart';

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

/// 一段回执落到发起端那一行上，该变成什么样子（**T143 片2**：唯一作者）。
///
/// 回 `null` = **什么都不动**，四种情形各有原因：
/// - 回执没带关联键（对面是旧版）⇒ 猜不得：按 `(peer,level,item,argument)` 配最老那条
///   未终结行是维护者 2026-10-14 明确否掉的歧义版 —— 同一条连发两次时分不出哪一发
///   被确认，错认领会把另一行标成"已回执"（造出一条假回执）；
/// - 本机没有 `exec` 那一行（重启前发的、或这根本不是一台发起端）；
/// - 那一行不是 out 方向（in 行的状态由本机执行链自己写，外部回执不许插手）；
/// - 状态机两次都不认（重复回执、或已经到终态）。
///
/// ⚠ **`pending` 直接收到终态**为什么要绕一步：状态机要求 `pending → executing → 终态`，
///   而第一段回执（`executing`）在路上丢一次是完全可能的 —— 若因此拒写，那一行就
///   **永远停在"待执行"**，而对面明明已经回了"办完了 / 没办成"。
///   这里合成两步合法迁移（每一小步都照样过 [advanceRemoteExecution]，词表与进项都管着），
///   而不是放宽状态机 —— 放宽它等于让 in 方向那条链也可能一步跨过去。
FnthinkRemoteExecutionRecord? remoteOutRowForReceipt({
  required FnthinkContract contract,
  required RemoteReceipt receipt,
  FnthinkRemoteExecutionRecord? row,
}) {
  if (receipt.exec.isEmpty) return null;
  final at = row;
  if (at == null) return null;
  if (at.direction != kFnthinkRemoteDirectionOut) return null;
  final to =
      (receipt.isFinished ? receipt.state : null) ??
      RemoteExecutionStates.executing;
  if (!contract.remoteExecutionStates.contains(to)) return null;
  final moved = _advanceOrBridge(contract, at.state, to);
  if (moved == null) return null;
  return FnthinkRemoteExecutionRecord(
    execId: at.execId,
    direction: at.direction,
    peerAddress: at.peerAddress,
    level: at.level,
    item: at.item,
    argument: at.argument,
    state: moved,
    source: at.source,
    createdAt: at.createdAt,
    // 回执说的是"对面那一段"，与 in 方向的执行结果同列：界面读的是这一格。
    result: receipt.result,
    // ⚠ 原样留着：`network` 那一枚记的是"我这一发在路上停过"，与对面办没办成是两件事。
    reason: at.reason,
  );
}

/// 先按状态机走一步；走不通时试"经 `executing` 的那两步"（只认**每一小步都合法**的）。
String? _advanceOrBridge(FnthinkContract contract, String from, String to) {
  final direct = advanceRemoteExecution(contract, from, to);
  if (direct case RemoteExecutionMoved(to: final d)) return d;
  const via = RemoteExecutionStates.executing;
  if (from == via || to == via) return null;
  final step1 = advanceRemoteExecution(contract, from, via);
  if (step1 case RemoteExecutionMoved(to: final m1)) {
    final step2 = advanceRemoteExecution(contract, m1, to);
    if (step2 case RemoteExecutionMoved(to: final m2)) return m2;
  }
  return null;
}
