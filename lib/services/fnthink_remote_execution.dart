import 'package:fnthink_push/fnthink_push.dart';

import 'fnthink_execution_log.dart';

/// 远程执行的**设备侧内核**（T-远程执行 批次 片2）：状态机 + 延时窗口 + 凭据校验 +
/// 两段回执 + 留痕映射。**纯函数，不碰界面、不碰通道、不碰 DB** —— 真实执行（MethodChannel）
/// 与真实 TOTP / 密钥存储分别落在片2 的接线与片3。
///
/// ⚠ 这里的每一个词都**从契约读**（`capabilities.remoteExecution.*`），本文件只提供形状：
/// 状态名的常量、允许的迁移、判定分支。理由与本仓其他几片一样 ——
/// 规则只该在契约里有一份，两端各持映射，两份一起改就会漂移。

/// 状态名（契约 `capabilities.remoteExecution.states` 的五档）。
///
/// ⚠ 这几个常量只是"调用方少打错字"，**不是第二份词表**：`test/` 有一条守卫断它们与
/// 契约那份逐项相等（`remote_execution_test.dart` 的「五态与契约逐项一致」）。
class RemoteExecutionStates {
  const RemoteExecutionStates._();

  static const String pending = 'pending';
  static const String executing = 'executing';
  static const String done = 'done';
  static const String failed = 'failed';
  static const String cancelled = 'cancelled';
}

/// 一次状态迁移的结论。
sealed class RemoteExecutionTransition {
  const RemoteExecutionTransition();
}

/// 迁成了。
class RemoteExecutionMoved extends RemoteExecutionTransition {
  const RemoteExecutionMoved(this.from, this.to);

  final String from;
  final String to;
}

/// 不许迁（**理由分四类，不合并** —— 界面与留痕要分别处置这四类）。
class RemoteExecutionRefused extends RemoteExecutionTransition {
  const RemoteExecutionRefused(this.from, this.to, this.reason);

  final String from;
  final String to;

  /// `unknown-state`（from 不在词表）｜`terminal-state`（from 是终态）｜
  /// `illegal-move`（这一跳不在允许表里）。
  final String reason;
}

/// 允许的迁移（[RemoteExecutionTransition] 的唯一出处）。
///
/// ⚠ 为什么只有这五条：延时到点才能 `pending → executing`（安全闸是"凭据 × 渠道"，
/// 不是执行前必须有人点头 —— 见 §7 第 8.176/8.177 版的 confirmForm 改形）；
/// `cancelled` 可从 `pending` 与 `executing` 来（用户在窗口内撤销）；
/// `done` / `failed` 是**终态**，进来之后谁也走不动（一条执行不许复活 —— 复活会让
/// "已执行完毕"那条回执之后又冒出一次结果）。
const Map<String, Set<String>> kRemoteExecutionMoves = {
  RemoteExecutionStates.pending: {
    RemoteExecutionStates.executing,
    RemoteExecutionStates.cancelled,
  },
  RemoteExecutionStates.executing: {
    RemoteExecutionStates.done,
    RemoteExecutionStates.failed,
    RemoteExecutionStates.cancelled,
  },
};

/// 判一次迁移。**非法迁移一律拒**（不是静默保持原状态 —— 静默保持的表现是
/// "调用方以为迁了、其实没迁"，界面与留痕于是各说各话）。
RemoteExecutionTransition advanceRemoteExecution(
  FnthinkContract contract,
  String from,
  String to,
) {
  final states = contract.remoteExecutionStates;
  if (!states.contains(from) || !states.contains(to)) {
    return RemoteExecutionRefused(from, to, 'unknown-state');
  }
  if (kRemoteExecutionMoves[from]?.contains(to) == true) {
    return RemoteExecutionMoved(from, to);
  }
  // 终态：from 有进项（不等于 to 有出项）
  final isTerminal = kRemoteExecutionMoves[from] == null;
  return RemoteExecutionRefused(
    from,
    to,
    isTerminal ? 'terminal-state' : 'illegal-move',
  );
}

/// 延时窗口的判定结论。
sealed class RemoteExecutionGate {
  const RemoteExecutionGate();
}

/// 到点了（或窗口是 0）⇒ 执行。
class RemoteExecutionGateGo extends RemoteExecutionGate {
  const RemoteExecutionGateGo();
}

/// 还在窗口内 ⇒ 等。
class RemoteExecutionGateWait extends RemoteExecutionGate {
  const RemoteExecutionGateWait(this.remaining);

  /// 还差多少毫秒才到点（0 也算到点）。
  final int remaining;
}

/// 窗口内被用户撤销 ⇒ 不执行。
class RemoteExecutionGateCancelled extends RemoteExecutionGate {
  const RemoteExecutionGateCancelled();
}

/// 延时窗口判定（维护者 2026-10-03 定：默认 10s、0–60s、**超时默认执行**、用户在场与否不影响计时）。
///
/// ⚠ **窗口是"撤销机会"不是"确认"**（契约 `l3.confirmForm = "cancelableDelay"`：
/// 「每次确认」的内核保留，形式从"点一下"变成"没去取消"）。
/// ⚠ 时钟由调用方注入：本函数只做算术，所以用例不用睡真表，也不用等到真实 10 秒。
RemoteExecutionGate resolveRemoteExecutionWindow({
  required FnthinkContract contract,
  required String state,
  required int windowSeconds,
  required DateTime startedAt,
  required DateTime now,
  required bool cancelled,
}) {
  if (cancelled) return const RemoteExecutionGateCancelled();
  final deadline = startedAt.add(Duration(seconds: windowSeconds));
  final remaining = deadline.difference(now).inMilliseconds;
  if (remaining <= 0) return const RemoteExecutionGateGo();
  if (state != RemoteExecutionStates.pending) {
    // 已经在执行里就不该再看窗口 —— 不这么判的话，第二次进函数会把「执行中」当成
    // 「还没到点」，于是一条已开始的执行会被反复判成「等」。
    return const RemoteExecutionGateGo();
  }
  return RemoteExecutionGateWait(remaining);
}

/// 凭据校验的外部依赖（本片只定接口，真实 TOTP 与哈希比对在片3 的凭据设置页接）。
abstract class RemoteExecutionCredentialProbe {
  /// 高级密钥是否与本机存的那把对得上（本机只存哈希）。
  Future<bool> keyMatches(String presentedKey);

  /// TOTP 6 位码是否有效（B 是持有种子的一侧，校验在这里做）。
  Future<bool> totpValid(String code);
}

/// 凭据校验结论。
sealed class RemoteExecutionAuth {
  const RemoteExecutionAuth();
}

class RemoteExecutionAuthOk extends RemoteExecutionAuth {
  const RemoteExecutionAuthOk(this.presented);

  /// 实际带了哪一种（`key` / `totp` / 空串=没带；L2 不带凭据是合法的）。
  final String presented;
}

class RemoteExecutionAuthRejected extends RemoteExecutionAuth {
  const RemoteExecutionAuthRejected(this.reason);

  /// `missing-required`（该级别必须带而没带）｜`wrong`（带了但不对）｜
  /// `unsupported-mode`（带了但不是契约允许的那两种）。
  final String reason;
}

/// 凭据校验（维护者定：L2 的高级密钥/TOTP **可选**、L3 **必填**；缺或错一律拒）。
Future<RemoteExecutionAuth> checkRemoteExecutionAuth(
  FnthinkContract contract, {
  required String level,
  required String? key,
  required String? totpCode,
  required RemoteExecutionCredentialProbe probe,
}) async {
  final modes = contract.remoteExecutionAuthModes;
  final hasKey = key != null && key.isNotEmpty;
  final hasTotp = totpCode != null && totpCode.isNotEmpty;
  if (!hasKey && !hasTotp) {
    // 没带凭据：L3 拒；L2 放行（可选）；L1 从来不需要
    final required = level == 'L3'
        ? contract.remoteExecutionL3RequiresAuth
        : contract.remoteExecutionL2RequiresAuth;
    return required
        ? const RemoteExecutionAuthRejected('missing-required')
        : const RemoteExecutionAuthOk('');
  }
  if (hasKey && !modes.contains('key')) {
    return const RemoteExecutionAuthRejected('unsupported-mode');
  }
  if (hasTotp && !modes.contains('totp')) {
    return const RemoteExecutionAuthRejected('unsupported-mode');
  }
  // 带了：任一种对就过（契约 onMissingOrWrong = reject ⇒ 带了就必须对，不能"带了但不校验"）
  if (hasKey && await probe.keyMatches(key)) {
    return const RemoteExecutionAuthOk('key');
  }
  if (hasTotp && await probe.totpValid(totpCode)) {
    return const RemoteExecutionAuthOk('totp');
  }
  return const RemoteExecutionAuthRejected('wrong');
}

/// 两段回执的词（契约 `remoteExecution.receipts.started` / `.finished`；顶层 receipts 里各有一个）。
///
/// ⚠ 缺键抛而不返回默认：回执词**不许造第二个**（8.178 那条判据断的就是这个）——
/// 回一个 `delivered` 出去，界面上看起来"执行过"，而对端其实没收到任何东西。
String remoteExecutionStartedReceipt(FnthinkContract contract) {
  final word = contract.remoteExecutionReceipts['started'];
  if (word == null || word.isEmpty) {
    throw StateError('契约缺 capabilities.remoteExecution.receipts.started');
  }
  return word;
}

String remoteExecutionFinishedReceipt(FnthinkContract contract) {
  final word = contract.remoteExecutionReceipts['finished'];
  if (word == null || word.isEmpty) {
    throw StateError('契约缺 capabilities.remoteExecution.receipts.finished');
  }
  return word;
}

/// 把"这一条执行现在什么状态"收成一条留痕行（T53 的形状）。
///
/// ⚠ 映射口径（**只有这一个出处**，界面与审计都读它）：
/// `done → ok`；`failed → failed`；`cancelled → skipped` 且 reason `cancelled-by-user`
/// —— 用户主动撤销**不是失败**（失败是"该做但做不成"；撤销是"没让它做"，
/// 与 T50/T51 里 rejected/failed 刻意分开同一条纪律）；`pending` / `executing` **不写留痕**
/// （还没执行完就记一条，等于把"打算做"记成"做过"）。
///
/// ⚠ 只填 [FnthinkExecutionLog] 的白名单键（`argument` 之外的正文/口令根本无处可放 ——
/// 这个类型压根没有那个字段），所以 `execution.forbiddenFields` 那一道天然过。
FnthinkExecutionLog? remoteExecutionAuditRow({
  required String kind,
  required String item,
  required String argument,
  required String from,
  required String state,
  required int atMs,
  String? reason,
}) {
  final result = switch (state) {
    RemoteExecutionStates.done => 'ok',
    RemoteExecutionStates.failed => 'failed',
    RemoteExecutionStates.cancelled => 'skipped',
    _ => null,
  };
  if (result == null) return null;
  return FnthinkExecutionLog(
    kind: kind,
    item: item,
    argument: argument,
    from: from,
    result: result,
    at: atMs,
    reason: state == RemoteExecutionStates.cancelled
        ? 'cancelled-by-user'
        : reason,
  );
}
