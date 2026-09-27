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

  List<String> get capabilityLevels =>
      strings(const ['capabilities', 'levels']);

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
    final poll = map(const ['presence', 'pollIntervalSeconds']);
    need(
      boolOf(const ['presence', 'separateHeartbeatProtocol']) == false,
      'presence.separateHeartbeatProtocol 必须为 false：poll 即心跳',
    );
    need(
      (intOf(const ['presence', 'onlineThresholdMultiplier']) ?? 0) >= 2,
      'presence.onlineThresholdMultiplier 至少 2（否则抖动一次就判离线）',
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
      intOf(const ['identity', 'identityKey', 'nativeMinSdkVersion']) == 30,
      'identityKey.nativeMinSdkVersion 必须是 30：KeyStore 的 EdDSA 自 Android 11 起才有',
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
