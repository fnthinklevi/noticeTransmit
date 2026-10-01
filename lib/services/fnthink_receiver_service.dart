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
    this.pollIntervalSeconds,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client(),
       _nonce = nonceFactory ?? _secureNonce {
    // 装配期就把"能不能发出第一发"判掉，而不是等第一次轮询：https 与 apiPaths 都是
    // **配置事实**，不是运行时状态。留到第一次发送才炸，会被内核的 catch 归成"传输异常"
    // —— 那是把契约与实现不匹配伪装成网络抖动（我这条就是被用例逼出来的）。
    for (final kind in [
      'poll',
      'ack',
      // 自登记（#177）：它是其余每一发的**共同前置** —— 服务端按设备表里那把钥匙验签，
      // 而表里那一行只能由这一发建。缺它时每一次请求都换回同形的 403，而看的人只会以为
      // "口令/签名错了"（真机上就是这么现形的）。
      'register',
      'pairArm',
      'pairConfirm',
      'pairRevoke',
      'endpointCreate',
      'endpointList',
      'endpointRevoke',
      'endpointRotate',
      // 投递面也在这张名单里，但它**不是一种事件**：那一条的签字节 `type` 取自能力词表
      // （notice / action / setting），所以下面的反查为它单独兜了一档。登记进名单要的是
      // "装配期就确认这条路存在"——缺它时第一次发送会在运行时炸成一句看起来像网络故障的话。
      'message',
    ]) {
      if (!contract.apiPaths.containsKey(kind)) {
        throw ArgumentError(
          '契约的 transport.apiPaths 少了 $kind：收货、配对与端点那几发要发这几种请求，缺一种就是整条链断在那一步',
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

  /// 本机那一档常态收取间隔（T88），null = 用户没选过 ⇒ 内核用契约的 default。
  /// 这里只是将设置里读到的值转交，范围判据在设置层与内核构造处各判一次（同一对 min/max）。
  final int? pollIntervalSeconds;

  FnthinkReceiveKernel? _kernel;

  /// 懒建：第一次用到才建，因为建内核会读契约那几个数（缺就抛）。装配期抛与第一次
  /// 轮询时抛，对用户的差别是"App 打不开"与"这一项功能不可用 + 说得清原因"。
  FnthinkReceiveKernel get kernel => _kernel ??= FnthinkReceiveKernel(
    contract: contract,
    addressCode: addressCode,
    signer: signer.call,
    transport: _transport,
    nonceFactory: _nonce,
    pollIntervalSeconds: pollIntervalSeconds,
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
    // 设备自己发一条消息时，被签的那个 `type` 是**能力词表**里的一个（notice / action / setting），
    // 不是 clientEvents 那个事件词表里的（契约 `clientEvents.notInCapabilitiesVocabulary` 钉的就是
    // 这两张表不许重合）。所以它按上面那圈反查必然落空 —— 落空之后**不许"随便挑一条路发过去"**，
    // 只认这一条：投递面那扇门，路径仍从契约读。
    if (contract.messageTypeLevels.containsKey(type)) {
      return contract.apiPath('message');
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
    // ⚠ 只按 UTF-8 解，**不走 `response.body`**（T85a）。实测过 `package:http` 的行为再写：
    // 没有 `charset` 时，**`text/*` 与干脆没有 content-type 的响应用 latin-1 解**，
    // `application/json` 那一档它已经按 UTF-8 解。所以今天线上是好的，坏的路径是
    // "反代/CDN/WAF 把类型改成 text/plain、或整段吃掉 content-type"那一刻 ——
    // 那时 UTF-8 的中文会**被"解成功"成 mojibake**，然后被当成真内容落进收件表、上通知栏。
    // `allowMalformed: false` = 字节不是合法 UTF-8 就抛：宁可不解析，也不替换成 U+FFFD ——
    // 静默替换才是那条"看起来收到了，但字是坏的"的路。
    String? text;
    if (response.bodyBytes.isNotEmpty) {
      try {
        text = utf8.decode(response.bodyBytes, allowMalformed: false);
      } on FormatException {
        // 内容读不出，但**状态码照旧分类**（403/429 这些不依赖正文）。
        // 不许在这里"退回按 latin-1 再解一遍"：那等于把上面那条判据反着写。
        text = null;
      }
    }
    if (text != null) {
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

  /// 设备自登记（#177）。**所有签名请求的共同前置**。
  ///
  /// 名字由调用方给（协调者从设备信息服务取），公钥**只从签名口取** —— 那是"与私钥成对"
  /// 的唯一来源；从别处（比如名单里对端的公钥）拿一把来交，表现与"没登记"同形。
  ///
  /// 与其余几发共用那两道闸：**签不出来就不发**（另加"没有公钥就不发"这一道：
  /// 没有身份的机器去登记，服务端只会回一句与签名不对同形的 403）。
  Future<FnthinkRegisterResult> register({required String name}) async {
    if (!await _canSign()) {
      return FnthinkRegisterResult(
        status: FnthinkPollStatus.failed,
        reason: 'signing-unavailable',
        signedWhileUncalibrated: !kernel.calibrated,
      );
    }
    final publicKey = await signer.publicKey();
    if (publicKey == null || publicKey.isEmpty) {
      return FnthinkRegisterResult(
        status: FnthinkPollStatus.failed,
        reason: 'no-public-key',
        signedWhileUncalibrated: !kernel.calibrated,
      );
    }
    return kernel.register(publicKey: publicKey, name: name);
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

  /// 把一个发送方从本机白名单里划掉（`/pair-revoke`，T31 B 片）。
  ///
  /// 与 [pairConfirm] 共用那两道闸：**签不出来就不发**、URL 从契约反查。
  /// `peer` 同时是签名的 `target` 与载荷里那个地址 —— 这一发在本机就只有一个参数，
  /// 所以"两处写岔"不是调用方要负责的事（服务端判的是两者必须逐字相等）。
  ///
  /// ⚠ 这道 `_canSign()` 短路今日**不可单独观察**：协调者的 `_resolveSpec` 在它之前已经
  ///   探过一次签名能力（反证 U6 把这里摘掉，全场仍绿，报告在 `outputs/_revokepeer.report.txt`）。
  ///   按规矩登记成纵深防御（防的是以后有人从别处直接调这一发），不登记成"已验证"。
  Future<FnthinkPairRevokeResult> pairRevoke({required String peer}) async {
    if (!await _canSign()) {
      return FnthinkPairRevokeResult(
        status: FnthinkPollStatus.failed,
        reason: 'signing-unavailable',
        signedWhileUncalibrated: !kernel.calibrated,
      );
    }
    return kernel.pairRevoke(peer: peer);
  }

  /// 给自己建一条接入端点（`/endpoint-create`，T42 第七片）。
  ///
  /// 与其余几发共用那两道闸（签不出来就不发、URL 从契约反查）。⚠ 这一发的**返回值里带着
  /// 一把明文口令**，而它只在这一次出现：本层不落盘、不日志、不缓存，转交就完了
  /// （把"顺手存一下方便显示"做进来，等于把这把长期口令写进 prefs —— 而 prefs 会跟着备份走）。
  Future<FnthinkEndpointCreateResult> endpointCreate({
    required String name,
  }) async {
    if (!await _canSign()) {
      return FnthinkEndpointCreateResult(
        status: FnthinkPollStatus.failed,
        reason: 'signing-unavailable',
        signedWhileUncalibrated: !kernel.calibrated,
      );
    }
    return kernel.endpointCreate(name: name);
  }

  /// 读自己名下那几把接入端点（`/endpoint-list`，#157 第二片）。
  ///
  /// 它是这一格里**唯一会往界面上画别人名下的东西**的那一发 —— 所以两道 `_canSign()` 之外的
  /// 判据都在内核里（owner 必须是自己、状态必须在词表上），这一层只负责"签不出来就不发"。
  /// ⚠ 读回来的那份**不落盘**：端点表在服务端，本机存一份就是一本会漂的账（在服务端吊销之后，
  ///   本机那本还会说"你还在用"）。每次要显示就重新读。
  ///
  /// 反证 **Z9**（`outputs/_eplist2.report.txt`）：把装配期判定名单里的 `endpointList` 删掉 ⇒
  /// 红在装配守卫「服务层装配判定里含 endpointList」。⚠ 它与 U6 不同，这一条今天能单独观察到：
  /// 摘掉之后构造期不再核对那条路径，而 `_pathForEnvelope` 是**运行时**按 messageType 反查的，
  /// 所以守卫抓到的是"这个判定漏了一类"，不是"发不出去"。
  /// 同理，这一层那道 `_canSign()` 短路仍按 U6 的登记看待（协调者先拦，今日不可单独观察）。
  Future<FnthinkEndpointListResult> endpointList() async {
    if (!await _canSign()) {
      return FnthinkEndpointListResult(
        status: FnthinkPollStatus.failed,
        reason: 'signing-unavailable',
        signedWhileUncalibrated: !kernel.calibrated,
      );
    }
    return kernel.endpointList();
  }

  /// 关掉自己名下一条接入端点（`/endpoint-revoke`，#157 第四片）。
  ///
  /// 这一发**只有一个参数、也不带回任何凭证形状的东西**，所以本层没有新的红线要守；
  /// 真正的判据（owner 核查、两种失败同形、幂等）都在服务端那一边，那里已反证过（RV1–RV8）。
  /// 与其余几发同样：签不出来就不发（那道短路与 U6 同案 —— 协调者先拦，今日不可单独观察，
  /// 按纵深防御登记，不登记成"已验证"）。
  ///
  /// 反证 **SA4**（`outputs/_eprv2.report.txt`）：装配判定名单里删掉 `endpointRevoke` ⇒
  /// 红在装配守卫「服务层装配判定里含 endpointRevoke」。摘掉之后行为上暂时还是通的
  /// （路径靠 messageType 反查），所以这一条只能由守卫看着那张名单本身 —— 它防的是
  /// "以后有人把反查换成查表，而这一类从来没登记过"。
  Future<FnthinkEndpointRevokeResult> endpointRevoke({
    required String endpointId,
  }) async {
    if (!await _canSign()) {
      return FnthinkEndpointRevokeResult(
        status: FnthinkPollStatus.failed,
        endpointId: endpointId,
        reason: 'signing-unavailable',
        signedWhileUncalibrated: !kernel.calibrated,
      );
    }
    return kernel.endpointRevoke(endpointId: endpointId);
  }

  /// 换那把入口的长期口令（`/endpoint-rotate`，#157 第六片）。
  ///
  /// ⚠ 这一发的**返回值里带一把新的明文口令**，与 [endpointCreate] 同一条红线：本层不落盘、
  /// 不日志、不缓存，转交就完了。差别只有一句：创建那一次错过是"没有这把入口"，
  /// 轮换这一次错过是"原来那把已经不能用了而新的没人知道" —— 后者更糟，所以内核把
  /// "`rotated:true` 而读不出口令"单独报成一个 reason，不并回"没换成"。
  ///
  /// 反证 **RC4**（`outputs/_erot2.report.txt`）：装配判定名单里删掉 `endpointRotate` ⇒
  /// 红在装配守卫「服务层装配判定里含 endpointRotate」。与 SA4 同一族：摘掉之后行为仍走得通
  /// （路径是按 messageType 反查的），所以这条守卫看着的是那张名单本身 —— 它防的是
  /// "以后有人把反查换成查表，而这一类从来没登记过"。
  Future<FnthinkEndpointRotateResult> endpointRotate({
    required String endpointId,
  }) async {
    if (!await _canSign()) {
      return FnthinkEndpointRotateResult(
        status: FnthinkPollStatus.failed,
        endpointId: endpointId,
        reason: 'signing-unavailable',
        signedWhileUncalibrated: !kernel.calibrated,
      );
    }
    return kernel.endpointRotate(endpointId: endpointId);
  }

  FnthinkSendKernel? _sendKernel;

  /// 发送内核（§4-10 片2）。它与收货内核**共用同一把 `ts`**：偏移只能从带 `serverTime` 的
  /// 响应里学，而那是收货那一侧的事 —— 这里再造一份偏移就是第二个真值，表现是"收货正常、
  /// 发送一路 410"（或反过来）。nonce 也共用同一个工厂：两类事件在同一个
  /// `sender|nonce` 去重空间里（契约 `clientEvents.nonceSpaceSharedWithMessages`），
  /// 各起一个计数器迟早撞一次，而撞的那次被服务端判成重放。
  FnthinkSendKernel get sendKernel => _sendKernel ??= FnthinkSendKernel(
    contract: contract,
    addressCode: addressCode,
    signer: signer.call,
    transport: _transport,
    signedTimestamp: () => kernel.signedTimestamp,
    nonceFactory: _nonce,
  );

  /// 发一条给名单里那台设备（`/message`，§4-10 片2 的接线层）。
  ///
  /// 这一层只判两件事，其余判据都在内核：
  ///  ① **签不出来就不发**（与其余几发同一条闸 —— 一个未签名的包都不许离机）；
  ///  ② **输入形状**（标题/正文里含签名字段的分隔符）翻成一句能显示的话，而不是让页面
  ///     去 `catch` 一个 `ArgumentError`：内核那条判据是对的（那是防伪边界），
  ///     但它的表达方式必须是状态与原因，否则每个调用方都会自己写一遍 try/catch，
  ///     而其中一处漏写就是把崩溃交给用户。
  ///
  /// ⚠ `type` 不在这里当参数传：今日这一格只发纯文本通知（`notice`，配对即有的 L1）。
  /// 做成可选参数就等于允许页面传 `action`/`setting` —— 那两档要逐条勾选的 `item`，
  /// 而设备这一路今日没有那个东西（服务端会回 403，用户看到的是一句莫名其妙的"没权限"）。
  Future<FnthinkSendResult> sendNotice({
    required String peer,
    required String title,
    required String text,
  }) async {
    if (!await _canSign()) {
      return FnthinkSendResult(
        status: FnthinkSendStatus.signingUnavailable,
        reason: 'signing-unavailable',
        signedWhileUncalibrated: !kernel.calibrated,
      );
    }
    final type = contract.messageTypeLevels.keys.firstWhere(
      (t) => t == 'notice',
      orElse: () => throw StateError(
        '契约 capabilities.messageTypes 里没有 notice：这一发要用的那个词不在词表上，'
        '换词就是换权限，不许在代码里补一个',
      ),
    );
    try {
      return await sendKernel.send(
        target: peer,
        type: type,
        title: title,
        text: text,
      );
    } on ArgumentError catch (e) {
      return FnthinkSendResult(
        status: FnthinkSendStatus.badInput,
        reason: 'input:${e.message}',
        signedWhileUncalibrated: !kernel.calibrated,
      );
    }
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

  /// 这一轮 poll 带回来的**等本机答复的配对请求**（`pairRequest.pollKey` 那一项）。
  /// 类型是内核解析过的那一种，不是 `Object?`：留成 `Object?` 的话，"少一个键"这件事
  /// 要等到页面动手到一半才发现，而它的表现是那一栏永远是空的。
  final List<FnthinkPairRequest> pairRequests;
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
    if (pairRequests.isNotEmpty) {
      parts.add('待本机答复的配对请求 ${pairRequests.length} 条');
    }
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

  /// 本机公钥（base64 裸 32 字节；就是原生那枚 `getFnthinkIdentity` 交出来的那一把）。
  ///
  /// 自登记是唯一要把公钥**交出去**的一发，而它必须与签名私钥成对 —— 所以它只能从这里取。
  /// null = 这台还没有身份（与 `probe()==false` 同一种事实）。
  Future<String?> publicKey();
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

  @override
  Future<String?> publicKey() async => (await _identity.identity())?.publicKey;
}
