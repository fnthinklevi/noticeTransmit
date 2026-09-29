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
/// 列名只在本文件的 [toDbRow] / [fromDbRow] 里出现（与 `FnthinkInboxMessage` 同一条纪律）。
class FnthinkPeer {
  const FnthinkPeer({
    required this.peerAddress,
    required this.publicKey,
    required this.level,
    required this.grantedAt,
    this.requestId = '',
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

  static const table = 'fnthink_peers';

  static const columns = <String>[
    'peer_address',
    'public_key',
    'level',
    'granted_at',
    'request_id',
  ];

  Map<String, Object?> toDbRow() => {
    'peer_address': peerAddress,
    'public_key': publicKey,
    'level': level,
    'granted_at': grantedAt,
    'request_id': requestId,
  };

  static FnthinkPeer fromDbRow(Map<String, Object?> row) => FnthinkPeer(
    peerAddress: '${row['peer_address'] ?? ''}',
    publicKey: '${row['public_key'] ?? ''}',
    level: '${row['level'] ?? ''}',
    grantedAt: (row['granted_at'] as num?)?.toInt() ?? 0,
    requestId: '${row['request_id'] ?? ''}',
  );

  /// 地址码是给用户看的（复制、二维码），公钥只给"确认是同一把"用 —— 都不算口令，
  /// 但公钥整串抄进日志没有意义，所以这里只留前 8 位。
  @override
  String toString() =>
      'FnthinkPeer($peerAddress, key=${publicKey.length > 8 ? '${publicKey.substring(0, 8)}…' : publicKey}, $level)';
}

/// 写一条授权的结果。三种必须分开：**换钥不是"更新"**。
enum FnthinkPeerWrite {
  /// 第一次见到这个地址码。
  created,

  /// 同码同钥再来一次 = 重新授权（刷新档位与时间）。
  refreshed,

  /// 同码**不同钥**：一行都没改。这台设备要么被重建过身份、要么有人在冒用地址码，
  /// 两种都需要人来判断，静默覆盖等于把"白名单里那个人"换成另一个人。
  keySwapped,
}
