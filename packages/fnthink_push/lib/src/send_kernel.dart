import 'dart:async';

import 'canonical_bytes.dart';
import 'contract.dart';
import 'receive_kernel.dart' show FnthinkReply, FnthinkSigner, FnthinkTransport;
import 'title_envelope.dart';

/// 一次发送的结论。**每一种的下一步不一样**，所以不能用一个 bool 糊过去：
///  - [accepted]：服务端收下了（还不等于送达，送达只有 ack 那一条路）；
///  - [rejectedUnsigned]：签名没被认（身份未证明那一段只有一句话，分不出"没这台设备"与"签名不对"）；
///  - [rejectedCapability]：身份过了而这一步不许（没配对、档位不够、type 不在词表、item 没勾）；
///  - [replayed]：nonce 撞了 ⇒ 换一个重签，别重放同一串字节；
///  - [needsCalibration]：`ts` 超出容差 ⇒ 先学到服务端时间再说；
///  - [rateLimited]：等 `Retry-After`，**不是这条消息没了**；
///  - [transportError]：连不上，什么都没发生；
///  - [signingUnavailable]：**本机签不出来**（KeyStore 里没有私钥、原生不肯签）。必须与
///    [transportError] 分开：前者要的是"去配对 / 去重置三件套"，后者要的是"等网络恢复"，
///    合并之后用户会一直等一个不会自己好的东西；
///  - [preconditionFailed]：**本机还没就绪**（没有三件套、服务地址不合法、契约读不出或不自洽）。
///    与 [signingUnavailable] 是同一家族，但那一档说的是"身份在而私钥取不到"（重置三件套能修），
///    这一档说的是"配置层就没配好"（要去页面把地址与开关补上）。合并之后给用户的建议就会错。
///  - [badInput]：**这一条本身发不出去**（标题或正文里有签名字段的分隔符、type 不在能力词表）。
///    与 [signingUnavailable] 的分别是"改内容"还是"改本机状态"：这一种重试一百次也是同一个结果，
///    而界面上如果只说"发送失败"，用户会去点第二下而不是去看正文里那个看不见的字符。
///  - [unparseable]：状态码看懂了而载荷看不懂（没有 messageId 的"收下"不能算收下）。
enum FnthinkSendStatus {
  accepted,
  rejectedUnsigned,
  rejectedCapability,
  replayed,
  needsCalibration,
  rateLimited,
  transportError,
  signingUnavailable,
  preconditionFailed,
  badInput,
  unparseable,
}

class FnthinkSendResult {
  const FnthinkSendResult({
    required this.status,
    this.messageId,
    this.receipt,
    this.action,
    this.evicted = const [],
    this.retryAfterSeconds,
    this.signedWhileUncalibrated = false,
    this.reason,
  });

  final FnthinkSendStatus status;

  /// 服务端给的那条 id —— 之后追状态、收回执都靠它。`accepted` 时一定有（没有就不算 accepted）。
  final String? messageId;

  /// 回执词（来自契约 `receipts` 那张词表）。
  final String? receipt;

  /// `new` / `refreshed` / `duplicate`（服务端 `enqueue` 的三种动作）。
  final String? action;

  /// 因为每设备上限被挤掉的那些条的 id。
  ///
  /// 把它们带回来不是装饰：发送端是唯一能看见"我上一条被丢了"的地方。服务端那边各条已经写了
  /// `dropped` 回执，下一次 poll 也会拿到 —— 这一份只是让**点发送的那个人**当场就知道，
  /// 而不是三天后去翻收件箱发现少了一条。
  final List<String> evicted;

  final int? retryAfterSeconds;

  /// 签的时候还没学到服务端时间（校准前那一发的诚实标记，与收货内核同一条纪律）。
  final bool signedWhileUncalibrated;

  /// 只给日志与界面的一句话原因，不含任何凭证。
  final String? reason;

  bool get accepted => status == FnthinkSendStatus.accepted;
}

/// 设备侧发送的**内核**（§4 第 10 条：配对设备逐条签名投给另一台设备）。
///
/// 与收货内核一样，这里一个 IO 都没有：签名与传输由调用方注入。
/// `ts` 也从外面给（`signedTimestamp`）—— 时钟偏移只有收货那一侧学得会（`serverTime` 从
/// poll 响应里来），这里再造一份偏移就是第二份真值，而两份偏移的差别会在"一端 410 一端正常"
/// 那一天暴露。
///
/// ⚠ 三条不是风格选择的判据：
///  ① **顶层不带 `title`**。签名字节里没有 title，而服务端是**整段比对**才收标题的，
///     所以顶层那个 title 一定被丢掉。既然一定丢，就不许"顺手带上试试"：那会让下一个读代码的人
///     以为它有用，而真正的标题在 body 的信封里。
///  ② **标题走 [FnthinkTitleEnvelope]，且分隔符不许出现在标题或正文里**。规范化函数见到
///     `signature.separator` 就抛（防伪边界）。带标题时那串会被 JSON 转义掉、不带标题时不会 ——
///     同一段文字"有时发得出去有时抛"是最难复现的一类缺陷，所以在这里对称地拒掉。
///  ③ **`type` 必须在契约的能力词表里**。词表外的 type 服务端会拒，但拒之前它已经是一次
///     签名、一次网络往返、一条 403 留痕；而客户端当场就能说清"你要发的是 `poll` 那一类事件，
///     不是消息" —— 这句话只有在这里说得出。
class FnthinkSendKernel {
  FnthinkSendKernel({
    required this.contract,
    required this.addressCode,
    required FnthinkSigner signer,
    required FnthinkTransport transport,
    required String Function() signedTimestamp,
    String Function()? nonceFactory,
  }) : _signer = signer,
       _transport = transport,
       _signedTimestamp = signedTimestamp,
       _nonceFactory = nonceFactory {
    // 装配期就把"这一发要发到哪"判掉：apiPaths 是设备面路径的唯一出处，缺 `message` 那一条
    // 时接线层要到第一次发送才炸，而炸出来的会是"传输异常"—— 把契约与实现不匹配伪装成网络抖动。
    if (!contract.apiPaths.containsKey('message')) {
      throw StateError(
        '契约 transport.apiPaths 里没有 message：设备发送那一发没有地址可发，'
        '而它不许自己拼路径（两边各写一份就是"服务端换了门、客户端还在敲旧门"）',
      );
    }
  }

  final FnthinkContract contract;

  /// 本机地址码：这一发的 `sender`，也是服务端查白名单的主键。
  final String addressCode;

  final FnthinkSigner _signer;
  final FnthinkTransport _transport;
  final String Function() _signedTimestamp;
  final String Function()? _nonceFactory;

  String? _lastReason;

  String? get lastReason => _lastReason;

  /// 参与签名的字段（顺序与名字都来自契约）。抽出来是为了让它**可断言**：
  /// 少一个键或多一个键都是换签名字节，而换签名字节在服务端只会得到一句同形的 403。
  Map<String, Object?> messageFields({
    required String type,
    required String target,
    required String wireBody,
    required String nonce,
    String? ts,
  }) {
    return {
      'version': contract.protocolVersionForSignature,
      'type': type,
      'target': target,
      'ts': ts ?? _signedTimestamp(),
      'nonce': nonce,
      'body': wireBody,
    };
  }

  /// 发一条。运行期的失败一律进 [FnthinkSendResult.status]（调用方的下一步取决于哪一种），
  /// 而**契约与实现不匹配**那一类照原样抛（canonicalOrder 少了 / 多了字段、值含分隔符、
  /// type 不在能力词表）：把"本包解释不了这份契约"伪装成"今天网络不好"是最坏的一种归并。
  Future<FnthinkSendResult> send({
    required String target,
    required String type,
    required String title,
    required String text,
  }) async {
    if (!contract.messageTypeLevels.containsKey(type)) {
      throw ArgumentError(
        'type「$type」不在契约 capabilities.messageTypes 的词表里：'
        '设备面事件那一类词（poll / ack / pair…）不是消息类型，拿它们发一条消息会被判能力不足',
      );
    }
    final separator = contract.signatureSeparator;
    for (final entry in {'title': title, 'text': text}.entries) {
      if (entry.value.contains(separator)) {
        throw ArgumentError(
          '${entry.key} 含签名字段分隔符：分隔符能出现在被签字段的值里，'
          '就等于能拼出与另一组字段完全相同的字节串（那是签名伪造的入口，不是边角情况）',
        );
      }
    }
    if (target.contains(separator)) {
      throw ArgumentError('target 含签名字段分隔符（同上一条）');
    }

    final nonce = (_nonceFactory ?? _fallbackNonce)();
    final wireBody = FnthinkTitleEnvelope.encode(
      contract,
      title: title,
      body: text,
    );
    final fields = messageFields(
      type: type,
      target: target,
      wireBody: wireBody,
      nonce: nonce,
    );
    // 形状问题在这里**照原样抛**（契约的 canonicalOrder 与实现给的字段名单不匹配、值含分隔符）：
    // 那不是"本机签不出来"，也不是"网络不通"。归进任何一种状态，都是在把
    // "这份契约本包解释不了"伪装成"今天运气不好"—— 后者用户会再试一次，前者不会自己好。
    final bytes = CanonicalMessage.bytes(contract, fields);
    final String signature;
    try {
      signature = await _signer(bytes);
    } catch (e) {
      // 签名这一段抛的还没进网络。归 signingUnavailable 而不是 transportError：
      // "本机签不出来"与"网络不通"给用户的下一句完全不同（前者是重置三件套 / 重新配对，
      // 后者是等一等），合并成一类就是把不会自己好的那种病说成会自己好的那一种。
      _lastReason = 'signing:${e.runtimeType}';
      return FnthinkSendResult(
        status: FnthinkSendStatus.signingUnavailable,
        reason: _lastReason,
      );
    }
    // 顶层**只有** sender / signature / fields 三个键。不放 title、item、dedupeId：
    // 那三个都不在被签的六个字段里，放了也一定被服务端丢掉（`item` 更是服务端明确要拒的）。
    final envelope = <String, Object?>{
      'sender': addressCode,
      'signature': signature,
      'fields': fields,
    };

    final FnthinkReply reply;
    try {
      reply = await _transport(envelope);
    } catch (e) {
      _lastReason = 'transport:${e.runtimeType}';
      return FnthinkSendResult(
        status: FnthinkSendStatus.transportError,
        reason: _lastReason,
      );
    }
    return interpret(reply);
  }

  FnthinkSendResult interpret(FnthinkReply reply) {
    final codes = contract.statusCodes;
    final receipt = reply.body['receipt'];
    final receiptText = receipt is String ? receipt : null;

    if (reply.status == codes['rateLimited']) {
      _lastReason = 'rate-limited:${reply.retryAfterSeconds ?? 'unknown'}';
      return FnthinkSendResult(
        status: FnthinkSendStatus.rateLimited,
        receipt: receiptText,
        retryAfterSeconds: reply.retryAfterSeconds,
        reason: _lastReason,
      );
    }
    if (reply.status == codes['expired']) {
      _lastReason = 'ts-expired-needs-calibration';
      return FnthinkSendResult(
        status: FnthinkSendStatus.needsCalibration,
        receipt: receiptText,
        reason: _lastReason,
      );
    }
    if (reply.status == codes['duplicate']) {
      _lastReason = 'nonce-replayed';
      return FnthinkSendResult(
        status: FnthinkSendStatus.replayed,
        receipt: receiptText,
        reason: _lastReason,
      );
    }
    if (reply.status == codes['unauthorized'] ||
        reply.status == codes['forbidden']) {
      // 403 在这一面上有两种说法，而且**只在身份证明之后**才分得开：
      // `rejected_unsigned` = 没认你这把钥匙；`rejected_capability` = 认得了而这一步不许。
      // 判据取自契约的回执词表，不在这里写字面量 —— 词表改了而这里还在比旧词，
      // 表现是把"没配对"报成"签名坏了"，用户会去重启 App 而不是去配对。
      final unsigned = contract.unsignedReceipt;
      final isCapability =
          receiptText != null &&
          receiptText != unsigned &&
          contract.receipts.contains(receiptText);
      _lastReason = isCapability
          ? 'capability:$receiptText'
          : 'unsigned-or-unknown';
      return FnthinkSendResult(
        status: isCapability
            ? FnthinkSendStatus.rejectedCapability
            : FnthinkSendStatus.rejectedUnsigned,
        receipt: receiptText,
        reason: _lastReason,
      );
    }
    if (reply.status == codes['queued']) {
      final id = reply.body['messageId'];
      if (id is! String || id.isEmpty) {
        // "收下了"而没有 id = 这一条从此追不回来。不猜一个 id，也不报成功。
        _lastReason = 'accepted-without-message-id';
        return FnthinkSendResult(
          status: FnthinkSendStatus.unparseable,
          receipt: receiptText,
          reason: _lastReason,
        );
      }
      _lastReason = null;
      return FnthinkSendResult(
        status: FnthinkSendStatus.accepted,
        messageId: id,
        receipt: receiptText,
        action: reply.body['action'] is String
            ? reply.body['action'] as String
            : null,
        evicted: _idList(reply.body['evicted']),
        reason: null,
      );
    }
    _lastReason = 'unexpected-status:${reply.status}';
    return FnthinkSendResult(
      status: FnthinkSendStatus.unparseable,
      receipt: receiptText,
      reason: _lastReason,
    );
  }

  List<String> _idList(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is String) item,
    ];
  }

  /// 默认 nonce：**只防自己重发，不防跨重启重放**（进程内单调计数）。
  /// 生产接线必须注入 `nonceFactory`（与收货内核同一条纪律，理由见那里的注释）。
  int _fallbackCounter = 0;
  String _fallbackNonce() {
    _fallbackCounter += 1;
    return 'local-$_fallbackCounter';
  }
}
