/// 幻念推送的收件行（T47）。
///
/// 一条 = 别人推给**本机**的一条消息。它不进 `notifications` 表：那张表的列形态是
/// "本机抓到的通知"（包名、原生 id、逐通道送达信息），而这里是"谁推给我的什么内容"；
/// 混在一起还会顺带改掉 `recordCount` 那条导出契约（路线图 T47 明确不要这个）。
///
/// ⚠ 列名只在本文件的 [toDbRow]/[fromDbRow] 里出现 —— 表结构、SQL 与测试都读这一处。
/// 两端各写一份字符串是本仓反复付过学费的形态（见 `DeviceSnapshot` 开头那段）。
class FnthinkInboxMessage {
  const FnthinkInboxMessage({
    required this.messageId,
    required this.sender,
    required this.type,
    required this.item,
    required this.title,
    required this.body,
    required this.receivedAt,
    this.read = false,
    this.ackResult = '',
    this.ackedAt = 0,
  });

  /// 服务端给的消息主键（`m_` 前缀那串）。它同时是表主键：投递是 at-least-once
  /// （ack 之前不删正文），同一条会来第二次，而去重与 ack 都只能按这个 id 说话。
  final String messageId;

  /// 谁发的：配对设备是它的地址码，接入端点是 `endpoint:<id>`。
  /// 空串 = 未知来源（对端是没带 `sender` 那列的旧服务端）—— 未知不等于没有这条消息。
  final String sender;

  /// 事件种类（`notice` / `action` / `poll` 之类的词表值，出处是契约 capabilities）。
  final String type;

  /// `type=action` 时要动的那一项；端点来源一律为空（端点只能产 L1，产不出 action）。
  final String item;

  final String title;
  final String body;

  /// **本机**收到的时刻（毫秒）。不用服务端的 `queuedAt`：这一列的用途是"我的收件箱按
  /// 时间排序"，而跨设备的时间戳要靠服务端 `serverTime` 校正后才可比（内核已经在算偏移，
  /// 但落库时刻取本机时钟最诚实 —— 它回答的是"我什么时候拿到的"）。
  final int receivedAt;

  final bool read;

  /// 本机对这一条报过的结果（`delivered` / `displayed` / `rejected_*` / `failed_action`）。
  /// 空串 = 还没报出去。记的是**我自己那一半**的事实，不是服务端状态机那一份 ——
  /// 后者只有 poll 才拿得回来，两端各存一份"当前状态"迟早漂。
  final String ackResult;

  /// 报出去的时刻（毫秒），0 = 没报过。
  final int ackedAt;

  /// 表名（SQL 与测试共用这一处字面量）。
  static const table = 'fnthink_messages';

  static const columns = <String>[
    'message_id',
    'sender',
    'type',
    'item',
    'title',
    'body',
    'received_at',
    'read',
    'ack_result',
    'acked_at',
  ];

  Map<String, Object?> toDbRow() => {
    'message_id': messageId,
    'sender': sender,
    'type': type,
    'item': item,
    'title': title,
    'body': body,
    'received_at': receivedAt,
    // bool 落 0/1：SQLite 没有布尔列语义，而 `read == true` 在 Dart 侧是 bool、
    // 在库里是 INTEGER —— 这里不写 0/1，读取侧的 `as bool` 会当场抛。
    'read': read ? 1 : 0,
    'ack_result': ackResult,
    'acked_at': ackedAt,
  };

  /// 读一行。**不做兜底猜测**：`read` 只认 0/1 两个整数（其它形状说明库里存的不是本表
  /// 该存的东西，宁可抛出来，也别在界面上把"未知"显示成"已读"）。
  static FnthinkInboxMessage fromDbRow(Map<String, Object?> row) {
    final readRaw = row['read'];
    if (readRaw is! int) {
      throw StateError('fnthink_messages.read 不是整数（实为 $readRaw）：不猜已读状态');
    }
    return FnthinkInboxMessage(
      messageId: '${row['message_id'] ?? ''}',
      sender: '${row['sender'] ?? ''}',
      type: '${row['type'] ?? ''}',
      item: '${row['item'] ?? ''}',
      title: '${row['title'] ?? ''}',
      body: '${row['body'] ?? ''}',
      receivedAt: (row['received_at'] as num?)?.toInt() ?? 0,
      read: readRaw != 0,
      ackResult: '${row['ack_result'] ?? ''}',
      ackedAt: (row['acked_at'] as num?)?.toInt() ?? 0,
    );
  }
}
