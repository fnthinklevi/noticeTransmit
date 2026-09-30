import 'dart:async';
import 'dart:convert';

import 'canonical_bytes.dart';
import 'contract.dart';
import 'title_envelope.dart';

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

  /// 组 pairRevoke 的签名字段（把某个发送方从本机白名单里划掉，T31 B 片）。
  ///
  /// ⚠ 这一发与 pairConfirm 同属「关于别人」那一类（`mustContainCounterpartAddress`）：
  /// 签名里的 `target` 是**被划掉那台**，不是本机。
  /// 这里刻意**只有一个参数**：服务端判的是「载荷里那个地址必须逐字等于签名里的 target」，
  /// 也就是同一件事的两个来源。做成两个参数等于把"能不能不一致"留给调用方去负责，
  /// 而不一致的那一发换回来的只是一句同形的 403 —— 让它在本机就不可能被写错，比事后拦更便宜。
  Map<String, Object?> pairRevokeFields({
    required String peer,
    required String nonce,
    String? ts,
  }) {
    final declared = contract.pairRevokeFields;
    if (declared.length != 1) {
      // 名单一旦多出一个键，"两个来源合一"这个前提就没了：那时载荷里写谁、签名里针对谁
      // 是两件事，必须由契约明说哪个算数，而不是让这里继续只收一个参数。
      throw StateError(
        'pairRevoke 的载荷应当只有一个键（契约 fields=$declared）：'
        '这里把签名的 target 与载荷里那个地址合成一个入参，靠的就是名单里就一个键',
      );
    }
    return {
      'version': contract.protocolVersionForSignature,
      'type': eventType('pairRevoke'),
      'target': peer,
      'ts': ts ?? signedTimestamp,
      'nonce': nonce,
      'body': jsonEncode({declared.single: peer}),
    };
  }

  /// 划掉一个发送方。失败不抛，状态→后果那张表仍只有 [interpret] 一份。
  ///
  /// ⚠ `revoked == false` **不是失败**：撤销是幂等的（目标状态「它不在我的名单里」已达成）。
  /// 把它当失败的那一端会留着本机那一行不再删，从此两边各说一段——
  /// 所以 [FnthinkPairRevokeResult.ok] 只要求"看得懂回的是什么"，不要求它说删掉过。
  Future<FnthinkPairRevokeResult> pairRevoke({required String peer}) async {
    final nonce = (nonceFactory ?? _fallbackNonce)();
    final sentAt = _nowMs();
    final signedWhileUncalibrated = !calibrated;
    final envelope = await buildEnvelope(
      fields: pairRevokeFields(peer: peer, nonce: nonce),
      nonce: nonce,
    );
    final FnthinkReply reply;
    final int receivedAt;
    try {
      reply = await _transport(envelope);
      receivedAt = _nowMs();
    } catch (e) {
      _lastReason = 'transport:${e.runtimeType}';
      return FnthinkPairRevokeResult(
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
      return FnthinkPairRevokeResult(
        status: verdict.status,
        signedWhileUncalibrated: signedWhileUncalibrated,
        reason: verdict.reason ?? 'pair-revoke-http:${reply.status}',
      );
    }
    final revoked = reply.body['revoked'];
    if (revoked is! bool) {
      // 200 但看不懂：宁可报失败。把它当"撤好了"，本机就删了一行而对面其实还在名单里。
      _lastReason = 'pair-revoke-unparsable-ack';
      return FnthinkPairRevokeResult(
        status: FnthinkPollStatus.failed,
        signedWhileUncalibrated: signedWhileUncalibrated,
        reason: _lastReason,
      );
    }
    _lastReason = null;
    return FnthinkPairRevokeResult(
      status: FnthinkPollStatus.ok,
      revoked: revoked,
      signedWhileUncalibrated: signedWhileUncalibrated,
    );
  }

  /// 组 endpointCreate 的签名字段（给自己建一条接入端点，T42 第七片）。
  ///
  /// self-only：`target` 就是本机地址码（与 pairArm 同一类）。契约的载荷名单里**没有** `secret`
  /// 也不许有 —— 口令由服务端生成，设备自带等于把"选一把多强的口令"交出去。所以这一发的入参只有
  /// `name`：多带一个键在内核这里就当场抛，而不是签出去换一句同形的 403。
  Map<String, Object?> endpointCreateFields({
    required String name,
    required String nonce,
    String? ts,
  }) {
    final declared = contract.endpointCreateFields;
    final payload = {'name': name};
    if (payload.length != declared.length ||
        !declared.every(payload.containsKey)) {
      throw ArgumentError(
        'endpointCreate 的载荷键必须与契约名单一致（期望 $declared，实到 '
        '${(payload.keys.toList()..sort())}）：名单里没有 secret，也不该有',
      );
    }
    return {
      'version': contract.protocolVersionForSignature,
      'type': eventType('endpointCreate'),
      'target': addressCode,
      'ts': ts ?? signedTimestamp,
      'nonce': nonce,
      'body': jsonEncode({for (final key in declared) key: payload[key]}),
    };
  }

  /// 建一条接入端点。**口令只在这一次的响应里出现**，所以 `ok` 的判据比别的发更严：
  /// 200 而读不出 `endpointId` 或 `secret` ⇒ 算失败，绝不回一个"看着成了但口令没了"的结果 ——
  /// 那种结果的表现是：表里多了一把他不知道的入口，而界面上写着"已创建"，NAS 永远配不通。
  /// 本内核**不存**这个结果（也没有地方存）：口令的唯一去处是返回值，交给调用方当场展示一次。
  ///
  /// 这一发被砸过什么（报告在本地 `outputs/_endpntpeer.report.txt`，按约定不入库）：
  ///  - **X1** 把"空串也算读不到"那半摘掉 ⇒ 红在「口令是空串也算读不到」；
  ///  - **X2** 把 `target` 从本机地址码改成别的 ⇒ 红在「target 是**本机**地址码」
  ///    （替别人建入口 = 拿到别人那条入口的明文口令，拿着它就能冒充那台设备）。
  Future<FnthinkEndpointCreateResult> endpointCreate({
    required String name,
  }) async {
    final nonce = (nonceFactory ?? _fallbackNonce)();
    final sentAt = _nowMs();
    final signedWhileUncalibrated = !calibrated;
    final envelope = await buildEnvelope(
      fields: endpointCreateFields(name: name, nonce: nonce),
      nonce: nonce,
    );
    final FnthinkReply reply;
    final int receivedAt;
    try {
      reply = await _transport(envelope);
      receivedAt = _nowMs();
    } catch (e) {
      _lastReason = 'transport:${e.runtimeType}';
      return FnthinkEndpointCreateResult(
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
      return FnthinkEndpointCreateResult(
        status: verdict.status,
        signedWhileUncalibrated: signedWhileUncalibrated,
        reason: verdict.reason ?? 'endpoint-create-http:${reply.status}',
      );
    }
    final id = reply.body['endpointId'];
    final secret = reply.body['secret'];
    if (id is! String || id.isEmpty || secret is! String || secret.isEmpty) {
      _lastReason = 'endpoint-create-unparsable-ack';
      return FnthinkEndpointCreateResult(
        status: FnthinkPollStatus.failed,
        signedWhileUncalibrated: signedWhileUncalibrated,
        reason: _lastReason,
      );
    }
    _lastReason = null;
    return FnthinkEndpointCreateResult(
      status: FnthinkPollStatus.ok,
      endpointId: id,
      secret: secret,
      postOnly: reply.body['postOnly'] is bool
          ? reply.body['postOnly'] as bool
          : null,
      signedWhileUncalibrated: signedWhileUncalibrated,
    );
  }

  /// 组 endpointList 的签名字段（读自己名下那几把接入端点，#157 第二片）。
  ///
  /// 载荷名单今日为空 ⇒ `body` 就是 `{}`。这一发的入参**刻意一个都没有**（连"只看可用的"、
  /// "连调用日志一起"都不给）：一旦允许客户端提要求，服务端就得照它过滤，"哪几把属于我"
  /// 的判据从此有两本账，而多出来的那半个读口正是运维面那份调用日志 —— 它不该从设备面出。
  ///
  /// ⚠ 名单哪天不再是空的 ⇒ 这里抛，而不是照旧发一份 `{}` 换一句同形 403：
  /// 那说明契约给这一发加了输入，而加进去的每一个输入都要先想清楚"谁能填"。
  Map<String, Object?> endpointListFields({required String nonce, String? ts}) {
    final declared = contract.endpointListFields;
    if (declared.isNotEmpty) {
      throw ArgumentError(
        'endpointList 的载荷名单必须是空的（实到 $declared）：这一发不改变任何东西，'
        '带键就说明有人在把它变成第二个读口',
      );
    }
    return {
      'version': contract.protocolVersionForSignature,
      'type': eventType('endpointList'),
      'target': addressCode,
      'ts': ts ?? signedTimestamp,
      'nonce': nonce,
      'body': jsonEncode(const <String, Object?>{}),
    };
  }

  /// 读自己名下那几把入口。
  ///
  /// **整读失败，绝不回一份少了行的列表**：「我有 2 把」与「我其实有 3 把，其中一行没解析出来」
  /// 在用户眼里是同一句话，而后者会让人把一把还在收信的入口当成不存在 —— 那正是本仓
  /// 「推送不因通道故障静默丢失，也不因界面少画而无声少一份」那条不变量在这格的形状。
  ///
  /// 两道额外判据（都朝"更保守"的方向，所以不会误伤诚实用户）：
  ///  - `status` 必须落在契约 `endpoint.statuses` 的词表上，不认识的那一档**不当成可用的**；
  ///  - 每一行的 `owner` 必须就是本机地址码。这一发按定义是 self-only，服务端已经按 owner 过滤过；
  ///    这里再判一次是**第二道咽喉**：万一那半挂了、别人名下一行漏出来，本机不会把它画进"我的端点"。
  ///
  /// 这一发被砸过什么（报告在本地 `outputs/_eplist2.report.txt` 与 `_eplist2b.report.txt`，
  /// 按约定不入库；11 条全部 named+restored）：
  ///  - **Z1** 载荷名单不空也照发（`if (declared.isNotEmpty)` 摘掉）⇒ 红在「契约名单一旦不空 ⇒ 当场抛」；
  ///  - **Z2** owner 那一道咽喉摘掉 ⇒ 红在「别人名下一行漏出来」；
  ///  - **Z3** 状态词表那一道摘掉 ⇒ 红在「状态不在契约词表上」—— 这一条与 **Z4** 是一对：
  ///    Z3 关掉"不认识的不许进"，Z4 把"认识的算哪一档"换成黑名单；
  ///  - **Z4** `usable` 改成 `status != 'revoked'` ⇒ 红在「usable 判的是契约那一个词」。
  ///    ⚠ 这一条今天能红，靠的是用例**喂了一份改了 `usableStatus` 的契约副本**：
  ///    拿原契约去断，两种写法给出同样的答案，用例就永远是绿的（同一类假绿本仓撞过两次）；
  ///  - **Z5** 缺 `endpoints` 键时默认成空列表 ⇒ 红在「服务端没回 endpoints ⇒ 失败」。
  ///    这一条是这一发最容易被"好心"改坏的地方：一个 `?? []` 就把"没读到"变成了"你没有"。
  Future<FnthinkEndpointListResult> endpointList() async {
    final nonce = (nonceFactory ?? _fallbackNonce)();
    final sentAt = _nowMs();
    final signedWhileUncalibrated = !calibrated;
    final envelope = await buildEnvelope(
      fields: endpointListFields(nonce: nonce),
      nonce: nonce,
    );
    final FnthinkReply reply;
    final int receivedAt;
    try {
      reply = await _transport(envelope);
      receivedAt = _nowMs();
    } catch (e) {
      _lastReason = 'transport:${e.runtimeType}';
      return FnthinkEndpointListResult(
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
      return FnthinkEndpointListResult(
        status: verdict.status,
        signedWhileUncalibrated: signedWhileUncalibrated,
        reason: verdict.reason ?? 'endpoint-list-http:${reply.status}',
      );
    }
    final raw = reply.body['endpoints'];
    if (raw is! List) {
      _lastReason = 'endpoint-list-unparsable';
      return FnthinkEndpointListResult(
        status: FnthinkPollStatus.failed,
        signedWhileUncalibrated: signedWhileUncalibrated,
        reason: _lastReason,
      );
    }
    final vocabulary = contract.endpointStatuses;
    final rows = <FnthinkEndpointSummary>[];
    for (var i = 0; i < raw.length; i += 1) {
      final entry = raw[i];
      if (entry is! Map) {
        _lastReason = 'endpoint-list-unparsable:row=$i';
        return FnthinkEndpointListResult(
          status: FnthinkPollStatus.failed,
          signedWhileUncalibrated: signedWhileUncalibrated,
          reason: _lastReason,
        );
      }
      final id = entry['id'];
      final status = entry['status'];
      if (id is! String || id.isEmpty || status is! String) {
        _lastReason = 'endpoint-list-unparsable:row=$i';
        return FnthinkEndpointListResult(
          status: FnthinkPollStatus.failed,
          signedWhileUncalibrated: signedWhileUncalibrated,
          reason: _lastReason,
        );
      }
      if (!vocabulary.contains(status)) {
        _lastReason = 'endpoint-list-unknown-status:row=$i';
        return FnthinkEndpointListResult(
          status: FnthinkPollStatus.failed,
          signedWhileUncalibrated: signedWhileUncalibrated,
          reason: _lastReason,
        );
      }
      final owner = entry['owner'];
      if (owner is String && owner.isNotEmpty && owner != addressCode) {
        _lastReason = 'endpoint-list-not-mine:row=$i';
        return FnthinkEndpointListResult(
          status: FnthinkPollStatus.failed,
          signedWhileUncalibrated: signedWhileUncalibrated,
          reason: _lastReason,
        );
      }
      rows.add(
        FnthinkEndpointSummary(
          id: id,
          name: entry['name'] is String ? entry['name'] as String : '',
          status: status,
          usable: status == contract.endpointUsableStatus,
          postOnly: entry['postOnly'] is bool
              ? entry['postOnly'] as bool
              : null,
          createdAt: entry['createdAt'] is int
              ? entry['createdAt'] as int
              : null,
          lastUsedAt: entry['lastUsedAt'] is int
              ? entry['lastUsedAt'] as int
              : null,
        ),
      );
    }
    _lastReason = null;
    return FnthinkEndpointListResult(
      status: FnthinkPollStatus.ok,
      endpoints: rows,
      signedWhileUncalibrated: signedWhileUncalibrated,
    );
  }

  /// 组 endpointRevoke 的签名字段（关掉自己名下一条接入端点，#157 第四片）。
  ///
  /// 与 `endpointListFields` 不同，这一发的载荷名单不是空的而是**恰好一个键**：那一个键就是
  /// 要关的那一把。名单哪天多出第二个键，这里必须抛 —— 因为"关哪一把"与"这一发替谁关"
  /// 就会变成两件事（pairRevoke 同一个论证），而本内核只收一个 `endpointId` 参数。
  Map<String, Object?> endpointRevokeFields({
    required String endpointId,
    required String nonce,
    String? ts,
  }) {
    final declared = contract.endpointRevokeFields;
    if (declared.length != 1) {
      throw StateError(
        'endpointRevoke 的载荷应当只有一个键（契约 fields=$declared）：这里把要关的那一把'
        '同时当 target 与载荷值用，靠的就是名单里就一个键',
      );
    }
    return {
      'version': contract.protocolVersionForSignature,
      'type': eventType('endpointRevoke'),
      'target': addressCode,
      'ts': ts ?? signedTimestamp,
      'nonce': nonce,
      'body': jsonEncode({declared.single: endpointId}),
    };
  }

  /// 关掉自己名下一条入口。
  ///
  /// ⚠ `revoked == false` 是一次**成功**（那把本来就不收了）：把它当失败，界面上就会出现
  /// "点了两下都说没成，而那把其实第一次就关掉了" —— 与 pairRevoke 同一条幂等论证。
  /// 判"成没成"因此只看"看得懂回的是什么"（`revoked` 是个布尔），不看它说没说"关掉过"。
  /// 失败时**什么表都不动**：本机没有端点表可动（那份真值在服务端），所以这一发唯一要小心的
  /// 是"把 403 说成已关闭" —— 那用户就不会去重建，而 NAS 那头还在往一把还收信的入口推。
  ///
  /// 这一发被砸过什么（`outputs/_eprv2.report.txt`，SA1–SA9 全 named+restored、基线先验过绿）：
  ///  - **SA1** 载荷里那个键名写死成 `'endpointId'`（不跟着契约走）⇒ 红在「载荷里那个键名跟着契约走」。
  ///    ⚠ 那条用例是**先反证、发现 NO FAILURE 再补**的：原来只有"形状对时键值是那把 id"那一条，
  ///    两边拿同一份契约比，写死与读契约当场分不出来 —— 与 X5、Z4 同一类假绿；
  ///  - **SA2** `revoked` 不是布尔时当成 true ⇒ 红在「200 而 revoked 不是布尔 ⇒ 不算关掉」；
  ///  - **SA3** 结论里的 id 改成跟着服务端回的那一个 ⇒ 红在「结论里带的是**调用方给的那一把**」。
  ///    这条看着像洁癖：服务端多回一个键就能把话说反 —— 而"要关的是哪一把"只有用户点的那一下知道。
  Future<FnthinkEndpointRevokeResult> endpointRevoke({
    required String endpointId,
  }) async {
    final nonce = (nonceFactory ?? _fallbackNonce)();
    final sentAt = _nowMs();
    final signedWhileUncalibrated = !calibrated;
    final envelope = await buildEnvelope(
      fields: endpointRevokeFields(endpointId: endpointId, nonce: nonce),
      nonce: nonce,
    );
    final FnthinkReply reply;
    final int receivedAt;
    try {
      reply = await _transport(envelope);
      receivedAt = _nowMs();
    } catch (e) {
      _lastReason = 'transport:${e.runtimeType}';
      return FnthinkEndpointRevokeResult(
        status: FnthinkPollStatus.transportError,
        endpointId: endpointId,
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
      return FnthinkEndpointRevokeResult(
        status: verdict.status,
        endpointId: endpointId,
        signedWhileUncalibrated: signedWhileUncalibrated,
        reason: verdict.reason ?? 'endpoint-revoke-http:${reply.status}',
      );
    }
    final revoked = reply.body['revoked'];
    if (revoked is! bool) {
      _lastReason = 'endpoint-revoke-unparsable-ack';
      return FnthinkEndpointRevokeResult(
        status: FnthinkPollStatus.failed,
        endpointId: endpointId,
        signedWhileUncalibrated: signedWhileUncalibrated,
        reason: _lastReason,
      );
    }
    _lastReason = null;
    return FnthinkEndpointRevokeResult(
      status: FnthinkPollStatus.ok,
      endpointId: endpointId,
      revoked: revoked,
      signedWhileUncalibrated: signedWhileUncalibrated,
    );
  }

  /// 组 endpointRotate 的签名字段（换那把入口的长期口令，#157 第六片）。
  ///
  /// 载荷形状与 `endpointRevokeFields` **逐字相同**（只有那一把的 id）：宽限期不由这一发决定，
  /// 所以这里连一个可选参数都不收 —— 多一个"旧口令立刻失效"的开关，就把一个安全属性
  /// 变成了客户端可以随口关掉的东西。
  Map<String, Object?> endpointRotateFields({
    required String endpointId,
    required String nonce,
    String? ts,
  }) {
    final declared = contract.endpointRotateFields;
    if (declared.length != 1) {
      throw StateError(
        'endpointRotate 的载荷应当只有一个键（契约 fields=$declared）：多一个键那天，'
        '"换哪一把"与"换成什么规矩"就成两件事，必须由契约明说哪个算数',
      );
    }
    return {
      'version': contract.protocolVersionForSignature,
      'type': eventType('endpointRotate'),
      'target': addressCode,
      'ts': ts ?? signedTimestamp,
      'nonce': nonce,
      'body': jsonEncode({declared.single: endpointId}),
    };
  }

  /// 换那把入口的口令。**这一发的结果里带一把新的明文口令**，与创建那一次同样的红线：
  /// 只在这里出现，内核不存、不落盘、不进日志（长期凭证进 prefs 会跟着备份走）。
  ///
  /// 两条判据比"读得懂"更严：
  ///  - `rotated:true` 而读不出非空 `secret` ⇒ **不算换成**（`endpoint-rotate-missing-new-secret`）：
  ///    那种场合表里的摘要已经换掉了，而用户手上什么都没有 —— NAS 从这一刻开始 401，
  ///    而没有任何人能说清新口令是什么。这比"没换成"更糟，所以要单独一个 reason 说清；
  ///  - `rotated:false`（那一把本来就不收了）是一次**看得懂的答复**：`ok` 为真、`secret` 为空，
  ///    界面对应的那句话是"没给它换，因为换口令不会把它复活"，不是失败。
  ///
  /// 这一发被砸过什么（`outputs/_erot2.report.txt` + `_erot2b.report.txt`，RC1–RC10 全 named+restored）：
  ///  - **RC1** 载荷键名写死成 `'endpointId'` ⇒ 红在「载荷里那个键名跟着契约走」。
  ///    ⚠ 这一条**第一次是 NO FAILURE**：轮换这组是照着吊销那组写的，连那条弱断言一起抄了
  ///    —— `expect(body.keys, contract.endpointRotateFields)` 两边读同一份契约，写死与读契约
  ///    当场分不出来。补了"喂一份改了键名的契约副本"那条用例才抓得住（同类的第三次：X5、Z4、SA1）；
  ///  - **RC2** `rotated:true` 而没口令时把空串当口令 ⇒ 红在「而读不出口令 ⇒ 不算换成」；
  ///  - **RC3** `rotated:false` 那一支摘掉 ⇒ 红在「是一次**看得懂的答复**」。
  Future<FnthinkEndpointRotateResult> endpointRotate({
    required String endpointId,
  }) async {
    final nonce = (nonceFactory ?? _fallbackNonce)();
    final sentAt = _nowMs();
    final signedWhileUncalibrated = !calibrated;
    final envelope = await buildEnvelope(
      fields: endpointRotateFields(endpointId: endpointId, nonce: nonce),
      nonce: nonce,
    );
    final FnthinkReply reply;
    final int receivedAt;
    try {
      reply = await _transport(envelope);
      receivedAt = _nowMs();
    } catch (e) {
      _lastReason = 'transport:${e.runtimeType}';
      return FnthinkEndpointRotateResult(
        status: FnthinkPollStatus.transportError,
        endpointId: endpointId,
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
      return FnthinkEndpointRotateResult(
        status: verdict.status,
        endpointId: endpointId,
        signedWhileUncalibrated: signedWhileUncalibrated,
        reason: verdict.reason ?? 'endpoint-rotate-http:${reply.status}',
      );
    }
    final rotated = reply.body['rotated'];
    if (rotated is! bool) {
      _lastReason = 'endpoint-rotate-unparsable-ack';
      return FnthinkEndpointRotateResult(
        status: FnthinkPollStatus.failed,
        endpointId: endpointId,
        signedWhileUncalibrated: signedWhileUncalibrated,
        reason: _lastReason,
      );
    }
    if (!rotated) {
      _lastReason = null;
      return FnthinkEndpointRotateResult(
        status: FnthinkPollStatus.ok,
        endpointId: endpointId,
        rotated: false,
        signedWhileUncalibrated: signedWhileUncalibrated,
      );
    }
    final secret = reply.body['secret'];
    if (secret is! String || secret.isEmpty) {
      _lastReason = 'endpoint-rotate-missing-new-secret';
      return FnthinkEndpointRotateResult(
        status: FnthinkPollStatus.failed,
        endpointId: endpointId,
        rotated: true,
        signedWhileUncalibrated: signedWhileUncalibrated,
        reason: _lastReason,
      );
    }
    _lastReason = null;
    return FnthinkEndpointRotateResult(
      status: FnthinkPollStatus.ok,
      endpointId: endpointId,
      rotated: true,
      secret: secret,
      rotatingUntil: reply.body['rotatingUntil'] is int
          ? reply.body['rotatingUntil'] as int
          : null,
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
    final signedTitle = raw['title'] is String ? raw['title'] as String : '';
    final wireBody = raw['body'] is String ? raw['body'] as String : '';
    // 设备那一路的标题在**已签的 body 信封**里（§4 第 10 条定稿：签名字节里没有 title，
    // 顶层那个未签的一定向被丢掉）。这一刀是收件端唯一的一处拆 —— 服务端从不拆，
    // 所以同一条消息在两台设备上只会有一种表现。已签标题非空时不拆（见 unwrap）。
    final content = FnthinkTitleEnvelope.unwrap(
      contract: contract,
      signedTitle: signedTitle,
      wireBody: wireBody,
    );
    return FnthinkDelivered(
      messageId: id,
      type: type,
      item: raw['item'] is String ? raw['item'] as String : '',
      title: content.title,
      body: content.body,
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

/// 划掉一个发送方的结论（T31 B 片）。
class FnthinkPairRevokeResult {
  const FnthinkPairRevokeResult({
    required this.status,
    required this.signedWhileUncalibrated,
    this.revoked,
    this.reason,
  });

  final FnthinkPollStatus status;

  /// 服务端**那边本来有没有**这一条关系。⚠ `false` 是一次成功，不是失败：
  /// 撤销的目标状态是「它不在我的名单里」，已经不在就是已达成（契约 `clientEvents.pairRevoke._why`）。
  /// 这一份只用来把"对面本来就没有"说给用户听，不用来判成没成。
  final bool? revoked;
  final bool signedWhileUncalibrated;
  final String? reason;

  bool get ok => status == FnthinkPollStatus.ok && revoked != null;
}

/// 建一条接入端点的结论（T42 第七片）。
///
/// ⚠ [secret] 是**只出现一次**的那把明文口令：内核与调用方都不许把它写进任何持久处
/// （表、prefs、日志、崩溃上报）。它的唯一合法去处是"当场显示一次，让用户抄走"。
/// 之所以把这条写在这里而不是页面注释里：下一个接这件事的人读的是这一层的签名。
class FnthinkEndpointCreateResult {
  const FnthinkEndpointCreateResult({
    required this.status,
    required this.signedWhileUncalibrated,
    this.endpointId,
    this.secret,
    this.postOnly,
    this.reason,
  });

  final FnthinkPollStatus status;
  final String? endpointId;
  final String? secret;

  /// 这条入口是不是只收 POST（契约 `transport.postOnlySwitch` / 端点策略）。
  /// null = 服务端没回这一项 —— 界面要据此说一句"没回就不猜"，而不是默认成某种。
  final bool? postOnly;
  final bool signedWhileUncalibrated;
  final String? reason;

  /// 建成 = 拿得到 id **且**拿得到口令。缺任何一个都不算成：那意味着表里多了一行而
  /// 用户手上什么都没有，而那行东西此后谁也打不开它。
  bool get ok =>
      status == FnthinkPollStatus.ok &&
      endpointId != null &&
      secret != null &&
      secret!.isNotEmpty;
}

/// 名下的一条接入端点（#157 第二片，`POST /endpoint-list` 的一行）。
///
/// ⚠ 这个形状里没有、也**不该有** `secret`：明文口令只在创建那一次给过，给完就没人再知道它；
/// 而摘要是一份"能拿去比对的东西"，配上这样一条读口就成了离线猜口令的入口。
/// 字段取自服务端唯一那份投影 `devicestore.endpointSummary`（管理面 `publicEndpoint` 的窄版，
/// 去掉逐条调用日志）—— 别处不许自己拼。
///
/// 反证 **Z11**（`outputs/_eplist2b.report.txt`）：往这个类体里加一个 `secret`（getter 形状）
/// ⇒ 红在装配守卫「摘要那一行没有口令」。这条守卫断的是**这个类里没有那个概念**，
/// 而不是"某个值等于什么" —— 值对了而字段多一个，正是这类读口漂坏的第一步。
class FnthinkEndpointSummary {
  const FnthinkEndpointSummary({
    required this.id,
    required this.name,
    required this.status,
    required this.usable,
    this.postOnly,
    this.createdAt,
    this.lastUsedAt,
  });

  final String id;

  /// 建的时候自己起的名，没起就是空串（空串是"没起名"，不是"名字读不出来"）。
  final String name;

  /// 契约 `endpoint.statuses` 词表上的那一个词，原样留着：界面上要说"这一档"，
  /// 而"这一档到底叫什么"是契约的事，不是这里的常量。
  final String status;

  /// 还收不收信。⚠ 判据是**白名单**（`status == endpointUsableStatus`），不是"不是 revoked"：
  /// 契约加第三档（比如 `frozen`）时黑名单式判定会把它画成可用的，而那一把其实早就不收了。
  final bool usable;

  /// null = 服务端没回这一项 ⇒ 界面说"没回就不猜"，不许默认成"只收 POST"或"什么都收"。
  final bool? postOnly;
  final int? createdAt;
  final int? lastUsedAt;
}

/// 读自己名下那几把入口的结论（#157 第二片）。
///
/// [endpoints] 为空列表是一次**成功**：名下确实一把都没有。之所以要能区分"空"与"没读到"，
/// 是因为这两句话在界面上长得一样而后果不同 —— 前者提示"要不要建一把"，
/// 后者必须说"这次没读到，别按没有来处理"，否则用户会当着一次失败的面把 NAS 配到别的入口上。
class FnthinkEndpointListResult {
  const FnthinkEndpointListResult({
    required this.status,
    required this.signedWhileUncalibrated,
    this.endpoints,
    this.reason,
  });

  final FnthinkPollStatus status;

  /// null = 没读出来（失败/传输错/整读被那两道额外判据拦下）。
  final List<FnthinkEndpointSummary>? endpoints;
  final bool signedWhileUncalibrated;
  final String? reason;

  bool get ok => status == FnthinkPollStatus.ok && endpoints != null;
}

/// 关掉一条接入端点的结论（#157 第四片）。
///
/// [endpointId] 是**调用方给的那一个**，原样带回：界面要说"你关掉了 ep_x"，而不是
/// 拿服务端回了什么再猜（这一发的响应刻意只有 `revoked`，不端整条记录）。
class FnthinkEndpointRevokeResult {
  const FnthinkEndpointRevokeResult({
    required this.status,
    required this.endpointId,
    required this.signedWhileUncalibrated,
    this.revoked,
    this.reason,
  });

  final FnthinkPollStatus status;
  final String endpointId;

  /// 服务端**那边本来是不是还在收信**。⚠ `false` 是一次成功，不是失败（幂等）。
  final bool? revoked;
  final bool signedWhileUncalibrated;
  final String? reason;

  bool get ok => status == FnthinkPollStatus.ok && revoked != null;
}

/// 换一条接入端点口令的结论（#157 第六片）。
///
/// ⚠ [secret] 与创建那一次同样：**新口令只在这一次出现**，之后谁也拿不回来（服务端只有摘要）。
/// 它唯一的合法去处是"当场显示一次，让用户抄走"—— 不落盘、不进日志、不进任何 `ValueNotifier`。
/// [rotatingUntil] 是旧那把的死刑日期（毫秒）：这一发不给"立刻失效"那个开关，
/// 所以宽限期只能被告知、不能被讨价。
class FnthinkEndpointRotateResult {
  const FnthinkEndpointRotateResult({
    required this.status,
    required this.endpointId,
    required this.signedWhileUncalibrated,
    this.rotated,
    this.secret,
    this.rotatingUntil,
    this.reason,
  });

  final FnthinkPollStatus status;
  final String endpointId;

  /// null = 看不懂回的是什么；`false` = 那一把本来就不收了（没换，但也不是失败）。
  final bool? rotated;
  final String? secret;
  final int? rotatingUntil;
  final bool signedWhileUncalibrated;
  final String? reason;

  bool get ok => status == FnthinkPollStatus.ok && rotated != null;

  /// 真的换过了（并且手上那把新口令读得出来）。界面只有在这一档才许说"新的那把是 …"。
  bool get exchanged => ok && rotated == true && secret != null;
}
