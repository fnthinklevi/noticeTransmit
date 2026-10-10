/// 本机记下的一个**已配对发送方**（T42 的数据源）。
///
/// 为什么这台设备需要这张表：授权本身在服务端（A 的 `grantsBy`），但 A 的界面上要能回答
/// "我允许了谁、给到哪一档、什么时候同意的、想撤怎么办"。没有这张表，T42 那页就没有数据源。
///
/// ⚠ **故意没有 `peer_name` 这一列**：对端注册时报的名字只进服务端设备表，
/// poll 的 `pairRequests` 里只有 `requester / requesterPublicKey / level`（见
/// `server/lib/fnthink/pairstore.js` 的 `pendingFor`），本机从没拿到过它。
/// 等有出处了再加列（先在契约里把它带上），别建一列空着让界面显示"（ unnamed ）"。
///
/// 有的那一列叫 **`alias`（T128 片1）**，与上面那句不矛盾也**不是同一件事**：
/// 它是**这台自己给对面起的名字**（"客厅那台"／"公司的手机"），只有本机看得见，
/// 不发给服务端、不进任何载荷。所以它不会遇到"对端改了名本机读到的是旧的那个"那类问题 ——
/// 那种问题只能靠契约带名字来解决，而契约今天没有带。
///
/// 列名只在本文件的 [toDbRow] / [fromDbRow] 里出现（与 `FnthinkInboxMessage` 同一条纪律）。
class FnthinkPeer {
  const FnthinkPeer({
    required this.peerAddress,
    required this.publicKey,
    required this.level,
    required this.grantedAt,
    this.requestId = '',
    this.items = const <String>[],
    this.revision = 0,
    this.forwards = false,
    this.alias = '',
  });

  /// 对端的 18 位地址码（Crockford Base32）。它是主键：一台设备只该有一行授权记录。
  final String peerAddress;

  /// 同意时看到的裸公钥（base64）。存它不是为了本机验签（验签在服务端做），
  /// 而是为了**发现换钥**：同一个地址码带着另一把公钥来，是要人看的事件，不是静默更新。
  final String publicKey;

  /// 授到哪一档（`L1` / `L2` / `L3`，词表来自契约 `capabilities.levels`）。
  final String level;

  final int grantedAt;

  /// 这条授权来自哪一条配对请求（排查用；`pairRequests` 里那个 id）。空串 = 没有出处可记。
  final String requestId;

  /// 逐条勾选过的项目 id（T49：L2 动作 / L3 设置）。**没有"通配"**：清单里没写就是没给。
  ///
  /// 为什么要落在本机这一份：档位只是天花板，真正判"这一条准不准做"的是这张清单
  /// （契约 `capabilities.itemRequiredFromLevel`）。而契约的授权缺省是 fail-closed 的
  /// （`grantDefaults.items = []`），所以这张表读不出值时**判"没给"** —— 哪怕
  /// `level` 写着 L3。写死成"档到了就都能做"的后果是：一个只同意过"开某个开关"的发送方
  /// 能改这台设备上任何一项系统设置。
  final List<String> items;

  /// 第几版授权（T49）。变更要重新确认，所以它只增不减。
  final int revision;

  /// 这台是否被勾为「幻念通道」的发送目标（T94，维护者 2026-10-05 定）。
  ///
  /// 与 `level` / `items` 无关，也**不是配对权限**：配对等于「对方可以往这台推」，
  /// 勾选等于「我同意这台可以收到我转发出去的通知」—— 方向相反，它扩的是**发出**。
  /// 两者各说一件事：一个是谁能往我这里发，一个是我能往哪里发。
  final bool forwards;

  /// 本机给这一行起的名字（T128 片1）。空串 = 没起过，界面上就只显地址码。
  ///
  /// ⚠ 它**不是**对端报来的名字（那个从没流到本机，见文件头），也不参与任何授权判断：
  /// 服务端认的一直是地址码。改名改的是"这一行在屏幕上叫什么"，仅此而已。
  final String alias;

  static const table = 'fnthink_peers';

  /// 别名能有多长（T128 片1，**唯一作者**）。
  ///
  /// 名单那一行是一行 `FnthinkNote`，没有省略号策略：不限长就会在 8 台设备之后
  /// 把行挤到换行、把「撤掉这一行」那枚按钮挤出屏幕。去掉首尾空白同时把中间的
  /// 连续空白压成一格（粘出来的名字常常带换行）。
  static String normalizeAlias(String raw) {
    final collapsed = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (collapsed.length <= 30) return collapsed;
    return '${collapsed.substring(0, 30)}…';
  }

  static const columns = <String>[
    'peer_address',
    'public_key',
    'level',
    'granted_at',
    'request_id',
    'items',
    'revision',
    'forwards',
    'alias',
  ];

  Map<String, Object?> toDbRow() => {
    'peer_address': peerAddress,
    'public_key': publicKey,
    'level': level,
    'granted_at': grantedAt,
    'request_id': requestId,
    // 清单存成 `\n` 分隔的一格而不是 JSON：它是"几个 id"而不是结构，
    // 而 db 里存 JSON 会让"这一格坏了"与"清单是空的"读起来一模一样（都是解析失败）。
    'items': items.join('\n'),
    'revision': revision,
    'forwards': forwards ? 1 : 0,
    'alias': alias,
  };

  static FnthinkPeer fromDbRow(Map<String, Object?> row) {
    // 形状不认识就当空清单（fail-closed）。⚠ 不是当"全给"：这一列写坏时的表现必须是
    // 收紧，而收紧的方向只有一个。
    final rawItems = '${row['items'] ?? ''}';
    return FnthinkPeer(
      peerAddress: '${row['peer_address'] ?? ''}',
      publicKey: '${row['public_key'] ?? ''}',
      level: '${row['level'] ?? ''}',
      grantedAt: (row['granted_at'] as num?)?.toInt() ?? 0,
      requestId: '${row['request_id'] ?? ''}',
      items: rawItems
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      revision: (row['revision'] as num?)?.toInt() ?? 0,
      // 读不出时当**未勾选**（fail-closed）：这一列写坏时的后果必须是"不发"，
      // 而"全发"那一头是静默把本机的通知推出去。
      forwards: (row['forwards'] as num?)?.toInt() == 1,
      alias: '${row['alias'] ?? ''}',
    );
  }

  /// 地址码是给用户看的（复制、二维码），公钥只给"确认是同一把"用 —— 都不算口令，
  /// 但公钥整串抄进日志没有意义，所以这里只留前 8 位。
  @override
  String toString() =>
      'FnthinkPeer($peerAddress, key=${publicKey.length > 8 ? '${publicKey.substring(0, 8)}…' : publicKey}, $level)';

  /// 名单那一行「是谁」那一段（T128 片1，**唯一作者**）。
  ///
  /// 顺序是刻意反过来的：地址码在前、别名在括号里。别名是本机自己编的，
  /// 它不能替换掉那一行唯一能被核对的东西 —— 用户对着对面那台的屏幕核的就是这 18 位。
  String get whoLabel => alias.isEmpty ? peerAddress : '$peerAddress ($alias)';
}

/// 写一条授权的结果。三种必须分开：**换钥不是"更新"**。
enum FnthinkPeerWrite {
  /// 第一次见到这个地址码。
  created,

  /// 同码同钥再来一次 = 重新授权（刷新档位与时间）。
  refreshed,

  /// 这一行**已经在名单里**，而这一发没有可写的新读数 ⇒ 一行都不改（T130 片3）。
  ///
  /// 来路只有那一条：对面替本机确认了一次（服务端双写的那一段），本机因此要把那台升格成
  /// 一行 —— 可那一行如果已经在本机自己的名单里（本机先前点过一次同意写进去的），
  /// 它的档位与逐条清单就是**本机自己勾的**那份，比升格这一发的空清单更权威。
  /// 与 `keySwapped` 分开是必须的：那是"要人判断的事件"，这是"什么都没发生"。
  alreadyPresent,

  /// 同码**不同钥**：一行都没改。这台设备要么被重建过身份、要么有人在冒用地址码，
  /// 两种都需要人来判断，静默覆盖等于把"白名单里那个人"换成另一个人。
  keySwapped,
}
