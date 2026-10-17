import 'dart:async';

import 'package:fnthink_push/fnthink_push.dart';

import '../models/fnthink_inbox_message.dart';
import '../models/fnthink_remote_execution_record.dart';
import 'fnthink_remote_command_handler.dart';
import 'fnthink_remote_execution.dart';
import 'fnthink_remote_out_record.dart';
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
///
/// ## 回执也是"不是消息"（T143 片2）
/// 对面回给我的 `FRR1:` 那一条走的是**同一条收件路**（线上它就是一条 L1 通知），
/// 所以认领它的位置只能在 [onCommand] 里、在判定"要不要弹出来"那一格之前。
/// ⚠ 这一段与指令那一段**共用前缀纪律但不同前缀**（`FRX1:` / `FRR1:`）：
/// 少了这一格，回执会被当成一条消息弹出来，而本机那一行永远停在"待执行"。
class RemoteCommandWiring {
  const RemoteCommandWiring({
    required this.contract,
    required this.recognizer,
    required this.runner,
    required this.notifier,
    required this.saveRecord,
    required this.loadRecord,
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

  /// 按关联键读发起端那一行（T143 片2 认领回执）。
  ///
  /// ⚠ 同样必填、不给默认值：这一格漏接时**症状比缺 `notifier` 更隐蔽** ——
  ///   回执照常被吃掉（不弹成通知）、对面也一切正常，只有本机那一行停在"待执行"，
  ///   而界面那句"已交出去"读起来完全没错。
  final Future<FnthinkRemoteExecutionRecord?> Function(String execId)
  loadRecord;

  /// 收货循环挂的那一格：**回 true = 这是指令，别按通知弹出来**。
  ///
  /// ⚠ 只有 `NotACommand` 那一路回 false。开关关着（`switch-off`）在 2026-10-12 裁定 1 之后
  /// 走的是**拒**那一档 ⇒ 留痕 + 回对面一条 `failed` 回执 + **不按通知弹**：一条远程指令是
  /// 一次动作，把它显示成一条消息就是把动作冒充成消息（维护者报的那个形状）。
  Future<bool> onCommand(FnthinkInboxMessage message) async {
    // 先认回执（T143 片2）：它是一条**答复**，既不是消息也不是一条要执行的指令。
    // ⚠ 必须排在 [RemoteCommandRecognizer.parse] **之前**：`FRR1:` 拆不进指令信封（前缀不同），
    //   排在后面会走 `NotACommand` 那一档被当普通通知弹出来。
    final receipt = RemoteReceiptEnvelope.decode(message.body);
    if (receipt != null) return _claimReceipt(receipt);
    final parsed = await recognizer.parse(message);
    switch (parsed) {
      case RemoteCommandNotACommand():
        // 它本来就不是指令 ⇒ 是一条普通消息，照常显示、不进远程历史。
        return false;
      case RemoteCommandRejected():
        await _recordRejected(parsed, messageId: message.messageId);
        return true;
      case RemoteCommandAccepted():
        await runner.run(parsed, messageId: message.messageId);
        return true;
    }
  }

  /// 认领一段回执 ⇒ 更新本机那一行（out 方向）。**恒回 true**（不弹成通知）。
  ///
  /// ⚠ 认领不上也回 true：一段回执不是一条消息，"我这台没这一行"（重启前发的、
  ///   或这台根本只收不发）不是把它显示出来的理由 —— 显示出来反而让用户以为对面来了一条话。
  /// 「能不能认领、动哪一格」的判据只住在 [remoteOutRowForReceipt]，这里不做第二次判断。
  Future<bool> _claimReceipt(RemoteReceipt receipt) async {
    final moved = remoteOutRowForReceipt(
      contract: contract,
      receipt: receipt,
      row: await loadRecord(receipt.exec),
    );
    if (moved == null) return true;
    await saveRecord(moved);
    return true;
  }

  Future<void> _recordRejected(
    RemoteCommandRejected rejected, {
    required String messageId,
  }) async {
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
      messageId: messageId,
    );
    await saveRecord(record);
    if (!remoteExecutionSendsReceipt(contract, rejected.source)) return;
    final receipt = remoteExecutionReceiptFor(
      contract: contract,
      level: record.level,
      item: record.item,
      argument: record.argument,
      state: RemoteExecutionStates.failed,
      // 被拒的那一发也要带回关联键：对面那一行否则同样停在 pending，而它**已经知道**没成。
      exec: rejected.command.exec,
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
  /// ## ⚠ 这一路只有「不是指令」那一档什么都不做
  /// 白名单通知**已经显示过了**（那条通知本身在通知栏里），所以 [RemoteCommandNotACommand]
  /// 直接返回、**不留痕** —— 留一行"没执行"的记录只会让历史里堆满噪声。
  /// 拒的那一档（含 `switch-off`）仍然留痕（复用 [_recordRejected]）：那里用户看到的是
  /// "通知正常、什么也没发生"，没有痕迹就永远查不出原因。
  /// ⚠ 但**不回执**：这一路没有远端发送方，`remoteExecutionSendsReceipt(contract, source)`
  /// 按契约 `localTriggerReceipt=none` 判掉 —— 这正是 [RemoteCommandRejected.source]
  /// 这一格存在的理由（拿 `sender` 当来源会朝一个不存在的地址发回执）。
  ///
  /// ## sender 恒为空串
  /// ⚠ 不是"没有 sender 所以填空"，而是**界面按 `peerAddress.isEmpty` 判**
  /// （`remote_history_page.dart`）⇒ 填一个本机包名会让历史行显示成"来自 com.xxx"，
  /// 把一台本机应用说成对面设备。留痕也不该记通知来源包名：执行留痕回答的是
  /// "谁让这台设备做了什么"（契约 `execution.fieldsWhy`），而本机这一路没有"谁"。
  ///
  /// ## 但 [sourcePackage] 要传进判定
  /// 它是「哪些应用的通知才允许触发」那一档唯一的输入（T145 ③）。⚠ 它**只当判据输入**，
  /// 不落进留痕的 sender、不进回执 —— 上面那一格的说法照旧成立。
  Future<void> onLocalContent(
    String content, {
    required String sourcePackage,
  }) async {
    final command = RemoteCommandEnvelope.decode(content);
    if (command == null) return;
    final parsed = await recognizer.judge(
      command: command,
      sender: '',
      sourcePackage: sourcePackage,
      source: contract.remoteExecutionLocalTriggerSource,
      // ⚠ **缺省档，不是"全给"**：这一路没有远端发送方，名单里那一行无从查起，而
      //   「本机白名单触发」**不等于**「本机用户勾过这一项」—— L3 的逐条勾选是那台设备上
      //   的人点出来的，不能从一条通知的正文里继承。
      //   这里显式给契约的 `grantDefaults`（L1 + 空清单）而不是省略参数：`grant` 一旦有个
      //   "全给"的默认值，这道收窄就静默消失了（T128 片2 把它从可选形参改成必填的同一理由）。
      //   它只放行 L1 也够这一路用：来源渠道那一道按契约 `sources` 已经把 L2/L3 拒了
      //   （`sources.L1` 是唯一含本机来源的那一档）。
      grant: FnthinkGrant(maxLevel: contract.grantDefaultMaxLevel),
    );
    switch (parsed) {
      case RemoteCommandNotACommand():
        return;
      case RemoteCommandRejected():
        await _recordRejected(parsed, messageId: '');
        return;
      case RemoteCommandAccepted():
        await runner.run(parsed, messageId: '');
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
      final item = await notifier.takeLocalCommand();
      if (item == null || item.body.isEmpty) break;
      taken++;
      await onLocalContent(item.body, sourcePackage: item.package);
    }
    return taken;
  }
}
