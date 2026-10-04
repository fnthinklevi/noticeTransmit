import 'dart:async';

import 'package:fnthink_push/fnthink_push.dart';

import '../models/fnthink_inbox_message.dart';
import '../models/fnthink_remote_execution_record.dart';
import 'fnthink_remote_command_handler.dart';
import 'fnthink_remote_execution.dart';
import 'fnthink_remote_runner.dart';

/// 收货循环那一格与判定层之间的**接线**（片3c-4）。
///
/// ⚠ 它存在的理由：`FnthinkReceiveLoop` 的 `onCommand`（判「这条要不要按通知弹出来」）
/// 与 `RemoteCommandRecognizer`（判「该不该执行」）之间**没有任何一行代码**——
/// 循环那一格从 8.183 起就挂着 `onCommand`，而 DI 里从来没给它值。
/// 缺这一层的后果不是崩：那些指令消息会**照常按通知弹出来**，
/// 而没有任何东西动手 —— 用户看到的是"对方说发了指令，我这边响了一声"。
///
/// ## 被拒的那一档也要留痕、也要回执
/// `RemoteCommandRejected` 不等于"什么都不做"：对面在等一个答复。
/// 对外的形状用**第二段回执**（`execution_done` + 终态 `failed`），
/// 理由字符串逐字带上（`auth:wrong` / `item:…` / `source-not-allowed:…`）——
/// ⚠ **不为"被拒"另造一个回执词**：那是顶层 `receipts` 封闭词表里的第二个新词，
/// 而「被拒」与「执行没成」对对面来说本来就是同一件事（我这台照你的话办了，没办成）。
/// 区分它们靠的是 `reason`，不是对外那个词。
///
/// ## 白名单那一路不回执
/// 判据是 [remoteExecutionSendsReceipt] 按 `source` 判 —— 那正是
/// `RemoteCommandRejected.source` 存在的理由。
class RemoteCommandWiring {
  const RemoteCommandWiring({
    required this.contract,
    required this.recognizer,
    required this.runner,
    required this.saveRecord,
  });

  final FnthinkContract contract;
  final RemoteCommandRecognizer recognizer;
  final RemoteCommandRunner runner;

  /// 落一行历史（拒的那一档也要落，见类注释）。
  final Future<void> Function(FnthinkRemoteExecutionRecord record) saveRecord;

  /// 收货循环挂的那一格：**回 true = 这是指令，别按通知弹出来**。
  Future<bool> onCommand(FnthinkInboxMessage message) async {
    final parsed = await recognizer.parse(message);
    switch (parsed) {
      case RemoteCommandNotACommand():
      case RemoteCommandNotEnabled():
        // 两种都**照常显示**：前者本来就不是指令；后者是"开关关着"，
        // 回"拒"的话那条消息会被吃掉且不显示、也不留痕 ——
        // 用户唯一看到的现象是"对方说发了，我这儿什么也没有"。
        return false;
      case RemoteCommandRejected():
        await _recordRejected(parsed);
        return true;
      case RemoteCommandAccepted():
        await runner.run(parsed);
        return true;
    }
  }

  Future<void> _recordRejected(RemoteCommandRejected rejected) async {
    final now = DateTime.now();
    final execId = newRemoteExecutionId(
      'rejected|${rejected.sender}|${rejected.command.level}|'
      '${rejected.command.item}|${now.millisecondsSinceEpoch}',
    );
    final record = FnthinkRemoteExecutionRecord(
      execId: execId,
      direction: kFnthinkRemoteDirectionIn,
      peerAddress: rejected.sender,
      level: rejected.command.level,
      item: rejected.command.item,
      argument: rejected.command.argument,
      // ⚠ 终态直接给 `failed` 而不是 `pending`：它没有窗口、不会执行，
      //   写成 pending 的话界面上会一直显示"待执行"而永远等不到结果。
      state: RemoteExecutionStates.failed,
      source: rejected.source,
      createdAt: now.millisecondsSinceEpoch,
      reason: rejected.reason,
    );
    await saveRecord(record);
    if (!remoteExecutionSendsReceipt(contract, rejected.source)) return;
    final receipt = remoteExecutionReceiptFor(
      contract: contract,
      level: record.level,
      item: record.item,
      argument: record.argument,
      state: RemoteExecutionStates.failed,
    );
    if (receipt == null) return;
    await runner.replyReceipt(rejected.sender, receipt);
  }
}
