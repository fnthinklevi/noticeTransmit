/// 投递状态机（T34）· Dart 这一半。
///
/// 与 `server/lib/fnthink/delivery.js` 是同一套规则的两份实现，两者都只从契约
/// `delivery` / `retention` / `limits` / `waitingOnline` 段读表，并共读
/// `protocol/fnthink-vectors-v1.json` 的 `delivery` 组各断言一遍。
/// 为什么要两份实现还非要一致：这条链上一半在服务端（排队、过期、挤位），
/// 一半在设备上（ack、重发），不一致时不会报错，只会变成
/// 「设备以为还能重试，服务端已经把它转成 waiting_online」——然后正文留在中间态删不掉。
library;

import 'contract.dart';

/// 一次推进的返回值。
///
/// `ignored` 非空表示"这个状态遇到这个事件**什么都不该做**"（迟到的 ack、重复的 poll）。
/// 这里刻意不抛异常：这类事件来自网络上不可信的时序，抛错会让调用方在错误处理里
/// 再造一个状态机。但**未知的事件名/状态名**仍然抛 —— 那是编程错误，不是网络噪声。
class DeliveryStep {
  const DeliveryStep({
    required this.state,
    required this.attempts,
    required this.receipt,
    required this.deleteBody,
    required this.resend,
    required this.ignored,
  });

  final String state;

  /// 本轮已尝试投递的次数。`dispatch` 累加它，`peer_online` 把它重置为 1
  /// （转 waiting_online 已经结束上一轮，补发是新一轮 —— 见 advanceDelivery 那段注释）。
  final int attempts;

  /// 要回给发送端的异步回执名，null 表示这一步不发回执。
  final String? receipt;

  /// 正文是否必须在此刻删除（契约 `retention.deleteBodyOn` 决定，不在代码里写状态名）。
  final bool deleteBody;

  /// 进入 `waiting_online` 时该走哪条补发路（取自契约 `waitingOnline` 段）。
  final String? resend;

  /// 被忽略的原因，形如 `ignored:queued+ack_ok`；null 表示这一步生效了。
  final String? ignored;

  bool get changed => ignored == null;

  @override
  String toString() =>
      'DeliveryStep($state, attempts=$attempts, receipt=$receipt, '
      'deleteBody=$deleteBody, resend=$resend, ignored=$ignored)';
}

/// 总尝试数 = 首次投递 + 重试次数。契约里那句 `_retryTotalMeans` 就是为了这一行不歧义。
int deliveryMaxAttempts(FnthinkContract contract) =>
    (contract.intOf(const ['limits', 'deliveryRetryTotal']) ?? 0) + 1;

/// 状态名取自契约表；不在表里直接抛（两边都不许自己造状态）。
String deliveryInitialState(FnthinkContract contract) {
  final state = contract.str(const ['delivery', 'initialState']);
  final states = contract.strings(const ['delivery', 'states']);
  if (state == null || !states.contains(state)) {
    throw StateError('delivery.initialState 不在 states 里：$state');
  }
  return state;
}

bool isDeliveryTerminal(FnthinkContract contract, String state) =>
    contract.strings(const ['delivery', 'terminalStates']).contains(state);

/// 终态必须释放正文 —— 这条不是这里的判断，而是契约 validate() 的不变量。
/// 这里只是**按契约表**回答，绝不写 `state == 'delivered' || state == 'expired'`：
/// 那是在代码里存第二份释放条件（第一版就漏了 `dropped`）。
bool releasesDeliveryBody(FnthinkContract contract, String state) =>
    contract.strings(const ['retention', 'deleteBodyOn']).contains(state);

bool canTransitionDelivery(FnthinkContract contract, String from, String to) {
  final table = contract.map(const ['delivery', 'transitions']);
  final targets = (table?[from] as List<Object?>?) ?? const [];
  return targets.map((e) => '$e').contains(to);
}

/// 排队中的消息是否已过最长保留期（`retention.maxRetentionDays`）。
bool isDeliveryExpired(
  FnthinkContract contract, {
  required int queuedAtMs,
  required int nowMs,
}) {
  final days = contract.intOf(const ['retention', 'maxRetentionDays']) ?? 0;
  if (days <= 0) return true;
  return nowMs - queuedAtMs >= days * 24 * 60 * 60 * 1000;
}

/// 状态机走一步。
///
/// 事件表（契约 `delivery.events`）：
/// - `dispatch`     设备 poll 取走这条（queued → delivering，尝试数 +1）
/// - `peer_online`  检测到这台设备上线（waiting_online → delivering，尝试数 +1）
/// - `ack_ok`       设备回"渲染成功"（唯一算送达的依据）
/// - `ack_fail`     设备回"没渲染成"
/// - `no_ack`       发了但没等到 ack（超时）
/// - `ttl_elapsed`  超过最长保留期
/// - `evicted`      被 pendingPerDeviceMax 上限挤掉
DeliveryStep advanceDelivery(
  FnthinkContract contract, {
  required String state,
  required String event,
  required int attempts,
  bool hasBackupChannel = false,
}) {
  final states = contract.strings(const ['delivery', 'states']);
  final events = contract.strings(const ['delivery', 'events']);
  if (!states.contains(state)) {
    throw ArgumentError.value(state, 'state', '不是契约里的投递状态');
  }
  if (!events.contains(event)) {
    throw ArgumentError.value(event, 'event', '不是契约里的投递事件');
  }
  final maxAttempts = deliveryMaxAttempts(contract);
  DeliveryStep to(
    String next, {
    int? at,
    String? receipt,
    String? resend,
    String? ignored,
  }) {
    return DeliveryStep(
      state: next,
      attempts: at ?? attempts,
      receipt: receipt,
      // 被忽略的那一步**什么都不该发生**：delivered 确实在 deleteBodyOn 里，
      // 但"重复 ack 触发一次删正文"是假的副作用（正文在真正进入终态那一步已经删过了）。
      deleteBody: ignored == null && releasesDeliveryBody(contract, next),
      resend: resend,
      ignored: ignored,
    );
  }

  DeliveryStep ignore() => to(state, ignored: 'ignored:$state+$event');

  String? waitingResend() {
    final section =
        contract.str(const ['delivery', 'resendDecisionFrom']) ??
        'waitingOnline';
    final table = contract.map([section]) ?? const {};
    final key = hasBackupChannel ? 'withBackupChannel' : 'withoutBackupChannel';
    return table[key] as String?;
  }

  switch (event) {
    case 'dispatch':
      if (state != 'queued') return ignore();
      // 尝试数已经用满 ⇒ 不再投，直接转 waiting_online（重试的出口在这里，不在 ack 分支）。
      if (attempts >= maxAttempts) {
        return to(
          'waiting_online',
          receipt: 'waiting_online',
          resend: waitingResend(),
        );
      }
      return to('delivering', at: attempts + 1);
    case 'peer_online':
      if (state != 'waiting_online') return ignore();
      // 尝试数按**投递轮次**算：转 waiting_online 已经结束了上一轮，补发是新一轮 ⇒ 回到 1。
      // 若把预算算成全局的，waiting_online 就成了死路（永远发不出去），与 §1 那张图直接矛盾。
      return to('delivering', at: 1);
    case 'ack_ok':
      if (state != 'delivering') return ignore();
      return to('delivered', receipt: 'delivered');
    case 'ack_fail':
    case 'no_ack':
      if (state != 'delivering') return ignore();
      if (attempts >= maxAttempts) {
        return to(
          'waiting_online',
          receipt: 'waiting_online',
          resend: waitingResend(),
        );
      }
      // 还有重试预算：留在 delivering（契约迁移表里的自环），等下一次 dispatch。
      return to('delivering');
    case 'ttl_elapsed':
      if (isDeliveryTerminal(contract, state)) return ignore();
      return to('expired', receipt: 'expired');
    case 'evicted':
      // 只有还没发出去的消息会被挤位；已经在飞的那条等它的 ack。
      if (state != 'queued') return ignore();
      return to('dropped', receipt: 'dropped');
    default:
      throw ArgumentError.value(event, 'event', '契约里有、实现没处理');
  }
}

/// pending 上限（`retention.pendingPerDeviceMax`）与溢出策略。
///
/// 溢出**丢最旧**（契约 `overflowAction = drop_oldest`），并给每条被丢的补一条
/// `dropped` 回执 —— 静默丢是这条产品不变量里明令禁止的那一半。
List<String> deliveryEvictionReceipts(FnthinkContract contract) {
  final action = contract.str(const ['retention', 'overflowAction']);
  if (action != 'drop_oldest') {
    throw StateError('契约的 overflowAction 不是 drop_oldest：$action');
  }
  final receipt = contract.str(const ['retention', 'overflowReceipt']);
  if (receipt == null || receipt.isEmpty) {
    throw StateError('retention.overflowReceipt 缺省：挤位必须发回执，不许静默丢');
  }
  return [receipt];
}

/// 新消息进来后需要挤掉多少条最旧的（0 = 不用挤）。
int deliveryEvictCount(
  FnthinkContract contract, {
  required int pendingNow,
  int incoming = 1,
}) {
  final max = contract.intOf(const ['retention', 'pendingPerDeviceMax']) ?? 0;
  if (max <= 0) return 0;
  final overflow = pendingNow + incoming - max;
  return overflow <= 0 ? 0 : overflow;
}
