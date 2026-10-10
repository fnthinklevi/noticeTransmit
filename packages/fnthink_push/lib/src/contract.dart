import 'dart:convert';
import 'dart:io';

/// 协议主版本号。⚠ 与 `protocol/fnthink-v1.json` 的 `contractVersion` 不一致时，
/// 双端契约测试必须变红 —— 这条不一致就是"两端各按自己的理解解释协议"的起点。
const int fnthinkProtocolMajor = 1;

/// 契约文件的默认路径（相对仓库根）。
const String fnthinkContractPath = 'protocol/fnthink-v1.json';

/// 跨端一致性向量的路径（T26：凭证的归一化与摘要，Dart 与 Node 各断言一遍同一份文件）。
const String fnthinkVectorsPath = 'protocol/fnthink-vectors-v1.json';

String _findUp(String relativePath, String? from) {
  var dir = Directory(from ?? Directory.current.path);
  for (var i = 0; i < 6; i++) {
    final candidate = '${dir.path}/$relativePath';
    if (File(candidate).existsSync()) return candidate;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError('找不到 $relativePath（从 ${Directory.current.path} 向上找 6 级）');
}

/// 找到契约文件的真实路径：从 [from] 逐级向上找 `protocol/fnthink-v1.json`。
///
/// 为什么要向上找而不是直接拼相对路径：`dart test` 在包目录里跑、`flutter test` 在仓库根跑、
/// CI 又是另一个 cwd。写死相对路径的测试结果会随运行位置变，那类"换个地方就红/就绿"的
/// 测试比没有测试更糟。
String fnthinkContractFile({String? from}) =>
    _findUp(fnthinkContractPath, from);

/// 向量文件的真实路径（同 [fnthinkContractFile] 的定位规则）。
String fnthinkVectorsFile({String? from}) => _findUp(fnthinkVectorsPath, from);

/// L3 系统设置表里的**一项**（契约 `capabilities.l3.settings` 的一项）。
///
/// [mode] 是这一项的形态（契约 `capabilities.l3.modes`）：
///  - `grant`  = 打开这项授权。不可逆的动作在系统那边，**只能请用户点**（原生侧至今
///    没有任何静默改系统设置的能力）；
///  - `toggle` = 翻这台设备自己的一项开关。可逆，且要先有对应授权。
///
/// ⚠ 为什么这一层必须带 mode 而不是一张光秃秃的清单：这两类的**承诺强度不同**，
/// 而界面上它们长得一模一样。合成一张没有 mode 的表，用户看到的就是
/// 「勾了就会静默改」与「勾了只是弹设置页」被显示成同一种承诺。
class FnthinkL3Setting {
  const FnthinkL3Setting({
    required this.key,
    required this.mode,
    required this.native,
    this.targetValue,
  });

  final String key;

  /// `grant` 或 `toggle`（取值来自契约 `capabilities.l3.modes`）。
  final String mode;

  /// 设备侧那一侧的落点（原生方法名 / 服务层方法名）。**不是**给远端用的 ——
  /// 远端只能通过契约的 `key` 说"要哪一项"，映射到哪一段代码由本地决定。
  final String native;

  /// 这一项能不能被**直接改**（`toggle`），还是只能**请用户去系统里开**（`grant`）。
  bool get isToggle => mode == 'toggle';

  bool get isGrant => mode == 'grant';

  /// **这一次要设成哪一档**（契约 `l3.itemTargetWords` 的 `on` / `off`）。
  ///
  /// ⚠ null = item 里没带目标值 ⇒ 沿用旧语义「读当前再翻」。而**那不可幂等**：
  ///   投递是 at-least-once（ack 没送到就重投），翻两次回到原状，
  ///   而本机留痕两条都记 done。带目标值则是幂等的（重投多少次都是同一档）。
  final bool? targetValue;

  /// 有没有带目标值（带的那一档才谈得上幂等）。
  bool get hasTarget => targetValue != null;

  @override
  String toString() =>
      '$key($mode${targetValue == null
          ? ''
          : targetValue!
          ? '/on'
          : '/off'})';

  @override
  bool operator ==(Object other) =>
      other is FnthinkL3Setting &&
      other.key == key &&
      other.mode == mode &&
      other.native == native &&
      other.targetValue == targetValue;

  @override
  int get hashCode => Object.hash(key, mode, native, targetValue);
}

/// 单一协议契约（T71）。
///
/// 为什么要有这么一层：幻念推送的规则散在路线图 W3a–W3g 的十几段话里，而它们**同时**约束
/// Dart 客户端与 Node 服务端。两边各抄一份，第一次分歧不会报错，只会表现成
/// "设备以为排队 7 天、服务端第 3 天就删了"这类查不出来的缺陷。
/// 所以规则只写在这一个 JSON 里，两端各自读它跑测试。
///
/// 本类只做两件事：① 取值（typed getter，避免字符串键在两侧各拼一遍）；
/// ② [validate] —— 检查这份表**自己是否自洽**。不自洽的契约表比没有契约表更危险：
/// 它会让人以为"两边都读同一份"就等于"两边一致"。
class FnthinkContract {
  FnthinkContract(this.raw);

  factory FnthinkContract.parse(String source) =>
      FnthinkContract(jsonDecode(source) as Map<String, Object?>);

  /// 从磁盘读。[path] 缺省用 [fnthinkContractFile] 向上找到仓库根那份。
  factory FnthinkContract.readFile([String? path]) => FnthinkContract.parse(
    File(path ?? fnthinkContractFile()).readAsStringSync(),
  );

  final Map<String, Object?> raw;

  /// 沿路径取值；任何一级不是 Map 就返回 null（[validate] 会把"缺键"报成问题，不静默）。
  Object? at(List<String> path) {
    Object? node = raw;
    for (final key in path) {
      if (node is! Map) return null;
      node = node[key];
    }
    return node;
  }

  String? str(List<String> path) => at(path) as String?;

  int? intOf(List<String> path) => (at(path) as num?)?.toInt();

  bool? boolOf(List<String> path) => at(path) as bool?;

  List<String> strings(List<String> path) =>
      (at(path) as List<Object?>? ?? const []).map((e) => '$e').toList();

  Map<String, Object?>? map(List<String> path) =>
      at(path) as Map<String, Object?>?;

  String get protocol => str(const ['protocol']) ?? '';

  int get contractVersion => intOf(const ['contractVersion']) ?? -1;

  /// 签名字节里 `version` 那一段的取值（向量与两端实现都用它，例如 `fnthink-v1` ⇒ `'1'`）。
  ///
  /// ⚠ 服务端**不读这个值的内容**（它按契约顺序重算整串再验签），所以这里错了不会当场报错，
  /// 而是让两端的规范化字节不同 ⇒ "签名永远失败"。正因为如此，它只能从契约推出来，
  /// 不许在客户端写一个 `'1'`：协议升 major 时那个字面量是最容易被忘掉的一处。
  String get protocolVersionForSignature {
    final declared = _protocolMajorOf(protocol);
    final version = contractVersion;
    if (declared == null || version <= 0) {
      throw StateError(
        '协议版本推不出来（protocol=$protocol, contractVersion=$version）',
      );
    }
    if (declared != version) {
      throw StateError(
        'protocol 名里的版本（v$declared）与 contractVersion（$version）不一致：'
        '签名字节里的 version 该用哪一个没有答案，先报错比猜一个强',
      );
    }
    return '$version';
  }

  /// 签名拼接用的分隔符。缺键直接抛：两处各写一个"默认 U+0000"就是第二份实现，
  /// 而分隔符不一致的两端会签出对不上、又看不出问题的字节串。
  String get signatureSeparator {
    final value = str(const ['signature', 'separator']);
    if (value == null || value.isEmpty) {
      throw StateError('契约缺 signature.separator（不补默认分隔符）');
    }
    return value;
  }

  /// 签名规范化的字段顺序（**顺序本身就是协议**：换序即换签名）。
  List<String> get canonicalOrder =>
      strings(const ['signature', 'canonicalOrder']);

  /// 同步响应码表（`_` 开头的说明性键与 `indistinguishable` 都不算码）。
  Map<String, int> get statusCodes {
    final table = map(const ['statusCodes']) ?? const {};
    return Map<String, int>.fromEntries(
      table.entries
          .where(
            (e) =>
                !e.key.startsWith('_') &&
                e.key != 'indistinguishable' &&
                e.value is num,
          )
          .map((e) => MapEntry(e.key, (e.value as num).toInt())),
    );
  }

  List<String> get receipts => strings(const ['receipts']);

  List<String> get indistinguishable =>
      strings(const ['statusCodes', 'indistinguishable']);

  Map<String, List<String>> get aliases => {
    'title': strings(const ['fieldTolerance', 'title']),
    'body': strings(const ['fieldTolerance', 'body']),
  };

  /// `endpoint.ingress.<which>` 那两条收单路径之一（T87 教程的唯一出处）。
  ///
  /// 缺键或不是以 `/` 开头就抛，不补默认值：教程里写一条服务器上不存在的路径，
  /// 用户复制下去只会拿到一个 404，而那句 404 看起来完全像"这功能坏了"——
  /// 与 `identityLength` 同一类：宁可装配期炸，不要在用户那侧静默错。
  String endpointIngressPath(String which) {
    final value = str(['endpoint', 'ingress', which]);
    if (value == null || !value.startsWith('/')) {
      throw StateError('契约缺 endpoint.ingress.$which（或不以 / 开头）：$value');
    }
    return value;
  }

  /// `endpoint.probe.bearerPath`（T106 片①b 格2：端点档干跑那条路的唯一出处）。
  ///
  /// 与 [endpointIngressPath] 分两个口子而不是共用一个：那一条读的是 `endpoint.ingress` 段、
  /// 这一条读的是 `endpoint.probe` 段，合成一个参数化的口子就会让"少一段"退化成
  /// "读到 null 就补个默认路径" —— 而默认路径意味着设备往一条不存在的路径送口令。
  String endpointProbePath() {
    final value = str(const ['endpoint', 'probe', 'bearerPath']);
    if (value == null || !value.startsWith('/')) {
      throw StateError('契约缺 endpoint.probe.bearerPath（或不以 / 开头）：$value');
    }
    return value;
  }

  /// `identity.<which>.length`。缺键直接抛而不是补个默认位数 —— 位数错生成出来的是
  /// 一把对端永远不认的凭证，而"默认 18"会让这个错误静默通过。
  int identityLength(String which) {
    final value = intOf(['identity', which, 'length']);
    if (value == null || value <= 0) {
      throw StateError('契约缺 identity.$which.length（不补默认值：默认位数等于换协议）');
    }
    return value;
  }

  int? identityTtlSeconds(String which) =>
      intOf(['identity', which, 'ttlSeconds']);

  bool? identityBool(String which, String key) =>
      boolOf(['identity', which, key]);

  // ── 配对（T28）──

  /// 二维码/一次性链接的前缀。两端各写一个前缀 = 互相解不开对方的码。
  String get pairingQrPrefix {
    final value = str(const ['pairing', 'qrPrefix']);
    if (value == null || value.isEmpty) {
      throw StateError('契约缺 pairing.qrPrefix（不补默认前缀）');
    }
    return value;
  }

  List<String> get pairingPayloadFields =>
      strings(const ['pairing', 'payloadFields']);

  /// 载荷里一律禁止出现的字段（私钥、签名、端点长期口令、口令摘要）。
  List<String> get pairingNeverCarry =>
      strings(const ['pairing', 'neverCarry']);

  /// 未知字段是否拒绝。缺键直接抛而不是"默认拒绝"——默认值本身就是第二份实现，
  /// 而且哪天有人把契约改成 false，这里必须跟着显式改代码才会生效。
  bool get pairingRejectUnknownFields {
    final value = boolOf(const ['pairing', 'rejectUnknownFields']);
    if (value == null) {
      throw StateError('契约缺 pairing.rejectUnknownFields（不补默认值）');
    }
    return value;
  }

  /// 必须有点头这一步：`confirmRequired` 为真 **且** `autoApprove` 为假。
  bool get pairingRequiresHumanConfirmation =>
      boolOf(const ['pairing', 'confirmRequired']) == true &&
      boolOf(const ['pairing', 'autoApprove']) == false;

  /// 配对阶段可请求的最高级别（免本地确认）。L3 不在这条路上。
  String get pairingMaxRequestableLevel =>
      str(const ['pairing', 'maxRequestableLevelFromPairing']) ?? '';

  /// 设备状态表：状态名 → 含义。**投递只认白名单里那几个状态**。
  Map<String, String> get deviceStatuses {
    final table = map(const ['revocation', 'deviceStatuses']) ?? const {};
    return {for (final e in table.entries) e.key: '${e.value}'};
  }

  /// 允许投递的状态（预期就是 `[active]`）。缺键抛而不是补默认值：
  /// 默认值就是"哪天契约把白名单删了，代码还照旧放行"。
  List<String> get deliveryAllowedStatuses {
    final list = strings(const ['revocation', 'deliveryAllowedStatuses']);
    if (list.isEmpty) {
      throw StateError('契约缺 revocation.deliveryAllowedStatuses（不补默认状态）');
    }
    return list;
  }

  bool get revokeKeepsHistory =>
      boolOf(const ['revocation', 'dataNeverDeletedByRevoke']) == true;

  List<String> get capabilityLevels =>
      strings(const ['capabilities', 'levels']);

  /// 端点（长期口令、无签名）被允许产的最高档。缺键直接抛：补一个默认值
  /// 就是"哪天契约把端点关掉，代码还按 L1 收"。
  String get endpointMaxLevel {
    final value = str(const ['capabilities', 'endpointMaxLevel']);
    if (value == null || value.isEmpty) {
      throw StateError('契约缺 capabilities.endpointMaxLevel（不补默认值）');
    }
    return value;
  }

  /// 一台设备最多能建几条接入端点（界面要说的那句"到数了只拒新的"里的这个数）。
  ///
  /// 页面不许写 `10`：那一位改小的时候界面上的解释会跟着说谎（而这一句正是用户决定
  /// "要不要再建一把"的唯一依据）。
  int get endpointMaxPerDevice {
    final value = intOf(const ['endpoint', 'perDeviceMax']);
    if (value == null || value <= 0) {
      throw StateError('契约缺 endpoint.perDeviceMax（或它不是正整数，实际「$value」）');
    }
    return value;
  }

  /// 签名载荷里 `type` 的取值表：`type → 最低级别`。**这张表就是词表**，
  /// 认不出的 type 一律拒（见 [rejectsUnknownMessageTypes]），不许"先收下再说"。
  Map<String, String> get messageTypeLevels {
    final table = map(const ['capabilities', 'messageTypes']) ?? const {};
    return {
      for (final entry in table.entries)
        if (entry.value is Map)
          entry.key: '${(entry.value as Map)['minLevel'] ?? ''}',
    };
  }

  /// 某一个 `type` 映射到哪一档；不在词表里返回 null。
  ///
  /// 单开一条而不是让调用方自己 `messageTypeLevels[type] ?? ''`：
  /// 那个写法在词表里没有这一项时得到**空串**，而空串在下游会被
  /// "级别不存在" 判成最窄那档 —— 表现是配好的一条动作静默退化成通知。
  String? typeTableLevelsFor(String type) => messageTypeLevels[type];

  /// L2 应用动作的**封闭词表**（契约 `capabilities.l2.actions`）。
  ///
  /// 两端各持一份枚举映射，这张表是它们共同的唯一出处。空表抛而不返回 `[]`：
  /// 空表读出来与「L2 这一档没有任何动作」在下游难以区分（枚举映射退化成空 switch
  /// 不报错，而表现是所有动作都不执行 —— 与「都执行」同样是静默）。
  List<String> get l2Actions {
    final value = strings(const ['capabilities', 'l2', 'actions']);
    if (value.isEmpty) {
      throw StateError(
        '契约缺 capabilities.l2.actions（或它是空表）：'
        '这张表是两端枚举映射的唯一出处，空表会让「未知 action」与「没有任何 action」读起来一样',
      );
    }
    return value;
  }

  /// 这些 L2 动作必须带参数（契约 `capabilities.l2.requiresArgumentFrom`）。
  List<String> get l2ActionsRequiringArgument =>
      strings(const ['capabilities', 'l2', 'requiresArgumentFrom']);

  /// L2 执行失败对外回哪一个回执词（契约 `capabilities.l2.actionReceipt`）。
  String get l2ActionReceipt {
    final value = str(const ['capabilities', 'l2', 'actionReceipt']);
    if (value == null || value.isEmpty) {
      throw StateError('契约缺 capabilities.l2.actionReceipt（不补默认值）');
    }
    return value;
  }

  /// 「会回传东西的动作」那张表（契约 `capabilities.l2.reports`，T124 片B）。
  ///
  /// 键 = 动作名，值 = 那份声明（参数形态／上下界／**可选的**回传消息标题）。
  /// ⚠ 带 `title` 的才回传；没带 `title` 的只是"参数有形状要求"（`app:launch`）。
  /// 缺这一节 ⇒ 空表 = **没有任何声明**（不是"默认允许"）。
  Map<String, Map<String, Object?>> get l2Reports {
    final raw = map(const ['capabilities', 'l2', 'reports']) ?? const {};
    final out = <String, Map<String, Object?>>{};
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value is Map) out[entry.key] = value.cast<String, Object?>();
    }
    return out;
  }

  /// 这条回传消息的标题（机器词；`title` 不在契约里 ⇒ null，不补默认）。
  String? l2ReportTitle(String action) {
    final value = l2Reports[action]?['title'];
    return value is String && value.isNotEmpty ? value : null;
  }

  /// 这条回传动作的参数是哪种形态（`count` = 要几条；`keyword` = 搜什么词）。
  /// 不是回传动作或缺项 ⇒ null（**不猜**：没声明的参数形态一律不放行，见 [reportArgumentProblem]）。
  String? l2ReportKind(String action) {
    final value = l2Reports[action]?['argumentKind'];
    return value is String && value.isNotEmpty ? value : null;
  }

  /// 参数（「要几条」）的下界／上界。不是 count 那一种或缺项 ⇒ null。
  int? l2ReportMinItems(String action) {
    final value = l2Reports[action]?['minItems'];
    return value is int ? value : null;
  }

  int? l2ReportMaxItems(String action) {
    final value = l2Reports[action]?['maxItems'];
    return value is int ? value : null;
  }

  /// 参数（「搜什么词」）的长度下界／上界。不是 keyword 那一种或缺项 ⇒ null。
  int? l2ReportMinChars(String action) {
    final value = l2Reports[action]?['minChars'];
    return value is int ? value : null;
  }

  int? l2ReportMaxChars(String action) {
    final value = l2Reports[action]?['maxChars'];
    return value is int ? value : null;
  }

  /// L3 系统设置的**封闭词表**（契约 `capabilities.l3.settings`）。
  ///
  /// 与 [l2Actions] 同一套做法：这张表是唯一出处，两端各持一份映射。空表抛而不返回
  /// `{}`：空表读出来与「L3 这一档没有任何设置项」在下游难以区分（映射退化成空 switch
  /// 不报错，而表现是所有设置项都不出现 —— 与「都出现」同样是静默）。
  Map<String, FnthinkL3Setting> get l3Settings {
    final raw = map(const ['capabilities', 'l3', 'settings']) ?? const {};
    if (raw.isEmpty) {
      throw StateError(
        '契约缺 capabilities.l3.settings（或它是空表）：'
        '这张表是两端映射的唯一出处，空表会让「未知设置项」与「没有任何设置项」读起来一样',
      );
    }
    final out = <String, FnthinkL3Setting>{};
    for (final entry in raw.entries) {
      final spec = entry.value;
      if (spec is! Map) continue;
      out[entry.key] = FnthinkL3Setting(
        key: entry.key,
        mode: '${spec['mode'] ?? ''}',
        native: '${spec['native'] ?? ''}',
      );
    }
    return out;
  }

  /// 某一档设置项的形态（契约 `capabilities.l3.modes`）。
  List<String> get l3SettingModes =>
      strings(const ['capabilities', 'l3', 'modes']);

  /// item 尾部那个目标值允许的词（契约 `capabilities.l3.itemTargetWords`，`on` / `off`）。
  ///
  /// ⚠ **读契约而不是写死**：这两个词经服务端透传回执、也在两端各拆一次，
  ///   写死等于第三份（第三份不会随契约一起改）。
  List<String> get l3ItemTargetWords =>
      strings(const ['capabilities', 'l3', 'itemTargetWords']);

  /// 这些设置项要先有对应授权才谈得上翻（契约 `capabilities.l3.requiresExistingGrantFrom`）。
  List<String> get l3SettingsRequiringExistingGrant =>
      strings(const ['capabilities', 'l3', 'requiresExistingGrantFrom']);

  /// L3 执行失败对外回哪一个回执词（契约 `capabilities.l3.settingsReceipt`）。
  String get l3SettingsReceipt {
    final value = str(const ['capabilities', 'l3', 'settingsReceipt']);
    if (value == null || value.isEmpty) {
      throw StateError('契约缺 capabilities.l3.settingsReceipt（不补默认值）');
    }
    return value;
  }

  /// 执行留痕里**能出现哪些键**（契约 `capabilities.execution.fields`）。
  ///
  /// 这是白名单 —— 落一条留痕时只有列出的键能进去。⚠ 它**不含正文与标题**：
  /// 消息正文已经在收件表里（那是本机的事），执行留痕要回答的是「谁让这台设备动了什么」，
  /// 多存一份正文等于同一段内容有两个留存点，而其中一个的删除策略与另一个不同。
  List<String> get executionFields =>
      strings(const ['capabilities', 'execution', 'fields']);

  /// 执行留痕里**一次都不许出现**的键（契约 `capabilities.execution.forbiddenFields`）。
  ///
  /// ⚠ 为什么白名单之外还要黑名单：白名单挡的是「没列的键」，而一个**名字像留痕的
  /// 正文键**（body / title）恰好可能被人顺手加进白名单去「留个底」——
  /// 那正是 `privacy.auditStoresMetadataOnly` 想防的事。
  List<String> get executionForbiddenFields =>
      strings(const ['capabilities', 'execution', 'forbiddenFields']);

  /// 留痕的两种种类（契约 `capabilities.execution.kinds`）。
  List<String> get executionKinds =>
      strings(const ['capabilities', 'execution', 'kinds']);

  /// 留痕的四种结果（契约 `capabilities.execution.results`）。
  ///
  /// ⚠ `rejected` 与 `failed` 刻意分开：`rejected` = 这一条**根本不该被执行**
  /// （不在词表 / 没逐条勾选 / 没确认 / 没前置授权），`failed` = 该执行但设备上做不成。
  /// 前者说明对端越界，后者说明这台设备做不到；合成一个之后，用户看到「有条消息没生效」
  /// 既不知道是对端越界还是自己没配好。
  List<String> get executionResults =>
      strings(const ['capabilities', 'execution', 'results']);

  /// 一个对端一天最多在这台设备上留多少条（契约 `capabilities.execution.maxPerPeerDay`）。
  ///
  /// 与 `retention.auditTrail.maxPerMessage`（投递态，按**消息**留）是两个不同的界：
  /// 那一条的界是「一条消息被反复推进」，这一条的是「对端连发大量互不相干的动作」。
  /// 缺这一档抛而不返回 0：0 意味着「一条都不留」，而那不是"有界"，那是"没记"。
  int get executionMaxPerPeerDay {
    final value = intOf(const ['capabilities', 'execution', 'maxPerPeerDay']);
    if (value == null || value <= 0) {
      throw StateError(
        '契约缺 capabilities.execution.maxPerPeerDay（或它不是正整数，实际'
        '「$value」）：留痕要么有界，要么就别记',
      );
    }
    return value;
  }

  /// 服务端那一侧的审计**只存元数据**（契约 `capabilities.execution.storesBody`）。
  ///
  /// 设备本机那一侧不受它约束 —— 本机存不存正文是本机自己的决定（T47 的收件表已经存了），
  /// 这一条只管**服务端**：留痕是元数据的另一个名字，不是「顺便把正文也存一份」的新入口。
  bool get executionStoresBody =>
      boolOf(const ['capabilities', 'execution', 'storesBody']) == true;

  // ── 远程执行（capabilities.remoteExecution，片1 契约先行）──────────────────

  /// 某一档允许从哪些渠道来（契约 `capabilities.remoteExecution.sources`）。
  ///
  /// ⚠ 渠道名是**封闭词表**：`fnthink` 与 `localNotificationWhitelist` 两种。
  /// 读不到回空表 —— 调用方必须把"空"当"没有任何渠道允许"，而不是"不限制"。
  List<String> remoteExecutionSourcesFor(String level) {
    final raw = map(const ['capabilities', 'remoteExecution', 'sources']);
    final value = raw == null ? null : raw[level];
    if (value is! List) return const <String>[];
    return value.map((e) => '$e').toList(growable: false);
  }

  /// 远程执行允许的两种凭据（契约 `capabilities.remoteExecution.auth.modes`）。
  List<String> get remoteExecutionAuthModes =>
      strings(const ['capabilities', 'remoteExecution', 'auth', 'modes']);

  /// L2 是否**必须**带凭据 —— 维护者 2026-10-03 定的是「可选」，所以这里应为 false。
  bool get remoteExecutionL2RequiresAuth =>
      boolOf(const ['capabilities', 'remoteExecution', 'auth', 'l2Requires']) ==
      true;

  /// L3 是否**必须**带凭据 —— 维护者定的是「必须」，所以这里应为 true。
  bool get remoteExecutionL3RequiresAuth =>
      boolOf(const ['capabilities', 'remoteExecution', 'auth', 'l3Requires']) ==
      true;

  int get remoteExecutionDelayDefaultSeconds =>
      intOf(const [
        'capabilities',
        'remoteExecution',
        'delay',
        'defaultSeconds',
      ]) ??
      -1;

  int get remoteExecutionDelayMinSeconds =>
      intOf(const ['capabilities', 'remoteExecution', 'delay', 'minSeconds']) ??
      -1;

  int get remoteExecutionDelayMaxSeconds =>
      intOf(const ['capabilities', 'remoteExecution', 'delay', 'maxSeconds']) ??
      -1;

  String get remoteExecutionOnTimeout =>
      str(const ['capabilities', 'remoteExecution', 'delay', 'onTimeout']) ??
      '';

  /// 用户在场与否影响计时吗 —— 维护者定的是「不影响」，所以这里应为 false。
  bool get remoteExecutionPresenceAffectsTiming =>
      boolOf(const [
        'capabilities',
        'remoteExecution',
        'delay',
        'userPresenceAffectsTiming',
      ]) ==
      true;

  /// 执行状态机的封闭词表（契约 `capabilities.remoteExecution.states`）。
  List<String> get remoteExecutionStates =>
      strings(const ['capabilities', 'remoteExecution', 'states']);

  /// 两段回执词（契约 `capabilities.remoteExecution.receipts`）。
  Map<String, String> get remoteExecutionReceipts {
    final raw =
        map(const ['capabilities', 'remoteExecution', 'receipts']) ?? const {};
    return {for (final e in raw.entries) e.key: '${e.value}'};
  }

  /// L3 那道闸的形态（契约 `capabilities.l3.confirmForm`）。
  String get l3ConfirmForm =>
      str(const ['capabilities', 'l3', 'confirmForm']) ?? '';

  /// 延时窗口的范围（契约 `capabilities.remoteExecution.delay` 的 min/max）。
  ///
  /// ⚠ 三个数（min/max/default）**同时**取才合法：少取一个就等于在代码里补一个默认值，
  /// 而界面上那根滑杆的两端正是从这里来的 —— 补出来的那一档协议从来没同意过。
  ({int min, int max}) get remoteExecutionDelayRange {
    final min = remoteExecutionDelayMinSeconds;
    final max = remoteExecutionDelayMaxSeconds;
    if (min < 0 || max < 0) {
      throw StateError(
        '契约缺 capabilities.remoteExecution.delay.minSeconds/maxSeconds'
        '（或有一项不是非负整数，实际 ${min}/${max}）',
      );
    }
    if (min > max) {
      throw StateError(
        'capabilities.remoteExecution.delay 的 minSeconds(${min}) > '
        'maxSeconds(${max})',
      );
    }
    return (min: min, max: max);
  }

  /// 用户选的那一档（null = 没选过）⇒ 真正该用的窗口秒数。
  ///
  /// ⚠ 选过的那一档**仍然要过范围校验**：prefs 里的值可能是备份恢复灌回来的
  /// （与 `FnthinkSettings.pollSeconds` 同一条教训），而"悄悄夹到合法区间"的表现是
  /// "界面写 60、实际按 10 跑"，用户唯一的线索就是屏幕上那个数字。
  int effectiveRemoteExecutionDelaySeconds(int? chosen) {
    final range = remoteExecutionDelayRange;
    if (chosen == null) return remoteExecutionDelayDefaultSeconds;
    if (chosen < range.min || chosen > range.max) {
      throw StateError('延时窗口选的是 ${chosen}s，协议只允许 ${range.min}–${range.max}s');
    }
    return chosen;
  }

  /// 高级密钥的最短长度（契约 `capabilities.remoteExecution.auth.keyMinLength`）。
  /// 缺键抛不补 8：长度是安全参数，补出来的那一档是代码替协议做的决定。
  int get remoteExecutionKeyMinLength {
    final value = intOf(const [
      'capabilities',
      'remoteExecution',
      'auth',
      'keyMinLength',
    ]);
    if (value == null || value <= 0) {
      throw StateError(
        '契约缺 capabilities.remoteExecution.auth.keyMinLength'
        '（或它不是正整数，实际「$value」）',
      );
    }
    return value;
  }

  /// TOTP 的位数与步长（契约 `auth.totpDigits` / `auth.totpPeriodSeconds`）。
  /// ⚠ 成对取：位数与步长只有一个的时候，另一半的默认值就是代码在发明协议。
  ({int digits, int periodSeconds}) get remoteExecutionTotpShape {
    final digits = intOf(const [
      'capabilities',
      'remoteExecution',
      'auth',
      'totpDigits',
    ]);
    final period = intOf(const [
      'capabilities',
      'remoteExecution',
      'auth',
      'totpPeriodSeconds',
    ]);
    if (digits == null || digits <= 0 || period == null || period <= 0) {
      throw StateError(
        '契约缺 capabilities.remoteExecution.auth.totpDigits/totpPeriodSeconds'
        '（或有一项不是正整数，实际 ${digits ?? "null"}/${period ?? "null"}）',
      );
    }
    return (digits: digits, periodSeconds: period);
  }

  /// 凭据缺失或不对时怎么办（契约 `auth.onMissingOrWrong`）。
  /// ⚠ 缺键抛：这一项是**安全方向**，补一个 `execute` 就是把"没带凭据也执行"写进代码。
  String get remoteExecutionOnMissingOrWrong {
    final value = str(const [
      'capabilities',
      'remoteExecution',
      'auth',
      'onMissingOrWrong',
    ]);
    if (value == null || value.isEmpty) {
      throw StateError(
        '契约缺 capabilities.remoteExecution.auth.onMissingOrWrong（不补默认值）',
      );
    }
    return value;
  }

  /// 本机白名单应用触发时有没有回执（契约 `remoteExecution.localTriggerReceipt`）。
  String get remoteExecutionLocalTriggerReceipt =>
      str(const ['capabilities', 'remoteExecution', 'localTriggerReceipt']) ??
      '';

  /// 哪一条来源是「本机触发」（契约 `remoteExecution.localTriggerSource`）。
  ///
  /// ⚠ 与上面那一条**刻意分开**：那一条答「回不回」，这一条答「是谁」。
  /// 代码里要判的是"这一条该不该回执"，而它得先知道本机那一路叫什么 ——
  /// 少了这一条就只有两条路可走：写死字符串（第二份字面量），或者按"在不在
  /// sources 里"来判（而本机那一路恰好在 L1 的 sources 里 ⇒ 判成要回）。
  /// 缺键抛而不补默认值：那等于让"判不出本机那一路"悄悄落成"每一路都回执"。
  String get remoteExecutionLocalTriggerSource {
    final value = str(const [
      'capabilities',
      'remoteExecution',
      'localTriggerSource',
    ]);
    if (value == null || value.isEmpty) {
      throw StateError(
        '契约缺 capabilities.remoteExecution.localTriggerSource（不补默认值：'
        '补上之后本机触发那一路会照发回执，而对面根本不存在）',
      );
    }
    return value;
  }

  /// 熔断阈值：一分钟内连续失败多少次就把档位降回去（契约 `capabilities.l3.circuitBreaker`）。
  int get l3CircuitBreakerFailuresPerMinute {
    final path = [
      ...const ['capabilities', 'l3', 'circuitBreaker'],
      'failuresPerMinute',
    ];
    final value = intOf(path);
    if (value == null || value <= 0) {
      throw StateError(
        '契约缺 capabilities.l3.circuitBreaker.failuresPerMinute'
        '（或它不是正整数，实际「$value」）：补默认值等于在代码里发明熔断线',
      );
    }
    return value;
  }

  /// 熔断之后降到哪一档（契约 `capabilities.l3.circuitBreaker.downgradeTo`）。
  String get l3CircuitBreakerDowngradeTo {
    final value = str(const [
      'capabilities',
      'l3',
      'circuitBreaker',
      'downgradeTo',
    ]);
    if (value == null || value.isEmpty || !capabilityLevels.contains(value)) {
      throw StateError(
        'capabilities.l3.circuitBreaker.downgradeTo=「$value」'
        '不是 capabilities.levels（${capabilityLevels.join('/')}）里的一档',
      );
    }
    return value;
  }

  bool get rejectsUnknownMessageTypes =>
      str(const ['capabilities', 'unknownMessageType']) == 'reject';

  /// 从哪一档起"光有级别不够，还要逐条勾选"。缺键直接抛：这决定 L2 是否要求 item，
  /// 补一个默认值就是两端各写一份规则。
  String get itemRequiredFromLevel {
    final value = str(const ['capabilities', 'itemRequiredFromLevel']);
    if (value == null || value.isEmpty) {
      throw StateError('契约缺 capabilities.itemRequiredFromLevel（不补默认值）');
    }
    return value;
  }

  /// 查不到授权清单时按哪一档判。fail-closed：缺键直接抛，不静默按"全给"或"全不给"。
  String get grantDefaultMaxLevel {
    final value = str(const ['capabilities', 'grantDefaults', 'maxLevel']);
    if (value == null || value.isEmpty) {
      throw StateError('契约缺 capabilities.grantDefaults.maxLevel（不补默认值）');
    }
    return value;
  }

  bool get grantChangeRequiresConfirmation =>
      boolOf(const ['capabilities', 'grantChangeRequiresConfirmation']) == true;

  /// 级别序：**直接取 `capabilities.levels` 里的位置**（validate 已保证它按权限升序）。
  /// 这里不写 `switch (level) { 'L1' => 1 ... }`：那等于在代码里存第二份档位表，
  /// 契约加一档时它不会报错，只会让比较结果静默错位。
  /// 不在词表里 ⇒ -1（任何真实档位都比它大 ⇒ 判不过），而不是抛 —— 调用方要的是
  /// "未知的那一侧一律不赢"。
  int levelRank(String level) => capabilityLevels.indexOf(level);

  /// 设备在线态的**三个**取值。少了 `unknown` 的那一份，界面上就会把"从未配过"
  /// 显示成"设备掉线了"—— 这是两件事，契约里 `unknownMeans` 写的就是这条。
  List<String> get presenceStates => strings(const ['presence', 'states']);

  /// 在线判定的秒数：`3 × 拉取间隔`（不另设心跳协议）。
  int? onlineThresholdSeconds({int? pollIntervalSeconds}) {
    final poll =
        pollIntervalSeconds ??
        intOf(const ['presence', 'pollIntervalSeconds', 'default']);
    final multiplier = intOf(const ['presence', 'onlineThresholdMultiplier']);
    if (poll == null || multiplier == null) return null;
    return poll * multiplier;
  }

  // ── 设备侧收货内核要读的那几个数（#126）──
  // 一律"缺就抛"而不是给默认值：这台设备多久问一次、有货时问到多密、时间能漂多少，
  // 都是**协议承诺**而不是客户端偏好。在 Dart 里写一个 20 当缺省，契约改成 30 时
  // 表现是"服务端按 30 判在线、设备按 20 问"，而那不会报错，只会让在线态一直慢半拍。

  /// 常态拉取间隔（秒）。
  int get pollIntervalSeconds {
    final value = intOf(const ['presence', 'pollIntervalSeconds', 'default']);
    if (value == null || value <= 0) {
      throw StateError('契约缺 presence.pollIntervalSeconds.default（不补默认值）');
    }
    return value;
  }

  /// 常态拉取间隔的**允许范围**（T88）。
  ///
  /// 这一对数字的作者只有契约：设备侧那格"多久收一次"的设置项读的就是它。在 Dart 里
  /// 另写一份 `5..60` 的表现是"契约哪天调档，界面上还能选到协议不允许的那一档"——
  /// 而那一档不会报错，只会让服务端按 `limits` 里推导出来的额度把这台设备持续 429。
  ({int min, int max}) get pollIntervalRange {
    final poll = map(const ['presence', 'pollIntervalSeconds']);
    final min = (poll?['min'] as num?)?.toInt();
    final max = (poll?['max'] as num?)?.toInt();
    if (min == null || max == null || min <= 0 || max < min) {
      throw StateError(
        '契约缺 presence.pollIntervalSeconds 的 min/max（或范围不合法）：'
        '设置那一格没有可校验的范围，宁可不开这一档',
      );
    }
    return (min: min, max: max);
  }

  /// 把一档间隔放进契约的范围里判一判。**越界就抛，不夹** ——
  /// 悄悄夹掉的表现是"界面写着 60、实际按 30 跑"，而用户唯一的线索就是那个数字。
  /// 报错里带着范围本身：这句话会原样出现在"这一档协议不允许"那一行上。
  int checkedPollIntervalSeconds(int seconds) {
    final range = pollIntervalRange;
    if (seconds < range.min || seconds > range.max) {
      throw StateError(
        '这个收取间隔协议不允许：${seconds}s 不在 [${range.min}, ${range.max}] 内',
      );
    }
    return seconds;
  }

  /// 用户选的那一档（没选过就是契约的 default）。**读的时候也校验**：
  /// 写的一路校验过不代表值一定合法 —— 备份恢复会把 prefs 里的值原样灌回来。
  int effectivePollIntervalSeconds(int? chosen) {
    if (chosen == null) return pollIntervalSeconds;
    return checkedPollIntervalSeconds(chosen);
  }

  /// 有货时的提频间隔与持续时长。`pending == 0` 时不该用它（省电，且契约语义是"有货才提频"）。
  ({int intervalSeconds, int durationSeconds}) get burstWhenPending {
    final burst = map(const ['presence', 'burstWhenPending']) ?? const {};
    final interval = burst['intervalSeconds'];
    final duration = burst['durationSeconds'];
    if (interval is! int ||
        interval <= 0 ||
        duration is! int ||
        duration <= 0) {
      throw StateError(
        '契约的 presence.burstWhenPending 缺 intervalSeconds/durationSeconds（不补默认值）',
      );
    }
    return (intervalSeconds: interval, durationSeconds: duration);
  }

  /// `ts` 允许的偏移上限（秒）。超过它，服务端会把这条判过期，而对外只有一句同形的话。
  int get maxSkewSeconds {
    final value = intOf(const ['signature', 'maxSkewSeconds']);
    if (value == null || value <= 0) {
      throw StateError('契约缺 signature.maxSkewSeconds（不补默认值）');
    }
    return value;
  }

  /// 一次 poll 最多取回多少条（服务端已按它截断，设备侧用它判"还有货没取完"）。
  int get maxBatchPerPoll {
    final value = intOf(const ['clientEvents', 'poll', 'maxBatchPerPoll']);
    if (value == null || value <= 0) {
      throw StateError('契约缺 clientEvents.poll.maxBatchPerPoll（不补默认值）');
    }
    return value;
  }

  /// poll 每条消息带回哪些字段。服务端按它投影响应、收件表（T47）按它设计列，
  /// 两边只有这一份共同出处 —— 名单不在契约里时，缺口只会以"动手到一半发现少一列"的形式现形。
  List<String> get pollMessageFields =>
      strings(const ['clientEvents', 'poll', 'messageFields']);

  /// poll 响应里"配对请求"那一项的键名（键名进契约是因为服务端就是从契约拼的）。
  String get pairRequestPollKey {
    final value = str(const ['pairRequest', 'pollKey']);
    if (value == null || value.isEmpty) {
      throw StateError('契约缺 pairRequest.pollKey（不补默认值）');
    }
    return value;
  }

  /// poll 响应里「**我发起过的那些**配对请求」那一项的键名（T110 第二面）。
  ///
  /// 与 [pairRequestPollKey] 分开两份，是因为两面**主语相反**：那一条按 `target` 选、只给
  /// pending，这一条按 `requester` 选、含终态。合成一个键名的话一次响应里两面互相盖掉，
  /// 而 B 屏幕上被盖出来的那一句是「谁在请求配对你」——发起请求的正是他自己。
  String get pairRequestSentPollKey {
    final value = str(const ['pairRequest', 'sentPollKey']);
    if (value == null || value.isEmpty) {
      throw StateError('契约缺 pairRequest.sentPollKey（不补默认值）');
    }
    return value;
  }

  /// 发出方那一条投影的字段名单（`id / target / level / status / createdAt / expiresAt / at`）。
  ///
  /// 名单里**没有** `codeDigest`，也没有 `requester`／`requesterPublicKey`（都是发起方自己的
  /// 东西，复述一遍只是多一处能漏的地方）。设备侧解析器照这份名单读，界面照它画 ⇒
  /// 「列表里只放地址码与状态」那条红线在这份名单上有出处，不在注释里。
  List<String> get pairRequestSentFields =>
      strings(const ['pairRequest', 'sentFields']);

  /// 非终态的那一个初始态（今日 = pending）。**不写死**：界面判"还在等"就读这一行。
  String get pairRequestInitialStatus {
    final value = str(const ['pairRequest', 'initialStatus']);
    if (value == null || value.isEmpty) {
      throw StateError('契约缺 pairRequest.initialStatus（不补默认值）');
    }
    return value;
  }

  /// 终态名单（approved / denied / expired）。界面要区分"同意／拒绝／过期"三句，
  /// 而这三者从契约上的推导关系取，不在 Dart 里再抄一份词表（抄的那份改不动服务端）。
  List<String> get pairRequestTerminalStatuses =>
      strings(const ['pairRequest', 'terminalStatuses']);

  /// 某一类客户端事件的载荷字段名单（服务端按名单逐字节比，多一个键都会被拒）。
  ///
  /// 名单**只许从这一处读**：加一类事件就在实现里抄一份字面量的话，契约改名的那一半
  /// 永远不会跟着改，而两端的表现是同一句同形的 403（本仓在 `type` 词表上撞过一次）。
  List<String> clientEventFields(String kind) =>
      strings(['clientEvents', kind, 'fields']);

  /// ack 载荷的字段名单。
  List<String> get ackFields => clientEventFields('ack');

  /// pairArm 载荷的字段名单（今日 = `["pairingCode"]`；档位不在这里，见 `pairing` 段）。
  List<String> get pairArmFields => clientEventFields('pairArm');

  /// pairConfirm 载荷的字段名单（今日 = `["requestId","decision","level"]`）。
  List<String> get pairConfirmFields => clientEventFields('pairConfirm');

  /// `pair`（B 侧那一发）载荷的字段名单，今日 = `["pairingCode","level"]`。
  ///
  /// 与 pairArm 那份分开列：两发的载荷名单**不同**（A 只挂口令，B 还要说自己想要哪一档），
  /// 合成一个 getter 就会有一边照抄另一边的名单 —— 服务端整条拒，而拒信与"口令错"同形。
  List<String> get pairFields => clientEventFields('pair');

  /// pairRevoke 载荷的字段名单（今日 = `["peerAddress"]`）。
  ///
  /// 这一发就一个键，但键名仍只从契约读：内核拿这份名单当**唯一**的载荷形状，
  /// 于是"给那个键改名"那一刀只在契约里落一次。写死在两份实现里的下场本仓撞过三次
  /// （`type` 词表、`pairingCode`、`decision`），每一次的表现都是同一句同形的 403。
  List<String> get pairRevokeFields => clientEventFields('pairRevoke');

  /// endpointCreate 载荷的字段名单（今日 = `["name"]`）。
  ///
  /// 名单里**没有也不该有** `secret`：口令由服务端生成，设备自带等于把"选一把多强的口令"
  /// 交给最不方便负责它的一端。这一条是设备侧唯一能判它的地方 —— 服务端只会照单收下形状对的键。
  List<String> get endpointCreateFields => clientEventFields('endpointCreate');

  /// endpointList 载荷的字段名单（今日 = `[]`，一条都不许带）。
  ///
  /// 空名单不是"这里忘了写"，它就是这一发的全部形状：读自己名下那几把入口不需要任何输入。
  /// 所以"多带一个键"不可能是便利，只能是有人在把这一发变成别的什么（比如按别人的地址列、
  /// 或"连调用日志一起给"）—— 那会长出第二个读口。名单为空 ⇒ 内核组出来的 `body` 就是 `{}`，
  /// 与服务端逐字节比名单的那一刀对得上。
  /// ⚠ 缺键时 `strings()` 抛，不许退化成空名单：契约没声明这条读口，设备就不该发这一发。
  List<String> get endpointListFields => clientEventFields('endpointList');

  /// endpointRevoke 载荷的字段名单（今日 = `["endpointId"]`）。
  ///
  /// 名单里**没有也不该有** `secret`：吊销要证明的是"你签过名 + 你说得清要关哪一把"，
  /// 而不是"你手里有那把口令"。带口令来证明是最想当然的一种写法，而它一旦成立，
  /// 这一发就成了"泄露过的口令还能用来关掉别人的入口"的第二条通道。
  List<String> get endpointRevokeFields => clientEventFields('endpointRevoke');

  /// endpointRotate 载荷的字段名单（今日 = `["endpointId"]`，与吊销逐字相同）。
  ///
  /// 名单里**没有** `graceSeconds`：宽限期是安全属性，不是客户端可传的偏好参数 ——
  /// 那个开关一存在，"旧口令还能用多久"就变成谁手快谁说了算。时长只读
  /// `endpoint.rotation.graceSeconds`，而设备侧连读都不必读：响应直接给 `rotatingUntil`。
  List<String> get endpointRotateFields => clientEventFields('endpointRotate');

  /// probe 载荷的字段名单（今日 = `["peer"]`，T106 的非浸入探针）。
  ///
  /// 载荷只有一个键：要查的那台**对端**的地址码。它刻意不是 `target` —— target 必须是本机
  /// （`targetMustEqualSender`），"要问谁"写在被签的 body 里，两者各司其职。
  List<String> get probeFields => clientEventFields('probe');

  /// 探针响应里那个结论键（今日 = `ready`）。**不写死**：服务端就是从契约拼这个键的，
  /// 名字住在两处时改一边不报错，只会让设备侧永远读到一个 null 而判成「探针没结论」。
  String get probeReadyField {
    final value = str(const ['clientEvents', 'probe', 'readyField']);
    if (value == null || value.isEmpty) {
      throw StateError('契约缺 clientEvents.probe.readyField（不补默认值）');
    }
    return value;
  }

  /// 探针载荷里那个「要问哪一台」的键名（今日 = `peer`）。
  ///
  /// 形状是**恰好一个键**：这一发只带一个地址码。多一个键（比如顺手问一句"对面在线吗"）
  /// 就是给它长第二条读口，而服务端那一刻能答的只有"这条链在服务端立不立得住"。
  /// 键名从契约读的理由与 pairArm 那份逐字相同：写一个 `'peer'` 字面量就是第二份真值。
  String get probePeerField {
    final declared = clientEventFields('probe');
    if (declared.length != 1 || declared.first.isEmpty) {
      throw StateError(
        '契约 clientEvents.probe.fields 必须恰好一个键（今日 = peer），实为 $declared',
      );
    }
    return declared.first;
  }

  /// 端点状态的**封闭**词表（今日 = `["active","revoked"]`）。
  List<String> get endpointStatuses => strings(const ['endpoint', 'statuses']);

  /// "这一把入口还收信"的那个状态词。**不写死 `'active'`**。
  ///
  /// 判一律走白名单（问"是不是 usableStatus"），不许问"是不是 revoked"：契约加第三档
  /// （比如 `frozen`）时黑名单式判定会把它当成可用的显示，而那正是本仓在 revocation
  /// 四个键上记过代价的那类错 —— 状态名写死在实现里，加档时不报错，只让没人认得的那一档照旧收信。
  String get endpointUsableStatus {
    final value = str(const ['endpoint', 'usableStatus']);
    if (value == null || value.isEmpty) {
      throw StateError('契约缺 endpoint.usableStatus（或是空串）：设备侧没法判"这一把还收不收信"');
    }
    return value;
  }

  /// 本机在这一发上能做的**那两种**决定（封闭集合：第三种取值服务端会整条拒）。
  List<String> get pairConfirmDecisions =>
      strings(['clientEvents', 'pairConfirm', 'decisions']);

  /// 名单里"同意"那一个词。**不写死 `'approved'`**：两端都从契约读，
  /// 词换了（比如改成 `granted`）时这里跟着走，而不是让新词一路 403。
  String get pairConfirmApproveDecision {
    final value = str(['clientEvents', 'pairConfirm', 'approveDecision']);
    if (value == null || value.isEmpty) {
      throw StateError('契约缺 clientEvents.pairConfirm.approveDecision（不补默认值）');
    }
    return value;
  }

  /// 逐条勾选清单（pairConfirm 的 `items`）的**取值域路径**（T134 片1）。
  ///
  /// 这里给的是"去哪两张表读"，不是清单本身 —— 设备侧构造勾选表时按这两个路径取，
  /// 别在本包再抄一份动作名（另立一本账不会报错，只会让两端各认一份清单）。
  List<String> get pairConfirmItemsVocabulary =>
      strings(['clientEvents', 'pairConfirm', 'itemsVocabularyFrom']);

  /// 声明过「可以缺席」的载荷键 → 缺席时该读成的值。
  Map<String, Object?> get pairConfirmOptionalFields =>
      map(['clientEvents', 'pairConfirm', 'optionalFields']) ?? const {};

  /// 拒绝时 items 必须为空 —— 设备侧在**构造答复**时就照这一条判（不等到服务端拒）。
  bool get pairConfirmItemsMustBeEmptyOnDeny =>
      at(['clientEvents', 'pairConfirm', 'itemsMustBeEmptyOnDeny']) == true;

  /// 词表外的取值回哪个状态码（值 = `statusCodes` 里的**键名**，不是数字）。
  String get pairConfirmUnknownItemStatus {
    final value = str(['clientEvents', 'pairConfirm', 'unknownItemStatus']);
    if (value == null || value.isEmpty) {
      throw StateError(
        '契约缺 clientEvents.pairConfirm.unknownItemStatus：'
        '状态码只有一个作者（statusCodes），在这里补默认值就是第二个来源',
      );
    }
    return value;
  }

  /// 配对请求在 poll 响应里带回来的那些字段。
  List<String> get pairRequestStoredFields =>
      strings(const ['pairRequest', 'storedFields']);

  /// 一条配对请求能处于哪些状态（封闭集合）。设备侧判断"服务端有没有把这件事结掉"
  /// 只认这张表 —— 词漂了要当场报，不能被读成"没有结果"。
  List<String> get pairRequestStatuses =>
      strings(const ['pairRequest', 'statuses']);

  /// 本机答复一条配对请求时**能写进载荷的最高一档**。
  ///
  /// `levelCeilingFrom` 存的是**路径**（今日 = `pairing.maxRequestableLevelFromPairing`），
  /// 不是档位字面量：服务端 `authorizePairConfirm` 读的就是这条路径，两端因此共用一个旋钮。
  /// 在这里写死 `'L2'` 的话，改契约的那一刀不会报错，只会变成"本机发得出去、服务端整条拒"，
  /// 而拒信是一句与"口令错"同形的 403。
  ///
  /// L3 不在这一发够得着的范围里：那一档要求对面在指令里携带高级密钥或二步验证码，
  /// 而**凭据只有接收端能校验**（服务端拿不到本机的哈希，也算不出 TOTP）——
  /// 所以它也不许从远程事件里被批准（T30 那条红线）。
  /// ⚠ 2026-10-04 之前这里写的是「要锁屏或生物认证」：那道本机认证的**平台通道从来没接过**
  /// （`unimplementedLocalAuthenticator` 永远回「没有认证器」，android/ 侧也没有
  /// `BiometricPrompt`），所以 L3 在那套条款下本来就开不起来。删掉它之后 L3 的安全度
  /// **只**由「对面带凭据」承担，而**这个上限值 L2 一个字节都没动**。
  String get pairConfirmLevelCeiling {
    final path = str(['clientEvents', 'pairConfirm', 'levelCeilingFrom']);
    if (path == null || path.isEmpty) {
      throw StateError(
        '契约缺 clientEvents.pairConfirm.levelCeilingFrom（不补默认档位：补了就是在代码里发明一档授权）',
      );
    }
    final value = str(path.split('.'));
    if (value == null || !capabilityLevels.contains(value)) {
      throw StateError(
        'clientEvents.pairConfirm.levelCeilingFrom=$path 取到的「$value」'
        '不是 capabilities.levels（${capabilityLevels.join('/')}）里的一档',
      );
    }
    return value;
  }

  /// 对方请求的那一档 → 本机实际能答应的那一档。
  ///
  /// 高于封顶 ⇒ **压到封顶**而不是原样发出去：发一个服务端必拒的档位换回的是一句同形的 403，
  /// 用户既不知道自己要的是 L3、也不知道是这一步被拦的。压完由界面把两个值都说出来
  /// （显示的是服务端回的 `grantedLevel`，不是用户点的那个）。
  /// 不在词表里的档位 ⇒ null：那一发**不该离机**，调用方据此不发并解释是哪个词。
  String? grantableLevel(String requested) {
    if (!capabilityLevels.contains(requested)) return null;
    final ceiling = pairConfirmLevelCeiling;
    return levelRank(requested) <= levelRank(ceiling) ? requested : ceiling;
  }

  /// B 侧「我要配对那台设备」时**够得着**的那几档（`clientEvents.pair.levelCeilingFrom`）。
  ///
  /// 为什么单开一条、不复用 [grantableLevel]：那一条读的是 `pairConfirm` 的路径，管的是
  /// "本机答复时能把授权写到哪"，而**请求**这一侧服务端判的方式不同 —— 超档是整条拒
  /// （`level-too-high`），不是压到封顶（`authorizePair`）。今天两条路径都指向
  /// `pairing.maxRequestableLevelFromPairing`，所以数字相同；复用的话，改一条不会有人喊，
  /// 而错的那一侧正是"L3 免确认"那道门。
  ///
  /// 界面上**摆不出来就不许点**：把 L3 放进选项、发出去换回的是一句与"口令错"同形的 403，
  /// 用户既不知道自己要的是哪一档，也不知道是这一步被拦的。
  /// 路径缺了 / 取到的不是词表里的一档 ⇒ 抛，不补默认档位（补一个默认档位等于在代码里发明一种授权）。
  List<String> get pairRequestableLevels {
    final path = str(['clientEvents', 'pair', 'levelCeilingFrom']);
    if (path == null || path.isEmpty) {
      throw StateError(
        '契约缺 clientEvents.pair.levelCeilingFrom（不补默认档位：补了就是在代码里发明一种授权）',
      );
    }
    final ceiling = str(path.split('.'));
    if (ceiling == null || !capabilityLevels.contains(ceiling)) {
      throw StateError(
        'clientEvents.pair.levelCeilingFrom=$path 取到的「$ceiling」'
        '不是 capabilities.levels（${capabilityLevels.join('/')}）里的一档',
      );
    }
    return capabilityLevels
        .where((level) => levelRank(level) <= levelRank(ceiling))
        .toList();
  }

  /// 挂出去的口令在这一步**不许带**的那一项：契约说它 arms 什么，实现就只发什么。
  String get pairArmPayloadField {
    final value = str(['clientEvents', 'pairArm', 'arms']);
    if (value == null || value.isEmpty) {
      throw StateError('契约缺 clientEvents.pairArm.arms（不补默认值）');
    }
    return value;
  }

  /// 设备能报的 `result` → 状态机事件。**这张表是封闭的**：不在表里的结果
  /// 设备不许自报（`expired` / `dropped` 是服务端自己的决定，让设备报就等于让它替服务端宣布结局）。
  Map<String, String> get ackResultToEvent {
    final table =
        map(const ['clientEvents', 'ack', 'resultToEvent']) ?? const {};
    return {for (final entry in table.entries) entry.key: '${entry.value}'};
  }

  /// 身份没证明之前那一句对外回执（`signature.onFailure.receipt`）。
  String get unsignedReceipt {
    final value = str(const ['signature', 'onFailure', 'receipt']);
    if (value == null || value.isEmpty) {
      throw StateError('契约缺 signature.onFailure.receipt（不补默认值）');
    }
    return value;
  }

  /// 某一类设备面事件要发到的路径（`transport.apiPaths.<kind>`）。
  ///
  /// 客户端不许自己拼 `'/api/fnthink/poll'`：服务端挂在哪儿由同一份契约说，两边各写一份的话，
  /// 改路径那一刀会变成"服务端换了门、客户端还在敲旧门" —— 而这一层在身份证明之前一律同形，
  /// 出问题时排查的人看不到任何区别。
  String apiPath(String kind) {
    final value = str(['transport', 'apiPaths', kind]);
    if (value == null || value.isEmpty) {
      throw StateError('契约缺 transport.apiPaths.$kind（不补默认值：拼出来的路径没人核对）');
    }
    return value;
  }

  /// 设备面路径全表（去掉解释性的 `_` 键）。给"声明的 = 实际挂的"那种双向守卫用。
  Map<String, String> get apiPaths {
    final table = map(const ['transport', 'apiPaths']) ?? const {};
    return {
      for (final entry in table.entries)
        if (!entry.key.startsWith('_')) entry.key: '${entry.value}',
    };
  }

  /// 设备这一路的标题信封（`deviceSend.titleEnvelope`）：前缀与两个键名。
  ///
  /// 三个值都必须从契约读而不是在代码里写死：写死了就是"第二份协议"—— 换前缀（v1→v2）时
  /// 发出去的一串与收件端拆的那一串不是同一串，症状是标题静默消失，而不是任何一处报错。
  String get deviceTitlePrefix {
    final value = str(const ['deviceSend', 'titleEnvelope', 'prefix']);
    if (value == null || value.isEmpty) {
      throw StateError('契约缺 deviceSend.titleEnvelope.prefix（不补默认前缀：默认前缀等于换协议）');
    }
    return value;
  }

  /// 信封里"标题"那个键的名字（`titleKey`）。
  String get deviceTitleKey {
    final value = str(const ['deviceSend', 'titleEnvelope', 'titleKey']);
    if (value == null || value.isEmpty) {
      throw StateError('契约缺 deviceSend.titleEnvelope.titleKey（不补默认值）');
    }
    return value;
  }

  /// 信封里"正文"那个键的名字（`bodyKey`）。
  String get deviceBodyKey {
    final value = str(const ['deviceSend', 'titleEnvelope', 'bodyKey']);
    if (value == null || value.isEmpty) {
      throw StateError('契约缺 deviceSend.titleEnvelope.bodyKey（不补默认值）');
    }
    return value;
  }

  /// 这一路要发到的路径（设备面投递面，`transport.apiPaths.message`）。
  String get deviceSendMessagePath => apiPath('message');

  /// 这份契约能不能被本包解释。返回 null = 可以；否则是不兼容的原因。
  String? unsupportedReason() {
    final declared = _protocolMajorOf(protocol);
    if (declared == null) {
      return 'protocol 名不是 fnthink-v<N> 的形状：$protocol';
    }
    if (declared != contractVersion) {
      return 'protocol 名里的版本（v$declared）与 contractVersion（$contractVersion）不一致';
    }
    if (contractVersion != fnthinkProtocolMajor) {
      return '契约 contractVersion=$contractVersion，本包只实现到 v$fnthinkProtocolMajor';
    }
    return null;
  }

  static int? _protocolMajorOf(String protocol) {
    final match = RegExp(r'^fnthink-v(\d+)$').firstMatch(protocol);
    return match == null ? null : int.parse(match.group(1)!);
  }

  /// 契约表自身的自洽检查。返回空列表 = 通过。
  ///
  /// 每条都对应一个"抄错时会静默生效"的点，所以宁可写密：
  /// 例如端点只能产 L1、私钥不可导出、口令错误与端点不存在同形、
  /// `delivered`/`expired` 都要删正文 —— 这些一旦在 JSON 里被改反，
  /// 两侧代码仍然各跑各的绿，只有这里会红。
  List<String> validate() {
    final problems = <String>[];
    void need(bool ok, String why) {
      if (!ok) problems.add(why);
    }

    need(unsupportedReason() == null, '协议版本声明不一致：${unsupportedReason()}');

    // ── 签名 ──
    final order = canonicalOrder;
    need(order.isNotEmpty, 'signature.canonicalOrder 为空');
    need(
      order.toSet().length == order.length,
      'signature.canonicalOrder 有重复字段：$order',
    );
    for (final required in const [
      'version',
      'type',
      'target',
      'ts',
      'nonce',
      'body',
    ]) {
      need(order.contains(required), '签名规范化顺序缺了 $required：$order');
    }
    need(
      (str(const ['signature', 'separator']) ?? '').isNotEmpty,
      'signature.separator 不能缺省或空串：两端各补一个默认值就是第二份实现',
    );
    need(
      boolOf(const ['signature', 'trustLocalClock']) == false,
      'signature.trustLocalClock 必须是 false：设备自算偏移，不信本机时钟',
    );
    need(
      str(const ['signature', 'timestampSource']) == 'serverTime',
      'signature.timestampSource 必须是 serverTime',
    );
    need(
      boolOf(const ['signature', 'nonceDedupe']) == true,
      'signature.nonceDedupe 必须为 true（双端去重是防重放的一半）',
    );
    need(
      boolOf(const ['signature', 'verifyOnlyForWhitelistedKeys']) == true,
      'signature.verifyOnlyForWhitelistedKeys 必须为 true：只对白名单内公钥验签',
    );
    // 验签的三个参数彼此有**关系**，不是三个孤立的数字。写歪一个不会报错，
    // 只会让"过期"和"重放"这两条在某个巧合下互相抵消。
    final skew = intOf(const ['signature', 'maxSkewSeconds']) ?? 0;
    final dedupe = intOf(const ['signature', 'nonceDedupeSeconds']) ?? 0;
    need(skew > 0, 'signature.maxSkewSeconds 必须是正数：为 0 等于要求两端时钟完全一致');
    need(
      dedupe >= skew * 2,
      'signature.nonceDedupeSeconds（$dedupe）必须不小于 2 × maxSkewSeconds（$skew）：'
      '否则一条"迟到在容差外、但仍在去重窗口内"的重放会两边都不管',
    );
    final encoding = map(const ['signature', 'publicKeyEncoding']);
    need(
      (encoding?['spkiPrefixHex'] as String? ?? '').length == 24 &&
          RegExp(
            r'^302a',
          ).hasMatch(encoding?['spkiPrefixHex'] as String? ?? ''),
      'publicKeyEncoding.spkiPrefixHex 必须是 12 字节的 Ed25519 SPKI 头（以 302a 开头）',
    );
    need(
      (encoding?['rawLength'] as num?)?.toInt() == 32,
      'publicKeyEncoding.rawLength 必须是 32：Ed25519 公钥就这个长度',
    );

    // 一根轴只许有一个旋钮。T71 那版留了个 `clockSkewSeconds: 120`（谁都没读），
    // T29-B 判过期用的是 `maxSkewSeconds: 300` —— 两份数值并排放着，漂了不会报错，
    // 只会表现成"一端严一端松"，而现场看到的是偶发 410。
    // 判据是"数值"：`maxSkewWhy` 那种解释性字符串不算第二个旋钮。
    final skewKeys =
        (map(const ['signature']) ?? const <String, Object?>{}).entries
            .where(
              (e) => e.key.toLowerCase().contains('skew') && e.value is num,
            )
            .map((e) => e.key)
            .toList()
          ..sort();
    need(
      skewKeys.length == 1 && skewKeys.first == 'maxSkewSeconds',
      'signature 段里 skew 类的键必须只有 maxSkewSeconds 一个，实为 $skewKeys',
    );
    need(
      boolOf(const ['signature', 'onFailure', 'count']) == true,
      'signature.onFailure.count 必须是 true：拒了不留数就是静默丢弃（T29 任务书那句"并计数"）',
    );

    // ── 设备这一路的标题信封（deviceSend.titleEnvelope）──
    // 这一节的四条都不是口味：每一条对应一个"改错了不会有任何东西报错"的现场。
    final envelope = map(const ['deviceSend', 'titleEnvelope']) ?? const {};
    need(
      envelope.isNotEmpty,
      '契约缺 deviceSend.titleEnvelope：设备发送那一路的标题去哪没有出处，'
      '两端就会各写一种编码（症状是收件端把整段信封当成正文显示）',
    );
    final envelopePrefix =
        str(const ['deviceSend', 'titleEnvelope', 'prefix']) ?? '';
    need(
      envelopePrefix.isNotEmpty,
      'deviceSend.titleEnvelope.prefix 不能为空：空前缀等于"任何正文都可能是信封"，'
      '收件端会开始把别人的第一行当标题',
    );
    // 前缀是**被签字段值的一部分**。分隔符混进去时 CanonicalMessage 会抛 —— 那是防伪边界，
    // 但抛在运行期就等于"这一路今天发不出去"，所以在这里判掉。
    // 这里读原始值而不是 `signatureSeparator` 那个 getter：分隔符本身缺失上面已经报过，
    // validate 不许把自己抛成一条异常（那会把"少一条问题"读成"契约没法读"）。
    final envelopeSeparator = str(const ['signature', 'separator']) ?? '';
    need(
      envelopePrefix.isEmpty || !envelopePrefix.contains(envelopeSeparator),
      'deviceSend.titleEnvelope.prefix 含 signature.separator：它出现在被签的 body 值里，'
      '而规范化函数见到分隔符就抛（能塞分隔符就能拼出与另一组字段相同的字节串）',
    );
    final titleKey =
        str(const ['deviceSend', 'titleEnvelope', 'titleKey']) ?? '';
    final bodyKeyValue =
        str(const ['deviceSend', 'titleEnvelope', 'bodyKey']) ?? '';
    need(
      titleKey.isNotEmpty &&
          bodyKeyValue.isNotEmpty &&
          titleKey != bodyKeyValue,
      'deviceSend.titleEnvelope 的 titleKey / bodyKey 必须非空且互不相同：'
      '同名时编码写得进去、拆不出来，标题与正文会互相覆盖',
    );
    // 交叉检查：信封挂在**已签的 body** 上。哪天 body 不在签名字节里，这一路发的标题
    // 就悄悄变成了未签内容 —— 而那条正是本协议反复拒的事，必须在这里红，不许靠人记得。
    need(
      order.contains('body'),
      'signature.canonicalOrder 里没有 body，而 deviceSend 的标题信封正是挂在这个字段上：'
      '此时的"标题"是未签内容',
    );
    need(
      str(const ['deviceSend', 'titleEnvelope', 'splitBy']) ==
          'receiving-client',
      'deviceSend.titleEnvelope.splitBy 必须是 receiving-client：本包只在收件端拆，'
      '声明成别的（例如服务端拆）就是两份实现各拆一半，同一条消息两种表现',
    );
    need(
      boolOf(const [
            'deviceSend',
            'titleEnvelope',
            'onlyWhenSignedTitleEmpty',
          ]) ==
          true,
      'deviceSend.titleEnvelope.onlyWhenSignedTitleEmpty 必须是 true：'
      '已签的标题是权威的，信封不许盖掉它',
    );

    // ── 状态码 ──
    final codes = statusCodes;
    need(codes.containsValue(202), 'statusCodes 里没有 202（queued 是异步投递的同步答复）');
    need(
      codes.entries.every(
        (e) => e.key == 'queued'
            ? e.value == 202
            : e.value >= 400 && e.value < 500,
      ),
      '除 queued 之外所有同步码都必须是 4xx：$codes',
    );
    need(codes.values.toSet().length == codes.length, '同步状态码有重复值：$codes');
    need(
      indistinguishable.length >= 2 &&
          indistinguishable.contains('unauthorized'),
      'statusCodes.indistinguishable 必须至少含 unauthorized 与"端点不存在"：'
      '否则返回码本身就能枚举端点',
    );
    for (final name in indistinguishable) {
      need(
        codes.containsKey(name) || name == 'notFoundEndpoint',
        'indistinguishable 引用了不存在的码 $name',
      );
    }

    // ── 回执 ──
    final receiptList = receipts;
    need(receiptList.isNotEmpty, 'receipts 为空');
    need(
      receiptList.toSet().length == receiptList.length,
      'receipts 有重复：$receiptList',
    );
    for (final path in const [
      ['signature', 'onFailure', 'receipt'],
      ['capabilities', 'endpointActionReceipt'],
      ['retention', 'overflowReceipt'],
    ]) {
      final value = str(path);
      need(
        value != null && receiptList.contains(value),
        '${path.join('.')} = $value 不在 receipts 里',
      );
    }

    // ── 字段容错 ──
    final aliasMap = aliases;
    for (final entry in aliasMap.entries) {
      need(entry.value.isNotEmpty, 'fieldTolerance.${entry.key} 为空');
      need(
        entry.value.first == entry.key,
        'fieldTolerance.${entry.key} 的首项必须是规范名（取第一个非空时以它为准）',
      );
      need(
        entry.value.toSet().length == entry.value.length,
        'fieldTolerance.${entry.key} 别名有重复：${entry.value}',
      );
    }
    need(
      aliasMap['title']!
          .toSet()
          .intersection(aliasMap['body']!.toSet())
          .isEmpty,
      'title 与 body 的别名集合不许相交：交集会让同一个字段在两处各取一次',
    );
    need(
      boolOf(const ['fieldTolerance', 'ignoreUnknownFields']) == true,
      'fieldTolerance.ignoreUnknownFields 必须为 true（多余字段要能吞掉）',
    );

    // ── presence ──
    final presenceList = strings(const ['presence', 'states']);
    final poll = map(const ['presence', 'pollIntervalSeconds']);
    need(
      boolOf(const ['presence', 'separateHeartbeatProtocol']) == false,
      'presence.separateHeartbeatProtocol 必须为 false：poll 即心跳',
    );
    need(
      (intOf(const ['presence', 'onlineThresholdMultiplier']) ?? 0) >= 2,
      'presence.onlineThresholdMultiplier 至少 2（否则抖动一次就判离线）',
    );
    need(
      presenceList.length == 3 &&
          Set<String>.from(
            presenceList,
          ).containsAll(const {'online', 'offline', 'unknown'}),
      'presence.states 必须正好是 online / offline / unknown 三态：$presenceList '
      '（少 unknown 就是把"从未上线"显示成"掉线"）',
    );
    need(
      (str(const ['presence', 'unknownMeans']) ?? '').isNotEmpty,
      'presence.unknownMeans 不能缺省：三态里那个 unknown 的解释必须写在契约上，不留在注释里',
    );
    if (poll != null) {
      final min = (poll['min'] as num).toInt();
      final max = (poll['max'] as num).toInt();
      final def = (poll['default'] as num).toInt();
      need(
        min <= def && def <= max,
        'presence.pollIntervalSeconds 的 default 不在 [min,max] 内',
      );
      // 提频与常态的关系只在这里判一次（下面 limits 那一段是同一件事的**唯一作者**，
      // 因为它手里才有推导所依据的那三个数）。这里曾经有第二条同判据的 need ——
      // 两条互相掩护，反证 K2 演过：摘掉这条另一位仍然报 ⇒ 全场绿，而那正是"两道闸互相掩护"
      // 的样本。判据没少，作者只剩一个。
    } else {
      need(false, 'presence.pollIntervalSeconds 缺失');
    }

    // ── 留存与上限（"不无谓留存"这条不变量）──
    need(
      (intOf(const ['retention', 'pendingPerDeviceMax']) ?? 0) > 0,
      'retention.pendingPerDeviceMax 必须 > 0',
    );
    need(
      (intOf(const ['retention', 'maxRetentionDays']) ?? 0) >= 1,
      'retention.maxRetentionDays 必须 ≥ 1',
    );
    final deleteOn = strings(const ['retention', 'deleteBodyOn']);
    for (final state in const ['delivered', 'expired']) {
      need(
        deleteOn.contains(state) && receiptList.contains(state),
        'retention.deleteBodyOn 必须包含 $state（既要是删除时机，也要是合法回执）',
      );
    }
    need(
      str(const ['retention', 'whilePending']) == 'static_encrypted',
      'retention.whilePending 必须是 static_encrypted',
    );
    need(
      boolOf(const ['retention', 'storeOnlyNecessaryFields']) == true,
      'retention.storeOnlyNecessaryFields 必须为 true',
    );
    final limits = map(const ['limits']);
    if (limits != null) {
      final perMinute = (limits['unauthenticatedPerMinute'] as num).toInt();
      final perDay = (limits['unauthenticatedPerDay'] as num).toInt();
      need(
        perMinute > 0 && perDay > perMinute,
        'limits.unauthenticatedPerDay 必须大于 unauthenticatedPerMinute',
      );
      need(
        (limits['groupSendMax'] as num).toInt() >= 1,
        'limits.groupSendMax 必须 ≥ 1',
      );
    } else {
      need(false, 'limits 段缺失');
    }

    // ── 能力分级（红线）──
    final levels = strings(const ['capabilities', 'levels']);
    need(
      levels.length >= 2 && levels.toSet().length == levels.length,
      'capabilities.levels 必须是不重复的两档以上：$levels',
    );
    need(
      levels.isNotEmpty && levels.first == 'L1',
      'capabilities.levels 必须按权限从低到高排（L1 在首）',
    );
    need(
      levels.isNotEmpty &&
          str(const ['capabilities', 'endpointMaxLevel']) == levels.first,
      'capabilities.endpointMaxLevel 必须是最低档（levels.first）：端点只能产 L1 消息',
    );
    need(
      boolOf(const ['capabilities', 'l3', 'allowSkipConfirm']) == false,
      'capabilities.l3.allowSkipConfirm 必须为 false：L3 不允许免确认',
    );
    need(
      boolOf(const ['capabilities', 'l3', 'noKeyValueGenericWrite']) == true,
      'capabilities.l3.noKeyValueGenericWrite 必须为 true：不做"键值通用写"接口',
    );
    need(
      str(const ['capabilities', 'l3', 'default']) == 'off',
      'capabilities.l3.default 必须是 off（默认全关）',
    );
    final downgrade = str(const [
      'capabilities',
      'l3',
      'circuitBreaker',
      'downgradeTo',
    ]);
    need(
      levels.contains(downgrade) && downgrade != levels.last,
      '熔断必须降到一个真实存在且低于最高档的级别：$downgrade',
    );
    need(
      str(const ['capabilities', 'l3', 'unknownAction']) == 'reject',
      'capabilities.l3.unknownAction 必须是 reject：两边不认识的 action 一律拒',
    );

    // ── L3 设置词表（T51）──
    // 与 L2 那张同一套做法：这张表是「L3 到底有哪几项设置」的**唯一出处**。
    // 两端各持一份映射，而它们的漂移不会报错 —— 表现是对面新加一项只有自己认得，
    // 设备端在 apply 段判成 unknown（而那一档恰好每次都要本地确认，用户看不出差别）。
    final l3SettingsRaw =
        map(const ['capabilities', 'l3', 'settings']) ?? const {};
    need(
      l3SettingsRaw.isNotEmpty,
      'capabilities.l3.settings 不能为空：为空等于 L3 这一档没有任何设置项，'
      '而 messageTypes.setting 仍然要求 L3',
    );
    final l3Modes = strings(const ['capabilities', 'l3', 'modes']);
    need(
      l3Modes.isNotEmpty,
      'capabilities.l3.modes 不能为空：settings 里每一项都要写 mode，'
      '而没有这张词表就没人能判它写对了没有',
    );
    for (final entry in l3SettingsRaw.entries) {
      final spec = entry.value;
      need(
        spec is Map,
        'capabilities.l3.settings.${entry.key} 必须是 {mode, native} 那一块',
      );
      if (spec is! Map) continue;
      final mode = '${spec['mode'] ?? ''}';
      need(
        mode.isNotEmpty && l3Modes.contains(mode),
        'capabilities.l3.settings.${entry.key} 的 mode=「$mode」不在 modes（${l3Modes.join('/')}）里',
      );
      need(
        '${spec['native'] ?? ''}'.isNotEmpty,
        'capabilities.l3.settings.${entry.key} 没写 native：'
        '没有落点的那一项等于"契约说有、设备上找不到"',
      );
    }
    final l3NeedsGrant = strings(const [
      'capabilities',
      'l3',
      'requiresExistingGrantFrom',
    ]);
    need(
      l3NeedsGrant.every(l3SettingsRaw.containsKey),
      'capabilities.l3.requiresExistingGrantFrom 里有不在 settings 里的项：$l3NeedsGrant',
    );
    // 先有授权才谈得上翻 —— 只对 toggle 成立。grant 那一类恰恰是要**去拿**那项授权，
    // 把它列进来就自相矛盾了（要"已有"的东西才能翻，而它正是要开的东西）。
    for (final key in l3NeedsGrant) {
      final spec = l3SettingsRaw[key];
      need(
        spec is Map && '${spec['mode'] ?? ''}' == 'toggle',
        'capabilities.l3.requiresExistingGrantFrom 里的 $key 不是 toggle：'
        '要求"先有授权才翻"的只可能是 toggle，而 grant 要的正是去拿那项授权',
      );
    }
    final l3Receipt = str(const ['capabilities', 'l3', 'settingsReceipt']);
    need(
      l3Receipt != null && l3Receipt.isNotEmpty,
      'capabilities.l3.settingsReceipt 必须写清（执行失败对外回哪一个词）',
    );
    need(
      l3Receipt != null && strings(const ['receipts']).contains(l3Receipt),
      'capabilities.l3.settingsReceipt=$l3Receipt 不在顶层 receipts 词表里：'
      '对外形状只能取那一处的词',
    );

    // ── 执行留痕（T53）──
    // 白名单 + 黑名单两份名单：白名单挡「没列的键」，黑名单挡「名字像留痕的正文键」
    // （body / title）被人顺手加进白名单去「留个底」—— 那正是 auditStoresMetadataOnly
    // 想防的事。两边合起来才是完整判据。
    final exFields = strings(const ['capabilities', 'execution', 'fields']);
    need(
      exFields.isNotEmpty,
      'capabilities.execution.fields 不能为空：为空等于执行留痕什么都记不下，'
      '而「谁让这台设备动了什么」这个问题就没有出处了',
    );
    final exForbidden = strings(const [
      'capabilities',
      'execution',
      'forbiddenFields',
    ]);
    need(
      exForbidden.isNotEmpty,
      'capabilities.execution.forbiddenFields 不能为空：白名单之外的正文类键'
      '需要单独喊出来，否则「留个底」这件事没有任何地方会拦',
    );
    final overlap = exFields.toSet().intersection(exForbidden.toSet());
    need(
      overlap.isEmpty,
      'capabilities.execution.fields 与 forbiddenFields 有交集：$overlap —— '
      '同一把键既在白名单又在黑名单里，实现读哪一边都不对',
    );
    for (final key in ['from', 'item', 'result', 'at']) {
      need(
        exFields.contains(key),
        'capabilities.execution.fields 缺 $key：'
        '少了它这条留痕答不出「谁让这台设备做了什么 / 成了没有」',
      );
    }
    final exKinds = strings(const ['capabilities', 'execution', 'kinds']);
    need(
      exKinds.isNotEmpty,
      'capabilities.execution.kinds 不能为空：界面按它分栏，'
      '而多一种就多一份没写过的显示逻辑',
    );
    final exResults = strings(const ['capabilities', 'execution', 'results']);
    need(
      exResults.contains('ok') &&
          exResults.contains('failed') &&
          exResults.contains('rejected'),
      'capabilities.execution.results 必须同时有 ok / failed / rejected：'
      'rejected（根本不该执行）与 failed（该执行但做不成）合成一个之后，'
      '用户看到「有条消息没生效」既不知道是对端越界还是自己没配好',
    );
    need(
      (intOf(const ['capabilities', 'execution', 'maxPerPeerDay']) ?? 0) > 0,
      'capabilities.execution.maxPerPeerDay 必须 > 0：'
      '0 意味着「一条都不留」，而那不是有界，那是没记',
    );
    need(
      boolOf(const ['capabilities', 'execution', 'storesBody']) == false,
      'capabilities.execution.storesBody 必须为 false：'
      '服务端审计只存元数据（与 privacy.auditStoresMetadataOnly 同一句承诺），'
      '留痕不是「顺便把正文也存一份」的新入口',
    );

    // ── L2 动作词表（T50）──
    // 这张表是「L2 到底有哪几个动作」的**唯一出处**：设备侧与服务端各持一份枚举映射，
    // 而它们之间的漂移不会报错 —— 表现是对面新加一个动作只有自己认得，
    // 服务端把它收进队列、设备端在 apply 段判成 unknown-action，两头日志互相看不懂。
    final l2Actions = strings(const ['capabilities', 'l2', 'actions']);
    need(
      l2Actions.isNotEmpty,
      'capabilities.l2.actions 不能为空：为空等于 L2 这一档没有任何合法动作，'
      '而它映射到的 messageTypes.action 仍然要求 L2',
    );
    need(
      l2Actions.toSet().length == l2Actions.length,
      'capabilities.l2.actions 里有重复项：$l2Actions',
    );
    need(
      l2Actions.every((a) => a.contains(':')),
      'capabilities.l2.actions 每项都要写成 <family>:<verb>（itemFormat）：$l2Actions',
    );
    need(
      str(const ['capabilities', 'l2', 'unknownAction']) == 'reject',
      'capabilities.l2.unknownAction 必须是 reject：认不出的 action 一律拒，'
      '不许「认不出就先跳过这一条」',
    );
    need(
      str(const ['capabilities', 'l2', 'itemFormat']) == '<family>:<verb>',
      'capabilities.l2.itemFormat 必须是 <family>:<verb>：actions 那张表按这个形状写，'
      '换一种形状两端的拆分就会各行其是',
    );
    final l2NeedsArg = strings(const [
      'capabilities',
      'l2',
      'requiresArgumentFrom',
    ]);
    need(
      l2NeedsArg.every((a) => l2Actions.contains(a)),
      'capabilities.l2.requiresArgumentFrom 里有不在 actions 里的 action：$l2NeedsArg',
    );
    // ── 回传动作那张表（T124 片B）──
    // count / keyword 两类的参数就是那条要回的东西，缺了它这一发没有东西可回 ⇒ 必须列进
    // requiresArgumentFrom；none（T124 片C-2 起）是**无参数的**回传动作 —— 它列进去反而
    // 自相矛盾（一处说必填、一处说没有）。
    final l2Reports = map(const ['capabilities', 'l2', 'reports']) ?? const {};
    for (final entry in l2Reports.entries) {
      final spec = entry.value;
      need(
        l2Actions.contains(entry.key),
        'capabilities.l2.reports 里有不在 actions 里的动作：${entry.key}',
      );
      final kind = spec is Map ? spec['argumentKind'] : null;
      need(
        kind == 'count' || kind == 'keyword' || kind == 'none',
        'capabilities.l2.reports.${entry.key}.argumentKind 必须是 count、keyword 或 none：$spec',
      );
      if (kind != 'none') {
        need(
          l2NeedsArg.contains(entry.key),
          'capabilities.l2.reports.${entry.key} 没列进 requiresArgumentFrom：'
          '回传的参数就是那条要回的东西，缺了它这一发没有东西可回',
        );
      }
      if (kind == 'count') {
        final minItems = spec is Map ? spec['minItems'] : null;
        final maxItems = spec is Map ? spec['maxItems'] : null;
        need(
          minItems is int && minItems >= 1,
          'capabilities.l2.reports.${entry.key}.minItems 必须是 ≥1 的整数：$spec',
        );
        need(
          maxItems is int && minItems is int && maxItems >= minItems,
          'capabilities.l2.reports.${entry.key}.maxItems 必须 ≥ minItems：$spec',
        );
      } else if (kind == 'keyword') {
        final minChars = spec is Map ? spec['minChars'] : null;
        final maxChars = spec is Map ? spec['maxChars'] : null;
        need(
          minChars is int && minChars >= 1,
          'capabilities.l2.reports.${entry.key}.minChars 必须是 ≥1 的整数：$spec',
        );
        need(
          maxChars is int && minChars is int && maxChars >= minChars,
          'capabilities.l2.reports.${entry.key}.maxChars 必须 ≥ minChars：$spec',
        );
      } else if (kind == 'none') {
        need(
          !l2NeedsArg.contains(entry.key),
          'capabilities.l2.reports.${entry.key} 是 none（无参数）却列进了 requiresArgumentFrom：'
          '一处说必填、一处说没有，读的人只能猜',
        );
        for (final stray in const [
          'minItems',
          'maxItems',
          'minChars',
          'maxChars',
        ]) {
          need(
            !(spec is Map && spec.containsKey(stray)),
            'capabilities.l2.reports.${entry.key}.$stray 属于别的 kind（none 没有上下界可写）：$spec',
          );
        }
        need(
          spec is Map && spec['title'] is String,
          'capabilities.l2.reports.${entry.key} 是 none ⇒ title 必写'
          '（不带 title 的 none 什么都没声明 —— 它存在的全部理由就是「这条无参动作会回传」）',
        );
      }
      // `title` **可选**：带它的那几项才会把东西回传（title 就是那条回传消息的标题）；
      // 没有 title 的只声明参数形状（`app:launch` 就是这一种——它不产出任何东西）。
      // 带错（空串／斜杠）仍要报：斜杠会与 item 的形状撞在读法上。
      if (spec is Map && spec.containsKey('title')) {
        final reportTitle = spec['title'];
        need(
          reportTitle is String &&
              reportTitle.isNotEmpty &&
              !reportTitle.contains('/'),
          'capabilities.l2.reports.${entry.key}.title 若写了就必须是非空、不含斜杠的串'
          '（它是回传那条消息的标题，斜杠会与 item 的形状撞在读法上）：$spec',
        );
      }
    }
    final l2Receipt = str(const ['capabilities', 'l2', 'actionReceipt']);
    need(
      l2Receipt != null && l2Receipt.isNotEmpty,
      'capabilities.l2.actionReceipt 必须写清（执行失败对外回哪一个词）',
    );
    need(
      l2Receipt != null && strings(const ['receipts']).contains(l2Receipt),
      'capabilities.l2.actionReceipt=$l2Receipt 不在顶层 receipts 词表里：'
      '对外形状只能取那一处的词',
    );
    need(
      typeTableLevelsFor('action') == 'L2',
      'capabilities.messageTypes.action 仍映射到 L2 —— L2 动作表存在而 type 侧不指向它，'
      '等于这张表没有读者',
    );
    // 同一条判据的 L3 那一半：`settings` 表存在而 type 侧不指向它 = 同样没有读者。
    // ⚠ 两条必须**各写一条**而不是合成一个循环：`for (final e in {...})` 里报出来的
    // 消息会含 type 名，而反证的点名串取自**测试标题**（标题里写的是 L2 或 L3）——
    // 合成一条之后，改 L3 那侧时红在同一条 L2 的消息上，读起来像「判据抓错了对象」。
    need(
      typeTableLevelsFor('setting') == 'L3',
      'capabilities.messageTypes.setting 仍映射到 L3 —— L3 设置表存在而 type 侧不指向它，'
      '等于这张表没有读者',
    );

    // ── 能力清单（T30）：type 词表与授权缺省 ──
    // 这张表是"同一把已配对的钥匙能做什么"的唯一出处。它松一格，
    // 表现不是报错，而是对端用一条本来只该是通知的消息触发了一个动作。
    final typeTable = messageTypeLevels;
    need(
      typeTable.isNotEmpty,
      'capabilities.messageTypes 不能为空：为空等于签名载荷里的 type 没有合法取值',
    );
    need(
      typeTable.values.every(levels.contains),
      'messageTypes 里有 minLevel 不在 levels 里：$typeTable',
    );
    need(
      typeTable.values.every((l) => l.isNotEmpty),
      'messageTypes 每项都必须写 minLevel（空串会被判成"级别不存在"而静默放行到最窄档）：$typeTable',
    );
    need(
      rejectsUnknownMessageTypes,
      'capabilities.unknownMessageType 必须是 reject：认不出的 type 不许"先收下、能做什么做什么"',
    );
    final itemFrom = str(const ['capabilities', 'itemRequiredFromLevel']) ?? '';
    need(
      levels.contains(itemFrom),
      'capabilities.itemRequiredFromLevel 必须是 levels 里的一档，实为 $itemFrom',
    );
    final grantDefault =
        str(const ['capabilities', 'grantDefaults', 'maxLevel']) ?? '';
    need(
      grantDefault == levels.first,
      'capabilities.grantDefaults.maxLevel 必须是最低档（查不到授权清单时要 fail-closed），实为 $grantDefault',
    );
    need(
      boolOf(const ['capabilities', 'grantChangeRequiresConfirmation']) == true,
      'capabilities.grantChangeRequiresConfirmation 必须为 true：授权变更要重新确认，不许远端悄悄升自己的权限',
    );
    // 每一档都得有能进它的 type，否则那档就是死档（配对了却什么都发不出来）。
    final covered = typeTable.values.toSet();
    need(
      levels.every(covered.contains),
      'levels 里有档位没有任何 type 能进：$levels vs $covered',
    );

    // ── 吊销与生命周期（T31）──
    final statuses = deviceStatuses.keys.toSet();
    need(
      statuses.isNotEmpty,
      'revocation.deviceStatuses 不能为空：设备状态没有词表就等于谁都能编一个',
    );
    need(
      statuses.contains('active'),
      'revocation.deviceStatuses 必须有 active（在册可投递那一档）：$statuses',
    );
    final allowed = strings(const ['revocation', 'deliveryAllowedStatuses']);
    need(
      allowed.isNotEmpty,
      'revocation.deliveryAllowedStatuses 不能缺省或为空（判投递时不许补默认状态）',
    );
    need(
      statuses.containsAll(allowed),
      'deliveryAllowedStatuses 里有不在 deviceStatuses 里的状态：$allowed vs $statuses',
    );
    // 白名单必须只有 active：多一个就是"某个被停用的状态仍能被投递"
    need(
      allowed.length == 1 && allowed.first == 'active',
      'revocation.deliveryAllowedStatuses 只能是 [active]：投递判定必须是白名单式，'
      '枚举"被停用的状态"会让将来新增的状态默认放行',
    );
    for (final key in const [
      'resetPairingCodeInvalidatesOutstanding',
      'identityRebuildInvalidatesAllPeers',
      'massRevokeSupported',
      'dataNeverDeletedByRevoke',
    ]) {
      need(
        boolOf(['revocation', key]) == true,
        'revocation.$key 必须为 true（重置即让旧配对失效、重建即让所有发送方重配、'
        '支持一键全部失效、吊销不删历史）',
      );
    }
    // #130-A5：状态词汇表 + 运维确认。这一段查两件事 ——「实现里那三个写死的状态字符串是不是
    // 还在跟契约各写一份」，以及「运维入口会不会把一整个设备群弄失联」。
    final revokedStatus = str(const ['revocation', 'revokedStatus']);
    final frozenStatus = str(const ['revocation', 'frozenStatus']);
    final resumableStatus = str(const ['revocation', 'resumableStatus']);
    final afterRebuildStatus = str(const ['revocation', 'afterRebuildStatus']);
    final statusNames = {
      'revokedStatus': revokedStatus,
      'frozenStatus': frozenStatus,
      'resumableStatus': resumableStatus,
      'afterRebuildStatus': afterRebuildStatus,
    };
    for (final entry in statusNames.entries) {
      need(
        entry.value != null && statuses.contains(entry.value),
        'revocation.${entry.key} 必须是 deviceStatuses 表上的一个（实际 ${entry.value}）：'
        '名字漂在表外的一档，表现不是报错，而是「这台设备的状态看着正常，但没有任何代码认得它」',
      );
    }
    // 四个动作各指向一档，且互不相同：两个动作写进同一档，记录上就分不出"是谁把它停在这里的"，
    // 而运维要回答的是"我刚才那一下动了什么"。
    final named = statusNames.values.whereType<String>().toSet();
    need(
      named.length == statusNames.length,
      'revocation 的四个状态名互不相同（吊销 / 冻结 / 允许投递 / 待重建）：实际 $statusNames —— '
      '其中两个相同就等于「两种后续完全相反的动作在记录上长成同一行」',
    );
    need(
      resumableStatus != null &&
          allowed.isNotEmpty &&
          resumableStatus == allowed.first,
      'revocation.resumableStatus 必须就是 deliveryAllowedStatuses 里那一个：'
      '「解冻」的去处必须是允许投递的那档，否则解完冻仍然一条都投不进去 —— '
      '而这在界面上看起来是成功的',
    );
    for (final name in [revokedStatus, afterRebuildStatus]) {
      need(
        name == null || !allowed.contains(name),
        'revocation 的「$name」不许出现在 deliveryAllowedStatuses 里：那等于「已吊销/待重建」仍算可投递',
      );
    }
    need(
      revokedStatus == null ||
          afterRebuildStatus == null ||
          revokedStatus != afterRebuildStatus,
      'revokedStatus 与 afterRebuildStatus 不许是同一档：两个动作写进同一个状态，'
      '「一键全部失效」与「本机重建身份」在记录上就分不开了，而它们的后续完全相反'
      '（前者是这台设备被踢掉，后者是等所有发送方重配）',
    );
    final confirmActions = strings(const ['ops', 'confirmationRequiredFor']);
    need(
      confirmActions.isNotEmpty &&
          confirmActions.toSet().length == confirmActions.length,
      'ops.confirmationRequiredFor 必须非空且无重复：${confirmActions.join(', ')}',
    );
    need(
      boolOf(const ['revocation', 'massRevokeSupported']) != true ||
          confirmActions.contains('revokeAll'),
      '支持一键全部失效（massRevokeSupported=true）就必须把它列进 confirmationRequiredFor：'
      '一次误点的代价是一整个设备群同时失联，而它在界面上和一个普通按钮长得一模一样',
    );
    need(
      !confirmActions.contains('freeze') && !confirmActions.contains('resume'),
      'freeze / resume 不许要求确认：冻结留着记录与公钥、随时可解、一条都不投 —— '
      '把确认压在可即时撤销的动作上，代价是运维很快就学会不看那个框直接点，'
      '而那才是真正危险的漂移（要确认的应该是回不去的那一类）',
    );
    final listMaxRows = intOf(const ['ops', 'listMaxRows']);
    need(
      (listMaxRows ?? 0) > 0,
      'ops.listMaxRows 必须是正整数（实际 $listMaxRows）：列状态没有上限，'
      '就是把管理面做成一台「一次拉走整张设备表」的机器',
    );
    final devicesMaxForOps = intOf(const ['limits', 'devicesMax']);
    need(
      listMaxRows == null ||
          devicesMaxForOps == null ||
          listMaxRows <= devicesMaxForOps,
      'ops.listMaxRows 不许大于 limits.devicesMax：超过表上限的上限本身没有意义，'
      '只会让人以为「列表一定是全的」',
    );
    // #138 T38：接入端点。这一段最容易写歪的不是数字大小，而是「缺省值朝哪个方向」
    // 与「日志里到底有什么」。
    final epStatuses = strings(const ['endpoint', 'statuses']);
    need(
      epStatuses.length == 2 &&
          epStatuses.contains('active') &&
          epStatuses.contains('revoked'),
      'endpoint.statuses 必须正好是 active 与 revoked（实际 ${epStatuses.join(', ')}）：'
      '端点状态回答的是「这把口令还能不能用」，多一档就有一次「被吊销的端点还在收信」的余地',
    );
    final epUsable = str(const ['endpoint', 'usableStatus']);
    final epRevoked = str(const ['endpoint', 'revokedStatus']);
    need(
      epUsable != null &&
          epStatuses.contains(epUsable) &&
          epRevoked != null &&
          epStatuses.contains(epRevoked) &&
          epUsable != epRevoked,
      'endpoint.usableStatus / revokedStatus 必须都在 statuses 上且互不相同'
      '（实际 $epUsable / $epRevoked）：判定"这个端点还能不能用"必须是白名单式（是不是 usable），'
      '枚举「被停用的状态」就是 T31 那次写反的那个形状 —— 加一档时它静默放行',
    );
    final perDeviceMax = intOf(const ['endpoint', 'perDeviceMax']);
    final endpointGlobalMax = intOf(const ['endpoint', 'globalMax']);
    need(
      (perDeviceMax ?? 0) > 0 && (endpointGlobalMax ?? 0) > 0,
      'endpoint.perDeviceMax / globalMax 必须是正整数：创建一个端点就是表里多一行加一把长期口令，'
      '没有上限等于让未认证侧按自己的意愿增长存储',
    );
    need(
      perDeviceMax == null ||
          endpointGlobalMax == null ||
          perDeviceMax <= endpointGlobalMax,
      'endpoint.perDeviceMax 不许大于 globalMax：单台上限超过全局上限的那条限制永远不会生效，'
      '而读契约的人会以为它管着些什么',
    );
    final graceSeconds = intOf(const ['endpoint', 'rotation', 'graceSeconds']);
    need(
      (graceSeconds ?? 0) >= 60,
      'endpoint.rotation.graceSeconds 至少 60 秒（实际 $graceSeconds）：宽限短于一次正常的运维操作，'
      '结果就是「换钥匙那一刻所有集成同时 401」—— 而那会让人从此不再换口令',
    );
    need(
      graceSeconds == null || graceSeconds <= 24 * 3600,
      'endpoint.rotation.graceSeconds 不许超过一天：宽限期越长，被拖走的旧口令还能用的窗口也越长，'
      '这是直接的取舍，不是可以无限给的好事',
    );
    need(
      str(const ['endpoint', 'ipAllowlistEmptyMeans']) == 'any',
      'endpoint.ipAllowlistEmptyMeans 只能是 any：空名单若意味着「谁都拒」，表现是「我建了端点、'
      '口令也对，却全 401」，而那看起来像服务端坏了。配置项的缺省必须是「没配也能跑」那个方向',
    );
    need(
      str(const ['endpoint', 'ipMismatchOutcome']) == 'same-as-bad-secret',
      'endpoint.ipMismatchOutcome 必须是 same-as-bad-secret：IP 不在白名单时若给出不同的结论，'
      '这个入口就成了一台专门回答「哪个来源 IP 被哪个端点允许」的探针',
    );
    final methodStatus = intOf(const ['endpoint', 'postOnlyMethodStatus']);
    need(
      methodStatus != null && methodStatus >= 400 && methodStatus < 500,
      'endpoint.postOnlyMethodStatus 必须是 4xx（实际 $methodStatus）：postOnly 拒绝 GET 是请求方式的问题，'
      '不是服务端故障，也不是身份问题',
    );
    need(
      methodStatus == null || !codes.containsValue(methodStatus),
      'endpoint.postOnlyMethodStatus 与 statusCodes 里的某个码重复（$methodStatus）：'
      '两个不同结论共用一个码 ⇒ 客户端只能猜，与 413/429 撞码是同一类错误',
    );
    final logMax = intOf(const ['endpoint', 'callLog', 'maxPerEndpoint']);
    need(
      logMax != null && logMax > 0 && logMax <= 1000,
      'endpoint.callLog.maxPerEndpoint 必须是 1–1000 的整数（实际 $logMax）：'
      '无界的「最近调用日志」就是攻击者驱动的存储，而它正是洪水最容易打到的那一项',
    );
    final logFields = strings(const ['endpoint', 'callLog', 'fields']);
    need(
      logFields.isNotEmpty && logFields.toSet().length == logFields.length,
      'endpoint.callLog.fields 必须非空且无重复：${logFields.join(', ')}',
    );
    for (final field in logFields) {
      need(
        const [
              'body',
              'title',
              'secret',
              'path',
              'url',
              'signature',
              'pairingCode',
            ].contains(field) ==
            false,
        'endpoint.callLog.fields 里出现了 $field：调用日志只许存元数据（时间/来源/结论）。'
        '正文一旦进了日志，privacy.auditStoresMetadataOnly 那句话就成空话 —— '
        '而日志字段是最容易被复制粘贴的东西，写下它的人不会再去查允许到什么程度',
      );
    }

    // ── 端点收单的两条入口（T39 / T40 / T41）──
    // 服务端（endpointintake.ingressFromContract）读到不达标就抛可降级的 SHAPE；客户端在这里
    // 拦下的是「一份看着齐全、其实会把长期口令送给别人日志」的契约。两侧读的是同一批数，
    // 所以这里的每一条都必须是方向性的（谁大谁小、只能取某个值），而不只是"键在不在"。
    final ingress = map(const ['endpoint', 'ingress']);
    need(
      ingress != null,
      'endpoint.ingress 必须存在：配额、长度上限、口令放在哪一段、能不能指定投递目标 —— '
      '这些都没有第二个来源，缺段就等于让两份实现各猜一次',
    );
    final inMinute = intOf(const ['endpoint', 'ingress', 'quota', 'perMinute']);
    final inDay = intOf(const ['endpoint', 'ingress', 'quota', 'perDay']);
    need(
      inMinute != null && inMinute > 0 && inDay != null && inDay > 0,
      'endpoint.ingress.quota 两个数必须是正整数（实际 分钟=$inMinute 日=$inDay）：'
      '没有配额的入口就是挂在公网上的无闸收单机',
    );
    need(
      inMinute == null || inDay == null || inDay > inMinute,
      'endpoint.ingress.quota 的日额度必须大于分钟额度（$inDay ≤ $inMinute）：'
      '日额度比分钟额度还小，正常用一天就会被自己的配额拦住，而那看起来像「服务端坏了」',
    );
    final inTitle = intOf(const ['endpoint', 'ingress', 'maxTitleChars']);
    final inBody = intOf(const ['endpoint', 'ingress', 'maxBodyChars']);
    final byteCap = intOf(const ['limits', 'requestBodyMaxBytes']);
    need(
      inTitle != null && inTitle > 0 && inBody != null && inBody > 0,
      'endpoint.ingress.maxTitleChars / maxBodyChars 必须是正整数（实际 $inTitle / $inBody）：'
      '超限是 400 明确拒，没有这两个数就没有"拒"的判据',
    );
    need(
      inBody == null || byteCap == null || inBody <= byteCap,
      'endpoint.ingress.maxBodyChars（$inBody）不许大于 limits.requestBodyMaxBytes（$byteCap）：'
      '字符数上限比字节闸还宽等于这条限制不存在，而读契约的人会以为它管着什么',
    );
    need(
      str(const ['endpoint', 'ingress', 'targetSource']) ==
              'owner-device-record' &&
          boolOf(const ['endpoint', 'ingress', 'maySpecifyTarget']) == false,
      'endpoint.ingress 必须把投递目标锁在「端点所属那台设备」上'
      '（targetSource=owner-device-record 且 maySpecifyTarget=false）：'
      '允许外部指定 target，等于一把口令泄露就能骚扰这台实例上的全部设备',
    );
    need(
      str(const ['endpoint', 'ingress', 'insecureTransport']) == 'reject',
      'endpoint.ingress.insecureTransport 只能是 reject：明文传输时口令裸奔在路径段里，'
      '「默认允许 + 偶尔提醒」不是这条承诺的表达方式（本地 http 走环境变量开关，不走契约）',
    );
    final redact = str(const ['transport', 'accessLogRedactPathPattern']) ?? '';
    final inPath = str(const ['endpoint', 'ingress', 'pathPattern']) ?? '';
    final inPostPath =
        str(const ['endpoint', 'ingress', 'postBearerPath']) ?? '';
    need(
      redact.isNotEmpty &&
          inPath.startsWith(redact) &&
          inPostPath.startsWith(redact),
      'endpoint.ingress 的两条路径都必须落在 transport.accessLogRedactPathPattern（$redact）之内：'
      '脱敏规则盖不住这个路径，就等于把长期口令写进别人的 access log',
    );
    need(
      inPath.endsWith(':secret') && !inPostPath.contains(':secret'),
      'pathPattern 必须以 :secret 作最后一段承载口令，而 postBearerPath 不许带它'
      '（那条是 Authorization: Bearer）：两条形状各自只说一种放法，'
      '否则实现会同时支持「口令在路径」与「口令在 query」，而后一种正是 transport.secretPlacement 禁的',
    );
    need(
      !inPath.contains('?') && !inPostPath.contains('?'),
      'endpoint.ingress 的两条路径里不许出现 query（?）：口令一旦能放进 query，'
      '脱敏与「只进路径段」这两句就同时失效，而且日志副本不止一份',
    );
    final capReceipt = str(const [
      'endpoint',
      'ingress',
      'rejectedCapabilityReceipt',
    ]);
    need(
      capReceipt != null &&
          strings(const ['receipts']).contains(capReceipt) &&
          capReceipt == str(const ['capabilities', 'endpointActionReceipt']),
      'endpoint.ingress.rejectedCapabilityReceipt（$capReceipt）必须是 receipts 里的一个词，'
      '且与 capabilities.endpointActionReceipt 同名：端点被能力边界拦住时对外只有一句话，'
      '两处各写一个词就变成了"同一个拒绝有两种说法"',
    );

    // ── 第三方载荷那枚 type 的折价（T120）──
    // 与 JS 侧 `ingressFromContract` 双端同读同一批数，两条都是**方向性**判据：
    //  ① 折成的词必须在 `capabilities.messageTypes` 的键上 —— 折成一个词表外的新词，等于把
    //     unknown-type 那道闸从收单处往后推给设备，而设备那条路收到的是"已经进队"的消息；
    //  ② 那一档的 minLevel 不许高于 `capabilities.endpointMaxLevel` —— 折价只能朝下，朝上就是
    //     把每一条读不懂的第三方推送都当成一次动作申请。
    // 设备侧为什么也要钉：这一折守的是「设备永远只见到词表内的 type」。契约漂了而这里不拦，
    // 表现是服务端按新词放行、设备按自己的表判成未知 —— 同一句话两种解释，正是双端校验存在的原因。
    final unknownTypeAs = str(const ['endpoint', 'ingress', 'unknownTypeAs']);
    final unknownTypeLevel = typeTable[unknownTypeAs ?? ''];
    need(
      unknownTypeAs != null &&
          unknownTypeAs.isNotEmpty &&
          unknownTypeLevel != null,
      'endpoint.ingress.unknownTypeAs（$unknownTypeAs）必须是 capabilities.messageTypes 里的一个词：'
      '词表外的值要折成的是「协议里有定义的那一档」，不是再造一个新词',
    );
    // ⚠ 只在缺省词本身合法时去比档位：缺省词都不合法时上面那条已经报了，这里再拿它去
    // `levels.indexOf` 会当场抛 —— 而 validate 抛异常的表现是"设备读契约时崩"，
    // 这一段存在的意义恰恰是"改坏了要报得清楚"。
    final endpointMax = str(const ['capabilities', 'endpointMaxLevel']) ?? '';
    if (unknownTypeLevel != null) {
      need(
        levels.contains(unknownTypeLevel) &&
            levels.contains(endpointMax) &&
            levels.indexOf(unknownTypeLevel) <= levels.indexOf(endpointMax),
        'endpoint.ingress.unknownTypeAs 那一档的 minLevel（$unknownTypeLevel）不许高于 '
        'capabilities.endpointMaxLevel（$endpointMax）：折价只能朝下',
      );
    }
    // 用 `at(...) is bool` 而不是 `boolOf(...) != null`：那枚 helper 是 `as bool?`，
    // 契约里写着 "yes" 时它抛 TypeError 而不是报一条问题（同一个坑，见上面那条注释）。
    need(
      at(const ['endpoint', 'ingress', 'ignoreItemField']) is bool,
      'endpoint.ingress.ignoreItemField 必须是布尔：第三方载荷里的 item 到底当噪音还是当越权，'
      '是一件要写下来并连同理由一起改的决定，不是实现里顺手的一个 if',
    );

    // ── 端点档的干跑（T106 片①b）──
    // 这一段与 JS 侧 `probeFromContract` 各判一次是**双端同读**，不是两份真值：两边读同一份
    // 契约的同一批键。设备侧连「这条 URL 长什么样」都不许自己拼 —— 路径只有契约一份作者
    //（与 T87 那份教程同一条纪律）。
    final probePath = str(const ['endpoint', 'probe', 'bearerPath']) ?? '';
    need(
      probePath.isNotEmpty &&
          redact.isNotEmpty &&
          probePath.startsWith(redact) &&
          !probePath.contains(':secret') &&
          !probePath.contains('?'),
      'endpoint.probe.bearerPath（$probePath）必须落在 transport.accessLogRedactPathPattern'
      '（$redact）之内，且既不带 :secret 也不带 query：探针会被自动重探反复打，'
      '口令进 URL 就是把副本多送一份给链路上每一层日志',
    );
    final probeTail = probePath.split('/').last;
    need(
      inPostPath.isNotEmpty &&
          probePath.startsWith('$inPostPath/') &&
          probePath.substring(inPostPath.length + 1) == probeTail &&
          !probeTail.startsWith(':'),
      'endpoint.probe.bearerPath 必须是 postBearerPath 再接**一个固定字面量**段（实际 "$probePath"，'
      '而 postBearerPath 是 "$inPostPath"）：中间多出参数段、或尾段本身是参数，它就会与 '
      'ingress.pathPattern 的 :secret 撞位 —— 而 Express 按注册顺序匹配，撞了的表现是探针打到收单'
      '那条并回 401，看起来像「口令错了」，实际是路由没接上（顺序这一半由服务端用例钉，契约只能钉形状）',
    );
    need(
      str(const ['endpoint', 'probe', 'secretPlacement']) == 'bearer-header',
      'endpoint.probe.secretPlacement 只能是 bearer-header：口令出现在请求头里，是这一发能被'
      '反复自动重探而不多留一份 URL 副本的前提',
    );
    need(
      boolOf(const ['endpoint', 'probe', 'writesCallLog']) == false,
      'endpoint.probe.writesCallLog 只能是 false：那份调用日志有界（callLog.maxPerEndpoint），'
      '自动重探每轮往里塞几行，等于让健康监测把自己要观察的那份历史挤掉',
    );
    need(
      boolOf(const ['endpoint', 'probe', 'chargesIngressQuota']) != null,
      'endpoint.probe.chargesIngressQuota 必须是布尔：健康监测花不花被监测那条路的额度，'
      '是一件要写下来并说清理由的决定，不是实现里顺手的一个 if',
    );

    // ── 投递状态机（T34）──
    // 这里查的是"这张表本身能不能跑"，不是"实现对不对"（那由双端共读的向量查）。
    // 一张少边的迁移表不会报错，只会让消息停在中间态 —— 而中间态 = 正文一直被留着。
    final dStates = strings(const ['delivery', 'states']);
    need(dStates.isNotEmpty, 'delivery.states 不能为空：状态机没有状态表，两边就只能各编一套');
    need(
      dStates.toSet().length == dStates.length,
      'delivery.states 有重复：$dStates',
    );
    final dInitial = str(const ['delivery', 'initialState']);
    need(
      dInitial != null && dStates.contains(dInitial),
      'delivery.initialState 必须是 states 里的一个：$dInitial vs $dStates',
    );
    final dTerminals = strings(const ['delivery', 'terminalStates']);
    need(
      dStates.toSet().containsAll(dTerminals),
      'delivery.terminalStates 里有不存在的状态：$dTerminals vs $dStates',
    );
    final dTransitions = map(const ['delivery', 'transitions']) ?? const {};
    need(
      dStates.every((s) => dTransitions.containsKey(s)),
      'delivery.transitions 必须给**每个**状态一条边（终态给空表）：缺的就是"走到那儿就不知道怎么办"：$dStates vs ${dTransitions.keys.toList()}',
    );
    need(
      dTransitions.keys.every((s) => dStates.contains(s)),
      'delivery.transitions 的键里有不在 states 里的状态：${dTransitions.keys.toList()}',
    );
    for (final entry in dTransitions.entries) {
      final targets = (entry.value as List<Object?>? ?? const [])
          .map((e) => '$e')
          .toList();
      need(
        dStates.toSet().containsAll(targets),
        'delivery.transitions.${entry.key} 指向不存在的状态：$targets',
      );
      need(
        dTerminals.contains(entry.key) ? targets.isEmpty : targets.isNotEmpty,
        'delivery.transitions.${entry.key}：终态不许有出边、非终态必须有出边（有出边的"终态"说明它不是终点，'
        '而没出边的非终态会让消息卡死）',
      );
    }
    // 从初态走不到某个状态 ⇒ 那条状态是死的：要么写错，要么实现永远不会进它。
    if (dInitial != null && dStates.isNotEmpty) {
      final reached = <String>{dInitial};
      var frontier = <String>[dInitial];
      while (frontier.isNotEmpty) {
        frontier = [
          for (final s in frontier)
            for (final t in (dTransitions[s] as List<Object?>? ?? const []).map(
              (e) => '$e',
            ))
              if (!reached.contains(t)) t,
        ].toSet().toList();
        reached.addAll(frontier);
      }
      need(
        reached.length == dStates.length,
        'delivery.states 里有从 initialState 走不到的状态：${dStates.where((s) => !reached.contains(s)).toList()}'
        '（写出来却到不了的状态，早晚会被两边按不同方式处理）',
      );
    }
    final dEvents = strings(const ['delivery', 'events']);
    need(
      dEvents.isNotEmpty && dEvents.toSet().length == dEvents.length,
      'delivery.events 必须非空且不重复：$dEvents',
    );
    // 正文释放条件必须**覆盖每一个终态**：漏一个（T34 第一次就漏了 dropped）等于
    // "这条消息永远不会再投了，而它的正文按契约合法地留到 7 天"。
    final deleteBodyOn = strings(const ['retention', 'deleteBodyOn']);
    need(
      dStates.toSet().containsAll(deleteBodyOn),
      'retention.deleteBodyOn 里有不是投递状态的值：$deleteBodyOn vs $dStates',
    );
    need(
      deleteBodyOn.toSet().containsAll(dTerminals),
      'retention.deleteBodyOn 必须覆盖全部终态 $dTerminals，实为 $deleteBodyOn —— '
      '漏掉的那个终态会永远留着正文，而它已经不会再被投递了',
    );
    final retryTotal = intOf(const ['limits', 'deliveryRetryTotal']);
    need(
      retryTotal != null && retryTotal >= 0 && retryTotal < 10,
      'limits.deliveryRetryTotal 必须是 0..9 的整数（它是重试次数，不是尝试总数）：$retryTotal',
    );
    for (final r in const [
      'delivered',
      'waiting_online',
      'expired',
      'dropped',
    ]) {
      need(
        (raw['receipts'] as List<Object?>? ?? const []).contains(r),
        '状态机要发的回执 $r 不在 receipts 里：回执词表与状态机必须同源',
      );
    }
    // 补发走哪条路，取自 waitingOnline 段（不许在 delivery 里再抄一份）。
    final resendFrom = str(const ['delivery', 'resendDecisionFrom']);
    final waiting = map([resendFrom ?? '']) ?? const {};
    need(
      waiting.isNotEmpty &&
          boolOf([resendFrom ?? '', 'mutuallyExclusive']) == true,
      'delivery.resendDecisionFrom 必须指向一个 mutuallyExclusive=true 的段'
      '（备用补推与排队补发二选一，绝不并存 —— 并存就是同一条消息提醒两次）：$resendFrom',
    );
    need(
      waiting['withBackupChannel'] != null &&
          waiting['withoutBackupChannel'] != null &&
          waiting['withBackupChannel'] != waiting['withoutBackupChannel'],
      '$resendFrom 的 withBackupChannel / withoutBackupChannel 必须都存在且互不相同：$waiting',
    );
    // poll 能取走哪些状态也是契约事实：代码里写 `state === 'queued'` 就是第二份状态表。
    final pollable = strings(const ['delivery', 'pollableStates']);
    need(
      pollable.isNotEmpty && pollable.toSet().length == pollable.length,
      'delivery.pollableStates 必须非空且不重复：$pollable',
    );
    need(
      dStates.toSet().containsAll(pollable),
      'delivery.pollableStates 里有不存在的状态：$pollable vs $dStates',
    );
    need(
      dInitial == null || pollable.contains(dInitial),
      'delivery.pollableStates 必须含初态（新消息就是从这里被取走的）：$pollable',
    );
    need(
      pollable.every((s) => !dTerminals.contains(s)),
      'delivery.pollableStates 里有终态（终态已经没有正文可发）：$pollable vs $dTerminals',
    );
    // 「取走了没等到 ack」的超时档必须存在且远大于一轮 poll：小于两三轮就会把一次正常往返
    // 误判成丢 ack（设备离线/提频时），而没有它 poll 的扫描无事可做、no_ack 永远不触发。
    final ackDeadline = intOf(const ['delivery', 'ackDeadlineSeconds']);
    final cadenceMax = intOf(const ['presence', 'pollIntervalSeconds', 'max']);
    need(
      ackDeadline != null && ackDeadline > 0,
      'delivery.ackDeadlineSeconds 必须是正整数（没有它 no_ack 没有触发时机）：$ackDeadline',
    );
    if (ackDeadline != null && ackDeadline > 0 && cadenceMax != null) {
      need(
        ackDeadline >= cadenceMax * 3,
        'delivery.ackDeadlineSeconds（$ackDeadline）必须 ≥ 3× cadence max（$cadenceMax）：'
        '太紧会把一次正常往返误判成丢 ack，太松则卡住窗口变长',
      );
    }
    need(
      str(const ['privacy', 'dedupeRefreshWhile']) != null &&
          dStates.contains(str(const ['privacy', 'dedupeRefreshWhile'])),
      'privacy.dedupeRefreshWhile 必须是一个投递状态：'
      '${str(const ['privacy', 'dedupeRefreshWhile'])}',
    );
    // 同意门（T56）：这一档是"文案变了要重新问一次"的唯一开关，必须存在且是正整数。
    // 缺了它，同意要么永远算成立（默认当同意 = 替用户做决定），要么永远算不成立
    // （功能对谁都不可用）—— 两种都不可接受，所以缺省一律判红。
    final consentVersion = intOf(const ['privacy', 'relayConsentVersion']);
    need(
      consentVersion != null && consentVersion > 0,
      'privacy.relayConsentVersion 必须是正整数（它是"同意过"的判据；缺了要么永远算同意'
      '、要么永远算没同意）：$consentVersion',
    );
    // 回执只走 poll 响应，且与「发送端不轮询状态接口」必须同向 ——
    // 一个说 poll_response、一个说 senderPollsStatusEndpoint=true，就是两条并存的路。
    need(
      str(const ['delivery', 'receiptDelivery']) == 'poll_response' &&
          boolOf(const ['delivery', 'senderPollsStatusEndpoint']) == false,
      'delivery.receiptDelivery 必须是 poll_response 且 senderPollsStatusEndpoint 必须为 false：'
      '回执另开一个状态接口，等于让发送端去轮一个契约没定义的入口',
    );

    // ── 设备侧签名事件（poll / ack）──
    // 这一段的存在理由只有一条：**事件不是消息**。poll 与 ack 复用同一套签字节、时间容差和
    // nonce 去重（不然就是给这两条路各开一个免检入口），但它们的 type 绝不能出现在
    // capabilities.messageTypes 里 —— 一台设备若能拿一次 poll 的签名冒充一条已授权的通知，
    // 前面整条验签链就白做了。下面每条判据都对应一种"看起来只是配置"的破坏方式。
    // 事件种类**遍历判定**，不写死 poll/ack：本仓刚加了第三种（register）。
    // 硬编码版本的后果不是报错，而是"新增的事件种类悄悄逃过全部三条判据"——正是这套判据要防的那类失效。
    final eventKinds = <String, Map<String, Object?>>{
      for (final entry
          in (map(const ['clientEvents']) ?? const <String, Object?>{}).entries)
        if (!entry.key.startsWith('_') && entry.value is Map)
          entry.key: Map<String, Object?>.from(entry.value as Map),
    };
    final vocabulary = messageTypeLevels.keys.toSet();
    // 「能作用于谁」的三条规则名也来自契约：判据里再硬写一遍名单，就是第二份真值。
    final selfOnlyRules = strings(const ['clientEvents', 'selfOnlyRules']);
    final declaredTypes = <String>[];
    for (final entry in eventKinds.entries) {
      final kind = entry.key;
      final type = '${entry.value['messageType'] ?? ''}';
      need(
        type.isNotEmpty,
        'clientEvents.$kind 缺 messageType：「这一步是哪种事件」必须由契约说，不能由实现猜',
      );
      need(
        !declaredTypes.contains(type),
        'clientEvents.$kind.messageType 与已声明的事件种类重复（$type）：'
        '两种事件共用一个 type，一次签名就能在两个接口之间互相冒用',
      );
      declaredTypes.add(type);
      need(
        !vocabulary.contains(type),
        'clientEvents.$kind 的 messageType「$type」出现在 capabilities.messageTypes 词表里'
        '（出现就等于一次设备事件的签名可以当一条用户消息用）：$vocabulary',
      );
      final verifyAgainst = '${entry.value['verifyAgainst'] ?? ''}';
      need(
        verifyAgainst == 'presented-public-key' ||
            verifyAgainst == 'device-table-public-key',
        'clientEvents.$kind.verifyAgainst 只能是 presented-public-key 或 '
        'device-table-public-key，实为「$verifyAgainst」：'
        '「为了统一代码偶尔信一下请求里的公钥」正是身份模型的塌方点',
      );
      // 「用请求自带的公钥验」与「这一步自带公钥」互为充要（契约 _carriesOwnPublicKeyWhy）。
      // 单向检查是不够的：只查「presented ⇒ 带钥匙」，那么带钥匙却声明查表验的那一种，
      // 那把随请求来的公钥就成了没人读的摆设 —— 而它的下一次使用多半是「顺手拿它验一下」。
      need(
        (verifyAgainst == 'presented-public-key') ==
            (entry.value['carriesOwnPublicKey'] == true),
        'clientEvents.$kind 的钥匙来源与公钥字段自相矛盾：'
        'verifyAgainst=$verifyAgainst，carriesOwnPublicKey=${entry.value['carriesOwnPublicKey']}：'
        '两者必须同真同假',
      );
      // 「地址码由客户端带来」⟹「只能按请求自带的公钥验」：带码来的这一步，表里还没有他这一行，
      // 拿设备表去验一个还不存在的身份，只能验出"不认识"。这条写成蕴含式而不是点名 register，
      // 因为点名那条在本片泛化后会退化 —— 按旗标判，下一片再来一种自带地址码的事件时它照样管得住。
      need(
        '${entry.value['addressCodeSource'] ?? ''}' != 'client-generated' ||
            verifyAgainst == 'presented-public-key',
        'clientEvents.$kind 的地址码来自客户端（addressCodeSource=client-generated），'
        'verifyAgainst 却写的是 $verifyAgainst：表里还没有他这一行，无从查起',
      );
      // 「这一步能作用于谁」：三条里**恰好一条**为真。零条 = 可以作用于别人的消息；
      // 两条 = 实现按 OR 判时比一条更宽（既能关于自己又能关于别人），不是更严。
      final declaredSelfOnly = selfOnlyRules
          .where((rule) => entry.value[rule] == true)
          .toList();
      need(
        declaredSelfOnly.length == 1,
        'clientEvents.$kind 必须声明 selfOnlyRules 里恰好一条为 true（可取：'
        '${selfOnlyRules.join(' / ')}，实为 $declaredSelfOnly）：'
        '不声明，任何已配对设备都能拿它作用于别人的消息（标题与正文里常有验证码）；'
        '声明两条，OR 判断下等于放宽而不是收紧',
      );
      // ⚠ 下面这条只在"恰好一条"成立时才读那条规则名：直接 `.single` 的话，
      // 0 条或 2 条会让 validate() **抛**而不是报 —— 契约不自洽应当是一条能读出来的问题，
      // 不是一次把加载方打挂的异常（这条在本片自己的 mutate 反证里冒出来的）。
      final rule = declaredSelfOnly.length == 1 ? declaredSelfOnly.first : null;
      if (rule == 'mustContainCounterpartAddress') {
        need(
          canonicalOrder.contains('target'),
          'clientEvents.$kind 靠 mustContainCounterpartAddress 划定作用范围，'
          '但 signature.canonicalOrder 里没有 target 这个被签字段：'
          '「对方地址码」不在已签字节里，就等于谁都能在转发时换一个收件人',
        );
      }
      // 档位与它的上限必须同进同出：载荷里有 level 却没有 levelCeilingFrom，
      // 那道上限就没人读（表现为"配对能直接要 L3"）；反之声明了上限而不带 level，那是空转的闸。
      final hasLevelField =
          (entry.value['fields'] as List<Object?>? ?? const [])
              .map((e) => '$e')
              .contains('level');
      final hasCeiling = '${entry.value['levelCeilingFrom'] ?? ''}'.isNotEmpty;
      need(
        hasLevelField == hasCeiling,
        'clientEvents.$kind 的档位与它的上限必须同进同出：fields 里有 level=$hasLevelField，'
        'levelCeilingFrom=$hasCeiling —— 只有一半时那道闸要么没人读，要么在读一个不存在的值',
      );
      if (hasCeiling) {
        final ceilingValue = at(
          '${entry.value['levelCeilingFrom'] ?? ''}'.split('.'),
        );
        need(
          capabilityLevels.contains('$ceilingValue'),
          'clientEvents.$kind.levelCeilingFrom=${entry.value['levelCeilingFrom']} '
          '取到的值「$ceilingValue」不是 capabilities.levels 里的一档：那道上限必须是一档真实存在的级别',
        );
      }
      // 「处理一张表里的记录」这类事件（pairConfirm）：它决定的那张表必须存在，
      // 状态名必须取自那张表的终态，两条红线（只能处理关于自己的、只能处理一次）都要在契约上 ——
      // 少任一条，第二次同名确认或别人手里的 requestId 都能改授权。
      final decided = '${entry.value['decides'] ?? ''}';
      if (decided.isNotEmpty) {
        need(
          map([decided]) != null,
          'clientEvents.$kind.decides = $decided，但契约顶层没有 $decided 这一段：'
          '它在处理一张没定义过的表',
        );
        // 路径从契约根算起：事件种类在 clientEvents 底下，不能直接拼 kind。
        final decisions = strings(['clientEvents', kind, 'decisions']);
        need(
          decisions.isNotEmpty && decisions.toSet().length == decisions.length,
          'clientEvents.$kind.decisions 必须非空且无重复，实为 $decisions',
        );
        final terminal = strings([decided, 'terminalStatuses']);
        need(
          terminal.toSet().containsAll(decisions),
          'clientEvents.$kind.decisions 里有不属于 $decided.terminalStatuses 的状态：'
          '$decisions vs $terminal（把一个非终态写回去，那条请求就永远处理不完）',
        );
        need(
          (entry.value['fields'] as List<Object?>? ?? const [])
              .map((e) => '$e')
              .contains('decision'),
          'clientEvents.$kind 声明了 decisions 却不在 fields 里带 decision：那这张表没人能推进',
        );
        need(
          decisions.contains(str(['clientEvents', kind, 'approveDecision'])),
          'clientEvents.$kind.approveDecision 必须是 decisions 里那一个「同意」的词，'
          '实为「${str(['clientEvents', kind, 'approveDecision'])}」：'
          '让实现自己认哪个词算同意，状态一改名字服务端就会把「同意」当「拒绝」执行，而不报错',
        );
        need(
          entry.value['requestMustBelongToTarget'] == true &&
              entry.value['consumesRequest'] == true,
          'clientEvents.$kind 必须同时声明 requestMustBelongToTarget 与 consumesRequest 为 true：'
          '前者丢了 = 谁能拿到 requestId 就能替别人答应配对；后者丢了 = 一次点头变成可反复使用的凭证',
        );
      }
      // 逐条勾选（items）这一段是 T134 片1 的接缝。清单今天还没有写入者，所以先把
      // 「谁说了算」钉死在契约上：取值域必须是**既有那两张表的路径**、拒绝时必须为空、
      // 词表外必须有一个来自 statusCodes 的状态码。四种漂移各自的表现都不是报错：
      // 没取值域 ⇒ 服务端只能"先收下"；可缺席的键不在 fields 里 ⇒ 谁能少带一个键都行；
      // 引用一张不存在的表 ⇒ 勾选表退化成自由文本；实现里写 400 ⇒ 状态码有两个来源。
      final fieldsOfKind = (entry.value['fields'] as List<Object?>? ?? const [])
          .map((e) => '$e')
          .toList();
      final optionalOfKind =
          (map(['clientEvents', kind, 'optionalFields']) ?? const {}).keys
              .map((e) => '$e')
              .toList();
      need(
        optionalOfKind.every((k) => fieldsOfKind.contains(k)),
        'clientEvents.$kind.optionalFields 里的键必须先出现在 fields 里：'
        '$optionalOfKind vs $fieldsOfKind —— 否则那是一份没人声明就能缺席的载荷',
      );
      final vocabPaths = strings(['clientEvents', kind, 'itemsVocabularyFrom']);
      if (fieldsOfKind.contains('items')) {
        need(
          vocabPaths.isNotEmpty,
          'clientEvents.$kind 的 fields 里有 items 却没有 itemsVocabularyFrom：'
          '勾选表没有取值域，服务端就只能在"收下并忽略"与"自己发明一份词表"之间挑一个',
        );
        need(
          entry.value['itemsMustBeEmptyOnDeny'] == true,
          'clientEvents.$kind 带 items 就必须声明 itemsMustBeEmptyOnDeny: true：'
          '拒绝时带清单 = 一边说不、一边把授权递过去',
        );
        for (final path in vocabPaths) {
          final table = at(path.split('.'));
          // 两张既有名单的**形状本来就不同**：L2 那张是值列表，L3 那张按设置项键控。
          // 取值域按各自的形状取（List 取值、Map 取键），但都必须非空 ——
          // 引用一张不存在或空着的表不会崩，只会让每一项勾选都判不过（或全判得过）。
          final entries = table is List
              ? table
              : table is Map
              ? table.keys.toList()
              : null;
          need(
            entries != null && entries.isNotEmpty,
            'itemsVocabularyFrom 指向的 $path 既不是非空名单也不是非空键控表（实为 $table）：'
            '勾上去的项从此没有一处能判对',
          );
        }
        final statusKey = '${entry.value['unknownItemStatus'] ?? ''}';
        final statusKeys = (map(['statusCodes']) ?? const {}).keys.toSet();
        need(
          statusKey.isNotEmpty && statusKeys.contains(statusKey),
          'clientEvents.$kind.unknownItemStatus 必须是 statusCodes 里一个真实存在的键名'
          '（实为「$statusKey」，那边有 $statusKeys）',
        );
      } else {
        need(
          vocabPaths.isEmpty,
          'clientEvents.$kind 的 fields 里没有 items，却声明了 itemsVocabularyFrom：'
          '那是一段没人读的取值域 —— 留着它，下一个人会以为这一发真的收清单',
        );
      }
    }
    // 规则名单本身也是判据的一部分：空的或带重复的名单会让上面那条「恰好一条」恒真。
    need(
      selfOnlyRules.isNotEmpty &&
          selfOnlyRules.toSet().length == selfOnlyRules.length,
      'clientEvents.selfOnlyRules 必须是非空且无重复的名单，实为 $selfOnlyRules：'
      '名单空 ⇒ 每种事件都判不出 self-only；有重复 ⇒ 「恰好一条」在两条同名规则上恒真',
    );
    need(eventKinds.isNotEmpty, 'clientEvents 至少要声明一种设备签名事件（路由侧要靠它分流）');
    need(
      boolOf(const ['clientEvents', 'notInCapabilitiesVocabulary']) == true,
      'clientEvents.notInCapabilitiesVocabulary 必须为 true（上面那条判据的声明处）',
    );
    // ── 规则名单与事件之间、事件与事件之间的对应关系（2B）──
    // 2A 故意欠着"每条规则都有人用"这一条：那时 counterpart 还没有使用者，判了就是自我矛盾。
    // 现在 pair 用它了，这条可以补上：名单里挂一条没人声明的规则，早晚被当成注释，
    // 而它下一次被真的用起来时，多半是"实现里没有那个分支"的那一种。
    final usedSelfOnlyRules = <String>{};
    for (final entry in eventKinds.entries) {
      final hit = selfOnlyRules.where((r) => entry.value[r] == true).toList();
      if (hit.length == 1) usedSelfOnlyRules.add(hit.single);
    }
    for (final rule in selfOnlyRules) {
      need(
        usedSelfOnlyRules.contains(rule),
        'clientEvents.selfOnlyRules 里的「$rule」没有任何事件声明它：'
        '名单上每条规则都得有对应的事件、实现分支与用例',
      );
    }
    // 挂口令的那一步与消耗口令的那一步必须共用同一个字段名，且必须是两个不同的事件种类：
    // 字段名各写一份的表现是"A 挂了口令、B 永远配不上"，而两边用例各自都还是绿的；
    // 同一个事件自挂自消，则是把配对做成了一步、里面没有对方。
    final armers = <String, String>{};
    final consumers = <String, String>{};
    for (final entry in eventKinds.entries) {
      final kind = entry.key;
      final fields = (entry.value['fields'] as List<Object?>? ?? const [])
          .map((e) => '$e')
          .toList();
      for (final pair in [('arms', armers), ('consumes', consumers)]) {
        final name = '${entry.value[pair.$1] ?? ''}';
        if (name.isEmpty) continue;
        need(
          fields.contains(name),
          'clientEvents.$kind.${pair.$1} = $name 不在它自己的 fields 清单里：'
          '那个值没进被签的载荷，等于挂出去/消耗掉的不是同一样东西',
        );
        pair.$2[name] = kind;
      }
    }
    need(
      armers.keys.toSet().containsAll(consumers.keys) &&
          consumers.keys.toSet().containsAll(armers.keys),
      '挂上来的东西与消耗掉的东西必须一一对应：实为 arms=${armers.keys.toList()} / '
      'consumes=${consumers.keys.toList()}（只有 arms 没人消耗 = 口令永远不过期地挂着；'
      '只有 consumes 没人挂 = 服务端手上根本没有可对照的摘要）',
    );
    for (final name in consumers.keys) {
      need(
        armers.containsKey(name) && armers[name] != consumers[name],
        'clientEvents.${consumers[name]} 自己挂自己消耗（$name）：配对必须有两个参与者，'
        '一步之内自挂自消就没有"对方确认"这一环了',
      );
    }
    // 事件"创建"的那段必须在契约顶层有定义，且那条记录自己得守规矩。
    for (final entry in eventKinds.entries) {
      final created = '${entry.value['creates'] ?? ''}';
      if (created.isEmpty) continue;
      final kind = entry.key;
      final section = map([created]);
      need(
        section != null,
        'clientEvents.$kind.creates = $created，但契约顶层没有 $created 这一段：'
        '创建了东西却没定义它长什么样，实现就只能自己发明一份',
      );
      final stored = strings([created, 'storedFields']);
      final never = strings([created, 'neverStored']);
      final statuses = strings([created, 'statuses']);
      final terminal = strings([created, 'terminalStatuses']);
      need(
        stored.isNotEmpty && stored.toSet().length == stored.length,
        '$created.storedFields 必须非空且无重复（实为 $stored）：'
        '空清单等于"什么都能存"，重复项会让下面那条交集判据看不出真正被存的那一份',
      );
      need(
        stored.toSet().intersection(never.toSet()).isEmpty,
        '$created 的字段表自相矛盾：${stored.toSet().intersection(never.toSet())} '
        '既"存"又"禁存"',
      );
      need(
        stored.contains('target') && stored.contains('requester'),
        '$created.storedFields 必须同时有 target（等谁确认）与 requester（谁发起）：'
        '少一个，这条请求就不知道是谁的、也不知道该显示给谁',
      );
      // 促成这条记录的那个秘密，不许以明文进这条记录（走的是摘要，见 neverStoredWhy）。
      for (final name
          in consumers.entries
              .where((e) => e.value == kind)
              .map((e) => e.key)) {
        need(
          never.contains(name),
          '$created.neverStored 必须含 $name（它由 ${armers[name] ?? '?'} 挂上、被 $kind 消耗）：'
          '那是用户抄过、印在二维码里、可能被拍过照的秘密，而这张表会跟着备份走',
        );
      }
      need(
        statuses.isNotEmpty &&
            terminal.toSet().difference(statuses.toSet()).isEmpty,
        '$created 的状态表不闭合：statuses=$statuses 而 terminalStatuses=$terminal',
      );
      final initial = str([created, 'initialStatus']) ?? '';
      need(
        statuses.contains(initial) && !terminal.contains(initial),
        '$created.initialStatus 必须是 statuses 里那个**非终态**的初始态，实为「$initial」：'
        '路由建新记录时照它写，没有它就只能自己猜一个',
      );
      final ttlPath = str([created, 'ttlSecondsFrom']) ?? '';
      need(
        ttlPath.isNotEmpty && intOf(ttlPath.split('.')) != null,
        '$created.ttlSecondsFrom 必须指向契约里一个真实存在的秒数，实为「$ttlPath」：'
        '另设一个 TTL 就会出现「口令还活着而请求已消失」，那的表现是重扫一次码被拒',
      );
      final perDevice = intOf([created, 'perDeviceLimit']);
      final globalLimit = intOf([created, 'globalLimit']);
      need(
        perDevice != null &&
            perDevice > 0 &&
            globalLimit != null &&
            globalLimit > 0 &&
            perDevice <= globalLimit,
        '$created 的两条上限不成样子：perDeviceLimit=$perDevice / globalLimit=$globalLimit'
        '（都要是正数，且每台不得超过全局）',
      );
      final pollKey = str([created, 'pollKey']) ?? '';
      if (str([created, 'visibleVia']) == 'poll') {
        need(
          pollKey.isNotEmpty &&
              strings(const [
                'clientEvents',
                'poll',
                'returns',
              ]).contains(pollKey),
          'poll 取走什么必须写在 clientEvents.poll.returns 里：$created.pollKey=「$pollKey」'
          '不在那份清单上（创建了东西却没人取得它，A 屏幕上就永远显示"等待配对"）',
        );
      }
      // T110 第二面：**发起方**那条读口。判据与上面那条同形 —— 缺了它，「契约声明了一条读口
      // 而路由没挂」与「路由挂了而设备读错键」在屏幕上都是同一句话：列表空着。
      // 外加**不许与第一面同名**：同名 ⇒ 一次响应里两面互相盖掉（盖掉顺序是 JS 的插入顺序，
      // 谁都不知道屏幕上那条是谁的），而 B 那边被盖出来的那一句是「谁在请求配对你」——
      // 发起请求的正是他自己，那一句还会诱导他去点同意。
      final sentKey = str([created, 'sentPollKey']) ?? '';
      need(
        sentKey.isNotEmpty &&
            strings(const [
              'clientEvents',
              'poll',
              'returns',
            ]).contains(sentKey) &&
            sentKey != pollKey,
        '$created.sentPollKey=「$sentKey」必须是一个写在 clientEvents.poll.returns 里、'
        '且与 $created.pollKey=「$pollKey」不同的响应键名：发出方这一面没有读口时，'
        '界面上只能显示"我提交了"那一瞬间，之后走到哪儿全是猜；与第一面同名时两面互相盖掉',
      );
      // 投影名单：空 = 实现只能自己拼一份（那正是第二份真值），少一列 = 界面答不了
      // 「现在算什么状态、多久之前」，多一列到口令类字段 = 违反"列表里只放地址码与状态"。
      final sentFields = strings([created, 'sentFields']);
      final neverStoredSent = strings([created, 'neverStored']);
      need(
        sentFields.isNotEmpty,
        '$created.sentFields 不能为空：面向发出方的投影照它挑字段，没有名单就是实现自己拼一份',
      );
      need(
        sentFields.toSet().length == sentFields.length,
        '$created.sentFields 有重名项（$sentFields）：投影里同一列被写两次，后写的盖掉先写的',
      );
      for (final must in const ['status', 'createdAt', 'at']) {
        need(
          sentFields.contains(must),
          '$created.sentFields 少了「$must」：这一面答的就是"现在算什么状态、什么时候立的、'
          '状态什么时候变的"，少一列界面就答不了其中一句（$sentFields）',
        );
      }
      for (final secret in neverStoredSent) {
        need(
          !sentFields.contains(secret),
          '$created.sentFields 含 neverStored 的那一项「$secret」：'
          '面向发出方的投影把口令类字段带出门了（T110 ③：列表里只放地址码与状态，不落任何口令副本）',
        );
      }
      // ⚠ 摘要单独挡，而不是靠上面那条：`codeDigest` 是**故意存**的（接收方那面要用它确认
      // 「这就是我刚挂出去的那枚」），所以它不在 neverStored 里。发起方这一面拿它换不到任何
      // 信息（那枚口令就是他自己的），而"能拿去比对的东西"多出一个出口就是离线猜口令的入口。
      need(
        !sentFields.contains('codeDigest'),
        '$created.sentFields 里有 codeDigest：这一面不回摘要 —— 发起方本来就知道自己用过的那枚口令，'
        '而一份能比对的摘要多一处出口就多一处能漏的地方（同 endpointList._neverReturnsSecretWhy）',
      );
      final ceiling = '${entry.value['levelCeilingFrom'] ?? ''}';
      if (ceiling.isNotEmpty) {
        // 这条的判据本体已经上移到事件主循环里（那里对**所有**声明了上限的事件生效：
        // pairConfirm 有上限但没有 creates，写在下面这一段里它就永远跑不到）。
        need(
          at(ceiling.split('.')) != null,
          'clientEvents.$kind.levelCeilingFrom=$ceiling 在契约里取不到值',
        );
      }
    }
    need(
      (intOf(const ['limits', 'devicesMax']) ?? 0) > 0,
      'limits.devicesMax 必须是正整数：POST /register 是唯一一类"提交者还没有身份"的写入面，'
      '设备表没有上限就等于给未认证流量送一台无限增长的存储',
    );
    // #130-A1：那两个数字光有大小没有"量谁" —— 那副形状的下场是实现绕开它自己定一个数
    // （本仓的 JS 侧正是这么长的），两端各一份真值。更要紧的是这两把尺子对**轮询**根本不成立：
    // presence 说常态 20 秒一次、提频 5 秒一次，而日额度 500 比正常一天的轮询量小一个数量级
    // ⇒ 照字面实现的结果是"上线即把每台设备卡死"。定名也跟着改：endpointPerMinute →
    // unauthenticatedPerMinute，因为"所有端点共用一把尺"这个读法本身就是错的。
    final perEndpoint = strings(const ['limits', 'perEndpoint']);
    final cadenceGoverned = strings(const ['limits', 'cadenceGoverned']);
    final perSenderOnly = strings(const ['limits', 'perSenderOnly']);
    need(
      perEndpoint.isNotEmpty,
      'limits.perEndpoint 不能为空：那两个数字总得有一组端点归它们管，'
      '只写数字不写适用面的限流，等于让每个实现自己猜该拿它量谁',
    );
    for (final entry in {
      'limits.perEndpoint': perEndpoint,
      'limits.cadenceGoverned': cadenceGoverned,
    }.entries) {
      for (final kind in entry.value) {
        need(
          eventKinds.containsKey(kind),
          '${entry.key} 里的 "$kind" 不是 clientEvents 里的事件种类：限流按 URL 段映射到事件种类，'
          '映射到一个不存在的东西上就是静默不限流',
        );
      }
    }
    need(
      perEndpoint.toSet().intersection(cadenceGoverned.toSet()).isEmpty &&
          perEndpoint.toSet().intersection(perSenderOnly.toSet()).isEmpty &&
          cadenceGoverned.toSet().intersection(perSenderOnly.toSet()).isEmpty,
      'limits 的三份端点名单不许重叠：同一个端点两把尺子时，谁先响取决于实现顺序 —— '
      '那是"看起来更严其实更宽"的形状',
    );
    for (final kind in const ['poll', 'ack']) {
      need(
        cadenceGoverned.contains(kind),
        'limits.cadenceGoverned 必须含 $kind：轮询与回执的量由 presence 的节奏参数决定，'
        '把它们塞进控制类额度（实测 4320 次/天 vs 500 次/天）等于上线即把所有设备卡死',
      );
    }
    // 名单不能是随手写的名字列表 —— 那从下一次改动起就会漂。钉住它的是一条 **principal 事实**：
    // 只有"签名还证明不了他是谁"的请求才该按 IP 计额度；已经能证明是谁的操作按 IP 计，
    // 等于让 NAT 后面几台设备共用一份配对额度（本仓 7 条配对路由用例第一次跑就是这么红的）。
    for (final kind in perEndpoint) {
      final event = eventKinds[kind];
      need(
        event != null && event['verifyAgainst'] == 'presented-public-key',
        'limits.perEndpoint 里的 "$kind" 不能按 IP 计：它的签名已经能证明是谁'
        '（verifyAgainst=${event?['verifyAgainst']}）⇒ 该进 perSenderOnly，'
        '按发送方设备地址计额度',
      );
    }
    for (final kind in perSenderOnly) {
      final event = eventKinds[kind];
      if (event == null) continue; // /message 这类不是 clientEvents 事件的投递面，允许列在这里
      need(
        event['verifyAgainst'] == 'device-table-public-key',
        'limits.perSenderOnly 里的 "$kind" 是按"请求自带公钥"验的：那它还没有身份可计，'
        '只能按 IP 计 ⇒ 该进 perEndpoint',
      );
      need(
        (event['mayNotCarry'] as List<Object?>?) != null,
        'limits.perSenderOnly 里的 "$kind" 没有 mayNotCarry：纯游标类请求属轮询，'
        '该由 cadenceGoverned 按推导额度管',
      );
    }
    for (final kind in cadenceGoverned) {
      final event = eventKinds[kind];
      need(
        event != null && event['mayNotCarry'] == null,
        'limits.cadenceGoverned 里的 "$kind" 带 mayNotCarry：它已经不是纯轮询类请求，'
        '按上面的分界它该受按 IP 或按发送方的额度管',
      );
    }
    final burstInterval = intOf(const [
      'presence',
      'burstWhenPending',
      'intervalSeconds',
    ]);
    final burstDuration = intOf(const [
      'presence',
      'burstWhenPending',
      'durationSeconds',
    ]);
    need(
      (burstInterval ?? 0) > 0 && (burstDuration ?? 0) > 0,
      'presence.burstWhenPending 的 intervalSeconds / durationSeconds 必须是正整数：'
      '轮询侧的分钟额度是**从它推导**的，这里缺一个数推导就只能猜',
    );
    final steadyInterval = intOf(const [
      'presence',
      'pollIntervalSeconds',
      'min',
    ]);
    need(
      // 等号放行同上（T88）：常态下界 5s 与提频档 5s 同值是定稿的结果，不是写错。
      (steadyInterval ?? 0) > 0 &&
          (burstInterval ?? 0) <= (steadyInterval ?? 0),
      'burstWhenPending.intervalSeconds 必须不大于 pollIntervalSeconds.min：'
      '提频比常态还慢，那这档参数本身就是矛盾的，推导出来的额度也没有意义',
    );
    final slack = intOf(const ['limits', 'pollBurstSlack']) ?? -1;
    need(
      slack >= 1,
      'limits.pollBurstSlack 必须 ≥ 1：设备在提频与常态之间切换的那一分钟里两种节奏会重叠计数，'
      '零余量会把"用户刚点了一条通知"判成攻击',
    );
    final burstPerMinute = burstInterval == null || burstInterval <= 0
        ? null
        : (60 / burstInterval).ceil();
    final controlPerMinute = intOf(const [
      'limits',
      'unauthenticatedPerMinute',
    ]);
    need(
      burstPerMinute == null ||
          controlPerMinute == null ||
          controlPerMinute >= burstPerMinute + slack,
      'limits.unauthenticatedPerMinute 不许严于轮询侧的推导额度（burstPerMinute + pollBurstSlack）：'
      '按 IP 计的端点额度只能当洪水闸，卡紧它误伤的是"家里一次装四台设备"的诚实用户'
      '（本仓 7 条配对路由用例就是这么红的），而攻击者换一个 IP 的成本是零 —— '
      '未认证写入真正的兜底是 limits.devicesMax 与整个面的总量闸门',
    );
    // #130-A2：按发送方计的那一档。主键是**已证明身份的设备地址**，不是 IP。
    final senderMinute = intOf(const ['limits', 'perSenderPerMinute']);
    final senderDay = intOf(const ['limits', 'perSenderPerDay']);
    need(
      senderMinute != null && senderDay != null && senderDay > senderMinute,
      'limits.perSenderPerDay 必须大于 perSenderPerMinute：白天额度不该比分钟额度还小',
    );
    need(
      senderMinute == null ||
          controlPerMinute == null ||
          senderMinute >= controlPerMinute,
      'limits.perSenderPerMinute 不许比按 IP 的 unauthenticatedPerMinute 还紧：'
      '这一档的意义是"跑飞保护"而不是反垃圾 —— 比匿名档还紧，先被卡住的只会是已经证明过身份的自己人',
    );
    // 这一片真正的不变量：**凡是签名已经能证明身份的端点，都必须有一份按设备地址计的额度**。
    // 漏一个的表现不是报错，而是那条端点静默地只剩"按 IP 的总量闸门"管 —— 反代之后
    // 就是一个出口后面的所有设备共享一辈子额度（A1 收成 6/分那次 7 条用例红的形状）。
    for (final entry in eventKinds.entries) {
      final event = entry.value;
      if (event['verifyAgainst'] != 'device-table-public-key') continue;
      final kind = entry.key;
      need(
        perSenderOnly.contains(kind) || cadenceGoverned.contains(kind),
        'clientEvents.$kind 的签名已经能证明身份（verifyAgainst=device-table-public-key），'
        '却不在 limits.perSenderOnly / cadenceGoverned 任何一份名单里 ⇒ 它只能被按 IP 计额度，'
        '等于让同一出口后面的几台设备共用一份配额',
      );
    }
    need(
      (intOf(const ['limits', 'requestBodyMaxBytes']) ?? 0) >= 4096,
      'limits.requestBodyMaxBytes 必须是一个说得出口的字节数（≥ 4096）：它是公网面上唯一'
      '在验签之前就要付成本的维度 —— 没有它，一发大请求花的只是攻击者的带宽，'
      '花的却是服务端的内存与 CPU；而小于一页正文的闸，症状会是「合法长通知永远 413」',
    );
    // #130-A4 突增告警。这一段最容易写歪的不是数字，而是「它管谁」—— 下面与 limits 三档
    // principal 的交叉判据就是为这个写的（A1 那次"两个数只写了大小、没写量谁"的同一个错）。
    need(
      map(const ['alerts']) != null,
      'alerts 段缺失：告警的四个数没有第二个来源。缺它时实现只有两种走法 —— 在自己代码里写一份'
      '缺省（第二份真值），或者静默不告警（更糟：一台什么都不报告的防护层）',
    );
    final nearRatio = at(const ['alerts', 'nearQuotaRatio']);
    need(
      nearRatio is num && nearRatio > 0 && nearRatio < 1,
      'alerts.nearQuotaRatio 必须在 (0,1) 开区间（实际 $nearRatio）：等于 1 时 near 只是 denied 的'
      '另一种写法，而 near 存在的全部意义是「还没拒就已经不对劲」；太小则把每台正常设备都报成告警，'
      '而第一次误报的代价不是多一行日志，是之后没人再看这个列表',
    );
    final alertCooldown = intOf(const ['alerts', 'cooldownSeconds']);
    need(
      (alertCooldown ?? 0) >= 60,
      'alerts.cooldownSeconds 必须 ≥ 60（实际 $alertCooldown）：没有冷却（或比一分钟还短）时告警的输出'
      '速率与请求速率成正比 ⇒ 它自己成为第二种洪水，还会挤满那个有界内存环、把真正的异常从最旧端'
      '淘汰掉 —— 等于洪水替攻击者清场',
    );
    final maxActiveAlerts = intOf(const ['alerts', 'maxActiveAlerts']);
    need(
      (maxActiveAlerts ?? 0) > 0,
      'alerts.maxActiveAlerts 必须是正整数（实际 $maxActiveAlerts）：告警主体来自外部输入'
      '（设备地址码、对端 IP），没有上限等于把一段无界内存挂在公网上，而那正是这批限流要防的东西',
    );
    need(
      boolOf(const ['alerts', 'persistToDisk']) == false,
      'alerts.persistToDisk 必须是 false：公网未认证面上每一次写盘都是「一个请求换一次磁盘写」的'
      '放大器（本仓 T29-B 的拒收计数同此取舍）。要改成 true，就得同时把写盘限频与上限写进本段、'
      '并让实现跟着读那两个数 —— 否则改的是文档，不是行为',
    );
    final alertKinds = strings(const ['alerts', 'subjectKinds']);
    need(
      alertKinds.isNotEmpty && alertKinds.toSet().length == alertKinds.length,
      'alerts.subjectKinds 必须非空且不许重叠：${alertKinds.join(', ')}',
    );
    // 这两条是本段真正的不变量：**名单必须与 limits 的三档 principal 对齐**。
    // 少一类 = 那一类主体的超额在告警里永远不出现（"看着什么都管，其实不吭声"）；
    // 多一类 = 契约声明了一个实现不产出的种类，它会让人以为已经覆盖。两个方向都要钉，
    // 因为它们是同一类错误的两面。
    need(
      (perSenderOnly.isEmpty && cadenceGoverned.isEmpty) ||
          alertKinds.contains('device'),
      'limits.perSenderOnly / cadenceGoverned 非空时 alerts.subjectKinds 必须含 device：'
      '按设备地址计额的那两档恰恰最会把正常用户拦住（跑飞的设备、提频中的轮询），'
      '名单里没有 device 就等于这一整类告警被丢掉',
    );
    need(
      perEndpoint.isEmpty || alertKinds.contains('ip'),
      'limits.perEndpoint 非空时 alerts.subjectKinds 必须含 ip：那一档的身份还没证明、只能按 IP 计，'
      '少了 ip 就看不见「同一个出口后面有多少台在被打」—— 而 #140 已经实测到反代后那个出口是 CDN',
    );
    // 端点有配额（endpoint.ingress.quota）却没有 endpoint 主体 ⇒ 那一整类超额在告警里永不出现。
    // 反过来也成立：先列上 endpoint 而没有配额与流量，就是一份看着齐全其实不响的名单。
    need(
      intOf(const ['endpoint', 'ingress', 'quota', 'perMinute']) == null ||
          alertKinds.contains('endpoint'),
      'endpoint.ingress.quota 存在时 alerts.subjectKinds 必须含 endpoint：'
      '按端点计的那一档被拦住时，运维只能从告警里看见它 —— 少了这一类，端点洪水就是无声的',
    );
    const knownSubjectKinds = ['device', 'ip', 'endpoint'];
    for (final kind in alertKinds) {
      need(
        knownSubjectKinds.contains(kind),
        'alerts.subjectKinds 里的 $kind 不是服务端认识的种类（只允许 '
        '${knownSubjectKinds.join(' / ')}）：写一个实现不产出的名字，表现是名单看着齐全而告警永远少一类',
      );
    }
    // 自带公钥的那一种事件（目前只有 register）字段规则与其它种类相反：必须带公钥
    // （否则无从证明私钥持有）、必须带不上任何秘密。按 `carriesOwnPublicKey` 旗标挑出来判，
    // 不按名字 —— 判据里写死 'register'，下一片再来一种自带公钥的事件时它不报错，
    // 只会静默地不受这三条管，而"必带"与"禁带"撞车正是这类事件最容易写歪的地方。
    for (final entry in eventKinds.entries) {
      if (entry.value['carriesOwnPublicKey'] != true) continue;
      final kind = entry.key;
      final required =
          (entry.value['requiredTopLevelFields'] as List<Object?>? ?? const [])
              .map((e) => '$e')
              .toList();
      final mayNot = (entry.value['mayNotCarry'] as List<Object?>? ?? const [])
          .map((e) => '$e')
          .toList();
      need(
        required.contains('publicKey'),
        'clientEvents.$kind.requiredTopLevelFields 必须含 publicKey：'
        '声明了自带公钥，这一步却没有别的东西能证明私钥持有',
      );
      need(
        mayNot.contains('privateKey'),
        'clientEvents.$kind.mayNotCarry 必须含 privateKey（红线：私钥永不出设备）',
      );
      need(
        required.toSet().intersection(mayNot.toSet()).isEmpty,
        'clientEvents.$kind 的字段表自相矛盾：${required.toSet().intersection(mayNot.toSet())} '
        '既"必带"又"禁带" —— 这种键写进契约之后，实现选哪一边都不对',
      );
    }
    need(
      boolOf(const ['clientEvents', 'poll', 'targetMustEqualSender']) == true,
      'clientEvents.poll.targetMustEqualSender 必须为 true：'
      '否则一台已配对设备能读走别人队列里的标题与正文（验证码常常就在正文里）',
    );
    need(
      boolOf(const ['clientEvents', 'ack', 'onlyForOwnMessages']) == true,
      'clientEvents.ack.onlyForOwnMessages 必须为 true：'
      '否则可以把别人队列里的消息逐个 ack 成 delivered，而正文按契约在 delivered 时立即删除 —— '
      '那等于替别人把消息销毁',
    );
    need(
      boolOf(const ['clientEvents', 'ack', 'resultMustBeReceipt']) == true,
      'clientEvents.ack.resultMustBeReceipt 必须为 true：ack 的 result 必须是回执词表里的值',
    );
    // 设备报上来的 result 要翻成状态机事件才能推进 —— 这张表必须在契约上。
    // 写在路由里的那个 switch 就是第二份状态机，而它下一次改动多半只改一边：
    // 于是"设备说 failed_action"还在把消息往 delivered 推。
    final resultToEvent =
        map(const ['clientEvents', 'ack', 'resultToEvent']) ?? const {};
    need(
      resultToEvent.isNotEmpty,
      'clientEvents.ack.resultToEvent 不能为空：没有它，设备的 ack 无法推进状态机',
    );
    for (final entry in resultToEvent.entries) {
      need(
        receipts.contains('${entry.key}'),
        'clientEvents.ack.resultToEvent 的键 ${entry.key} 不在 receipts 词表里',
      );
      need(
        dEvents.contains('${entry.value}'),
        'clientEvents.ack.resultToEvent 的值 ${entry.value} 不是 delivery.events 里的事件',
      );
    }
    need(
      resultToEvent['displayed'] == 'ack_ok' &&
          resultToEvent['failed_action'] == 'ack_fail',
      'displayed 必须推进到 ack_ok、failed_action 必须推进到 ack_fail'
      '（这两条是"设备真看到了"与"设备做失败了"的唯一锚点）',
    );
    for (final serverOnly in const [
      'waiting_online',
      'expired',
      'dropped',
      'rejected_unsigned',
      'rejected_capability',
    ]) {
      need(
        !resultToEvent.containsKey(serverOnly),
        'resultToEvent 里有 $serverOnly：那是服务端自己的决定，设备证明不了它 —— '
        '允许设备这么报，等于让它替服务端下结论',
      );
    }
    need(
      strings(const ['clientEvents', 'ack', 'fields']).join('|') ==
          strings(const ['delivery', 'ackFields']).join('|'),
      'clientEvents.ack.fields 必须与 delivery.ackFields 逐字相同（两张表各写一份，'
      '早晚一张改了另一张没改，那时 ack 会静默地读不到 result）',
    );
    need(
      strings(const ['clientEvents', 'poll', 'returns']).contains('serverTime'),
      'clientEvents.poll.returns 必须含 serverTime：'
      '「ts 以服务端时间判定」要有承载处，设备自算偏移只能在拿到响应之后进行',
    );
    final maxBatch =
        intOf(const ['clientEvents', 'poll', 'maxBatchPerPoll']) ?? 0;
    need(
      maxBatch > 0 &&
          maxBatch <= (intOf(const ['retention', 'pendingPerDeviceMax']) ?? 0),
      'clientEvents.poll.maxBatchPerPoll 必须是正整数且不超过 pendingPerDeviceMax：$maxBatch',
    );
    // poll 每条消息回哪些字段：这份名单是「服务端投影」与「收件表列设计」的唯一共同出处。
    final messageFields = strings(const [
      'clientEvents',
      'poll',
      'messageFields',
    ]);
    need(
      messageFields.isNotEmpty &&
          messageFields.toSet().length == messageFields.length,
      'clientEvents.poll.messageFields 必须非空且无重复，实为 $messageFields：'
      '空名单 = poll 回一堆空对象，有重复 = 「投影出的键数」与名单长度不再相等',
    );
    need(
      messageFields.contains('messageId'),
      'clientEvents.poll.messageFields 少了 messageId：设备手上没有主键就 ack 不了那一条，'
      '收件表也失去去重水位线（message_id 就是它的主键）',
    );
    need(
      messageFields.contains('sentAt'),
      'clientEvents.poll.messageFields 少了 sentAt：收件详情那一列「发送时间」无处取值 —— '
      '它只可能来自服务端的受理时刻（设备本地时钟答不了「对方什么时候发的」），'
      '而投影面只有 POLL_PROJECTABLE 一处',
    );
    need(
      messageFields.contains('sender'),
      'clientEvents.poll.messageFields 少了 sender：收件表里那一行无处归属 —— '
      '「是谁发的」只有这一个数据源，这条缺口是 T47 设计表列时才现形的（当时 sender 列无值可灌）',
    );
    // 能投影出来的只有两处：消息表里的身份列，和解开密信封后的那两个键（封里就是 title/body，
    // 见 retention 那段「名单里没有 title」）。名单里多写一个别的名字不会让服务端报错，
    // 只会让它回一个空值 ⇒ 收件箱从此有一列永远为空，而没人会去查一个「看起来正常」的空字段。
    // `state`/`attempts`/`queuedAt` 这些存盘元数据同样一律不在名单里：delivery.ackIsOnlyProof
    // 说投递状态只由服务端推进，顺手回给设备就是让两端各算一份事实。
    final contentKeys =
        (map(const ['fieldTolerance']) ?? const <String, Object?>{}).entries
            .where((e) => e.value is List)
            .map((e) => e.key)
            .toSet();
    // T105 片②：`sentAt` 也在可投影面里 —— 它取自消息表的
    // `queuedAt`（服务端受理那一刻），而上面那句「存盘元数据一律不回」
    // 说的是 `state`/`attempts`/`queuedAt` 这三个**名字**（投递状态的账）。
    // 两边同步：服务端那份名单在 `routes.js` 的 POLL_PROJECTABLE。
    final projectable = {
      'messageId',
      'type',
      'item',
      'sender',
      'sentAt',
      ...contentKeys,
    };
    final undeliverable = messageFields
        .where((f) => !projectable.contains(f))
        .toList();
    need(
      undeliverable.isEmpty,
      'clientEvents.poll.messageFields 里有投影不出来的名字：$undeliverable；'
      '可投影面只有 $projectable（消息表的身份列 + 密信封里的 $contentKeys）',
    );
    need(
      boolOf(const ['clientEvents', 'nonceSpaceSharedWithMessages']) == true,
      'clientEvents.nonceSpaceSharedWithMessages 必须为 true：'
      '事件与消息共用同一个 nonce 空间，抓到一个已签的 poll 就不能换个接口再放一次',
    );

    // ── 存储侧的"必要字段"与正文静态加密（T34-B）──
    final storedFields = strings(const ['retention', 'storedFields']);
    need(
      storedFields.isNotEmpty &&
          storedFields.toSet().length == storedFields.length,
      'retention.storeOnlyNecessaryFields=true 就必须给出一份 storedFields 名单（非空不重复）：$storedFields',
    );
    for (final required in const ['messageId', 'state', 'queuedAt', 'body']) {
      need(
        storedFields.contains(required),
        'retention.storedFields 少了 $required —— 没有它就跑不了状态机或正文释放',
      );
    }
    // 投递要有目标，回执要有来源。这两个字段是 T35「把投递结果推回发送端」的前提：
    // 消息表里只记 device 的话，一条已终态的消息**无法回答"该把它的回执送给谁"**，
    // 而回执是发送端唯一能看见"消息没有送达"的通道（不送达就悄悄烂在库里，
    // 正是产品不变量「不许静默丢」的反面）。#126 第一片写 poll 时就是被这点卡住的。
    for (final side in const ['device', 'sender']) {
      need(
        storedFields.contains(side),
        'retention.storedFields 少了 $side：投递/回执少了归属，'
        '终态消息就没法回答"该通知谁"（回执通道从此没有收件人）',
      );
    }
    final atRest = map(const ['retention', 'bodyAtRest']) ?? const {};
    need(
      atRest['algorithm'] == 'aes-256-gcm',
      'retention.bodyAtRest.algorithm 必须是 aes-256-gcm（换算法=换协议）：${atRest['algorithm']}',
    );
    need(
      (atRest['ivBytes'] as num?)?.toInt() == 12,
      'retention.bodyAtRest.ivBytes 必须是 12（GCM 的标准 IV 长度）：${atRest['ivBytes']}',
    );
    need(
      atRest['refuseWithoutKey'] == true &&
          boolOf(const ['privacy', 'serverStoresBodyPlaintext']) == false,
      'retention.bodyAtRest.refuseWithoutKey 必须为 true：没有密钥时**拒绝入队**，'
      '不许像 TOTP 那样退回明文存储（那会当场违反 serverStoresBodyPlaintext=false）',
    );

    // ── 投递留痕（T45 第二片）──
    // 时间线必须**有界**：一条 waiting_online 的消息每次 poll 都会被推进一次，7 天保留期
    // ÷ 15 秒 ≈ 四万条，而无界的日志就是攻击者驱动的存储（端点调用日志那处算过同一笔账）。
    // 服务端读这一档时是**抛**而不是退回默认值，所以这里缺了必须报，不能让它在第一次推进时才炸。
    final auditTrail = map(const ['retention', 'auditTrail']) ?? const {};
    final trailMax = (auditTrail['maxPerMessage'] as num?)?.toInt();
    need(
      trailMax != null && trailMax > 0,
      'retention.auditTrail.maxPerMessage 必须是正整数（实为 ${auditTrail['maxPerMessage']}）：'
      '投递时间线要么有界，要么就别记',
    );
    final trailFields = strings(const ['retention', 'auditTrail', 'fields']);
    need(
      trailFields.isNotEmpty &&
          trailFields.toSet().length == trailFields.length,
      'retention.auditTrail.fields 必须非空且不重复（实为 $trailFields）：它是"一条留痕能有哪些键"'
      '的名单 —— 没有名单就等于允许往时间线里塞正文',
    );
    // 这条交叉检查才是这一片最容易写错的地方：留痕是新列，而那道"只保留必要字段"的白名单
    // 会把手写的与机器写的**一视同仁地丢掉**。少了它，症状是"时间线永远是空的"，
    // 而不是任何一处报错。
    for (final column in const ['trail', 'trailDropped']) {
      need(
        storedFields.contains(column),
        'retention.storedFields 少了 $column：有 auditTrail 却没有存放它的字段 ⇒ '
        '白名单会把它当场丢掉，时间线永远是空的',
      );
    }

    // ── 身份与凭证（红线）──
    need(
      intOf(const ['identity', 'addressCode', 'length']) == 18,
      '设备地址码位数固定为 18（改了就是换协议）',
    );
    need(
      intOf(const ['identity', 'pairingCode', 'length']) == 20,
      '配对口令位数固定为 20',
    );
    need(
      intOf(const ['identity', 'pairingCode', 'ttlSeconds']) == 300,
      '配对口令有效期 5 分钟（300 秒）',
    );
    need(
      boolOf(const ['identity', 'pairingCode', 'singleUse']) == true,
      '配对口令必须是一次性的（配对即消耗）',
    );
    // 端点长期口令（T27/T38）：形状与配对口令同族，但它是长期凭证，所以两条方向相反的规则
    // 必须同时钉住 —— 长期凭证反而比 5 分钟一次的东西短，是配反了方向。
    need(
      (intOf(const ['identity', 'endpointSecret', 'length']) ?? 0) >=
          (intOf(const ['identity', 'pairingCode', 'length']) ?? 99),
      'identity.endpointSecret.length 不得短于配对口令位数',
    );
    need(
      boolOf(const ['identity', 'endpointSecret', 'public']) == false,
      'identity.endpointSecret.public 必须是 false（它是秘密，不像地址码那样可分享）',
    );
    need(
      boolOf(const ['identity', 'endpointSecret', 'singleUse']) == false &&
          boolOf(const ['identity', 'endpointSecret', 'rotatable']) == true,
      '端点口令是"长期有效直到轮换"：singleUse 必须 false、rotatable 必须 true',
    );
    need(
      boolOf(const ['identity', 'pairingCode', 'derivedFromDeviceIdentity']) ==
          false,
      '凭证不得由设备信息推导（否则可反推）',
    );
    need(
      str(const ['identity', 'generator']) == 'csprng',
      'identity.generator 必须是 csprng',
    );
    need(
      boolOf(const ['identity', 'identityKey', 'privateKeyExportable']) ==
          false,
      '身份私钥不可导出',
    );
    need(
      str(const ['identity', 'identityKey', 'algorithm']) == 'Ed25519',
      '身份密钥算法固定 Ed25519',
    );
    // 平台门槛（T26 第三片）：AndroidKeyStore 的 Ed25519 自 API 30 起，而 minSdk 是 24。
    // 这两个键把"30 以下怎么办"写进协议，而不是留给某个 Kotlin 文件里的注释。
    need(
      intOf(const ['identity', 'identityKey', 'nativeMinSdkVersion']) == 33,
      'identityKey.nativeMinSdkVersion 必须是 33：KeyStore 30 起能【生成】Ed25519，'
      '但签名要的 EdECPoint / EdECPublicKey / NamedParameterSpec 自 Android 13 才有',
    );
    need(
      str(const ['identity', 'identityKey', 'belowNativeSdk']) ==
          'keystoreWrappedSoftwareKey',
      'identityKey.belowNativeSdk 必须是 keystoreWrappedSoftwareKey：'
      '写成 softwarePlaintext 就等于把"私钥不可导出"这条红线改成注释',
    );
    need(
      boolOf(const ['identity', 'identityKey', 'keystoreBackedCapability']) ==
          true,
      '必须上报 keystoreBacked 能力位：两条路径的强度不同，对端与用户都有权知道',
    );
    final neverIn = strings(const ['identity', 'identityKey', 'neverIn']);
    for (final place in const ['url', 'log']) {
      need(neverIn.contains(place), '私钥的 neverIn 必须包含 $place');
    }
    need(
      strings(const [
        'privacy',
        'credentialsNeverIn',
      ]).toSet().containsAll(const ['url', 'log']),
      'privacy.credentialsNeverIn 必须包含 url 与 log',
    );
    need(
      boolOf(const ['privacy', 'serverStoresBodyPlaintext']) == false,
      'privacy.serverStoresBodyPlaintext 必须为 false',
    );
    need(
      boolOf(const ['privacy', 'auditStoresMetadataOnly']) == true,
      'privacy.auditStoresMetadataOnly 必须为 true',
    );

    // ── 投递与补发 ──
    need(
      boolOf(const ['delivery', 'ackIsOnlyProof']) == true,
      'delivery.ackIsOnlyProof 必须为 true：设备 ack 是唯一送达依据',
    );
    need(
      boolOf(const ['delivery', 'senderPollsStatusEndpoint']) == false,
      'delivery.senderPollsStatusEndpoint 必须为 false：回执作为一条消息推回发送端',
    );
    need(
      boolOf(const ['waitingOnline', 'mutuallyExclusive']) == true,
      'waitingOnline.mutuallyExclusive 必须为 true：备用补推与排队补发不可并存',
    );
    need(
      str(const ['waitingOnline', 'withBackupChannel']) !=
          str(const ['waitingOnline', 'withoutBackupChannel']),
      'waitingOnline 的两个分支必须是两条不同路径',
    );
    need(
      boolOf(const ['waitingOnline', 'notifySenderProactively']) == false,
      '进入 waiting_online 不主动通知发送端（已定）',
    );
    // 补推那三样（幂等键 / 上限 / 标签）是 T46 那条内核唯一的读数来源。缺任意一样时它的表现
    // 都**不报错**：幂等键缺 ⇒ 拿空串去重（等于没去重），上限缺 ⇒ 退回 0（这条路径直接消失），
    // 标签缺 ⇒ 记录上那一格空着。三个都判在契约这一层，是因为"实现里退回默认值"这一族错误
    // 从来不会自己暴露，只会在某条消息被补推两次的那天被人当成玄学。
    final replayMax = intOf(const ['limits', 'backupReplayMax']);
    need(
      replayMax != null && replayMax > 0 && replayMax < 10,
      'limits.backupReplayMax 必须是 1..9 的整数（备用补推最多再走几条路，'
      '0 = 这条路径被静默关掉）：$replayMax',
    );
    final replayKey = str(const [
      'waitingOnline',
      'backupReplayIdempotencyKey',
    ]);
    need(
      replayKey != null && replayKey.isNotEmpty,
      'waitingOnline.backupReplayIdempotencyKey 不能为空：'
      '没有幂等键，同一条消息会被补推两次（＝同一条消息提醒两次）',
    );
    need(
      (str(const ['waitingOnline', 'backupReplayLabel']) ?? '').isNotEmpty,
      'waitingOnline.backupReplayLabel 不能为空：补推那一发在记录上要有个名字',
    );

    // ── 传输 ──
    need(
      boolOf(const ['transport', 'httpsOnly']) == true,
      'transport.httpsOnly 必须为 true',
    );
    need(
      str(const ['transport', 'secretPlacement']) == 'path_segment',
      '口令必须放路径段（query 会进 access log）',
    );
    need(
      (str(const ['transport', 'accessLogRedactPathPattern']) ?? '').isNotEmpty,
      'transport.accessLogRedactPathPattern 不能为空',
    );
    // ── 设备面的路径（transport.apiPaths）──
    // 为什么值得进契约：客户端要知道往哪个 URL 发，服务端知道自己挂在哪儿。两边各写一份字面量
    // 时，改路径的那一刀不会报错，只会变成「服务端换了门、客户端还在敲旧门」—— 而这一层在身份
    // 证明之前一律同形（防枚举），所以排查的人从响应里看不出"敲错门"和"口令错"的区别。
    final declaredPaths = apiPaths;
    final missingPathFor = eventKinds.keys
        .where((k) => !declaredPaths.containsKey(k))
        .join(', ');
    final unknownPathKeys = declaredPaths.keys
        .where((k) => !eventKinds.containsKey(k) && k != 'message')
        .join(', ');
    need(
      declaredPaths.isNotEmpty,
      'transport.apiPaths 必须非空：设备面路径没有第二个来源，缺段就是让两份实现各拼一次',
    );
    need(
      missingPathFor.isEmpty,
      'transport.apiPaths 必须覆盖每一种设备签名事件（缺：$missingPathFor）：'
      '漏掉的那个客户端发不出去，而它看起来只是"少了一行配置"',
    );
    need(
      unknownPathKeys.isEmpty,
      'transport.apiPaths 里有不属于 clientEvents 的键：$unknownPathKeys'
      '（/message 是投递面、可以单独声明；其余键必须真是一种事件，否则这条路径没人挂）',
    );
    for (final entry in declaredPaths.entries) {
      need(
        entry.value.startsWith('/api/fnthink/') &&
            !entry.value.contains('?') &&
            !entry.value.contains('//'),
        'transport.apiPaths.${entry.key} 必须是 /api/fnthink/ 下的纯路径（实为「${entry.value}」）：'
        '带 query 就等于把参数写进协议路径，而口令类参数进 query 正是这个协议禁止的那件事',
      );
    }
    need(
      declaredPaths.values.toSet().length == declaredPaths.length,
      'transport.apiPaths 的值有重复：两个事件共用一条路径时，服务端只能按其中一种裁决',
    );
    // 端点收单那两条**不许**混进这张表（它们走共享口令，鉴权方式完全不同一类）。
    final ingressPaths = {
      str(const ['endpoint', 'ingress', 'pathPattern']) ?? '',
      str(const ['endpoint', 'ingress', 'postBearerPath']) ?? '',
    };
    need(
      declaredPaths.values.every((p) => !ingressPaths.contains(p)),
      'transport.apiPaths 里出现了端点收单的路径：那张表是设备面（签名鉴权），'
      '混在一起下一个人会以为设备面也能携带口令',
    );
    // 域名是**部署形态**而不是注释：客户端要拼成 `https://<host>/api/...`，而大陆那条
    // 从 pushfnthink.com 改成 push.fnthink.com 时，契约里那行没有任何读者与校验，
    // 于是错的串一直"看起来是配置"。钉三件事：两个都非空、两个必须不同（同域就没有
    // 双域名部署这回事了）、默认值必须是两者之一（默认值指向一个不存在的域名，
    // 表现是"装了 App 检查更新能通、推送全连不上"）。不钉"默认=国际那条"：那是
    // 可以随产品改的选择，钉死了就变成每次换默认值都要动协议。
    final endpointHosts = <String, String>{
      for (final k in const ['international', 'mainland', 'default'])
        k: str(['transport', 'endpoints', k]) ?? '',
    };
    // 点分隔的标签，每段首尾是字母数字、中间可有连字符，且至少两段
    final hostPattern = RegExp(
      r'^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?'
      r'(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$',
    );
    for (final entry in endpointHosts.entries) {
      need(entry.value.isNotEmpty, 'transport.endpoints.${entry.key} 不能为空');
      // 只许裸主机名：带 scheme 或路径会被拼成 https://https//… 这种没人报错的 URL
      // ⚠ 不能用 Uri.tryParse(...).host 判 —— 不带 scheme 的串会被当成 path，host 恒空，
      //   于是**正确值也会被判红**（我第一版就是这么写错的）。
      need(
        hostPattern.hasMatch(entry.value),
        'transport.endpoints.${entry.key} 必须是裸主机名（不含 scheme/路径/空格），'
        '客户端按 https://<host>/api/… 拼接，当前值「${entry.value}」不合形状',
      );
    }
    need(
      endpointHosts['international'] != endpointHosts['mainland'],
      '双域名必须不同，否则 T57 的「能力等价、可互相切换」落空',
    );
    need(
      endpointHosts['default'] == endpointHosts['international'] ||
          endpointHosts['default'] == endpointHosts['mainland'],
      'transport.endpoints.default 必须是两个域名之一，'
      '当前值「${endpointHosts['default']}」指向了没声明过的域名',
    );

    // ── 配对（T28）──
    need(
      (str(const ['pairing', 'qrPrefix']) ?? '').isNotEmpty,
      'pairing.qrPrefix 不能缺省：两端各写一个前缀就互相解不开对方的二维码',
    );
    need(
      boolOf(const ['pairing', 'confirmRequired']) == true &&
          boolOf(const ['pairing', 'autoApprove']) == false,
      'pairing 必须"要人确认、不自动批准"：扫码即入白名单 = 谁捡到二维码谁就是可信发送方',
    );
    for (final required in ['v', 'to', 'code', 'level']) {
      need(
        strings(const ['pairing', 'payloadFields']).contains(required),
        '配对载荷缺字段 $required：${strings(const ['pairing', 'payloadFields'])}',
      );
    }
    need(
      boolOf(const ['pairing', 'rejectUnknownFields']) == true,
      'pairing.rejectUnknownFields 必须为 true：配对载荷上的"容错"就是往身份交换里塞料的口子',
    );
    // ── 配对关系存在哪张表、由哪一端判（#131 第三片）──
    // 这一段的存在理由：前两片把"关系"建起来了，收单却还在读发送方自己那一行的 grant ——
    // 那等于"谁登记过就能给任何人投"。判据写下来之后，把关系挪回发送方、或者收单不再判，
    // 都会在契约自洽这一步就报，而不是等到某台设备的队列里出现陌生人的验证码。
    need(
      str(const ['pairing', 'relationshipStoredOn']) == 'target-device-record',
      'pairing.relationshipStoredOn 只能是 target-device-record（授权是"被投那台"做的决定，'
      '存在发送方记录上时，"逐条勾选 / 每次本地确认 / 重建后所有发送方重配"这三条都执行不了）',
    );
    need(
      (str(const ['pairing', 'relationshipField']) ?? '').isNotEmpty,
      'pairing.relationshipField 不能缺：收单要知道去哪一列读这段关系，缺了就等于没有这道判据',
    );
    // ── 一次确认创建几段关系（T130 片2）──
    // 上面那条讲的是「一段住在哪一行」，这一条讲的是「一次确认写几段」。两件必须分开钉：
    // 合成一条的话，把双写关掉时 `relationshipStoredOn` 那条照样绿，而设备上表现是
    // "两台都以为配好了，发过去却是 403" —— 那一半从来没有人报过。
    final reverseOn = boolOf(const ['pairing', 'reverseGrantOnConfirm']);
    need(
      reverseOn != null,
      'pairing.reverseGrantOnConfirm 必须明写 true 或 false（没有缺省档）：一次确认创建一段还是两段，'
      '由实现挑的话挑错那一侧正好是"看着成功、其实发不出去"，界面分不出来',
    );
    if (reverseOn == true) {
      need(
        str(const ['pairing', 'reverseGrantMaxLevel']) == 'same-as-forward',
        'pairing.reverseGrantMaxLevel 只能是 same-as-forward（实为'
        '「${str(const ['pairing', 'reverseGrantMaxLevel'])}」）：两段的封顶取自同一个数才只有一本账，'
        '而两端都只执行这一种写法 —— 换一个词就是声明了一段谁都不执行的规则',
      );
      need(
        str(const ['pairing', 'reverseGrantItems']) == 'empty',
        'pairing.reverseGrantItems 只能是 empty（实为'
        '「${str(const ['pairing', 'reverseGrantItems'])}」）：逐条勾选取自**点头那一台**的屏幕，'
        '反向那一段的对象从没勾过 ⇒ 复制正向那份就是替对面点头，而"不替谁点头"是整块勾选存在的原因',
      );
    }
    need(
      str(const ['pairing', 'revokeDirection']) == 'incoming',
      'pairing.revokeDirection 只能是 incoming（实为'
      '「${str(const ['pairing', 'revokeDirection'])}」）：划得到的只有签名者自己那一行里的那一段；'
      '放开成 outgoing 就是一台能替别人删授权，而 revocableBy 讲的正是同一件事',
    );
    need(
      str(const ['pairing', 'enforcedAt']) == 'server-intake',
      'pairing.enforcedAt 只能是 server-intake（实为「${str(const ['pairing', 'enforcedAt'])}」）：'
      '本实现只有服务端收单那一条执行路径，写成 device-only 就是声明了一条没人执行的闸',
    );
    // 上面那条已把执行点钉成 server-intake，所以这里不再套 if：条件恒真就是噪音。
    need(
      boolOf(const ['pairing', 'relationshipRequiredForIntake']) == true,
      '关系在服务端判而 relationshipRequiredForIntake 不为 true ⇒ 报：'
      '查不到关系就落到 capabilities.grantDefaults 那一档，等于"谁都没配过对"默认放行（fail-open）',
    );
    final entryFields = strings(const ['pairing', 'relationshipEntryFields']);
    need(
      entryFields.isNotEmpty,
      'pairing.relationshipEntryFields 不能为空：那张表里每一项至少要能读出一个档位',
    );
    // 每一项必须能当作 capabilities 的那份授权节点来读：两处形状一致才只有一份规则。
    for (final key
        in (map(const ['capabilities', 'grantDefaults']) ?? const {}).keys) {
      need(
        entryFields.contains(key),
        'pairing.relationshipEntryFields 缺 $key：grantDefaults 用的就是这份节点形状，'
        '关系项少这个键时缺省档根本补不进去（表现为"配过对的设备反而被自己的档位卡住"）',
      );
    }
    need(
      (str(const ['pairing', 'revocableBy']) ?? '').isNotEmpty,
      'pairing.revocableBy 必须写明谁能撤销：能授权的人才能撤销，'
      '否则 A 划掉 B 之后 B 的签名仍进得来，那道"划掉"是装饰',
    );
    for (final secret in ['privateKey', 'signature', 'pairingCodeDigest']) {
      need(
        strings(const ['pairing', 'neverCarry']).contains(secret),
        '配对载荷必须禁止携带 $secret：${strings(const ['pairing', 'neverCarry'])}',
      );
    }
    need(
      str(const ['pairing', 'failureMessageShape']) == 'single-generic',
      '配对失败必须只有一种提示：文案能分辨"没这台设备"与"口令错"，服务端就成了地址码枚举器',
    );
    need(
      str(const ['pairing', 'clockAuthority']) == 'server',
      '配对口令的计时以服务端为准（设备本机时钟不参与判定）',
    );
    final requestable = str(const [
      'pairing',
      'maxRequestableLevelFromPairing',
    ]);
    need(
      strings(const ['capabilities', 'levels']).contains(requestable) &&
          requestable != 'L3',
      '配对时可请求的最高级别必须是契约已定义的级别且不得是 L3（L3 要本地锁屏/生物认证）',
    );

    // ── 远程执行（片1：契约先行，读口与判据成对）──
    for (final level in const ['L1', 'L2', 'L3']) {
      need(
        remoteExecutionSourcesFor(level).isNotEmpty,
        'capabilities.remoteExecution.sources.$level 为空：这一档没有任何渠道允许，等于把它禁掉',
      );
    }
    for (final level in const ['L2', 'L3']) {
      final sources = remoteExecutionSourcesFor(level);
      need(
        sources.every((s) => s == 'fnthink'),
        'capabilities.remoteExecution.sources.$level 只允许 fnthink（维护者定：L2/L3 仅幻念推送），实为 $sources',
      );
    }
    need(
      remoteExecutionAuthModes.contains('key') &&
          remoteExecutionAuthModes.contains('totp'),
      'capabilities.remoteExecution.auth.modes 必须同时含 key 与 totp（L3 二者其一即可用）',
    );
    need(
      !remoteExecutionL2RequiresAuth && remoteExecutionL3RequiresAuth,
      '凭据是 L2 可选、L3 必填（维护者定）；写反了就是一个安全漏',
    );
    need(
      remoteExecutionDelayMinSeconds <= remoteExecutionDelayDefaultSeconds &&
          remoteExecutionDelayDefaultSeconds <= remoteExecutionDelayMaxSeconds,
      '延时窗口的默认值要落在 [minSeconds, maxSeconds] 里：'
      '${remoteExecutionDelayDefaultSeconds}s'
      '（⚠ 区间反了——min > max——也必然走这一条，所以**没有**另立一条次序判据：'
      '那会是一条永远不可观察的判断，摘掉它之后没有任何用例会红）',
    );
    need(
      remoteExecutionOnTimeout == 'execute',
      '超时语义必须是 execute（维护者定：所有级别超时默认执行）',
    );
    need(!remoteExecutionPresenceAffectsTiming, '用户在场与否不影响计时（维护者定）');
    need(
      remoteExecutionStates.contains('executing') &&
          remoteExecutionStates.contains('cancelled'),
      '执行状态词表必须含 executing（两段回执那一段）与 cancelled（窗口内撤销）',
    );
    final receiptWords = strings(const ['receipts']);
    final twoStageReceipts = remoteExecutionReceipts;
    need(
      twoStageReceipts.length == 2 &&
          twoStageReceipts.values.every(receiptWords.contains),
      '两段回执词必须是 receipts 词表里的词（不许另造一份词表）：$twoStageReceipts',
    );
    need(
      l3ConfirmForm == 'cancelableDelay',
      'L3 那道闸是 cancelableDelay（改形不改内核：那个窗口就是"每次确认"的新形式）',
    );
    // 片3c 补：本机触发那一路的**来源名**必须落在 L1 的词表里。
    // ⚠ 走裸读口而不是上面的 getter：那个 getter「缺了就抛」，而在校验里抛异常
    //   报出的是崩溃而不是问题（见下面那段注），现场两种失败分不开。
    // ⚠ **只判「是谁」，不判「回不回」**：后者已经有一条更宽的判据（哨兵词或 receipts
    //   词表里的词），契约也刻意留了「改主意要回给谁就改这一处」的口子 ——
    //   在这里再钉一条「必须是 none」会把那个口子焊死，且与那条既有用例直接冲突
    //   （它明确断言换成 `delivered` 应当照收）。两条分开：来源判合法性，回执判词表。
    final localTrigger = str(const [
      'capabilities',
      'remoteExecution',
      'localTriggerSource',
    ]);
    need(
      localTrigger != null &&
          localTrigger.isNotEmpty &&
          remoteExecutionSourcesFor('L1').contains(localTrigger),
      'capabilities.remoteExecution.localTriggerSource 必须在 '
      'sources.L1 里（实为「$localTrigger」，'
      '词表 ${remoteExecutionSourcesFor('L1')}）：写一个不在词表里的来源名，'
      '「本机那一路按契约不回执」会永远不成立 —— 判据绿着，而本机触发照发回执',
    );
    // 片3b 补的三组读口各带一条判据：长度/位数/步长/安全方向/范围次序，
    // 每一项丢了或写反了，界面或校验那一层就会**静默地**按一个协议从没同意过的值走。
    //
    // ⚠ 这几条走 `intOf` / `str` 的**裸读口**，不走上面那几个 getter：那几个是
    //   "缺了就抛"（调用方要拿到一个能用的值），而这里是"把缺了这件事报出来"——
    //   一个在校验里抛异常的判据，报出的不是问题而是崩，届时"契约被改坏"会显示成
    //   "测试崩了"，两种失败在现场分不开。
    final reAuth =
        map(const ['capabilities', 'remoteExecution', 'auth']) ??
        const <String, Object?>{};
    final reDelay =
        map(const ['capabilities', 'remoteExecution', 'delay']) ??
        const <String, Object?>{};
    final keyMin = (reAuth['keyMinLength'] as num?)?.toInt();
    need(
      keyMin != null && keyMin > 0,
      'auth.keyMinLength 必须是正整数（长度是安全参数，不补默认值），实为「$keyMin」',
    );
    final totpDigits = (reAuth['totpDigits'] as num?)?.toInt();
    final totpPeriod = (reAuth['totpPeriodSeconds'] as num?)?.toInt();
    need(
      totpDigits != null &&
          totpDigits > 0 &&
          totpPeriod != null &&
          totpPeriod > 0,
      'auth.totpDigits 与 auth.totpPeriodSeconds 都必须是正整数'
      '（位数与步长缺一个，另一半的默认值就变成代码在发明协议），'
      '实为「$totpDigits」/「$totpPeriod」',
    );
    final onMissing = reAuth['onMissingOrWrong'] as String?;
    need(
      onMissing == 'reject',
      'auth.onMissingOrWrong 必须是 reject（缺凭据或凭据不对一律拒；'
      '改成 execute 就是把"没带凭据也执行"写进协议），实为「$onMissing」',
    );
    final delayMin = (reDelay['minSeconds'] as num?)?.toInt();
    final delayMax = (reDelay['maxSeconds'] as num?)?.toInt();
    need(
      delayMin != null && delayMax != null && delayMin >= 0,
      'delay.minSeconds 与 delay.maxSeconds 都必须存在且 min 非负'
      '（⚠ **不另判 min ≤ max**：区间反了时 default 必然掉出区间，'
      '上面「默认值要落在」那条已经必然红，所以次序判据是**不可观察**的 —— '
      'R10 那发植入摘掉它之后全绿，证的就是这件事），'
      '实为「$delayMin」/「$delayMax」',
    );
    final localReceipt = str(const [
      'capabilities',
      'remoteExecution',
      'localTriggerReceipt',
    ]);
    // ⚠ `none` 是**故意不在** receipts 词表里的那个词：它说的不是"回哪一个回执"，
    // 而是"这一路上没有任何人可以回"。把它也要求 ∈ receipts 会让契约必须为一件
    // 不存在的事造一个回执词 —— 那恰好是本地触发这一路的全部要点。
    need(
      localReceipt == null ||
          localReceipt.isEmpty ||
          localReceipt == _remoteExecutionNoReceiptSentinel ||
          receiptWords.contains(localReceipt),
      'remoteExecution.localTriggerReceipt 只能是「$_remoteExecutionNoReceiptSentinel」'
      '（不回执：那一路上没有远端发送方）或 receipts 词表里的词（另造一个词 = 第二份词表），'
      '实为「$localReceipt」',
    );

    return problems;
  }
}

/// "这一路上没有回执"那个哨兵词（契约 `remoteExecution.localTriggerReceipt`）。
///
/// ⚠ 它**不在**顶层 `receipts` 词表里，这是刻意的：那一列列的是"回哪一个回执"，
/// 而本机白名单触发的那一路**没有任何人可以回**（`sourcesWhy` 里写了原因）。
/// 把它加进 `receipts` 等于为一件不存在的事造一个对外形状。
const String _remoteExecutionNoReceiptSentinel = 'none';

/// 本机触发那一路**到底回不回**（契约 `remoteExecution.localTriggerReceipt`）。
///
/// ⚠ 这是判据（用哨兵比字面量）那一半的公开读口。**有了它，调用方就不必知道
/// `'none'` 这个哨兵长什么样** —— 那个字面量此前只有 `validate()` 内部认，
/// 于是别处只能写第二份 `"none"`，而改了契约那个词之后它会**静默失配**。
bool localTriggerReceiptIsNone(FnthinkContract contract) {
  return contract.remoteExecutionLocalTriggerReceipt ==
      _remoteExecutionNoReceiptSentinel;
}
