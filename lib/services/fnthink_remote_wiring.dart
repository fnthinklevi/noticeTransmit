import 'dart:async';

import 'package:fnthink_push/fnthink_push.dart';

import '../models/fnthink_inbox_message.dart';
import '../models/fnthink_remote_execution_record.dart';
import 'fnthink_remote_command_handler.dart';
import 'fnthink_remote_execution.dart';
import 'fnthink_remote_runner.dart';
import 'remote_execution_notifier.dart';

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
    required this.notifier,
    required this.saveRecord,
  });

  final FnthinkContract contract;
  final RemoteCommandRecognizer recognizer;
  final RemoteCommandRunner runner;

  /// 白名单那一路的取口。
  ///
  /// ⚠ 显式必填而不是从 `runner.statusBar` 拿：`statusBar` 是可空的，
  ///   而"白名单那一路没人取"这件事**没有任何症状**（通知照常显示、照常推送）——
  ///   可空的隐式依赖会让它退化成一条静默失效的链。要断，就在编译期断。
  final RemoteExecutionNotifier notifier;

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

  /// 白名单通知触发那一路（契约 `sources.L1` 的第二条来源）。
  ///
  /// ## 它**不是** [onCommand] 的第二个调用点，是另一条路
  /// 白名单通知**不进收件表** —— 它没有 [FnthinkInboxMessage] 可拆，也没有远端发送方。
  /// 但判定**复用同一份** [RemoteCommandRecognizer.judge]（`source` 换掉），不重写：
  /// 开关、来源渠道、凭据、item 形状这几道判据在这一条路上同样成立，
  /// 重写一遍就等于出现第二个"认不认得这条指令"的读者。
  ///
  /// ## ⚠ 四档里前两档在这里什么都不做
  /// [RemoteCommandNotACommand] / [RemoteCommandNotEnabled] 在收件表那一路是"照常显示"，
  /// 而这一路**已经显示过了**：那条通知本身就在通知栏里，用户看得见。
  /// 所以直接返回，且**不留痕** —— 留一行"没执行"的记录只会让历史里堆满噪声。
  /// 被拒那一档仍然留痕（复用 [_recordRejected]）：那里用户看到的是"通知正常、什么也没发生"，
  /// 没有痕迹就永远查不出原因。
  ///
  /// ## sender 恒为空串
  /// ⚠ 不是"没有 sender 所以填空"，而是**界面按 `peerAddress.isEmpty` 判**
  /// （`remote_history_page.dart`）⇒ 填一个本机包名会让历史行显示成"来自 com.xxx"，
  /// 把一台本机应用说成对面设备。留痕也不该记通知来源包名：执行留痕回答的是
  /// "谁让这台设备做了什么"（契约 `execution.fieldsWhy`），而本机这一路没有"谁"。
  Future<void> onLocalContent(String content) async {
    final command = RemoteCommandEnvelope.decode(content);
    if (command == null) return;
    final parsed = await recognizer.judge(
      command: command,
      sender: '',
      source: contract.remoteExecutionLocalTriggerSource,
      // ⚠ **不带任何前置授权**：L3 的"逐条勾选"是本机用户在那台设备上做的动作，
      //   不能从一条通知的正文里继承。这里显式给空集而不是省略参数 ——
      //   `grantedKeys` 一旦有个"全给"的默认值，这道收窄就静默消失了。
      grantedKeys: const <String>{},
    );
    switch (parsed) {
      case RemoteCommandNotACommand():
      case RemoteCommandNotEnabled():
        return;
      case RemoteCommandRejected():
        await _recordRejected(parsed);
        return;
      case RemoteCommandAccepted():
        await runner.run(parsed);
        return;
    }
  }

  /// 把原生那边攒着的取空（一次一条，循环到 null 为止）。
  ///
  /// ⚠ 调用方**必须**循环而不是只调一次：原生那一侧是 FIFO 且一次只给一条，
  ///   只取一次会留下后面几条，而它们既没被执行也没被丢弃 —— 下次 drain 才动。
  /// ⚠ 上限 [maxDrains]：原生那一侧已经限了 8 条，这里再多一层是防"取回来的是空串
  ///   之类的坏值"时把循环变成死循环 —— 每一轮都必须真的减少一条。
  Future<int> drainLocalCommands({int maxDrains = 16}) async {
    var taken = 0;
    for (var i = 0; i < maxDrains; i++) {
      final body = await notifier.takeLocalCommand();
      if (body == null || body.isEmpty) break;
      taken++;
      await onLocalContent(body);
    }
    return taken;
  }
}
