import 'fnthink_remote_execution_record.dart'
    show kFnthinkRemoteDirectionIn, kFnthinkRemoteDirectionOut;

/// 本机关于**一条配对请求**知道的全部（T116）。
///
/// 为什么必须落这一张表，而不是像 T110 那两片那样只放在协调者的内存账里：
/// 服务端对一条**已终态**请求的保留期就是它自己的 TTL（契约 `pairRequest.ttlSecondsFrom`
/// 引用口令那一个 TTL），到下一建新请求时被剪掉（`pairstore.createRequest` 里那段清扫）。
/// 于是「对方已拒绝」这句话在服务端只活几分钟，而用户问的恰恰是"后来怎么样了"——
/// 不落盘的话，重启、超时、剪枝三种情况都会把结论弄丢，而丢失的表现是"那一格空着"，
/// 用户读到的是"没发生过"。
///
/// 三个口径写在这里，都在数据这一层：
/// - **一行＝一条请求，两个主语用 `direction` 分开**（`in`＝冲我来的、等我答；
///   `out`＝我发起的、等对面答）。两个主语**不会撞主键**：请求 id 由服务端生成，
///   一条请求只有一个 id，本机上它只可能属于其中一个主语。
/// - **终态判定是 `changedAt > 0`，不是"状态词在某个名单里"**：`statusChangedAt` 这一列
///   按契约只有两处作者（本机答复与到期扫描），pending 的那一条服务端从没写过它。
///   再存一列布尔就是第二份真值，而两份真值早晚一张改了另一张没改。
/// - **时刻列一律是服务端那份**（`createdAt` / `changedAt` / `expiresAt`）；
///   `updatedAt` 才是本机时刻，它只回答"这一台最后一次看见它是什么时候"。
///
/// ⚠ **口令与摘要不进这张表**（契约 `pairRequest.neverStored` 同一份名单）：
/// 历史是本机留存最久的一份记录，而口令是"抄过、印在二维码里、可能被拍过照"的东西。
/// 界面上那一行要的只是「谁 · 哪一档 · 什么结论 · 什么时候」，口令一样都不贡献。
class FnthinkPairRequestRecord {
  const FnthinkPairRequestRecord({
    required this.requestId,
    required this.direction,
    required this.peerAddress,
    required this.updatedAt,
    this.level = '',
    this.status = '',
    this.createdAt = 0,
    this.changedAt = 0,
    this.expiresAt = 0,
  });

  /// 服务端那条请求的 id（主键）。
  final String requestId;

  /// `in` = 别人请求配对我、等我答复；`out` = 我请求配对别人、等对面答复。
  /// ⚠ 与 `FnthinkInboxMessage.direction`、`FnthinkRemoteExecutionRecord.direction`
  ///   同一对词（三张表的方向若各起一套名字，界面上"收/发"那两个档位迟早不一样）。
  final String direction;

  /// 另一端是谁。`out` 那档是"我发给谁"，`in` 那档是"谁在请求我"。
  final String peerAddress;

  /// 当时请求的是哪一档（空串 = 不知道，界面画 '—'，不许替对面决定成 L1）。
  final String level;

  /// 契约 `pairRequest.statuses` 里的那个词（原词存，不存本机翻译后的说法）。
  final String status;

  /// 这条请求什么时候立起来的（服务端时刻）。0 = 不知道。
  final int createdAt;

  /// 状态最后一次变更的那一刻（= 契约里出门叫 `at` 的那一列）。**0 = 还没变更过 ⇒ 还在等**。
  final int changedAt;

  /// 这条什么时候作废。0 = 不知道（过期判定不拿本机时钟说事）。
  final int expiresAt;

  /// 本机最后一次改写这一行的时刻。
  final int updatedAt;

  bool get incoming => direction == kFnthinkRemoteDirectionIn;
  bool get outgoing => direction == kFnthinkRemoteDirectionOut;

  /// 有没有结论了。判据是"状态变更那一列被写过没有"，见类注释第二条。
  bool get settled => changedAt > 0;

  Map<String, Object?> toRow() => {
    'request_id': requestId,
    'direction': direction,
    'peer_address': peerAddress,
    'level': level,
    'status': status,
    'created_at': createdAt,
    'changed_at': changedAt,
    'expires_at': expiresAt,
    'updated_at': updatedAt,
  };

  static const table = 'fnthink_pair_requests';

  static const columns = <String>[
    'request_id',
    'direction',
    'peer_address',
    'level',
    'status',
    'created_at',
    'changed_at',
    'expires_at',
    'updated_at',
  ];

  static FnthinkPairRequestRecord fromMap(Map<String, Object?> map) =>
      FnthinkPairRequestRecord(
        requestId: '${map['request_id'] ?? ''}',
        direction: '${map['direction'] ?? kFnthinkRemoteDirectionIn}',
        peerAddress: '${map['peer_address'] ?? ''}',
        level: '${map['level'] ?? ''}',
        status: '${map['status'] ?? ''}',
        createdAt: (map['created_at'] as num?)?.toInt() ?? 0,
        changedAt: (map['changed_at'] as num?)?.toInt() ?? 0,
        expiresAt: (map['expires_at'] as num?)?.toInt() ?? 0,
        updatedAt: (map['updated_at'] as num?)?.toInt() ?? 0,
      );

  @override
  String toString() =>
      'FnthinkPairRequestRecord($requestId $direction $peerAddress $status)';
}

/// 把一行写成"我发起的那一条"。三个来源（发起响应 / poll 的发起面 / 到期那一下）共用，
/// 免得每个调用点各拼一遍列名 —— 那正是"同一个字段在三个地方含义不同"的来路。
FnthinkPairRequestRecord outgoingPairRequest({
  required String requestId,
  required String target,
  required int updatedAt,
  String level = '',
  String status = '',
  int createdAt = 0,
  int changedAt = 0,
  int expiresAt = 0,
}) => FnthinkPairRequestRecord(
  requestId: requestId,
  direction: kFnthinkRemoteDirectionOut,
  peerAddress: target,
  level: level,
  status: status,
  createdAt: createdAt,
  changedAt: changedAt,
  expiresAt: expiresAt,
  updatedAt: updatedAt,
);

/// 把一行写成"冲我来的那一条"。
FnthinkPairRequestRecord incomingPairRequest({
  required String requestId,
  required String requester,
  required int updatedAt,
  String level = '',
  String status = '',
  int createdAt = 0,
  int changedAt = 0,
  int expiresAt = 0,
}) => FnthinkPairRequestRecord(
  requestId: requestId,
  direction: kFnthinkRemoteDirectionIn,
  peerAddress: requester,
  level: level,
  status: status,
  createdAt: createdAt,
  changedAt: changedAt,
  expiresAt: expiresAt,
  updatedAt: updatedAt,
);
