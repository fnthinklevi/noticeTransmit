/// 幻念推送的收件行（T47）。
///
/// 一条 = 别人推给**本机**的一条消息。它不进 `notifications` 表：那张表的列形态是
/// "本机抓到的通知"（包名、原生 id、逐通道送达信息），而这里是"谁推给我的什么内容"；
/// 混在一起还会顺带改掉 `recordCount` 那条导出契约（路线图 T47 明确不要这个）。
///
/// ⚠ 列名只在本文件的 [toDbRow]/[fromDbRow] 里出现 —— 表结构、SQL 与测试都读这一处。
/// 两端各写一份字符串是本仓反复付过学费的形态（见 `DeviceSnapshot` 开头那段）。
/// 消息方向（T43 加的那一列）。**这两个串是列值的唯一出处**：表结构、读口、写口都读它。
///
/// 为什么不用 bool `isOutgoing`：界面上要说的是「收件 / 发出」两个词，而 `direction` 这一列
/// 以后还能长出第三档（比如「草稿」）；一个 bool 到那时就得再加一列，两张账。
const String kFnthinkDirectionIn = 'in';
const String kFnthinkDirectionOut = 'out';

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
    this.direction = kFnthinkDirectionIn,
    this.viaBackup = false,
  });

  /// 服务端给的消息主键（`m_` 前缀那串）。它同时是表主键：投递是 at-least-once
  /// （ack 之前不删正文），同一条会来第二次，而去重与 ack 都只能按这个 id 说话。
  final String messageId;

  /// 对端是谁。**含义随 [direction] 变，这是这张表唯一一处这样的列**：
  /// `direction == kFnthinkDirectionIn` ⇒ 来源（谁推给本机的，配对设备是地址码、接入端点是 `endpoint:<id>`）；
  /// `direction == kFnthinkDirectionOut` ⇒ 收件人（本机发给哪一台）。
  /// 共用一列而不是再加一列，是因为「这条消息的另一端」永远只有一个，而分两列必然有一列恒空。
  ///
  /// 空串 = 未知来源（对端是没带 `sender` 那列的旧服务端，或本机自己发的那条还没记下对端）
  /// —— 未知不等于没有这条消息。
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

  /// 这条是本机收到的（`kFnthinkDirectionIn`）还是本机发出去的（`kFnthinkDirectionOut`）。
  /// 历史页的那两档就按它分：收件档只显示 in、发出档只显示 out；首页未读卡也只数 in。
  final String direction;

  /// 这一条是**降级后**从备用通道发出去的（T94 片4d）。
  ///
  /// 原生那一侧从路由决策就知道这件事（`routeChannels()` 的 `viaBackup`），并把它写进
  /// 待发队列；**在这之前它断在半路** —— 队列里带着，Dart 侧那一项没有这个字段，
  /// 于是值在解析那一步被丢掉，历史里这一条与"走主通道发的"长得一模一样。
  /// 表现比"不标"更坏：另外三族都标，只有幻念这一族不标 ⇒ 用户看到的是"有时标有时不标"。
  ///
  /// 只对 `direction == kFnthinkDirectionOut` 有意义（收件那一侧不存在主备路由）。
  final bool viaBackup;

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
    'direction',
    'via_backup',
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
    'direction': direction,
    'via_backup': viaBackup ? 1 : 0,
  };

  /// 读一行。**不做兜底猜测**：`read` 只认 0/1 两个整数（其它形状说明库里存的不是本表
  /// 该存的东西，宁可抛出来，也别在界面上把"未知"显示成"已读"）。
  /// 方向列的解析：只认两个词，别的一律抛（与 `read` 只认 0/1 同一条纪律）。
  static String _directionOf(Object? raw) {
    final value = '$raw';
    if (value == kFnthinkDirectionIn || value == kFnthinkDirectionOut) {
      return value;
    }
    throw StateError('fnthink_messages.direction 不是已知方向（实为 $raw）：不猜它是收件还是发出');
  }

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
      // 老行由迁移的 DEFAULT 补成 'in'（收件表先存在、方向列后加），所以这里不猜：读到别的
      // 值说明有人没走迁移就往里塞行，宁可抛出，也别把一条方向未知的消息当成收件显示在
      // 「别人推给我的」那一档里。
      direction: _directionOf(row['direction']),
      // ⚠ 这里**故意比 [read] 松一档**：缺键当 false，形状不对（非整数）才抛。
      // 区别在于 `read` 那列自建表起就在，缺键只可能是有人手搭了坏行；
      // 而 `via_backup` 是 v20 才加的，v20 之前写的行**本来就没有这一列**，
      // 而迁移给它们补的正是 DEFAULT 0 —— 所以"缺"与"0"是同一件事的两种写法，
      // 把缺当 false 才与迁移一致。反过来对非整数仍然抛：那是形状不对，不是缺失。
      viaBackup: _viaBackupOf(row['via_backup']),
    );
  }

  static bool _viaBackupOf(Object? raw) {
    if (raw == null) return false;
    if (raw is! int) {
      throw StateError(
        'fnthink_messages.via_backup 不是整数（实为 $raw）：'
        '不猜这一条是不是走了备用出口',
      );
    }
    return raw != 0;
  }
}
