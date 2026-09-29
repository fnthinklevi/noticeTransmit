import 'dart:async';
import 'dart:convert';

import 'canonical_bytes.dart';
import 'contract.dart';

/// 设备侧的收货内核（#126 / T28-B 与 T35 的设备那一半）。
///
/// 这里**一个 IO 都没有**：签名与传输都由调用方注入。理由不是"好测试"这一句空话，
/// 而是这件事的三种失败方式完全不同，混在一个函数里就分不开：
///  - **传输失败**（超时、DNS、TLS）⇒ 什么状态都不该改，下一轮照常问；
///  - **协议拒绝**（401/403/409/410/429）⇒ 每种后果不一样（429 要等 `Retry-After`，
///    410 说明本机时间不可信，409 说明 nonce 撞了）；
///  - **本机时钟**⇒ 只有在这一层才谈得上"偏移"，而它决定签出去的 `ts` 服务端认不认。
///
/// ⚠ 三条不是风格选择的判据：
///  ① **`ts` 用服务端时间，不用裸本机时钟**（契约 `signature.timestampSource` /
///     `trustLocalClock=false`）。偏移从任一带 `serverTime` 的响应里学（RTT 折半），
///     没学到之前 `calibrated` 是 false 并如实带在结果里 —— 伪装成"已经校准"最坏：
///     一次重装后时钟漂了两小时，登记与收货会一路 403，而日志上看着一切正常。
///  ② **提频只在有货的时候**。`pending > 0`（或这一轮取满了一整批 ⇒ 后面还有）才用
///     `burstWhenPending`，用完 `durationSeconds` 就回落常态。反过来（一直提着）是拿用户的电
///     换不到任何东西；"取满了却按 20 秒再问"则是把一条已经等在那里的通知压了 20 秒。
///  ③ **设备不许自报 `expired` / `dropped`**。`result` 的取值只能来自契约
///     `clientEvents.ack.resultToEvent` 的键；那两档是服务端自己的决定，让设备报就等于
///     让它替全世界宣布"这条已经结束了"。
///
/// ⚠ 签名载荷里的 `type` **不在这里当参数传**：poll 与 ack 各有一个词，而这两个词在
///   `clientEvents.<kind>.messageType` 上。把它做成构造参数，表现是"一个内核跑两种事件时，
///   ack 一路签成 poll"—— 服务端只会回一句同形的 403，而设备侧什么日志都看不出来。
class FnthinkReceiveKernel {
  FnthinkReceiveKernel({
    required this.contract,
    required this.addressCode,
    required FnthinkSigner signer,
    required FnthinkTransport transport,
    this.nonceFactory,
    int Function()? nowMs,
  }) : _signer = signer,
       _transport = transport,
       _nowMs = nowMs ?? _systemNowMs;

  final FnthinkContract contract;

  /// 本机地址码：poll 与 ack 的 `target` 都必须是它（契约 selfOnlyRules），
  /// 放开就等于任何一台配过对的设备能读走别人的标题与正文。
  final String addressCode;

  final FnthinkSigner _signer;
  final FnthinkTransport _transport;
  final int Function() _nowMs;

  /// nonce 由调用方给（真机上要跨重启唯一，所以不能在这儿用随机数糊过去）。
  /// 没给就用一个进程内单调计数器 —— **够防自己重发，不够防跨重启重放**，
  /// 所以生产接线必须注入；这条不是便利参数，是留给调用方的一个洞，见测试里那条断言。
  final String Function()? nonceFactory;

  int? _offsetMs;
  int? _burstUntilMs;
  String? _lastReason;

  /// 已经学到过服务端时间（收到过带 `serverTime` 的响应）。
  bool get calibrated => _offsetMs != null;

  /// 服务端时间减本机时间的偏移（毫秒）。没校准过是 null，调用方要显示就显示"未知"。
  int? get offsetMs => _offsetMs;

  /// 上一次为什么没成（只给日志与 UI，不含任何凭证）。
  String? get lastReason => _lastReason;

  /// 某一类事件在签名载荷 `type` 上的那个词，**从契约读**。
  /// 服务端也是从同一处读的（`events.js` 拿 `spec.messageType` 比），两边各写一份字面量
  /// 早晚会漂，而漂了的表现是一句同形的 403 —— 最难查的那类失败。
  String eventType(String kind) {
    final value = contract.str(['clientEvents', kind, 'messageType']);
    if (value == null || value.isEmpty) {
      throw StateError('契约缺 clientEvents.$kind.messageType（不补默认值）');
    }
    return value;
  }

  /// 现在该用哪个节奏：`pending > 0` 或上一轮取满 ⇒ 提频窗口内，否则常态。
  Duration get currentDelay {
    final burst = contract.burstWhenPending;
    if (_burstUntilMs != null && _nowMs() < _burstUntilMs!) {
      return Duration(seconds: burst.intervalSeconds);
    }
    return Duration(seconds: contract.pollIntervalSeconds);
  }

  /// 校正到服务端时间之后的"现在"（毫秒）。**没校准时就是本机时间**，同时 [calibrated]
  /// 是 false —— 调用方要把这当作一个值得说出来的状态，而不是静默当成准的。
  int get timestampMs => _nowMs() + (_offsetMs ?? 0);

  /// 签名字段里的那个 `ts`：**秒**，而且必须是字符串。
  /// 服务端算的是 `|now - ts*1000| > maxSkewSeconds*1000`（`now` 是毫秒），
  /// 所以把毫秒写成 `ts` 不会报错 —— 它只会让每一条都超出容差，看起来像"服务端不认我的签名"。
  String get signedTimestamp => (timestampMs ~/ 1000).toString();

  /// 拼一次请求：规范化字节 → 交给 signer 签 → 组成对外信封。
  Future<Map<String, Object?>> buildEnvelope({
    required Map<String, Object?> fields,
    required String nonce,
  }) async {
    final bytes = CanonicalMessage.bytes(contract, fields);
    final signature = await _signer(bytes);
    // 顶层只有三个键：sender / signature / fields。多带一个（比如 publicKey）在 poll/ack
    // 这两类事件上是**明确的禁止项**：服务端只按设备表里那把钥匙验，多带的那把它根本不读。
    return {'sender': addressCode, 'signature': signature, 'fields': fields};
  }

  Map<String, Object?> pollFields({required String nonce, String? ts}) {
    return {
      'version': contract.protocolVersionForSignature,
      'type': eventType('poll'),
      'target': addressCode,
      'ts': ts ?? signedTimestamp,
      'nonce': nonce,
      // poll 没有载荷，`body` 是空串 —— 但**这个键必须在**：缺字段与填空值签出的字节不同
      // （见 CanonicalMessage 那条），而服务端是按契约顺序重算的。
      'body': '',
    };
  }

  /// 一次取货。失败不抛：返回的 [FnthinkPollResult.status] 说清是哪一种失败，
  /// 因为**调用方的下一步取决于它**（等一会 / 换 nonce / 先去校准时间）。
  Future<FnthinkPollResult> poll() async {
    final nonce = (nonceFactory ?? _fallbackNonce)();
    final sentAt = _nowMs();
    final signedUncalibrated = !calibrated;
    final envelope = await buildEnvelope(
      fields: pollFields(nonce: nonce),
      nonce: nonce,
    );
    final FnthinkReply reply;
    final int receivedAt;
    try {
      reply = await _transport(envelope);
      receivedAt = _nowMs();
    } catch (e) {
      // 传输异常：**什么状态都不改**。不校准、不提频、不清窗口 ——
      // 一次连不上不说明任何关于服务端的anything，改了状态反而把一次抖动放大成一串错误判断。
      _lastReason = 'transport:${e.runtimeType}';
      return FnthinkPollResult(
        status: FnthinkPollStatus.transportError,
        nextDelay: currentDelay,
        signedWhileUncalibrated: signedUncalibrated,
        reason: _lastReason,
      );
    }
    return interpret(
      reply,
      signedAt: sentAt,
      receivedAt: receivedAt,
      signedWhileUncalibrated: signedUncalibrated,
    );
  }

  /// 把一次响应翻成结论。校准排在读消息之前 —— 一次失败的响应也可能带 `serverTime`，
  /// 而"时间对了但没有货"与"时间没学到"是两件不同的事。
  FnthinkPollResult interpret(
    FnthinkReply reply, {
    required int signedAt,
    required int receivedAt,
    bool signedWhileUncalibrated = false,
  }) {
    final serverTime = reply.body['serverTime'];
    if (serverTime is int) {
      final midpoint = signedAt + (receivedAt - signedAt) ~/ 2;
      _offsetMs = serverTime - midpoint;
    }
    final codes = contract.statusCodes;
    if (reply.status == codes['rateLimited']) {
      // 429 不是投递结论，所以这里不产生任何"消息没了"的判断：等 Retry-After，
      // 且**不因此停止提频窗口**（货还在服务端排着）。
      final wait = reply.retryAfterSeconds ?? contract.pollIntervalSeconds;
      _lastReason = 'rate-limited:$wait';
      return FnthinkPollResult(
        status: FnthinkPollStatus.rateLimited,
        nextDelay: Duration(seconds: wait),
        signedWhileUncalibrated: signedWhileUncalibrated,
        reason: _lastReason,
      );
    }
    if (reply.status == codes['expired']) {
      // 410 说的是"你签的 ts 我不认"。方向必须是**先学到服务端时间再说**，而不是
      // 换个 nonce 重签同一个 ts（那会一路 410，而现场看起来像服务端坏了）。
      _lastReason = 'ts-expired-needs-calibration';
      return FnthinkPollResult(
        status: FnthinkPollStatus.needsCalibration,
        nextDelay: currentDelay,
        signedWhileUncalibrated: signedWhileUncalibrated,
        reason: _lastReason,
      );
    }
    if (reply.status == codes['duplicate']) {
      // nonce 撞了（服务端 900 秒去重窗口）。**换 nonce 重签，不要重放同一个字节串** ——
      // 同一个 ts + 同一个 nonce 再发一次只会又撞一次。
      _lastReason = 'nonce-replayed';
      return FnthinkPollResult(
        status: FnthinkPollStatus.replayed,
        nextDelay: currentDelay,
        signedWhileUncalibrated: signedWhileUncalibrated,
        reason: _lastReason,
      );
    }
    if (reply.status == codes['unauthorized'] ||
        reply.status == codes['forbidden']) {
      // 这一面在身份证明之前只有一句话（同形规则），所以设备**分不清**"没这台设备"
      // 与"签名不对"与"状态不可投递"。内核不许猜：只报 rejectedUnsigned，
      // 把"要不要停"这个决定留给调用方（停 = 用户以为彻底坏了；不停 = 白耗流量）。
      _lastReason = 'rejected-unsigned';
      return FnthinkPollResult(
        status: FnthinkPollStatus.rejectedUnsigned,
        nextDelay: currentDelay,
        signedWhileUncalibrated: signedWhileUncalibrated,
        reason: _lastReason,
      );
    }
    if (reply.status != 200) {
      _lastReason = 'http:${reply.status}';
      return FnthinkPollResult(
        status: FnthinkPollStatus.failed,
        nextDelay: currentDelay,
        signedWhileUncalibrated: signedWhileUncalibrated,
        reason: _lastReason,
      );
    }

    final messages = <FnthinkDelivered>[];
    for (final raw in (reply.body['messages'] as List<Object?>? ?? const [])) {
      final one = FnthinkDelivered.tryFrom(contract, raw);
      if (one != null) messages.add(one);
    }
    final receipts = <FnthinkReceipt>[];
    for (final raw in (reply.body['receipts'] as List<Object?>? ?? const [])) {
      final one = FnthinkReceipt.tryFrom(contract, raw);
      if (one != null) receipts.add(one);
    }
    final pending = (reply.body['pending'] as num?)?.toInt() ?? 0;
    // 取满一整批 = 服务端按 `maxBatchPerPoll` 截断过 ⇒ 后面还有货，这一轮不等 pending
    // （pending 是"还在队列里的条数"，它本来就会 >= 本轮取走的数）。
    final moreWaiting =
        pending > 0 || messages.length >= contract.maxBatchPerPoll;
    if (moreWaiting) {
      _burstUntilMs =
          _nowMs() + contract.burstWhenPending.durationSeconds * 1000;
    } else {
      _burstUntilMs = null;
    }
    _round = {for (final m in messages) m.messageId: m};
    _lastReason = null;
    return FnthinkPollResult(
      status: FnthinkPollStatus.ok,
      messages: messages,
      receipts: receipts,
      pending: pending,
      nextDelay: currentDelay,
      pairRequests: FnthinkPairRequest.parseList(
        reply.body[contract.pairRequestPollKey],
      ),
      signedWhileUncalibrated: signedWhileUncalibrated,
    );
  }

  /// 这一轮取到、还没 ack 的消息。**ack 只认这里有的那几条**：
  /// 下一轮 poll 会替换掉这张表，所以"上一轮的 id 现在再 ack"是本地就能判出来的错，
  /// 不必发出去让服务端回一句同形的 403（那既不说明问题，也白耗一发额度）。
  Map<String, FnthinkDelivered> _round = const {};
  Set<String> _ackedThisRound = <String>{};

  /// 回一条 ack。`result` 必须是契约 `ackResultToEvent` 的键。
  Future<FnthinkAckResult> ack({
    required String messageId,
    required String result,
  }) async {
    final table = contract.ackResultToEvent;
    if (!table.containsKey(result)) {
      // 包含 expired / dropped：那是服务端自己的决定。设备能报的只有"到了/显示了/动作失败了"。
      _lastReason = 'unknown-result:$result';
      return FnthinkAckResult(
        status: FnthinkPollStatus.failed,
        reason: _lastReason,
        nextDelay: currentDelay,
      );
    }
    if (!_round.containsKey(messageId)) {
      _lastReason = 'not-in-current-round';
      return FnthinkAckResult(
        status: FnthinkPollStatus.failed,
        reason: _lastReason,
        nextDelay: currentDelay,
      );
    }
    if (_ackedThisRound.contains(messageId)) {
      // 同一条 ack 两次会走状态机两次（delivering→delivered→? 第二次被 ignored，
      // 服务端不会坏），但**设备侧不该指望这一点**：渲染回调可能来两次，
      // 在本地拦掉比让服务端"忽略"更省，也更接近"送达只有一句话"的原意。
      return FnthinkAckResult(
        status: FnthinkPollStatus.ok,
        duplicateSuppressed: true,
        nextDelay: currentDelay,
      );
    }
    final nonce = (nonceFactory ?? _fallbackNonce)();
    final envelope = await buildEnvelope(
      fields: {
        'version': contract.protocolVersionForSignature,
        'type': eventType('ack'),
        'target': addressCode,
        'ts': signedTimestamp,
        'nonce': nonce,
        // 载荷里**只有那两个键**：服务端把名单排过序逐字节比，多一个键就整条拒。
        'body': jsonEncode({'messageId': messageId, 'result': result}),
      },
      nonce: nonce,
    );
    final FnthinkReply reply;
    try {
      reply = await _transport(envelope);
    } catch (e) {
      _lastReason = 'transport:${e.runtimeType}';
      return FnthinkAckResult(
        status: FnthinkPollStatus.transportError,
        reason: _lastReason,
        nextDelay: currentDelay,
      );
    }
    if (reply.status != 200) {
      final one = reply.body['receipt'];
      _lastReason = 'ack-http:${reply.status}';
      return FnthinkAckResult(
        status: reply.status == contract.statusCodes['rateLimited']
            ? FnthinkPollStatus.rateLimited
            : FnthinkPollStatus.failed,
        reason: _lastReason,
        serverReceipt: one is String ? one : null,
        nextDelay: currentDelay,
      );
    }
    _ackedThisRound.add(messageId);
    final receipt = reply.body['receipt'];
    _lastReason = null;
    return FnthinkAckResult(
      status: FnthinkPollStatus.ok,
      serverReceipt: receipt is String ? receipt : null,
      state: reply.body['state'] is String
          ? reply.body['state'] as String
          : null,
      nextDelay: currentDelay,
    );
  }

  /// 组 pairArm 的签名字段（T42「添加设备」的第一跳：把这枚一次性口令挂到服务器上）。
  ///
  /// 载荷的键名单**从契约读**（`clientEvents.pairArm.fields` / `arms`），不是在这里抄一份字面量：
  /// 多塞一个键（比如顺手带上 `level`）在服务端是整条拒，而拒信只有一句同形的 403 ——
  /// 看不出是"我多带了一样东西"。所以名单对不上时这里**当场抛**，把编程错误留在它发生的地方。
  Map<String, Object?> pairArmFields({
    required Map<String, Object?> payload,
    required String nonce,
    String? ts,
  }) {
    final declared = contract.pairArmFields;
    if (declared.isEmpty) {
      throw StateError('契约没写 clientEvents.pairArm.fields：这一发不知道该带什么，不猜');
    }
    if (payload.length != declared.length ||
        !declared.every(payload.containsKey)) {
      throw ArgumentError(
        'pairArm 的载荷键必须与契约名单一致（期望 $declared，实到 '
        '${(payload.keys.toList()..sort())}）',
      );
    }
    return {
      'version': contract.protocolVersionForSignature,
      'type': eventType('pairArm'),
      // selfOnlyRules：pairArm 的 target 必须是本机自己（挂口令的人是 A，不是别人）。
      'target': addressCode,
      'ts': ts ?? signedTimestamp,
      'nonce': nonce,
      // 按契约顺序编码：规范化字节是逐字节比的，键序不同就签成另一封信。
      'body': jsonEncode({for (final key in declared) key: payload[key]}),
    };
  }

  /// 挂出口令并**问服务器收到没有**。
  ///
  /// 为什么这一步值得单独存在：本机 prefs 里写过口令 ≠ 服务器认得它。B 扫了 A 屏幕上那串去
  /// `/pair`，服务器只会回"口令不存在"，而 A 的界面上还挂着"已挂出 5 分钟"——
  /// 那是让界面替一件没发生的事作保。返回值就是那条分界线的证据。
  ///
  /// 失败不抛（同 poll）：429 要按 `Retry-After` 等、410 要先校准时间、403 是身份问题不是网络问题。
  /// 状态→后果这张表**只有 [interpret] 一份**，这里借用它，不再写第二个"如果状态是 429 就…"。
  ///
  /// 这一片被砸过什么（报告在本地 outputs/_pairarm_falsify.report.txt，按约定不入库）：
  ///  - 名单校验改成恒不触发 ⇒ 红在「多带一个 level 当场抛」；
  ///  - `type` 借 poll 的那个词 ⇒ 红在「type 用 pairArm 自己的那个词」；
  ///  - `target` 填成对端地址码 ⇒ 红在「target 必须是本机地址码」；
  ///  - `ts` 签成毫秒 ⇒ 红在「ts 是秒」；
  ///  - ⚠ [FnthinkPairArmResult.ok] 里那道"没有过期时间就不算成功"的二次判定**今日不可单独观察**：
  ///    上面那个分支先拦住了，把它摘掉全场仍绿。它是纵深防御（防的是"以后有人把分支改了却留着 ok"），
  ///    按规矩登记成纵深防御，不登记成"已验证"。
  Future<FnthinkPairArmResult> pairArm({required String pairingCode}) async {
    final nonce = (nonceFactory ?? _fallbackNonce)();
    final sentAt = _nowMs();
    final signedWhileUncalibrated = !calibrated;
    final envelope = await buildEnvelope(
      // 键名也来自契约（arms），所以"契约说这步挂的是口令"这句在实现里落到了实处：
      // 契约把 arms 改成别的词，这一发会因名单不匹配当场抛，而不是悄悄发出一封带错键的信。
      fields: pairArmFields(
        payload: {contract.pairArmPayloadField: pairingCode},
        nonce: nonce,
      ),
      nonce: nonce,
    );
    final FnthinkReply reply;
    final int receivedAt;
    try {
      reply = await _transport(envelope);
      receivedAt = _nowMs();
    } catch (e) {
      _lastReason = 'transport:${e.runtimeType}';
      return FnthinkPairArmResult(
        status: FnthinkPollStatus.transportError,
        signedWhileUncalibrated: signedWhileUncalibrated,
        reason: _lastReason,
      );
    }
    final verdict = interpret(
      reply,
      signedAt: sentAt,
      receivedAt: receivedAt,
      signedWhileUncalibrated: signedWhileUncalibrated,
    );
    if (verdict.status != FnthinkPollStatus.ok) {
      return FnthinkPairArmResult(
        status: verdict.status,
        signedWhileUncalibrated: signedWhileUncalibrated,
        reason: verdict.reason ?? 'pair-arm-http:${reply.status}',
      );
    }
    final expiresAt = reply.body['expiresAt'];
    if (reply.body['armed'] != true || expiresAt is! int) {
      // 200 但没给出过期时间 = 服务器没有承认它收下这枚口令。宁可让用户重试一次，
      // 也不能让界面说"已挂出"而服务器那边根本没有这条记录。
      _lastReason = 'pair-arm-acked-without-expiry';
      return FnthinkPairArmResult(
        status: FnthinkPollStatus.failed,
        signedWhileUncalibrated: signedWhileUncalibrated,
        reason: _lastReason,
      );
    }
    _lastReason = null;
    final ttl = reply.body['ttlSeconds'];
    return FnthinkPairArmResult(
      status: FnthinkPollStatus.ok,
      expiresAtMs: expiresAt,
      ttlSeconds: ttl is int ? ttl : null,
      signedWhileUncalibrated: signedWhileUncalibrated,
    );
  }

  /// 组 pairConfirm 的签名字段。
  ///
  /// ⚠ 这是全协议里**唯一一发 `target` 不是自己**的事件（`mustContainCounterpartAddress`）：
  /// 同意的是"让那个人配上我"，所以要写给对端。把它写成 `addressCode`（本机）不会报错，
  /// 只会换回一句与"我不该管这件事"同形的 403 —— 而 self-only 那几条恰恰禁止反过来，
  /// 所以两端的判据都在这一个键上，不许在实现里各写一份。
  Map<String, Object?> pairConfirmFields({
    required Map<String, Object?> payload,
    required String counterpart,
    required String nonce,
    String? ts,
  }) {
    final declared = contract.pairConfirmFields;
    if (payload.length != declared.length ||
        !declared.every(payload.containsKey)) {
      throw ArgumentError(
        'pairConfirm 的载荷键必须与契约名单一致（期望 $declared，实到 '
        '${(payload.keys.toList()..sort())}）',
      );
    }
    // 决定与档位都在契约给的封闭集合里：把界面上任意一个字符串签出去，
    // 换回来的只是同一句 403，而"被拒"与"这个词根本不存在"在设备侧长得一样。
    if (!contract.pairConfirmDecisions.contains(payload['decision'])) {
      throw ArgumentError(
        'decision「${payload['decision']}」不在契约 decisions '
        '${contract.pairConfirmDecisions} 里：这台不许自创第三种答复',
      );
    }
    if (!contract.capabilityLevels.contains(payload['level'])) {
      throw ArgumentError(
        'level「${payload['level']}」不在契约 capabilities.levels '
        '${contract.capabilityLevels} 里：档位词表两端同源',
      );
    }
    return {
      'version': contract.protocolVersionForSignature,
      'type': eventType('pairConfirm'),
      'target': counterpart,
      'ts': ts ?? signedTimestamp,
      'nonce': nonce,
      'body': jsonEncode({for (final key in declared) key: payload[key]}),
    };
  }

  /// 答复一条配对请求（同意或拒绝）。
  ///
  /// 与 [pairArm] 一样：失败不抛，状态→后果那张表仍只有 [interpret] 一份。
  /// `ok` 要求服务端回一个**认识的状态词**（契约 `pairRequest.statuses`）——
  /// 200 而状态词看不懂时宁可报失败：那意味着两端对"这件事结束了没有"的理解已经漂了。
  /// 这一条被砸过什么（报告在本地 outputs/_pairconfirm_falsify.report.txt，按约定不入库）：
  ///  - `target` 写成本机 ⇒ 红在「target 写的是对端，不是本机」；
  ///  - 摘掉答复词与档位的封闭集合校验 ⇒ 红在「答应的词与档位都必须在契约的封闭集合里」；
  ///  - 状态词看不懂也算已答复 ⇒ 红在「200 但状态词看不懂 ⇒ 不算已答复」；
  ///  - [FnthinkPairRequest.tryFrom] 不再拒收缺键那行 ⇒ 红在「键缺或为空的请求被丢掉」；
  ///  - 服务层摘掉"签不出来就不发"那道闸 ⇒ 红在「签不出来时不发出答复」。
  /// 五条各自点名一条用例，且逐字节还原。
  Future<FnthinkPairConfirmResult> pairConfirm({
    required String requestId,
    required String decision,
    required String level,
    required String counterpart,
  }) async {
    final nonce = (nonceFactory ?? _fallbackNonce)();
    final sentAt = _nowMs();
    final signedWhileUncalibrated = !calibrated;
    final envelope = await buildEnvelope(
      fields: pairConfirmFields(
        payload: {'requestId': requestId, 'decision': decision, 'level': level},
        counterpart: counterpart,
        nonce: nonce,
      ),
      nonce: nonce,
    );
    final FnthinkReply reply;
    final int receivedAt;
    try {
      reply = await _transport(envelope);
      receivedAt = _nowMs();
    } catch (e) {
      _lastReason = 'transport:${e.runtimeType}';
      return FnthinkPairConfirmResult(
        status: FnthinkPollStatus.transportError,
        signedWhileUncalibrated: signedWhileUncalibrated,
        reason: _lastReason,
      );
    }
    final verdict = interpret(
      reply,
      signedAt: sentAt,
      receivedAt: receivedAt,
      signedWhileUncalibrated: signedWhileUncalibrated,
    );
    if (verdict.status != FnthinkPollStatus.ok) {
      return FnthinkPairConfirmResult(
        status: verdict.status,
        signedWhileUncalibrated: signedWhileUncalibrated,
        reason: verdict.reason ?? 'pair-confirm-http:${reply.status}',
      );
    }
    final returned = reply.body['status'];
    if (reply.body['requestId'] != requestId ||
        !contract.pairRequestStatuses.contains(returned)) {
      _lastReason = 'pair-confirm-unparsable-ack';
      return FnthinkPairConfirmResult(
        status: FnthinkPollStatus.failed,
        signedWhileUncalibrated: signedWhileUncalibrated,
        reason: _lastReason,
      );
    }
    _lastReason = null;
    final granted = reply.body['grantedLevel'];
    return FnthinkPairConfirmResult(
      status: FnthinkPollStatus.ok,
      requestStatus: '$returned',
      grantedLevel: granted is String ? granted : null,
      signedWhileUncalibrated: signedWhileUncalibrated,
    );
  }

  int _nonceCounter = 0;
  String _fallbackNonce() {
    // 进程内唯一（时间戳 + 计数）。跨重启的唯一性由调用方保证 —— 这也是
    // `signature.nonceDedupeSeconds` 那个窗口的意思：重启后旧 nonce 还在别人的台账里。
    _nonceCounter += 1;
    return '${_nowMs()}-$_nonceCounter';
  }

  static int _systemNowMs() => DateTime.now().toUtc().millisecondsSinceEpoch;
}

/// 一次往返的传输结果（HTTP 由调用方翻成这三样）。
class FnthinkReply {
  const FnthinkReply({
    required this.status,
    this.body = const <String, Object?>{},
    this.retryAfterSeconds,
  });

  /// 数字必须来自契约 `statusCodes` 那一份，不是本类的默认值。
  final int status;
  final Map<String, Object?> body;
  final int? retryAfterSeconds;
}

typedef FnthinkSigner = Future<String> Function(List<int> canonicalBytes);
typedef FnthinkTransport =
    Future<FnthinkReply> Function(Map<String, Object?> envelope);

enum FnthinkPollStatus {
  ok,
  rateLimited,
  rejectedUnsigned,
  replayed,
  needsCalibration,
  transportError,
  failed,
}

/// 一条已经取到的消息（服务端把标题与正文一起解密后回过来）。
class FnthinkDelivered {
  const FnthinkDelivered({
    required this.messageId,
    required this.type,
    required this.item,
    required this.title,
    required this.body,
    required this.sender,
  });

  final String messageId;
  final String type;
  final String item;
  final String title;
  final String body;

  /// 谁发的（配对设备是它的地址码，端点是 `endpoint:<id>`）。
  /// 收件表那一行要有归属，界面要显示「是谁发的」，都只读这一列。
  /// 缺值时留空串而不是丢弃这条：正文已经到手了，因为少一个归属就把消息扔掉是
  /// 「不静默丢」的反面 —— 旧服务端不回 sender 时，那一条显示成未知来源，但看得见。
  final String sender;

  /// 形状不对 ⇒ null（**不猜**）。一条缺 messageId 的记录没法 ack，而猜一个 id 去 ack
  /// 就是在替另一条消息宣布结局。
  static FnthinkDelivered? tryFrom(FnthinkContract contract, Object? raw) {
    if (raw is! Map) return null;
    final id = raw['messageId'];
    final type = raw['type'];
    if (id is! String || id.isEmpty || type is! String || type.isEmpty) {
      return null;
    }
    return FnthinkDelivered(
      messageId: id,
      type: type,
      item: raw['item'] is String ? raw['item'] as String : '',
      title: raw['title'] is String ? raw['title'] as String : '',
      body: raw['body'] is String ? raw['body'] as String : '',
      sender: raw['sender'] is String ? raw['sender'] as String : '',
    );
  }
}

/// 一条回执（"我发的第三条已经送达了"）。回执是元数据，正文早按契约删了。
class FnthinkReceipt {
  const FnthinkReceipt({required this.messageId, required this.receipt});

  final String messageId;
  final String receipt;

  static FnthinkReceipt? tryFrom(FnthinkContract contract, Object? raw) {
    if (raw is! Map) return null;
    final id = raw['messageId'];
    final receipt = raw['receipt'];
    if (id is! String || id.isEmpty || receipt is! String) return null;
    // 回执词表是封闭的（契约 `receipts`）：不在表里的词说明两端对"结论"的理解漂了。
    if (!contract.receipts.contains(receipt)) return null;
    return FnthinkReceipt(messageId: id, receipt: receipt);
  }
}

class FnthinkPollResult {
  const FnthinkPollResult({
    required this.status,
    this.messages = const [],
    this.receipts = const [],
    this.pending = 0,
    this.pairRequests = const [],
    required this.nextDelay,
    required this.signedWhileUncalibrated,
    this.reason,
  });

  final FnthinkPollStatus status;
  final List<FnthinkDelivered> messages;
  final List<FnthinkReceipt> receipts;
  final int pending;

  /// 等着本机答复的配对请求。**解析不出来的那几条被丢掉**（见 [FnthinkPairRequest.tryFrom]）：
  /// 宁可少显示一条，也不把一条键不对的请求画成"某人请求配对你"再让人去同意。
  final List<FnthinkPairRequest> pairRequests;

  /// 下一轮该等多久。**由内核算，不由调用方猜**：提频窗口与 `Retry-After` 都在这里。
  final Duration nextDelay;

  /// 这一发是在还没学到服务端时间时签的 —— 调用方要把这当作"值得告诉用户一次"的状态，
  /// 而不是静默重试：一路 403/410 而屏幕上只有"连接失败"，是最难排查的那种形状。
  final bool signedWhileUncalibrated;
  final String? reason;

  bool get ok => status == FnthinkPollStatus.ok;
}

class FnthinkAckResult {
  const FnthinkAckResult({
    required this.status,
    required this.nextDelay,
    this.serverReceipt,
    this.state,
    this.reason,
    this.duplicateSuppressed = false,
  });

  final FnthinkPollStatus status;
  final Duration nextDelay;
  final String? serverReceipt;
  final String? state;
  final String? reason;

  /// 本地就把重复的渲染回调挡掉了（没发出去）。
  final bool duplicateSuppressed;
}

/// 挂口令那一发的结论。
///
/// `expiresAtMs` 只有**服务器确实收下并回给了过期时间**才有值 —— 界面上"已挂出"那一句
/// 必须挂在这个字段上，而不是挂在"我本地写成功"上：那两件事差一次网络往返，而用户看不出差别。
class FnthinkPairArmResult {
  const FnthinkPairArmResult({
    required this.status,
    required this.signedWhileUncalibrated,
    this.expiresAtMs,
    this.ttlSeconds,
    this.reason,
  });

  final FnthinkPollStatus status;

  /// 服务端算好的过期时刻（**毫秒 epoch**，与它回显的 `serverTime` 同一单位）。
  final int? expiresAtMs;

  /// 服务端给的剩余秒数。没回就是 null —— 界面上不显示"还剩 X 秒"，而不是自己估。
  final int? ttlSeconds;
  final bool signedWhileUncalibrated;
  final String? reason;

  bool get ok => status == FnthinkPollStatus.ok && expiresAtMs != null;
}

/// 一条等本机答复的配对请求（poll 的 `pairRequests` 那一项）。
///
/// 只解析"要拿去答复与要显示"的那几个键：`target` 与 `status` 服务端不必回（这一发是发给
/// 本机的、状态今日只有 pending），所以**不拿 storedFields 的全表当解析必填**——
/// 那会让每一条请求都被判成不合法，表现是"有人配你"那一栏永远是空的。
class FnthinkPairRequest {
  const FnthinkPairRequest({
    required this.requestId,
    required this.requester,
    required this.requesterPublicKey,
    required this.level,
    this.createdAt,
    this.expiresAt,
  });

  /// 答复它时要带回给服务端的那个 id（`pairConfirm.fields.requestId`）。
  final String requestId;

  /// 谁在请求 —— 也是 pairConfirm 那一发的 `target`（全协议唯一一发 target 不是自己）。
  final String requester;
  final String requesterPublicKey;

  /// 对方要的那一档（词表来自契约 `capabilities.levels`，显示与封顶都在消费方判）。
  final String level;
  final int? createdAt;
  final int? expiresAt;

  static List<FnthinkPairRequest> parseList(Object? raw) {
    if (raw is! List) return const [];
    final out = <FnthinkPairRequest>[];
    for (final item in raw) {
      final parsed = tryFrom(item);
      if (parsed != null) out.add(parsed);
    }
    return out;
  }

  /// 键缺或类型不对 ⇒ null（这条被丢掉）。"读成空字符串"是最坏的一种宽容：
  /// 那条请求会画成"某台设备请求配对你"，而它的 `requester` 是空的 —— 用户点同意时
  /// 连要授权给谁都不知道。
  static FnthinkPairRequest? tryFrom(Object? raw) {
    if (raw is! Map) return null;
    String req(String key) {
      final v = raw[key];
      return v is String && v.isNotEmpty ? v : '';
    }

    final id = req('id');
    final requester = req('requester');
    final publicKey = req('requesterPublicKey');
    final level = req('level');
    if (id.isEmpty || requester.isEmpty || publicKey.isEmpty || level.isEmpty) {
      return null;
    }
    final created = raw['createdAt'];
    final expires = raw['expiresAt'];
    return FnthinkPairRequest(
      requestId: id,
      requester: requester,
      requesterPublicKey: publicKey,
      level: level,
      createdAt: created is int ? created : null,
      expiresAt: expires is int ? expires : null,
    );
  }
}

/// 答复一条配对请求的结论。
///
/// `requestStatus` 只在服务端回了一个**契约认识的状态词**时才有值（`pairRequest.statuses`）：
/// 200 而词看不懂 = 两端对"这件事结了没有"的理解已经漂了，宁可报失败也不报成功。
class FnthinkPairConfirmResult {
  const FnthinkPairConfirmResult({
    required this.status,
    required this.signedWhileUncalibrated,
    this.requestStatus,
    this.grantedLevel,
    this.reason,
  });

  final FnthinkPollStatus status;
  final String? requestStatus;

  /// 服务端实际记下的档位。⚠ 它**可能低于本机答应的**（`levelCeilingFrom` 那道封顶，
  /// L2 以上必须在设备本地确认），所以界面要显示的是这个值，而不是用户刚才点的那个。
  final String? grantedLevel;
  final bool signedWhileUncalibrated;
  final String? reason;

  bool get ok => status == FnthinkPollStatus.ok && requestStatus != null;
}
