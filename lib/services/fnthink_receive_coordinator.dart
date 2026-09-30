import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:http/http.dart' as http;

import '../models/fnthink_inbox_message.dart';
import '../models/fnthink_peer.dart';
import 'fnthink_contract_loader.dart';
import 'fnthink_credential_store.dart';
import 'fnthink_receive_loop.dart';
import 'fnthink_receiver_service.dart';
import 'fnthink_settings.dart';

/// 一次启动请求的结论。**reason 总是有值**：started 之外每一种都要能被界面原样说给用户 ——
/// "为什么没在收货"是这类后台功能最常被问的一句，而答案是"不知道"就等于没做。
typedef FnthinkStartResult = ({bool started, String reason});

/// 服务器认了这条授权，但**本机名单那一行没写成**的三种原因。各对应一种用户动作，
/// 所以不用一个 `bool` 折叠（"没写成"与"写成了但没落盘"在用户那里是完全不同的两句）。
enum FnthinkPeerSkip {
  /// 服务端回了 200 却没有可用的档位（缺 `grantedLevel`，或那个词不在契约的档位表里）。
  /// 本机不知道该记哪一档 ⇒ 宁可不记。
  grantedLevelUnusable,

  /// 这台设备没装配落库链路（`recordPeer` 为 null）。表现是"服务器那边配好了，
  /// 本机名单里没有"，而这一格将来是取消配对的入口。
  storeUnavailable,

  /// 写的时候抛了（表被锁、磁盘满）。服务端那边**已经**结了，所以这不是"配对失败"。
  writeFailed,
}

/// 答复一条配对请求的**完整**结论：服务器那一头 + 本机名单这一行。
///
/// 分成两个字段是因为它们会各自失败：服务端收下并记到 L2、本机写名单时抛了 ⇒
/// 用户要看到的是"配好了，但这一台的名单没更新"，而不是一个笼统的"失败"（后者会让人
/// 再点一次同意，而第二次同意换回的是一句与"口令错"同形的 403）。
class FnthinkPairAnswer {
  const FnthinkPairAnswer({required this.result, this.wrote, this.skipped});

  final FnthinkPairConfirmResult result;

  /// 本机名单那一行的写法（`created` / `refreshed` / `keySwapped`）。null = 这一步没做。
  final FnthinkPeerWrite? wrote;

  /// 没做的原因（与 [wrote] 互斥）。
  final FnthinkPeerSkip? skipped;

  bool get ok => result.ok;
  String? get reason => result.reason;
}

/// 服务端**认了**这次撤销，但**本机名单那一行没删掉**的两种原因。
/// 与 [FnthinkPeerSkip] 同一族：这两件事各自会失败，折叠成一个 bool 就说不清"现在到底什么样"。
enum FnthinkPeerRemoveSkip {
  /// 这台设备没装配删行链路（`removePeer` 为 null）。表现是"对面已经推不进来了，
  /// 而这一台的名单里还留着它"——界面必须能说出来，否则用户会以为撤销没成而再点一次。
  storeUnavailable,

  /// 删的时候抛了（表被锁、磁盘满）。服务端那边**已经**撤了，所以这不是"撤销失败"。
  removeFailed,
}

/// 撤销那一发的**完整**结论：服务器那一头 + 本机名单那一行。
///
/// ⚠ 两件事的先后是判据，不是实现细节：**先撤服务端，再删本机行**。反过来（先删行）的话，
/// 服务端那一发一旦失败，本机就再也不显示这一行，而授权还留着 —— 对面照样能推进来，
/// 而屏幕上没有任何一行解释它从哪来。那正是"推送静默丢失"那一类，本仓把它列为产品不变量。
class FnthinkPeerRevoke {
  const FnthinkPeerRevoke({
    required this.result,
    this.rowRemoved,
    this.skipped,
  });

  final FnthinkPairRevokeResult result;

  /// 本机那一行**被删掉了**没有。`true` = 删掉了；`false` = 名单里本来就没有这一行
  /// （不是失败：那边撤了、这里也没东西可留）；null = 没走到这一步。
  final bool? rowRemoved;

  /// 没删的原因（与 [rowRemoved] 互斥）。
  final FnthinkPeerRemoveSkip? skipped;

  bool get ok => result.ok;
  String? get reason => result.reason;
}

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
    this.onRound,
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

  /// 每轮结束后的账（**只**用来把这一轮 poll 到的配对请求交给协调者，见 [FnthinkReceiveLoop.onRound]）。
  /// 由协调者在 `_resolveSpec` 里填 `_noteRound`，所以这里带着它出去、`buildFnthinkReceiveLoop` 再把它接上。
  final void Function(FnthinkLoopReport report)? onRound;

  final http.Client? client;
}

typedef FnthinkLoopFactory = FnthinkReceiveLoop Function(FnthinkLoopSpec spec);

/// 服务构造的唯一出处。循环与"挂口令那一发"都要一个 `FnthinkReceiverService`，
/// 两处各 new 一份的话，装配期那三道判定（apiPaths / httpsOnly / 签名）就分成了两份口径 ——
/// 表现是循环起不来而挂口令却能发出去（或反过来）。
FnthinkReceiverService buildFnthinkReceiveService(FnthinkLoopSpec spec) {
  return FnthinkReceiverService(
    contract: spec.contract,
    baseUri: spec.baseUri,
    signer: spec.signer,
    addressCode: spec.addressCode,
    client: spec.client,
  );
}

typedef FnthinkServiceFactory =
    FnthinkReceiverService Function(FnthinkLoopSpec spec);

/// 生产装配：收货服务（HTTP + 签名 + nonce）→ 收货循环（顺序与后果）。
///
/// 单独拎出来是为了**让测试打得到**："拼出来的地址到底是哪扇门"这件事要是藏在
/// coordinator 的一行 `return FnthinkReceiveLoop(...)` 里，就只有真机能回答它了。
FnthinkReceiveLoop buildFnthinkReceiveLoop(FnthinkLoopSpec spec) {
  final service = buildFnthinkReceiveService(spec);
  return FnthinkReceiveLoop(
    poll: service.pollOnce,
    ack: (messageId, result) =>
        service.ack(messageId: messageId, result: result),
    persist: spec.persist,
    display: spec.display,
    recordAck: spec.recordAck,
    onRound: spec.onRound,
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
    this.recordPeer,
    this.removePeer,
    this.presenceNotice,
    FnthinkSettings Function(FnthinkContract contract)? buildSettings,
    FnthinkCredentialStore Function(FnthinkContract contract)? buildCredentials,
    FnthinkLoopFactory? loopFactory,
    FnthinkServiceFactory? serviceFactory,
  }) : _buildSettings =
           buildSettings ?? ((contract) => FnthinkSettings(contract: contract)),
       _buildCredentials =
           buildCredentials ??
           ((contract) => FnthinkCredentialStore(contract: contract)),
       _loopFactory = loopFactory ?? buildFnthinkReceiveLoop,
       _serviceFactory = serviceFactory ?? buildFnthinkReceiveService;

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

  /// 服务端**认了**一条授权之后，把这一条写进本机配对名单（`fnthink_peers`）。
  /// null = 这台设备没装配落库链路 ⇒ 名单不写，而结论里会带着 [FnthinkPeerSkip.storeUnavailable]
  /// 说破这件事（"服务器配好了、本机名单是空的"必须能被区分出来，否则下一片那个取消配对的
  /// 入口会让人以为对面已经推不进来了）。
  ///
  /// ⚠ 这一行是 `fnthink_peers` 在**生产代码里的第一个写入者**（表与 `upsertFnthinkPeer` 早就有了，
  /// 但没有作者时它只是一张空表）。装配点漏接的表现为"点了同意、名单里没有"，
  /// 而全场测试仍然绿 —— 所以守卫在 `test/architecture/fnthink_receive_wiring_test.dart`。
  final Future<FnthinkPeerWrite> Function(FnthinkPeer peer)? recordPeer;

  /// 服务端**撤了**一条授权之后，把本机名单里那一行删掉（`fnthink_peers`）。
  /// 返回"这一行本来在不在"。null = 这台设备没装配删行链路 ⇒ 结论里带
  /// [FnthinkPeerRemoveSkip.storeUnavailable]，而不是悄悄留着那一行。
  ///
  /// ⚠ 装配点漏接时的表现与 [recordPeer] 同族：撤销在服务端生效了，本机名单却还留着那一行，
  /// 而用户看到的是"点了没反应"——所以守卫在 `test/architecture/fnthink_receive_wiring_test.dart`，
  /// 反证在 `outputs/_revokepeer.report.txt`。
  final Future<bool> Function(String peerAddress)? removePeer;

  /// 每一轮之后 / 停下来的那一下，告诉原生"这台还要不要自己醒"（T33 第二片 / §4-9）。
  ///
  /// 为什么挂在协调者上而不是页面或循环上：**"这台需不需要继续醒着"的判断依据全在这里**
  /// （开关、契约、签名能力），而间隔在契约里、发送通道的形状在平台层 ——
  /// 让页面去排闹钟，等于每个入口都得记得续排一次；让循环去排，循环又不知道开关是不是被关了。
  /// 这里只说"要不要醒"，**一秒都不在这儿算**。
  ///
  /// null = 这台没装配续排链路。后果不是崩溃而是**链条悄悄断**：收货照常、界面照常，
  /// 只有"被杀掉之后"那一天没人再去问一次货 —— 所以装配点由守卫看着，不靠运行时报错。
  final Future<void> Function({required bool keepAwake})? presenceNotice;

  final FnthinkSettings Function(FnthinkContract) _buildSettings;
  final FnthinkCredentialStore Function(FnthinkContract) _buildCredentials;
  final FnthinkLoopFactory _loopFactory;
  final FnthinkServiceFactory _serviceFactory;

  FnthinkReceiveLoop? _loop;

  /// 最近一轮 poll 看到的、**还在等本机答复**的配对请求。
  ///
  /// 只在真跑成的那一轮更新（[FnthinkLoopReport.pairRequests]）：失败的取货不产生判断，
  /// 把它当成"清空"会在一次网络抖动之后藏掉一条真在等的请求，而用户分不出它是被撤了、
  /// 过期了、还是这一台根本没看见。
  ///
  /// 为什么是 `ValueNotifier` 而不是一个普通字段：用户挂出口令之后是**盯着屏幕等对面来配**的，
  /// 后台每 20s 一轮的账要能自己上界面。留成字段的话页面就得自己定个定时器去翻它 ——
  /// 那份"什么时候该看"的口径就长到界面里去了（而它一漏，表现是列表看着看着不再更新）。
  final ValueNotifier<List<FnthinkPairRequest>> _pairRequests =
      ValueNotifier<List<FnthinkPairRequest>>(const []);

  /// 待确认列表的数据源（页面 `ListenableBuilder` 挂它，不自己 poll、也不自己数）。
  Listenable get pairRequestsListenable => _pairRequests;

  /// 页面上那张待确认列表的数据源（不在这里判断过期：过期由服务端裁，下一轮 poll 就不带回来了）。
  List<FnthinkPairRequest> get pendingPairRequests => _pairRequests.value;

  /// 这一台**已经答复过、且服务端已经结掉**的请求 id。
  ///
  /// 为什么需要它：一次 poll 可能在用户点下同意**之前**就出发了，它的回信里那条还在 ——
  /// 落地的时刻晚于答复，`_noteRound` 就会把已经答复的那一条重新画回去（幽灵行）。
  /// 用户对着一条看不见的旧账再点一次，换来的是一句与"口令错"同形的 403。
  /// 这份名单只挡"本机答过的这一条"，不改服务端那份真相：下一轮如果没有它，本来就不该有它。
  ///
  /// 这一条被砸过什么（反证 P15）：`_noteRound` 里那层过滤摘掉 ⇒ 红在
  /// 「在途那一轮的旧回信，不会把已答复的那条画回来」；只红那一条，其余照绿 ——
  /// 因为这个形状只在"点击与一次 poll 的往返撞车"时才出现，用例是把那一轮重放出来的。
  final Set<String> _answeredRequestIds = <String>{};

  List<FnthinkPairRequest> _withoutAnswered(
    Iterable<FnthinkPairRequest> incoming,
  ) => List.unmodifiable(
    incoming.where((r) => !_answeredRequestIds.contains(r.requestId)),
  );

  /// 一轮的账 → 本机状态。**唯一的一处实现**：后台循环走 `onRound`，页面上"立即收取"那一下
  /// 走 [receiveOnce]（它调的是 `runOnce`，不经过 `_tick`，所以不会自己响）。两条路共用这一个
  /// 函数，是因为"待确认列表什么时候变"这件事只能有一个口径。
  void _noteRound(FnthinkLoopReport report) {
    if (report.status == FnthinkPollStatus.ok) {
      _pairRequests.value = _withoutAnswered(report.pairRequests);
    }
    // 失败的那一轮同样要续排：transportError / 429 说明"这一路还活着，只是这次没取到"，
    // 停在这儿等于"一次网络抖动就把这台永久叫醒的机会弄没了"。
    _presence(keepAwake: true);
  }

  /// 把"要不要醒"交给平台层。**不等、也不抛**：这是每轮的副作用，
  /// 让它失败把收货循环拖住，是拿主路给旁路陪葬。失败留一行日志，而已排上的那次仍会响。
  void _presence({required bool keepAwake}) {
    final hook = presenceNotice;
    if (hook == null) return;
    unawaited(
      hook(keepAwake: keepAwake).catchError((Object e) {
        debugPrint('[fnthink] 续排闹钟没送到（keepAwake=$keepAwake）：$e');
      }),
    );
  }

  bool get isRunning => _loop?.isRunning ?? false;

  /// 按当前设置决定要不要开始。已经在跑就是幂等 ——
  /// 两个循环读同一条队列的表现是同一条 ack 两次、未读数上下跳。
  Future<FnthinkStartResult> startIfEnabled() async {
    if (isRunning) return (started: true, reason: 'already-running');

    final resolved = await _resolveSpec(requireEnabled: true);
    if (resolved.reason != null) {
      // 起不来就顺手撤掉闹钟：留着它，被杀之后那一轮会起引擎、签不出名、什么也不动 ——
      // 白耗一次唤醒与流量，而界面上写着"收货是关着的"。撤掉才是与开关一致的状态。
      _presence(keepAwake: false);
      return (started: false, reason: resolved.reason!);
    }

    final loop = _loopFactory(resolved.spec!);
    _loop = loop;
    loop.start();
    debugPrint('[fnthink] 收货循环已启动 → ${resolved.spec!.baseUri}');
    return (started: true, reason: 'started');
  }

  /// 「能不能发这一发」的那串前置判定，**只有一份**：`startIfEnabled` 与
  /// [publishPairingCode] 用的是同一批事实（契约 → 服务地址 → 本机地址码 → 签名能力）。
  ///
  /// 顺序本身是判据：契约先于设置（设置项的默认值要从契约读），设置先于签名探测
  /// （关着的时候不该去向 KeyStore 要一次签名能力 —— 那是把"这个功能没开"变成
  /// "系统在后台悄悄动钥匙"）。
  ///
  /// `requireEnabled` 是这两条路唯一的差别：**挂口令不要求总开关开着**。配对是接收的前置，
  /// 不是它的后果；用开关挡住挂口令，用户就没有第二条路把两台设备连起来了。
  Future<({FnthinkLoopSpec? spec, String? reason})> _resolveSpec({
    required bool requireEnabled,
  }) async {
    final FnthinkContract contract;
    try {
      contract = await contracts.load();
    } on FnthinkContractUnavailable catch (e) {
      return (spec: null, reason: 'contract-unavailable: ${e.reason}');
    }

    final settings = _buildSettings(contract);
    if (requireEnabled && !await settings.receiveEnabled) {
      return (spec: null, reason: 'disabled');
    }

    final Uri baseUri;
    final String addressCode;
    try {
      baseUri = await settings.baseUrl;
      // spec 是**启动那一刻的快照**：`baseUri` 与 `addressCode` 都在这里定一次型，之后循环就带着它跑。
      // 所以半途改这两样都必须重启才生效（页面上那两处改动的调用点都按这条写了重启）：
      // 换码不重启 ⇒ 刚签出去的那一发 target 与本轮要 ack 的那条不是同一台设备；
      // 换地址不重启 ⇒ 屏幕上写着新地址，而货还在从旧地址取（两边都"看起来没反应"）。
      // 这里刻意不做"监听设置变化自动重启"：那会把"谁改了它"这件事从页面上抹掉。
      addressCode = (await _buildCredentials(
        contract,
      ).ensureAddressCode()).value;
    } on FnthinkSettingsInvalid catch (e) {
      return (spec: null, reason: 'settings-invalid: ${e.reason}');
    } on FnthinkCredentialCorrupted catch (e) {
      return (spec: null, reason: 'credential-corrupted: ${e.reason}');
    }

    if (!await signer.probe()) {
      return (spec: null, reason: 'signing-unavailable');
    }

    return (
      spec: FnthinkLoopSpec(
        contract: contract,
        baseUri: baseUri,
        addressCode: addressCode,
        signer: signer,
        persist: persist,
        display: display,
        recordAck: recordAck,
        // 后台那几轮也要有人记账：只有页面"立即收取"那一条接了 `_noteRound`，
        // 待确认列表就会变成"点了按钮才有人来"，而开关开着时它本来就是自动在收的。
        onRound: _noteRound,
      ),
      reason: null,
    );
  }

  /// 把页面已经在本机挂好的那枚口令**发到服务器**（T42「添加设备」的网络那一半）。
  ///
  /// 为什么这一步值得单独存在：本机 prefs 里写过 ≠ 服务器认得它。对端扫屏幕上那串去
  /// `/pair`，服务器只会回"口令不存在"，而这一台界面上还挂着「已挂出 5 分钟」——
  /// 那是界面替一件没发生的事作保。返回值带 `expiresAt` 才算"服务器收下了"。
  ///
  /// ⚠ 一次性用完就 `dispose`：这一发是用户点了才发的，不像循环那样需要一个长期客户端。
  ///
  /// 这一条被砸过什么（报告在本地 outputs/_publish_falsify.report.txt，按约定不入库）：
  ///  - `requireEnabled` 改成 true ⇒ 红在「开关关着也挂得出去」；
  ///  - 挂口令时顺手 `_loopFactory(...)..start()` ⇒ 红在同一条的 `isRunning` 那半；
  ///  - 前置失败不早退（`if (resolved.reason != null)` 摘掉）⇒ 红在「一句都没离机，且各有各的原话」；
  ///  - 在这里直接 `FnthinkReceiverService(...)` 构造第二份 ⇒ 红在装配守卫「构造只有一个出处」；
  ///  - 服务层那道"签不出来就不发"的闸摘掉 ⇒ 红在「一个字节都不离机」（见 `FnthinkReceiverService.pairArm`）。
  Future<FnthinkPairArmResult> publishPairingCode(String pairingCode) async {
    final resolved = await _resolveSpec(requireEnabled: false);
    if (resolved.reason != null) {
      return FnthinkPairArmResult(
        status: FnthinkPollStatus.failed,
        reason: resolved.reason,
        signedWhileUncalibrated: false,
      );
    }
    final service = _serviceFactory(resolved.spec!);
    try {
      return await service.pairArm(pairingCode: pairingCode);
    } finally {
      service.dispose();
    }
  }

  /// 答复一条配对请求（页面上"同意 / 拒绝"那两下），并把结果落到本机名单。
  ///
  /// 三个决定都在这里做，**都不交给页面**，理由是同一条：让 UI 传字符串等于把协议词表抄进界面。
  ///  - **答复词**从契约取（`pairConfirm.decisions` / `approveDecision`）。名单里若冒出第三个词，
  ///    这里直接抛，而不是猜哪个算"拒绝"。
  ///  - **档位**也从契约取：`grantableLevel(对方要的那一档)` —— 高于封顶（今日 L2）就压到封顶，
  ///    因为 L3 要锁屏/生物认证，而这一发来自远程、服务端看不见屏幕前的人。发一个必被拒的档位
  ///    只换回一句与"口令错"同形的 403；压完由界面把两个值都说出来（显示的是服务端回的
  ///    `grantedLevel`，不是用户点的那一档）。对方报的档位不在词表里 ⇒ 同意**不发**（那等于给一个
  ///    没人请求过的档位）；拒绝照发封顶那一档 —— 拒绝不写任何授权，服务端只是要求这个键存在，
  ///    而一条消不掉的畸形请求会一直挂在待确认栏里。
  ///  - **本机名单那一行**只在"同意 + 服务端认了 + 服务端说了记到哪一档"之后才写。
  ///
  /// 与挂口令同样：**不要求总开关开着**（配对是接收的前置，不是它的后果）。
  ///
  /// 这一片被砸过什么（报告在本地 `outputs/_pairui_falsify.report.txt`，按约定不入库；
  /// P1–P14 全 named + restored）：
  ///  - 封顶不压（`grantableLevel` 原样把 L3 发出去）⇒ 红在「对方要 L3 ⇒ 发出去的是封顶那一档」；
  ///  - 词表外的档位被当成可用 ⇒ 红在「对方报的档位不在词表里」（包内那条红在「词表里没有的档位」）；
  ///  - 名单记成"本机发出去的那一档"⇒ 红在「名单里那一行记的是服务端回的档位」；
  ///  - 失败轮也清空列表 ⇒ 红在「失败的那一轮不清空待确认列表」；
  ///  - `receiveOnce` 里那句记账摘掉 ⇒ 红在「循环已在跑时，手动那一轮带回来的请求也会上账」。
  ///    ⚠ 这条**第一版是假绿**：用例没起循环就点手动收取，走的其实是 `start` 那条会响
  ///    `onRound` 的路，摘掉那句照样全绿 —— 是反证抓出来的，不是读代码读出来的；
  ///  - `onRound: _noteRound` 摘掉 ⇒ 红在「后台那一轮看到的请求会被接住」；
  ///  - `if (!result.ok)` 摘掉 ⇒ 红在「答复没成 ⇒ 那一条还留着」。⚠ 它**证不到"不写名单"**那一半：
  ///    未成的那一发本来就没有可用档位，下面的 `grantedLevel` 检查会先拦 —— 两道闸各管一道，
  ///    所以两条用例各自点名，别把它们合成一条"失败时什么都不做"；
  ///  - DI 漏接 `recordPeer` ⇒ 只有装配守卫「三条副作用都在」红，其余 30 多条全绿
  ///    （"漏接时没人喊"那一族，与 `display`/`recordAck` 同形）。
  Future<FnthinkPairAnswer> confirmPairing({
    required FnthinkPairRequest request,
    required bool approve,
  }) async {
    final resolved = await _resolveSpec(requireEnabled: false);
    if (resolved.reason != null) {
      return FnthinkPairAnswer(
        result: FnthinkPairConfirmResult(
          status: FnthinkPollStatus.failed,
          reason: resolved.reason,
          signedWhileUncalibrated: false,
        ),
      );
    }
    final spec = resolved.spec!;
    final contract = spec.contract;
    final approved = contract.pairConfirmApproveDecision;
    final others = contract.pairConfirmDecisions
        .where((d) => d != approved)
        .toList();
    if (others.length != 1) {
      // 契约哪天给出第三个答复词时，"拒绝"就不再是一个能猜的东西。宁可炸在这里。
      throw StateError(
        '契约 decisions 里除 "$approved" 之外有 ${others.length} 个词（$others）：'
        '哪个算"拒绝"必须由契约明说',
      );
    }
    final ceiling = contract.pairConfirmLevelCeiling;
    final wanted = contract.grantableLevel(request.level);
    if (approve && wanted == null) {
      return FnthinkPairAnswer(
        result: FnthinkPairConfirmResult(
          status: FnthinkPollStatus.failed,
          reason: 'unknown-level:${request.level}',
          signedWhileUncalibrated: false,
        ),
      );
    }
    final service = _serviceFactory(spec);
    final FnthinkPairConfirmResult result;
    try {
      result = await service.pairConfirm(
        requestId: request.requestId,
        decision: approve ? approved : others.single,
        level: wanted ?? ceiling,
        // 全协议唯一一发 target 不是自己：授权给谁，就写给谁。
        counterpart: request.requester,
      );
    } finally {
      service.dispose();
    }
    if (!result.ok) {
      // 没结成 ⇒ 本机一份都不动，列表里那条还留着（可以再答一次，或等它过期）。
      return FnthinkPairAnswer(result: result);
    }
    // 服务端 `consumesRequest`：一条请求只会被答复一次。它已经结掉，这一台就把它从待确认
    // 列表里摘掉 —— 留着那一行等于邀请用户点第二下，而第二下换回的是同形的那句 403。
    _answeredRequestIds.add(request.requestId);
    _pairRequests.value = _withoutAnswered(_pairRequests.value);
    if (!approve) return FnthinkPairAnswer(result: result);

    // 写进名单的那一档**必须是服务端回的那一档**，不是本机发出去的那一档：两端哪天对封顶的
    // 理解漂了，本机这份要跟着服务端走，否则名单显示 L2 而对面实际被限在 L1。
    final granted = result.grantedLevel;
    if (granted == null || !contract.capabilityLevels.contains(granted)) {
      return FnthinkPairAnswer(
        result: result,
        skipped: FnthinkPeerSkip.grantedLevelUnusable,
      );
    }
    final write = recordPeer;
    if (write == null) {
      return FnthinkPairAnswer(
        result: result,
        skipped: FnthinkPeerSkip.storeUnavailable,
      );
    }
    try {
      final wrote = await write(
        FnthinkPeer(
          peerAddress: request.requester,
          publicKey: request.requesterPublicKey,
          level: granted,
          // 本机看到的时刻（服务端另有一份 grantedAt，不回给设备）。名单按它排序，
          // 而"什么时候在这台设备上同意的"本来就以这一台为准。
          grantedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
          requestId: request.requestId,
        ),
      );
      return FnthinkPairAnswer(result: result, wrote: wrote);
    } catch (e) {
      // 服务端那边已经结了，这不是"配对失败"：报成失败会让人再点一次同意，而那一下会被拒。
      debugPrint('[fnthink] 配对名单落库失败（服务端已认，本机没记）: ${request.requester} $e');
      return FnthinkPairAnswer(
        result: result,
        skipped: FnthinkPeerSkip.writeFailed,
      );
    }
  }

  /// 把一个发送方从自己的名单里划掉（T31 B 片那一发）。
  ///
  /// 与 [confirmPairing] 同一条前置口径：**不要求总开关开着**。"关掉收货"是这一台不去取，
  /// 而"别再推给我"是另一件事，它在关着的时候也必须能生效 —— 否则用户只能在打开收货的情况下
  /// 才能撤回自己的许可。
  ///
  /// ⚠ 顺序：先撤服务端，服务端认了之后才删本机那一行。反过来做的话，服务端那一发一旦失败，
  /// 本机就再也不显示这一行而授权还在 —— 对面照样推得进来，而屏幕上没有一行解释来源，
  /// 那是"推送静默丢失"里最难发现的一种。
  ///
  /// 这一发被砸过什么（报告在本地 `outputs/_revokepeer.report.txt`，按约定不入库）：
  ///  - **U2** 摘掉 `if (!result.ok)`（撤失败也删行）⇒ 红在「服务端没撤成 ⇒ 本机那一行一个字都不动」；
  ///  - **U3** 把 `ok` 改成要求 `revoked == true`（幂等那半被读成失败）⇒ 红在「revoked:false 也算成」；
  ///  - **U5** 把 `storeUnavailable` 换成 `removeFailed`（两种后果一句话）⇒ 红在「这台没装配删行 ⇒
  ///    storeUnavailable」；
  ///  - **U7** DI 漏接 `removePeer` ⇒ 红在装配守卫「四条副作用都在」与「读与删各只有一个咽喉」；
  ///  - **U6** 服务层那道"签不出来就不发"摘掉 ⇒ **全场仍绿**：协调者的 `_resolveSpec` 先拦住了。
  ///    它是纵深防御，按规矩登记成纵深防御，不登记成"已验证"（同一句话也写在服务层那边）；
  ///  - ⚠ **顺序**（先撤服务端再删行）今日只有行为用例（`steps` 记 `'request'→'remove'`），
  ///    没有单独的植入：把它反过来不是一行能改坏的形状，而 U2 已经从另一侧钉住了同一个事故
  ///    ——「授权还在而来源从屏幕上消失」。
  Future<FnthinkPeerRevoke> revokePeer(FnthinkPeer peer) async {
    final resolved = await _resolveSpec(requireEnabled: false);
    if (resolved.reason != null) {
      return FnthinkPeerRevoke(
        result: FnthinkPairRevokeResult(
          status: FnthinkPollStatus.failed,
          reason: resolved.reason,
          signedWhileUncalibrated: false,
        ),
      );
    }
    final service = _serviceFactory(resolved.spec!);
    final FnthinkPairRevokeResult result;
    try {
      result = await service.pairRevoke(peer: peer.peerAddress);
    } finally {
      service.dispose();
    }
    if (!result.ok) {
      // 服务端那一头没撤成 ⇒ 本机一份都不动：留着那一行才是此刻的真话（它还在名单里）。
      return FnthinkPeerRevoke(result: result);
    }
    final remove = removePeer;
    if (remove == null) {
      return FnthinkPeerRevoke(
        result: result,
        skipped: FnthinkPeerRemoveSkip.storeUnavailable,
      );
    }
    try {
      // `revoked:false` 走到这里同样是"已达成"：那边本来没有这一条，而本机这一行该删。
      final gone = await remove(peer.peerAddress);
      return FnthinkPeerRevoke(result: result, rowRemoved: gone);
    } catch (e) {
      // 服务端已经撤了，这不是"撤销失败"：报成失败会让人再点一次，而那一下换回的是幂等的 200
      // —— 用户看到的是点了两下都"没成"，而名单里那一行一直留着。
      debugPrint('[fnthink] 配对名单删行失败（服务端已撤，本机还留着）: ${peer.peerAddress} $e');
      return FnthinkPeerRevoke(
        result: result,
        skipped: FnthinkPeerRemoveSkip.removeFailed,
      );
    }
  }

  /// 给自己建一条接入端点（T42 第七片那一发）。
  ///
  /// 与 [publishPairingCode] / [revokePeer] 同一条前置口径：**不要求总开关开着** —— 端点是一条
  /// 入口，"建入口"这件事与"这一台现在去不去取货"无关。
  ///
  /// ⚠ 返回的那一段里带着**只出现一次的明文口令**：这里不落盘、不进日志、不缓存，
  /// 也不把它塞进任何 `ValueNotifier`（那等于把长期凭证留在进程里一份没人负责清掉的东西）。
  /// 页面对它的处理只有一个合法去处：当场显示一次，让用户抄走。
  Future<FnthinkEndpointCreateResult> createEndpoint({
    required String name,
  }) async {
    final resolved = await _resolveSpec(requireEnabled: false);
    if (resolved.reason != null) {
      return FnthinkEndpointCreateResult(
        status: FnthinkPollStatus.failed,
        reason: resolved.reason,
        signedWhileUncalibrated: false,
      );
    }
    final service = _serviceFactory(resolved.spec!);
    try {
      return await service.endpointCreate(name: name);
    } finally {
      service.dispose();
    }
  }

  /// 读自己名下那几把接入端点（#157 第二片）。
  ///
  /// 与 [createEndpoint] 同一条前置口径（不要求总开关开着）：**"我有哪些入口"与"这台现在
  /// 去不去取货"是两件事**。把它绑到总开关上的那天下场是：用户关掉接收来省电，页面随之说
  /// "还没有端点"，而他挂在 NAS 上那把还在收信 —— 界面把一件没发生的事说成了另一件。
  ///
  /// 这里**不缓存**结果，也没有 `ValueNotifier` 记账：那份表在服务端，本机存一份就是一本
  /// 会漂的账（服务端吊销之后本机还写着"在用"）。每次翻开这一格重新读一次。
  ///
  /// 反证 **Z10**（`outputs/_eplist2.report.txt`）：`requireEnabled: false` 改成 `true` ⇒
  /// 三条一起红，其中点名的是「总开关关着也读得到」。这条判据与 `createEndpoint` 那一条
  /// 同族，所以值得单独钉一次：入口是**在别人那一边**还在收信的东西，与本机的开关无关。
  Future<FnthinkEndpointListResult> listEndpoints() async {
    final resolved = await _resolveSpec(requireEnabled: false);
    if (resolved.reason != null) {
      return FnthinkEndpointListResult(
        status: FnthinkPollStatus.failed,
        reason: resolved.reason,
        signedWhileUncalibrated: false,
      );
    }
    final service = _serviceFactory(resolved.spec!);
    try {
      return await service.endpointList();
    } finally {
      service.dispose();
    }
  }

  /// 关掉自己名下一条接入端点（#157 第四片）。
  ///
  /// 与 [listEndpoints] 同一条前置口径（不要求总开关开着）：**关一把入口与这台现在去不去取货无关** ——
  /// 关着接收的时候恰恰最可能需要关掉一把还在收信的入口。
  ///
  /// 这一发**只发请求，不动本机任何东西**：端点表没有本机副本（见 [listEndpoints] 那段），
  /// 所以没有"先撤服务端再删本机行"那一步（那是配对名单的形状）。页面在拿到结果之后
  /// 重新读一次列表即可 —— 让屏幕跟上服务端，而不是自己把那一行画成灰色。
  ///
  /// 反证 **SA5**（`outputs/_eprv2.report.txt`）：`requireEnabled: false` 改成 `true` ⇒
  /// 红在「总开关关着也关得掉」。它与读那一条的 Z10 同族但后果不同档：
  /// 读错了只是看不见，关错了是**关着接收的时候，想关掉一把还在收信的入口却关不掉**。
  Future<FnthinkEndpointRevokeResult> revokeEndpoint({
    required String endpointId,
  }) async {
    final resolved = await _resolveSpec(requireEnabled: false);
    if (resolved.reason != null) {
      return FnthinkEndpointRevokeResult(
        status: FnthinkPollStatus.failed,
        endpointId: endpointId,
        reason: resolved.reason,
        signedWhileUncalibrated: false,
      );
    }
    final service = _serviceFactory(resolved.spec!);
    try {
      return await service.endpointRevoke(endpointId: endpointId);
    } finally {
      service.dispose();
    }
  }

  /// 换那把入口的口令（#157 第六片）。前置口径与 [revokeEndpoint] 同一条
  /// （不要求总开关开着：口令泄露了而接收正关着，恰恰是要换的那一回）。
  ///
  /// ⚠ 返回值里的新口令**只在这里过一下**：不落盘、不进 `ValueNotifier`、不写日志。
  /// 也不缓存"换过了"这件事 —— 换没换、旧那把还能用到什么时候，都以服务端那一份为准，
  /// 页面在拿到结果之后重新读一次列表。
  ///
  /// 反证 **RC5**（`outputs/_erot2.report.txt`）：`requireEnabled: false` 改成 `true` ⇒
  /// 红在「总开关关着也换得动」这一条（连带另两条一起红，因为它们都靠这一发发得出去）。
  /// 与 Z10/SA5 同一族，但这里后果更具体：**口令泄露了而接收正关着**，那正是最需要换的一回。
  Future<FnthinkEndpointRotateResult> rotateEndpoint({
    required String endpointId,
  }) async {
    final resolved = await _resolveSpec(requireEnabled: false);
    if (resolved.reason != null) {
      return FnthinkEndpointRotateResult(
        status: FnthinkPollStatus.failed,
        endpointId: endpointId,
        reason: resolved.reason,
        signedWhileUncalibrated: false,
      );
    }
    final service = _serviceFactory(resolved.spec!);
    try {
      return await service.endpointRotate(endpointId: endpointId);
    } finally {
      service.dispose();
    }
  }

  /// 发一条通知给名单里那台设备（`/message`，§4-10 片2）。
  ///
  /// 前置口径与 `listEndpoints` / `revokeEndpoint` 同一条（`requireEnabled: false`）：
  /// **发这一条与"这台现在去不去取货"是两件事**。把它绑到总开关上的表现很具体 —— 用户为了省电
  /// 关掉接收，随之手表上那条"到家了"也发不出去，而屏幕上只会说"发送失败"。
  ///
  /// 这里**不查本机名单**（名单在 `fnthink_peers`，由页面负责只让人选里面那一台）。协调者若再判一次，
  /// 就有了两个地方决定"能不能发给这个人"，而它们判的还不是同一份数据（服务端判的是被投那台的
  /// `grantsBy`）。本机这一份只是给人挑的候选，不是授权。
  Future<FnthinkSendResult> sendNotice({
    required String peer,
    required String title,
    required String text,
  }) async {
    final resolved = await _resolveSpec(requireEnabled: false);
    if (resolved.reason != null) {
      return FnthinkSendResult(
        status: FnthinkSendStatus.preconditionFailed,
        reason: resolved.reason,
      );
    }
    final service = _serviceFactory(resolved.spec!);
    try {
      return await service.sendNotice(peer: peer, title: title, text: text);
    } finally {
      service.dispose();
    }
  }

  /// 停下来。已在途的那一轮跑完为止（强行掐断等于把 ack 停在半路）。
  void stop() {
    _loop?.stop();
    _loop = null;
    // 关掉接收 ⇒ 闹钟一起撤（与 `startIfEnabled` 那条早退同一口径：醒着的意义就是去取货）。
    _presence(keepAwake: false);
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
    final report = await loop.runOnce();
    // 手动那一轮不经过 `_tick`，所以 `onRound` 不会响 —— 这里补上同一个口径。
    // 少这一行时的表现很具体：开关开着、后台一直在收，而"有人请求配对"那一栏要等下一次
    // 定时器才更新，用户点了"立即收取"却看见空栏。
    _noteRound(report);
    return report;
  }
}
