import 'package:flutter/foundation.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:http/http.dart' as http;

import '../models/fnthink_inbox_message.dart';
import 'fnthink_contract_loader.dart';
import 'fnthink_credential_store.dart';
import 'fnthink_receive_loop.dart';
import 'fnthink_receiver_service.dart';
import 'fnthink_settings.dart';

/// 一次启动请求的结论。**reason 总是有值**：started 之外每一种都要能被界面原样说给用户 ——
/// "为什么没在收货"是这类后台功能最常被问的一句，而答案是"不知道"就等于没做。
typedef FnthinkStartResult = ({bool started, String reason});

/// 装配一次收货循环需要的东西（也是生产构造函数的入参形状）。
class FnthinkLoopSpec {
  const FnthinkLoopSpec({
    required this.contract,
    required this.baseUri,
    required this.addressCode,
    required this.signer,
    required this.persist,
    this.display,
    this.recordAck,
    this.client,
  });

  final FnthinkContract contract;
  final Uri baseUri;
  final String addressCode;
  final FnthinkIdentitySigner signer;
  final Future<bool> Function(FnthinkInboxMessage message) persist;

  /// 把这条收件显示进通知栏；null = 这台设备还没有显示链路（循环会一律按 delivered 报）。
  final Future<bool> Function(FnthinkInboxMessage message)? display;

  /// 服务端收下 ack 之后，把结论记进收件表（`ack_result` / `acked_at`）。
  final Future<bool> Function({
    required String messageId,
    required String result,
    required int at,
  })?
  recordAck;

  final http.Client? client;
}

typedef FnthinkLoopFactory = FnthinkReceiveLoop Function(FnthinkLoopSpec spec);

/// 生产装配：收货服务（HTTP + 签名 + nonce）→ 收货循环（顺序与后果）。
///
/// 单独拎出来是为了**让测试打得到**："拼出来的地址到底是哪扇门"这件事要是藏在
/// coordinator 的一行 `return FnthinkReceiveLoop(...)` 里，就只有真机能回答它了。
FnthinkReceiveLoop buildFnthinkReceiveLoop(FnthinkLoopSpec spec) {
  final service = FnthinkReceiverService(
    contract: spec.contract,
    baseUri: spec.baseUri,
    signer: spec.signer,
    addressCode: spec.addressCode,
    client: spec.client,
  );
  return FnthinkReceiveLoop(
    poll: service.pollOnce,
    ack: (messageId, result) =>
        service.ack(messageId: messageId, result: result),
    persist: spec.persist,
    display: spec.display,
    recordAck: spec.recordAck,
  );
}

/// 把「契约 + 设置 + 本机凭证 + 收件表 + 收货循环」接成一个能启停的东西（#126 第四片）。
///
/// 这一层**不判断任何协议语义**，只回答三件事：能不能开始、为什么不能、现在在跑吗。
/// 节奏在契约与内核里，顺序在循环里，内容怎么落进收件表由 `persist` 决定 ——
/// 这里一旦出现第四个"如果状态是 403 就…"，那份判据就有两处了。
///
/// ⚠ 五种"起不来"各有各的成因，必须分开说（它们对应五种不同的用户动作）：
///  - `disabled`：总开关关着（默认就是关的，见 [FnthinkSettings]）。关掉 = 既不发送也不接收。
///  - `contract-unavailable`：随包契约读不到 / 不合法 / 这一包解释不了 ⇒ **整体停手**，不重试成静默降级。
///  - `settings-invalid`：服务地址这一项不可用（手填错，或备份恢复灌回来一个坏值）。
///  - `credential-corrupted`：本机地址码存量过不了契约校验 ⇒ 抛给人看，**不自动换一枚**。
///  - `signing-unavailable`：原生取不到签名（没建钥 / Keystore 被拒）。这是**身份**问题不是网络问题 ——
///    混在一起的表现是"提示用户检查网络"，而网络一直是好的。
///
/// 顺序也是判据之一：契约先于设置（设置项的默认值要从契约读），设置先于签名探测
/// （关着的时候不该去向 KeyStore 要一次签名能力 —— 那是把"这个功能没开"变成"系统在后台悄悄动钥匙"）。
class FnthinkReceiveCoordinator {
  FnthinkReceiveCoordinator({
    required this.contracts,
    required this.signer,
    required this.persist,
    this.display,
    this.recordAck,
    FnthinkSettings Function(FnthinkContract contract)? buildSettings,
    FnthinkCredentialStore Function(FnthinkContract contract)? buildCredentials,
    FnthinkLoopFactory? loopFactory,
  }) : _buildSettings =
           buildSettings ?? ((contract) => FnthinkSettings(contract: contract)),
       _buildCredentials =
           buildCredentials ??
           ((contract) => FnthinkCredentialStore(contract: contract)),
       _loopFactory = loopFactory ?? buildFnthinkReceiveLoop;

  final FnthinkContractLoader contracts;
  final FnthinkIdentitySigner signer;
  final Future<bool> Function(FnthinkInboxMessage) persist;

  /// 收件显示（通知栏）。与 persist 一样是"能不能报 displayed"的唯一依据，见 [FnthinkReceiveLoop] 的 ⑤。
  final Future<bool> Function(FnthinkInboxMessage)? display;

  /// 服务端收下 ack 后写进收件表的那一列（与 [display] 同理：不接就是没人写，别显示）。
  final Future<bool> Function({
    required String messageId,
    required String result,
    required int at,
  })?
  recordAck;
  final FnthinkSettings Function(FnthinkContract) _buildSettings;
  final FnthinkCredentialStore Function(FnthinkContract) _buildCredentials;
  final FnthinkLoopFactory _loopFactory;

  FnthinkReceiveLoop? _loop;

  bool get isRunning => _loop?.isRunning ?? false;

  /// 按当前设置决定要不要开始。已经在跑就是幂等 ——
  /// 两个循环读同一条队列的表现是同一条 ack 两次、未读数上下跳。
  Future<FnthinkStartResult> startIfEnabled() async {
    if (isRunning) return (started: true, reason: 'already-running');

    final FnthinkContract contract;
    try {
      contract = await contracts.load();
    } on FnthinkContractUnavailable catch (e) {
      return (started: false, reason: 'contract-unavailable: ${e.reason}');
    }

    final settings = _buildSettings(contract);
    if (!await settings.receiveEnabled) {
      return (started: false, reason: 'disabled');
    }

    final Uri baseUri;
    final String addressCode;
    try {
      baseUri = await settings.baseUrl;
      // 地址码在这里定一次型：循环带着它跑，半途换码（resetAddressCode）必须重启才生效 ——
      // 否则刚签出去的那一发 target 与本轮要 ack 的那条不是同一台设备。
      addressCode = (await _buildCredentials(
        contract,
      ).ensureAddressCode()).value;
    } on FnthinkSettingsInvalid catch (e) {
      return (started: false, reason: 'settings-invalid: ${e.reason}');
    } on FnthinkCredentialCorrupted catch (e) {
      return (started: false, reason: 'credential-corrupted: ${e.reason}');
    }

    if (!await signer.probe()) {
      return (started: false, reason: 'signing-unavailable');
    }

    final loop = _loopFactory(
      FnthinkLoopSpec(
        contract: contract,
        baseUri: baseUri,
        addressCode: addressCode,
        signer: signer,
        persist: persist,
        display: display,
        recordAck: recordAck,
      ),
    );
    _loop = loop;
    loop.start();
    debugPrint('[fnthink] 收货循环已启动 → $baseUri');
    return (started: true, reason: 'started');
  }

  /// 停下来。已在途的那一轮跑完为止（强行掐断等于把 ack 停在半路）。
  void stop() {
    _loop?.stop();
    _loop = null;
  }

  /// 页面上"立即收取"那一下。返回 null = 这次没做（没就绪），原因按 `startIfEnabled` 同一套口径记日志。
  /// ⚠ 它同样尊重总开关：关掉就是既不发送也不接收，手动那一下也不能把它叫醒。
  Future<FnthinkLoopReport?> receiveOnce() async {
    var loop = _loop;
    if (loop == null) {
      final result = await startIfEnabled();
      loop = _loop;
      if (loop == null) {
        debugPrint('[fnthink] 手动收取被跳过：${result.reason}');
        return null;
      }
    }
    return await loop.runOnce();
  }
}
