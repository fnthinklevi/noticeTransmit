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
      str(const ['pairing', 'maxRequestableLevelWithoutLocalAuth']) ?? '';

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
      final burst = map(const ['presence', 'burstWhenPending']);
      need(
        burst != null && (burst['intervalSeconds'] as num).toInt() < min,
        'burstWhenPending.intervalSeconds 必须小于常规拉取间隔，否则"提频"是假的',
      );
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
      final perMinute = (limits['endpointPerMinute'] as num).toInt();
      final perDay = (limits['endpointPerDay'] as num).toInt();
      need(
        perMinute > 0 && perDay > perMinute,
        'limits.endpointPerDay 必须大于 endpointPerMinute',
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
    need(
      str(const ['privacy', 'dedupeRefreshWhile']) != null &&
          dStates.contains(str(const ['privacy', 'dedupeRefreshWhile'])),
      'privacy.dedupeRefreshWhile 必须是一个投递状态：'
      '${str(const ['privacy', 'dedupeRefreshWhile'])}',
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
    final pollType = str(const ['clientEvents', 'poll', 'messageType']) ?? '';
    final ackType = str(const ['clientEvents', 'ack', 'messageType']) ?? '';
    final vocabulary = messageTypeLevels.keys.toSet();
    need(
      pollType.isNotEmpty && ackType.isNotEmpty && pollType != ackType,
      'clientEvents.poll/ack.messageType 必须都非空且互不相同：$pollType / $ackType',
    );
    need(
      !vocabulary.contains(pollType) && !vocabulary.contains(ackType),
      'clientEvents 的事件类型不得出现在 capabilities.messageTypes 里'
      '（出现就等于一次设备事件的签名可以当一条用户消息用）：'
      '$pollType / $ackType vs $vocabulary',
    );
    need(
      boolOf(const ['clientEvents', 'notInCapabilitiesVocabulary']) == true,
      'clientEvents.notInCapabilitiesVocabulary 必须为 true（上面那条判据的声明处）',
    );
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
      'maxRequestableLevelWithoutLocalAuth',
    ]);
    need(
      strings(const ['capabilities', 'levels']).contains(requestable) &&
          requestable != 'L3',
      '配对时可请求的最高级别必须是契约已定义的级别且不得是 L3（L3 要本地锁屏/生物认证）',
    );

    return problems;
  }
}
