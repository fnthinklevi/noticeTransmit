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
