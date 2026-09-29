import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:fnthink_push/fnthink_push.dart';
import 'package:notice_transmit/services/fnthink_identity_service.dart';

/// 设备侧收货的**接线层**（#126 第二片）：把 `receive_kernel.dart` 那套判据接到真实 HTTP 上。
///
/// 分工是刻意切开的：判据（时钟、节奏、结果边界）在内核，传输的事实（发到哪个 URL、
/// 状态码与 `Retry-After` 怎么读、签名从哪儿来）在这里。所以这一层故意不判断任何协议语义 ——
/// 它一旦出现 `if (status == 403) …`，内核里那张"五种失败各走各的下一步"就变成两份，
/// 而改的时候只会改到一边。
///
/// ⚠ 三条与"能不能上线"直接有关的取舍：
///  ① **URL 由契约说一次**（`transport.apiPaths`）。这里不出现 `'/api/fnthink/poll'` 这种字面量：
///     两边各写一份的话，改路径的那一刀不会报错，只会变成"服务端换了门、客户端还在敲旧门"，
///     而这一层在身份证明之前一律同形，排查的人从响应里分不出"敲错门"与"口令错"。
///  ② **https-only 在客户端也判一次**。服务端会拒明文，但那是"发出去之后"的事；本机就拒的
///     好处是不会把签名与正文先交给链路上一跳。契约 `transport.httpsOnly` 是真值来源。
///  ③ **签名出不来 ≠ 网络不通**。原生返回 null 时这里直接短路成 `signingUnavailable`，
///     不进内核 —— 否则它会被 `catch` 归成"传输异常"，而调用方看到的建议就成了"等网络恢复"。
class FnthinkReceiverService {
  FnthinkReceiverService({
    required this.contract,
    required this.baseUri,
    required this.signer,
    required this.addressCode,
    http.Client? client,
    String Function()? nonceFactory,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client(),
       _nonce = nonceFactory ?? _secureNonce {
    // 装配期就把"能不能发出第一发"判掉，而不是等第一次轮询：https 与 apiPaths 都是
    // **配置事实**，不是运行时状态。留到第一次发送才炸，会被内核的 catch 归成"传输异常"
    // —— 那是把契约与实现不匹配伪装成网络抖动（我这条就是被用例逼出来的）。
    for (final kind in ['poll', 'ack', 'pairArm', 'pairConfirm']) {
      if (!contract.apiPaths.containsKey(kind)) {
        throw ArgumentError(
          '契约的 transport.apiPaths 少了 $kind：收货与配对要发这几种请求，缺一种就是整条链断在那一步',
        );
      }
    }
    if (contract.boolOf(const ['transport', 'httpsOnly']) == true &&
        baseUri.scheme != 'https') {
      throw ArgumentError(
        '契约 transport.httpsOnly=true，而服务地址是「${baseUri.scheme}」：'
        '明文会把签名、正文与本机地址码一起交给链路上任何人 —— '
        '自部署要用 http 请显式改契约，别在客户端开后门',
      );
    }
  }

  final FnthinkContract contract;
  final Uri baseUri;
  final FnthinkIdentitySigner signer;
  final String addressCode;
  final http.Client _client;
  final String Function() _nonce;
  final Duration timeout;

  FnthinkReceiveKernel? _kernel;

  /// 懒建：第一次用到才建，因为建内核会读契约那几个数（缺就抛）。装配期抛与第一次
  /// 轮询时抛，对用户的差别是"App 打不开"与"这一项功能不可用 + 说得清原因"。
  FnthinkReceiveKernel get kernel => _kernel ??= FnthinkReceiveKernel(
    contract: contract,
    addressCode: addressCode,
    signer: signer.call,
    transport: _transport,
    nonceFactory: _nonce,
  );

  /// 事件种类 → 契约声明的路径。内核签出来的 `fields.type` 就是契约的 `messageType`，
  /// 所以这里按它反查种类，不额外传参数（多一个参数就多一次传错的机会）。
  String _pathForEnvelope(Map<String, Object?> envelope) {
    final fields = envelope['fields'];
    final type = fields is Map ? '${fields['type']}' : '';
    final paths = contract.apiPaths;
    for (final kind in paths.keys) {
      if (contract.str(['clientEvents', kind, 'messageType']) == type) {
        return paths[kind]!;
      }
    }
    // 走到这里说明内核要发的事件种类不在 apiPaths 里 —— 契约自己不自洽（validate 会拦），
    // 但这里不许"随便挑一条路径发过去"：那会把事件发到别的种类的入口上。
    throw StateError(
      '契约里找不到 messageType=「$type」对应的事件种类（apiPaths 与 clientEvents 不匹配）',
    );
  }

  Future<FnthinkReply> _transport(Map<String, Object?> envelope) async {
    final response = await _client
        .post(
          baseUri.resolve(_pathForEnvelope(envelope)),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(envelope),
        )
        .timeout(timeout);
    Map<String, Object?> body = const {};
    final text = response.body;
    if (text.isNotEmpty) {
      try {
        final decoded = jsonDecode(text);
        // 只认对象。数组或标量塞进 FnthinkReply 会让内核把"看不懂"读成"没有这个键"，
        // 那正好是最安静的一种错。
        if (decoded is Map) body = Map<String, Object?>.from(decoded);
      } catch (_) {
        // 非 JSON（反代返回的 HTML 错误页最常见）保持 body 为空：状态码照旧分类，
        // 内容由内核判成"没有结论可解析"。
        body = const {};
      }
    }
    final retryAfter = int.tryParse(
      response.headers['retry-after']?.trim() ?? '',
    );
    return FnthinkReply(
      status: response.statusCode,
      body: body,
      // 只在真给了的时候带上：内核的缺省是"按常规节奏重来"，编一个 0 会变成疯狂重试。
      retryAfterSeconds: retryAfter != null && retryAfter > 0
          ? retryAfter
          : null,
    );
  }

  /// 一次取货。签名拿不出来时**不发**：那既不是网络问题也不该被算成一次失败的重试依据。
  Future<FnthinkReceiveOutcome> pollOnce() async {
    if (!await _canSign()) {
      return FnthinkReceiveOutcome(
        status: FnthinkPollStatus.failed,
        reason: 'signing-unavailable',
        nextDelay: kernel.currentDelay,
      );
    }
    final result = await kernel.poll();
    return FnthinkReceiveOutcome(
      status: result.status,
      messages: result.messages,
      receipts: result.receipts,
      pending: result.pending,
      pairRequests: result.pairRequests,
      nextDelay: result.nextDelay,
      signedWhileUncalibrated: result.signedWhileUncalibrated,
      reason: result.reason,
    );
  }

  /// 回一条送达结论（唯一送达依据）。`result` 的取值边界在内核判。
  Future<FnthinkAckResult> ack({
    required String messageId,
    required String result,
  }) async {
    if (!await _canSign()) {
      return FnthinkAckResult(
        status: FnthinkPollStatus.failed,
        reason: 'signing-unavailable',
        nextDelay: kernel.currentDelay,
      );
    }
    return kernel.ack(messageId: messageId, result: result);
  }

  /// 把这枚一次性配对口令发到服务器（`/pair-arm`，T42「添加设备」那一跳）。
  ///
  /// 与 pollOnce / ack 同一道闸：**签名拿不出来就不发**。那既不是网络问题，也不该被记成
  /// "服务器拒了" —— 否则界面会去提示用户检查网络，而网络一直是好的。
  Future<FnthinkPairArmResult> pairArm({required String pairingCode}) async {
    if (!await _canSign()) {
      return FnthinkPairArmResult(
        status: FnthinkPollStatus.failed,
        reason: 'signing-unavailable',
        signedWhileUncalibrated: !kernel.calibrated,
      );
    }
    return kernel.pairArm(pairingCode: pairingCode);
  }

  /// 答复一条配对请求（同意或拒绝）。`counterpart` 是**对端**的地址码：
  /// 这一发的 `target` 不是本机（全协议唯一一处），写错了就换回一句同形的 403。
  Future<FnthinkPairConfirmResult> pairConfirm({
    required String requestId,
    required String decision,
    required String level,
    required String counterpart,
  }) async {
    if (!await _canSign()) {
      return FnthinkPairConfirmResult(
        status: FnthinkPollStatus.failed,
        reason: 'signing-unavailable',
        signedWhileUncalibrated: !kernel.calibrated,
      );
    }
    return kernel.pairConfirm(
      requestId: requestId,
      decision: decision,
      level: level,
      counterpart: counterpart,
    );
  }

  /// 身份与签名是否可用。**只问一次每进程**：原生那边取不到身份是稳定事实（没建钥、
  /// Keystore 被拒），每次轮询都去问一遍会把一条 MethodChannel 变成周期性的开销。
  bool? _signingOk;

  Future<bool> _canSign() async {
    if (_signingOk != null) return _signingOk!;
    _signingOk = await signer.probe();
    if (_signingOk == false) {
      debugPrint('[fnthink] 本机身份或签名不可用：收货暂停（不猜签名、不发未签的包）');
    }
    return _signingOk!;
  }

  /// 进程内 nonce：Crockford 字母表中不出现的 `I L O U` 这里无所谓（nonce 不是凭证、
  /// 也不给人抄），但**必须跨重启不重复** —— 服务端去重窗口有 900 秒，而"重启后从 0 开始
  /// 计数"会让老 nonce 在窗口内被当成新请求。随机 12 字节把这个概率压到可以不管。
  static String _secureNonce() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(12, (_) => rnd.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  void dispose() {
    _client.close();
  }
}

/// 一次轮询的结果（内核那个类的对外形状，多了"这一轮该做什么"的可读解释）。
class FnthinkReceiveOutcome {
  const FnthinkReceiveOutcome({
    required this.status,
    this.messages = const [],
    this.receipts = const [],
    this.pending = 0,
    this.pairRequests = const [],
    required this.nextDelay,
    this.signedWhileUncalibrated = false,
    this.reason,
  });

  final FnthinkPollStatus status;
  final List<FnthinkDelivered> messages;
  final List<FnthinkReceipt> receipts;
  final int pending;
  final List<Object?> pairRequests;
  final Duration nextDelay;

  /// 还没学到服务端时间就签了这一发 —— 值得让 UI 说一次"请先校准设备时钟"，
  /// 而不是让用户面对一条无限的"连接失败"。
  final bool signedWhileUncalibrated;
  final String? reason;

  bool get ok => status == FnthinkPollStatus.ok;

  /// 给日志与界面用的一句话结论（不含任何凭证）。
  String get summary {
    if (!ok) return '${status.name}${reason == null ? '' : '（$reason）'}';
    final parts = <String>['取到 ${messages.length} 条'];
    if (receipts.isNotEmpty) parts.add('回执 ${receipts.length} 条');
    if (pending > 0) parts.add('队列还有 $pending 条');
    if (signedWhileUncalibrated) parts.add('时间未校准');
    return parts.join('，');
  }
}

/// 注入点：内核只要"给我字节，我还你 base64 签名"，外加一次"你到底签不签得出来"的探测。
///
/// 探测不是多余的：原生那两枚方法在失败时返回 null / 抛 PlatformException，而"返回 null"
/// 与"签出来一个空串"必须走同一条路（都算不可用），否则会出现发了一个空签名的包出去。
abstract class FnthinkIdentitySigner {
  /// 规范化字节 → base64 裸签名。签不出来要抛（内核会把它分类成失败，不会发未签的包）。
  Future<String> call(List<int> canonicalBytes);

  /// 本机是否具备签名能力（一次性判定）。
  Future<bool> probe();
}

/// 用 App 里那个 `FnthinkIdentityService` 实现签名注入点。
///
/// 这里**不另设一个抽象身份服务**：那个抽象除测试之外没有第二个实现者，而它一旦存在，
/// "真机上的签名到底取不取得到"就变成只在测试里被回答的问题（本仓为这类空抽象记过几次账）。
class FnthinkKeystoreSigner implements FnthinkIdentitySigner {
  FnthinkKeystoreSigner(this._identity);

  final FnthinkIdentityService _identity;

  @override
  Future<String> call(List<int> canonicalBytes) async {
    final signature = await _identity.signCanonicalBytes(canonicalBytes);
    if (signature == null || signature.isEmpty) {
      throw StateError('本机签名不可用（不发出未签名的包）');
    }
    return base64Encode(signature);
  }

  @override
  Future<bool> probe() => _identity.canSign();
}
