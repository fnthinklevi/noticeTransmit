import 'package:fnthink_push/fnthink_push.dart';

import '../services/fnthink_remote_execution.dart';

/// 远程执行历史的一条（片3b）。
///
/// 维护者 2026-10-03 定：**所有远程执行指令都存在远程执行历史记录里，区分收指令和发指令**。
/// 与 `FnthinkInboxMessage` 的方向档同一条纪律（复用 `direction` 的语义），但**是另一张表** ——
/// 两者回答的问题不同：收件表回答"消息到了没有"，这张表回答"这条指令执行到哪一步了"。
/// 合成一张表的后果是"一条还没执行的消息"与"一条执行了一半的消息"长得一样，
/// 而它们在界面上的下一步动作完全不同（等 vs 去查为什么没成）。
///
/// ⚠ 凭据**不进这张表**（契约 `execution.forbiddenFields` 同一份黑名单）：
/// 种子与哈希对"这条指令后来怎么了"这个问题没有任何用处，而它们进来就等于给每个
/// 能读本机数据库的人发一把钥匙。
class FnthinkRemoteExecutionRecord {
  const FnthinkRemoteExecutionRecord({
    required this.execId,
    required this.direction,
    required this.peerAddress,
    required this.level,
    required this.item,
    required this.argument,
    required this.state,
    required this.source,
    required this.createdAt,
    this.result = '',
    this.reason = '',
  });

  /// 本机给这一条的主键。⚠ 为什么要有它而不是拿消息号当主键：
  /// 本机白名单应用触发的那一路**没有远端消息号**（契约 `localTriggerReceipt:"none"`
  /// 说明那条路上根本没有远端发送方），主键不能建在一个一半时候不存在的列上。
  final String execId;

  /// `in` = 别人让这台设备做事；`out` = 这台设备让别人做事。
  /// ⚠ 与 `FnthinkInboxMessage.direction` **同一套词**，不另起一个（两个方向词表
  /// 迟早会不一样，而界面上"收指令/发指令"那两个档位是同一个开关）。
  final String direction;

  /// 另一端是谁（对端地址码；本机触发的那一行是空串 —— 没有对端）。
  final String peerAddress;

  /// L1 / L2 / L3（契约 `capabilities.levels`）。
  final String level;

  /// 要动的那一项（`listener:start` / `exact_alarm` 之类）。
  final String item;

  /// 参数（`channel:toggle` 才有；其余空串）。
  final String argument;

  /// 执行状态机的五档之一（契约 `remoteExecution.states`）。
  final String state;

  /// 指令从哪来：`fnthink` 或 `localNotificationWhitelist`（契约 `remoteExecution.sources`）。
  ///
  /// ⚠ 落盘而不是只当个标签：白名单那一路**没有远端发送方**，所以"这一条是哪来的"
  /// 是那一路上唯一能回答"谁干的"的线索（`peerAddress` 是空的）。
  final String source;

  final int createdAt;

  /// 完成时的结果摘要（**只放已经算好的短句**，不放正文与凭据）。
  final String result;

  /// 没成的理由（机器词，如 `cancelled-by-user` / `wrong`）。
  final String reason;

  bool get incoming => direction == kFnthinkRemoteDirectionIn;
  bool get outgoing => direction == kFnthinkRemoteDirectionOut;

  /// 还在跑（还没到终态）⇒ 界面上要给"撤销"那一下。
  bool get unsettled =>
      state == RemoteExecutionStates.pending ||
      state == RemoteExecutionStates.executing;

  /// 收成一行（**白名单以外的键一个都不出** —— 与 `FnthinkExecutionLog.toRow` 同一纪律）。
  Map<String, Object?> toRow() => {
    'exec_id': execId,
    'direction': direction,
    'peer_address': peerAddress,
    'level': level,
    'item': item,
    'argument': argument,
    'state': state,
    'source': source,
    'created_at': createdAt,
    'result': result,
    'reason': reason,
  };

  static const table = 'fnthink_remote_executions';

  static const columns = <String>[
    'exec_id',
    'direction',
    'peer_address',
    'level',
    'item',
    'argument',
    'state',
    'source',
    'created_at',
    'result',
    'reason',
  ];

  static FnthinkRemoteExecutionRecord fromMap(Map<String, Object?> map) =>
      FnthinkRemoteExecutionRecord(
        execId: '${map['exec_id'] ?? ''}',
        direction: '${map['direction'] ?? kFnthinkRemoteDirectionIn}',
        peerAddress: '${map['peer_address'] ?? ''}',
        level: '${map['level'] ?? ''}',
        item: '${map['item'] ?? ''}',
        argument: '${map['argument'] ?? ''}',
        state: '${map['state'] ?? ''}',
        source: '${map['source'] ?? ''}',
        createdAt: (map['created_at'] as num?)?.toInt() ?? 0,
        result: '${map['result'] ?? ''}',
        reason: '${map['reason'] ?? ''}',
      );

  @override
  String toString() =>
      'FnthinkRemoteExecutionRecord($execId $direction $level $item=$state)';
}

/// 方向词的**唯一定义**（与 `FnthinkInboxMessage` 共用同一对词，不另起名字）。
const String kFnthinkRemoteDirectionIn = 'in';
const String kFnthinkRemoteDirectionOut = 'out';

/// 造一行的主键。⚠ 不带时间戳前缀也没关系：主键只要求"本机这一列不重复"，
/// 而 `created_at` 已经带着时间，做两个可排的列是为了"同一毫秒里来两条"也能各存一条。
String newRemoteExecutionId(String seed) {
  var h = 0x811c9dc5;
  for (final unit in seed.codeUnits) {
    h = ((h ^ unit) * 0x01000193) & 0x7fffffff;
  }
  return 'x${h.toRadixString(16).padLeft(8, '0')}';
}

/// 收成一句人话的形状（界面唯一作者在页面层，这一处只给数据）。
///
/// ⚠ **不许在这里拼"远程指令 XX 执行完毕"那句话**：那是回执的形状（走消息发给 A），
/// 历史的这一行是本机自己的记录，两者混在一起会出现"界面上写着执行完毕、
/// 而对面其实没收到任何回执"。
RemoteExecutionRecordView viewRemoteExecutionRecord(
  FnthinkContract contract,
  FnthinkRemoteExecutionRecord record,
) => RemoteExecutionRecordView(
  state: record.state,
  stateKnown: contract.remoteExecutionStates.contains(record.state),
  result: record.result,
  reason: record.reason,
);

/// 界面上要用的那一格（把"状态词存不认得"与"状态词认得"分开 ——
/// 存量里出现词表外的状态时必须显示成"不认得"，不能当它等于某个已知状态）。
class RemoteExecutionRecordView {
  const RemoteExecutionRecordView({
    required this.state,
    required this.stateKnown,
    required this.result,
    required this.reason,
  });

  final String state;
  final bool stateKnown;
  final String result;
  final String reason;
}
