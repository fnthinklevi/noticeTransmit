import 'dart:convert';

/// 一条远程指令的**载荷**（远程执行 片3b-2）。
///
/// ⚠ **为什么它住在包里、而不在 `lib/services/`**：它决定"一段 body 怎么拼"，
/// 而拼出来的那段 body 要进被签的六个字段（`canonicalOrder` 里那个 `body`）—— 也就是说
/// **它决定签什么**。两端（Dart 与 Node）都要按同一套拼，拼错的后果不是"界面不好看"，
/// 而是「对端解不出 item」与「回执对不上」两种各查不到根因的错。
///
/// ⚠ **与既有 envelope 的关系**：`FnthinkTitleEnvelope` 是**标题**信封（`title` 段），
/// 这一条是**指令**信封（另一个键）。⚠ 为什么**套在同一个 body 里**而不是改 `canonicalOrder`：
/// 加字段动的是签名规范 —— 签名规范一改，两端对**任何一条已发消息**的验签结论都可能变，
/// 而这件事今天没有回滚路径。所以按"不改签名规范、只在已签的那个字段里多带一份结构"办。
class RemoteCommandEnvelope {
  const RemoteCommandEnvelope._();

  /// 载荷里的键名（唯一一个作者；`decode` 只认它）。
  static const commandKey = 'fnthink_remote';

  /// 这个前缀不在契约里 —— ⚠ 与 `deviceTitlePrefix` 刻意**不同**：
  /// 两者共用一个前缀的话，「一条标题消息」与「一条指令消息」在拆的时候就分不开了，
  /// 而分不开的形状是"指令被当通知显示出来"。
  static const prefix = 'FRX1:';

  /// 拼出一条指令的 body。
  ///
  /// ⚠ **不套标题信封**：指令没有"标题/正文"这个划分，把标题塞进去只会让拆出来的那一格
  /// 永远为空，而空标题与"这条本来没有标题"在 `FnthinkTitleEnvelope` 里不可区分。
  static String encode({
    required String level,
    required String item,
    String argument = '',
    String? key,
    String? totpCode,
  }) {
    final payload = <String, Object?>{
      'level': level,
      'item': item,
      if (argument.isNotEmpty) 'argument': argument,
      // ⚠ 凭据**只在指令里出现**，不进签名之外的任何地方（不进 title、不进日志、
      // 不进回执）。契约 `execution.forbiddenFields` 的同一份黑名单管的是留痕，
      // 这里管的是**线上载荷**：凭据随指令走密文正文这一层是协议的一部分，
      // 而服务端只看到 `body` 这一段，不解析它。
      if (key != null && key.isNotEmpty) 'key': key,
      if (totpCode != null && totpCode.isNotEmpty) 'totp': totpCode,
    };
    return prefix + jsonEncode(payload);
  }

  /// 拆一条指令。**拆不出来就回 null，不猜**（与 `FnthinkTitleEnvelope` 同一纪律）。
  static RemoteCommand? decode(String wire) {
    if (!wire.startsWith(prefix)) return null;
    final Object? parsed;
    try {
      parsed = jsonDecode(wire.substring(prefix.length));
    } on FormatException {
      return null;
    }
    if (parsed is! Map) return null;
    final level = parsed['level'];
    final item = parsed['item'];
    // 三件缺一不可：`level` 定这一条按哪一档判（凭据要求不同），`item` 是要动的那一项。
    // 缺了就当"这不是一条指令" —— 那种情况下设备端应当按普通通知处置，
    // 而不是按一条字段不全的指令去执行半个动作。
    if (level is! String || level.isEmpty) return null;
    if (item is! String || item.isEmpty) return null;
    final argument = parsed['argument'];
    final key = parsed['key'];
    final totp = parsed['totp'];
    return RemoteCommand(
      level: level,
      item: item,
      argument: argument is String ? argument : '',
      key: key is String && key.isNotEmpty ? key : null,
      totpCode: totp is String && totp.isNotEmpty ? totp : null,
    );
  }
}

/// 拆出来的一条指令。
class RemoteCommand {
  const RemoteCommand({
    required this.level,
    required this.item,
    this.argument = '',
    this.key,
    this.totpCode,
  });

  final String level;
  final String item;
  final String argument;
  final String? key;
  final String? totpCode;

  bool get hasCredential =>
      (key?.isNotEmpty ?? false) || (totpCode?.isNotEmpty ?? false);

  /// ⚠ **`toString` 里没有凭据**：它会进日志，而日志会离开这台机。
  @override
  String toString() =>
      'RemoteCommand($level $item${argument.isEmpty ? '' : '/$argument'}, '
      'credential: ${hasCredential ? '已带' : '没带'})';
}

/// 一条**回执**的载荷（B → A，片3c-1）—— 与 [RemoteCommandEnvelope] 反向的那一半。
///
/// ## 为什么它是"消息"而不是 ack
/// 契约 `capabilities.remoteExecution.receiptsWhy` 写死了：两段回执走**回发给发送方的消息**，
/// 不是 ack。ack 答的是「这条投递我收没收到」，而回执答的是「这件事我做到哪一步了」——
/// 把它塞进 ack 的话，at-least-once 的重投会与「执行中」互相污染（同一条重投一次就多 ack 一次）。
///
/// ## 与指令信封的分工
/// 指令（`FRX1:`）只在 `fnthink` 那一条渠道上出现，带凭据、来自对面；
/// 回执（`FRR1:`）是本机**执行完之后**回给那个发送方的，不带凭据（对面已经证明过自己了，
/// 而回执里再回一份凭据等于把它抄进第三处存储）。两条路的 `level`/`item`/`argument`
/// 逐字相同，**这正是对面能把一条回执对回一条指令的依据**。
///
/// ⚠ **故意不带执行 id**：协议形状一改，两端对**任何一条已发消息**的解读都可能变，
/// 而这一批的指令形状（[RemoteCommandEnvelope]）已经发出去了。发送方是串行的，
/// 「回执对回自己发过的哪一条」由它自己按 `level+item+argument` 配最老那条未终结的发件记录——
/// 那是**发送侧**的一条规则，不该由协议来承担。
class RemoteReceiptEnvelope {
  const RemoteReceiptEnvelope._();

  /// 载荷里的键名（唯一一个作者；`decode` 只认它）。
  static const receiptKey = 'fnthink_receipt';

  /// 前缀。⚠ 与 [RemoteCommandEnvelope.prefix] 刻意**不同**（`FRX1:` / `FRR1:`），
  /// 且与标题信封也不同：三者共用一个前缀的话，"这是一条回执"与"这是一条指令"在拆的时候
  /// 分不开，而分不开的形状是**把别人的回执当成一条指令执行一遍** ——
  /// 比「指令被当通知弹出来」严重一个量级。
  static const prefix = 'FRR1:';

  /// 拼出一条回执的 body。
  ///
  /// [state] 只在**第二段**（执行完）才有，且必须是执行状态机的终态三选一
  /// （`done` / `failed` / `cancelled`）。传空串按"没带"处理 ——
  /// 拼一条带空串的载荷和拼一条不带的是同一件事，不留第二种形状。
  static String encode({
    required String result,
    required String level,
    required String item,
    String argument = '',
    String? state,
  }) {
    final payload = <String, Object?>{
      'result': result,
      'level': level,
      'item': item,
      if (argument.isNotEmpty) 'argument': argument,
      if (state != null && state.isNotEmpty) 'state': state,
    };
    return prefix + jsonEncode(payload);
  }

  /// 拆一条回执。**拆不出来就回 null，不猜**（与 [RemoteCommandEnvelope.decode] 同一纪律）。
  static RemoteReceipt? decode(String wire) {
    if (!wire.startsWith(prefix)) return null;
    final Object? parsed;
    try {
      parsed = jsonDecode(wire.substring(prefix.length));
    } on FormatException {
      return null;
    }
    if (parsed is! Map) return null;
    final result = parsed['result'];
    final level = parsed['level'];
    final item = parsed['item'];
    // 三件缺一不可。`result` 单独缺了尤其危险：那正是"对面说执行完了"那一段，
    // 认不出它就等于把一段回执当一条普通通知显示给用户看。
    if (result is! String || result.isEmpty) return null;
    if (level is! String || level.isEmpty) return null;
    if (item is! String || item.isEmpty) return null;
    final argument = parsed['argument'];
    final state = parsed['state'];
    return RemoteReceipt(
      result: result,
      level: level,
      item: item,
      argument: argument is String ? argument : '',
      state: state is String && state.isNotEmpty ? state : null,
    );
  }
}

/// 拆出来的一条回执。
class RemoteReceipt {
  const RemoteReceipt({
    required this.result,
    required this.level,
    required this.item,
    this.argument = '',
    this.state,
  });

  /// 契约 `capabilities.remoteExecution.receipts` 里那一个词：
  /// `executing`（收到即回的那一段）｜`execution_done`（执行完的那一段）。
  final String result;

  final String level;
  final String item;
  final String argument;

  /// 终态（`done` / `failed` / `cancelled`）。**只有第二段回执带**。
  final String? state;

  bool get isFinished => state != null;

  @override
  String toString() =>
      'RemoteReceipt($result $level $item'
      '${argument.isEmpty ? '' : '/$argument'}'
      '${state == null ? '' : ' → $state'})';
}
