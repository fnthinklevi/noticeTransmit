import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:get_it/get_it.dart';

import '../l10n/app_localizations.dart';
import '../models/fnthink_peer.dart';
import '../services/channel_display.dart';
import '../services/channel_health_store.dart';
import '../services/fnthink_contract_loader.dart';
import '../services/fnthink_credential_store.dart';
import '../services/fnthink_identity_service.dart';
import '../services/fnthink_peer_service.dart';
import '../services/fnthink_presence_scheduler.dart';
import '../services/fnthink_receive_coordinator.dart';
import '../services/fnthink_settings.dart';
import '../theme/app_colors.dart';
import '../widgets/fnthink_send_dialog.dart';
import '../widgets/ios_dialog_actions.dart';

/// 页面要用到的那一小包依赖。
///
/// 为什么不直接散着 `GetIt.instance<X>()` 取：这一页要同时碰契约、开关、凭证、身份、
/// 启停五件事，测试里必须能把它们一起换成替身（否则"点开关 ⇒ 写 prefs ⇒ 起循环 ⇒ 起不来就
/// 把原话显示出来"这条只能靠真机回答）。
class FnthinkPushDeps {
  FnthinkPushDeps({
    required this.contracts,
    required this.coordinator,
    required this.identity,
    required this.loadPeers,
    required this.presence,
    this.healthOf,
  });

  factory FnthinkPushDeps.fromLocator() => FnthinkPushDeps(
    contracts: GetIt.instance<FnthinkContractLoader>(),
    coordinator: GetIt.instance<FnthinkReceiveCoordinator>(),
    identity: FnthinkIdentityService(),
    // 名单只从读咽喉取。退回 `DatabaseHelper().loadFnthinkPeers` 的话，页面就会自己长出一份
    // 排序/时间口径，而 `history_page` 那批守卫已经证明过这种分叉是怎么开始的。
    loadPeers: GetIt.instance<FnthinkPeerService>().list,
    // 「下一次自己醒」那一行只**读**这一个源（§4-9 片1d）：页面既不自己算间隔、也不自己排闹钟
    // （排/撤那一半在协调者 + scheduler 里，各只有一处）。DI 漏接时这一行取不到值 —— 守卫在
    // `test/architecture/fnthink_presence_guard_test.dart`。
    presence: GetIt.instance<FnthinkPresenceScheduler>(),
    // T60（approach B）：对着某台服务器的最近一次发送健康度。读源与写源（协调者 recordHealth
    // 落到 ChannelHealthStore）都认 `kFnthinkChannelSlug` 这一个 family，页面不自己 new 读写实现。
    healthOf: (host) =>
        GetIt.instance<ChannelHealthStore>().of(kFnthinkChannelSlug, host),
  );

  final FnthinkContractLoader contracts;
  final FnthinkReceiveCoordinator coordinator;
  final FnthinkIdentityService identity;
  final Future<List<FnthinkPeer>> Function() loadPeers;
  final FnthinkPresenceScheduler presence;

  /// 读某台服务器的健康度（null = 这台没装配健康度链路 ⇒ 那一行不画/显示"从没发过"）。
  final ChannelHealth? Function(String host)? healthOf;
}

/// 幻念推送页（T44 的②③ + T42 的入口那半）。
///
/// 这一页存在的理由是**一条断链**：收货链路（契约→地址码→循环→收件表→通知栏）五片都落完了，
/// 而总开关住在 SharedPreferences 里、默认关，界面上没有任何一处能把它翻开 ——
/// 于是整条链对真实用户是不可达的。顺带把"这台设备是谁"（地址码 / 配对口令 / 身份密钥）
/// 第一次显示给人看：在此之前它们只在日志与测试里出现过。
///
/// ⚠ 页面上刻意没有的东西，都不是忘了：
///  - **一键"全部撤销"**：名单上有的只是**逐行那一下**「撤销」（T31 B 片第二片），它撤的是
///    服务端那份授权，而已经收到的通知不在这一发的范围里（撤销只停投递、不删历史）。
///    "把这台设备上所有许可一次收回"需要另一套二次确认（它得先说清"这会切断 N 台"），
///    那是 T31 的另一档，不在这一格顺手加一个按钮的范围里。
///  - **对端的名字**：`fnthink_peers` 故意没有这一列（见 `FnthinkPeer` 的注释：poll 的回信里
///    从没带过它，等有出处了再加列）。所以名单只能显示 18 位地址码 —— 难看，但是有出处的难看。
///  - **大陆那台预设地址**：`transport.endpoints.mainland` 今天**已部署**（#137 走"先把它部署起来"收口，
///    两个域名的能力等价有外网实测），但这一页仍然不给那一档 —— 缺的已经不是地址，而是
///    **"什么时候该建议切"的判据**：契约的 `suggestSwitchOnMainlandNetwork` 要靠网络测量，
///    而设备侧没有任何测量口径（那半属于 T44 ①，未做）。摆两个都能用的地址却不给选择的依据，
///    等于把决策甩回给用户，而且他一旦选错，症状是"网络好好的却连不上"。
///  - **收件未读数**：它属于 T48 那张入口卡与历史页筛选，不是这一页的责任。
class FnthinkPushPage extends StatefulWidget {
  const FnthinkPushPage({super.key, this.deps});

  final FnthinkPushDeps? deps;

  @override
  State<FnthinkPushPage> createState() => _FnthinkPushPageState();
}

class _FnthinkPushPageState extends State<FnthinkPushPage> {
  late final FnthinkPushDeps _deps;
  late final FnthinkReceiveCoordinator _coordinator;

  FnthinkSettings? _settings;
  FnthinkCredentialStore? _credentials;

  /// 契约不可用的原话。非空时整页只显示这一条 —— 设置项的默认值要从契约读，
  /// 拿不到契约还让人改开关与地址，等于把值写进一个说不清含义的地方。
  String? _contractError;

  bool _enabled = false;
  bool _running = false;

  /// 这台同意过「通知内容经服务器中转」没有（T56 的同意门）。
  ///
  /// **它与 [_enabled] 是两件不同的事**：开关是"要不要收"，同意是"允不允许内容离开这台设备"。
  /// 两格都在接收卡上、都不许替用户点 —— 升级不改任一个。
  bool _consented = false;

  /// T60（approach B）：最近一次发送与服务器通话的健康度（family=fnthink、id=服务器 host）。
  /// null = 这一台对着这个服务器从没发出过一发（或还没读到）⇒ 那一行显示"从没发过"，
  /// 而不是猜一个"正常"。
  ChannelHealth? _serverHealth;

  /// 最近一次"起不来"的原话（五种各有各的成因，不许归并成"出错了"）。
  String? _startNote;

  /// 上一轮的账（`FnthinkLoopReport.summary`，只有计数）。
  String? _lastRound;

  /// 这一发的性质：null=没点，skipped=上一轮还在途，disabled=开关关着。
  /// 三者都不该被显示成"收到 0 条"。
  String? _roundNote;

  String? _addressCode;
  FnthinkArmedPairingCode? _pairing;

  /// 挂出口令那一发，服务器**有没有**收下。三态各有各的话，不许合并：
  ///  - `true` 服务器回了过期时间 ⇒ 对端现在拿这串能配上；
  ///  - `false` 本机写成了但那一发没成 ⇒ 必须当面说，否则界面就是在替一件没发生的事作保
  ///    （对端扫码只会收到"口令不存在"，而这一台写着"已挂出 5 分钟"）；
  ///  - `null` 只是进页面时读到本机存着一枚 ⇒ 这一台没发过那一发，**不知道**。
  /// 剩余时间那一行说的是本机倒计时，所以三态下都可以显示 —— 但必须和这一行一起读。
  bool? _pairingAcked;

  /// `_pairingAcked == false` 时服务器/前置给的原话（与状态行同一条纪律：不折叠成"出错了"）。
  String? _pairingPublishNote;

  /// 本机凭证存量与契约对不上。这是**要人来处理**的状态，不是可自愈的状态，
  /// 所以它留在页面上直到用户重置，而不是悄悄换一枚然后显示一片绿。
  String? _credentialError;

  /// 契约那一页读到的那一份（读不到时整页已经只显示错误了，所以这里可空）。
  /// 待确认列表要拿它算"这一发实际会给到哪一档"——**算法在契约层**（`grantableLevel`），
  /// 页面只是把结果念出来；页面自己写一份 min(L?) 的话，封顶换档时界面还在说旧的。
  FnthinkContract? _contract;

  /// 最近一次答复的结论（null = 这一页还没答过）。留着它而不是弹个 toast 就消失：
  /// "服务端认了但本机名单没写"那一态必须经得起用户回去再看一眼。
  ///
  /// 待确认列表本身**不在页面里存一份**：它挂在协调者的 `pairRequestsListenable` 上（见下）。
  ({FnthinkPairRequest request, bool approve, FnthinkPairAnswer answer})?
  _pairAnswer;

  /// 本机配对名单（`fnthink_peers`）。**null = 还不知道**（还没读到，或读失败），
  /// 空列表 = 真的一个都没配对过。两者不许合并成同一句"还没有配对过任何设备"：
  /// 读失败时那句是假话，而这一格存在的意义恰恰是"我同意过谁"。
  List<FnthinkPeer>? _peers;

  /// 读名单失败时的原话（与 `_startNote` 同一条纪律：不折叠成"出错了"）。
  String? _peersError;

  /// 最近一次撤销的结论（null = 这一页还没撤过）。与 `_pairAnswer` 同一条理由：
  /// "服务器撤了而本机那一行没删掉"必须经得起回去再看一眼，不能弹个 toast 就消失。
  ({FnthinkPeer peer, FnthinkPeerRevoke revoke})? _peerRevoke;

  /// 最近一次「发一条」的结论（null = 这一页还没发过）。
  /// 与撤销那一条同一个理由：只弹一句 toast 的话，用户回头就分不出"没发出去"与
  /// "发出去了但那台还没回执" —— 而这两件事的下一步动作完全不同。
  ({FnthinkPeer peer, FnthinkSendResult result})? _sendNote;

  /// 刚建好的那条接入端点。**口令只在这里活这么长**：页面不把它写进 prefs、不写进表、
  /// 不拼进任何日志 —— 这一格存在的目的就是让用户当场抄走，抄不到就重新建一把。
  /// （留一份"方便回去再看"的副本是这个功能最容易做错的形状：那等于把长期凭证存进
  ///  一个会跟着备份走、又不加密的地方，而服务端那边只存了摘要，谁都不知道丢了什么。）
  FnthinkEndpointCreateResult? _endpoint;

  /// 「我建过哪些入口」那一次读的结论（null = 这一页还没读过）。
  /// ⚠ 这一份**不持久化**，也不与 `_endpoint` 合成一个东西：口令是一次性的、这份是每次读重来的，
  /// 两者放一起的下场是"重新读一次把刚拿到的口令覆盖掉"，而那份口令本来就只有这一次。
  /// 端点表在服务端，本机不留副本 —— 留了就是一本会漂的账（那边吊销了，这本还写着在用）。
  FnthinkEndpointListResult? _endpointList;

  /// 最近一次"关掉一把入口"的结论（null = 这一页还没关过）。
  /// 与名单那一格同一个道理：结论必须经得起回去再看一眼，不能弹个 toast 就消失 ——
  /// 而这里更需要，因为**关掉之后列表里那一行还在**（只是不再收信），
  /// 没有这句结论，用户看不出那一行是自己刚关的还是一早就停的。
  FnthinkEndpointRevokeResult? _endpointRevoked;

  /// 最近一次"换口令"的结论（null = 这一页还没换过）。
  /// ⚠ 与 `_endpoint` 同一条红线：它带着**只出现一次的新明文口令**，所以不落盘、不进日志；
  /// 页面关掉这一格就是它消失的时候（换过一次而没抄走，只能再换一次 —— 旧那把会跟着进宽限期）。
  FnthinkEndpointRotateResult? _endpointRotated;

  FnthinkDeviceIdentity? _identity;
  bool _identityUnavailable = false;

  String _host = '';

  /// 改地址失败的原因（校验在 `FnthinkSettings` 那一处，这里只显示）。
  String? _hostError;

  /// 「下一次自己醒」那一行读回来的那一份（null = 还没读到，或读口抛了）。
  ///
  /// ⚠ null 与 `armed == false` 是**两件事**：前者是"不知道"，后者是"确实没排" ——
  /// 合并成一句话，就是拿"读不出来"冒充"没在醒着"，而这两者的下一步动作完全不同
  /// （一个要查通道/版本，一个只要把开关打开）。
  FnthinkPresenceStatus? _presence;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _deps = widget.deps ?? FnthinkPushDeps.fromLocator();
    _coordinator = _deps.coordinator;
    _load();
  }

  Future<void> _load() async {
    final FnthinkContract contract;
    try {
      contract = await _deps.contracts.load();
    } on FnthinkContractUnavailable catch (e) {
      if (mounted) setState(() => _contractError = e.reason);
      return;
    }
    final settings = FnthinkSettings(contract: contract);
    final credentials = FnthinkCredentialStore(contract: contract);
    String host;
    try {
      host = await settings.host;
    } on FnthinkSettingsInvalid catch (e) {
      // 备份恢复可能灌回来一个坏值：这里不抛到页外，而是把"哪一项坏了"显示出来。
      host = '';
      _hostError = e.reason;
    }
    String? addressCode;
    FnthinkArmedPairingCode? pairing;
    try {
      addressCode = (await credentials.storedAddressCode())?.value;
      pairing = await credentials.currentPairingCode();
    } on FnthinkCredentialCorrupted catch (e) {
      _credentialError = e.reason;
    }
    final identity = await _deps.identity.identity();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _credentials = credentials;
      _contract = contract;
      _host = host;
      _addressCode = addressCode;
      _pairing = pairing;
      _identity = identity;
      _identityUnavailable = identity == null;
      _running = _coordinator.isRunning;
    });
    // 开关的真值**只**从 prefs 读：它是用户做过的那个决定。契约那边没有任何一项能替代它
    // （契约管的是节奏与档位，不是"这台设备同不同意被中转"）。
    // 两件读事互不依赖，一起发出去（`_loadPeers` 之后在 `_answer` 里还要被单独调一次，
    // 所以这里不写成一句 `await _loadPeers();`，免得两处的形状看不出谁是谁）。
    await Future.wait<void>([_readEnabled(), _loadPeers(), _readPresence()]);
  }

  /// 读一次「这台还要不要自己醒、下一次在什么时候」。
  ///
  /// 这是**只读**的一发：它不排闹钟、不撤闹钟、也不改任何开关 —— 那三件事各有各的作者
  /// （协调者按开关裁决、scheduler 按契约读数）。页面拿到的是一个毫秒时间点与一档秒数，
  /// 于是"到底还有没有人醒"这句话在界面上第一次有了出处，而不是靠用户猜。
  ///
  /// 读失败**什么都不改**（保持上一次那份，或者干脆不显示这一行）：通道没接（桌面/老包）时
  /// 显示 0 会让这一行看起来像"没在醒着"，而真值是"不知道"。
  Future<void> _readPresence() async {
    final FnthinkPresenceStatus status;
    try {
      status = await _deps.presence.status();
    } catch (_) {
      // 保持原样。原生那侧已经会为"排不上/撤不掉"留日志，这一层不重复喊。
      return;
    }
    if (!mounted) return;
    setState(() => _presence = status);
  }

  /// `HH:mm:ss`。**只做格式化**：页面不推算"还有多久"（那个数只有排闹钟的那一方知道）。
  String _presenceClock(int millis) {
    final at = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
  }

  String _presenceText(AppLocalizations l10n) {
    final status = _presence!;
    if (!status.armed) return l10n.fnthinkPresenceAsleep;
    final clock = _presenceClock(status.nextRoundAt);
    return status.cadenceSeconds > 0
        ? l10n.fnthinkPresenceNext(clock, status.cadenceSeconds)
        : l10n.fnthinkPresenceNextNoCadence(clock);
  }

  /// 读本机配对名单。**只有读咽喉那一个入口**（`FnthinkPushDeps.loadPeers`）。
  /// 失败时不退回空表：那一格会把"读不出来"显示成"一个都没配过"，而后者是可行动的真话、
  /// 前者不是（这里没得可点，界面上只能让用户去查权限/存储）。
  Future<void> _loadPeers() async {
    List<FnthinkPeer>? rows;
    String? error;
    try {
      rows = await _deps.loadPeers();
    } catch (e) {
      error = '$e';
      rows = null;
    }
    if (!mounted) return;
    setState(() {
      _peers = rows;
      _peersError = error;
    });
  }

  Future<void> _readEnabled() async {
    final settings = _settings;
    if (settings == null) return;
    // 两个真值一起读：开关是"要不要收"，同意是"允不允许经服务器中转"（T56）。
    // 两件事互不派生，合成一个状态字段就会在某一处漏掉重读 —— 而漏掉的那一处
    // 表现是"界面说已同意，协调者说不认"，用户看不出该点哪一下。
    final values = await Future.wait<bool>([
      settings.receiveEnabled,
      settings.hasRelayConsent(),
    ]);
    if (!mounted) return;
    setState(() {
      _enabled = values[0];
      _consented = values[1];
    });
    // T60（approach B）：对着这个服务器最近一次发送通没通过（读通道健康度）。
    // 主机名要在 settings 那边现取（发送用的就是它），健康度按 (fnthink, host) 读那一条；
    // 读不到 = 这台对这个服务器从没发出过一发 ⇒ 那一行说"从没发过"，不猜"正常"。
    await _readServerHealth();
  }

  Future<void> _readServerHealth() async {
    final settings = _settings;
    if (settings == null) return;
    final String host;
    try {
      host = await settings.host;
    } catch (_) {
      // 服务地址本身没配好：这一行留"从没发过"（连该读哪台都不知道，谈不上健康度）。
      if (!mounted) return;
      setState(() => _serverHealth = null);
      return;
    }
    final health = _deps.healthOf?.call(host);
    if (!mounted) return;
    setState(() => _serverHealth = health);
  }

  String _serverHealthText(AppLocalizations l10n) {
    final health = _serverHealth;
    if (health == null) return l10n.fnthinkHealthNever;
    return health.reachable
        ? l10n.fnthinkHealthReachable
        : l10n.fnthinkHealthUnreachable;
  }

  /// 一次性同意「通知内容经服务器中转」（T56）。三情形说明放在确认弹层里，确认键才写下同意。
  ///
  /// ⚠ **同意是一次显式动作**，所以它走 `askConfirm` 而不是"点一下开关就算"：
  /// 这一格的后果是"通知内容会离开这台设备、经服务器中转"，那是本产品里最重的一件事，
  /// 静默发生就是把用户没做过的决定替他做了（"升级/新功能不许悄悄做让用户意外的事"）。
  /// 取消 ⇒ 一个字节都不写，也不改任一开关（不写半份同意）。
  Future<void> _grantConsent() async {
    final settings = _settings;
    if (settings == null || _busy) return;
    final l10n = AppLocalizations.of(context);
    final ok = await IosDialogActions.askConfirm(
      context,
      title: l10n.fnthinkConsentTitle,
      message: l10n.fnthinkConsentMsg,
      confirmText: l10n.fnthinkConsentAgree,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    await settings.grantRelayConsent();
    if (!mounted) return;
    setState(() {
      _consented = true;
      _busy = false;
    });
    // 同意之前收货循环起不来（协调者 early-return not-consented）；用户刚同意 ⇒ 若开关已开，
    // 立刻试一次起来，让"同意"这件事当场有可见后果（否则要等下一轮后台闹钟）。
    if (_enabled) unawaited(_toggleReceive(true));
  }

  /// 开关。⚠ 这里有一个必须写下来的取舍：**开关那一格显示的是"用户要的状态"（prefs 真值），
  /// 运行那一格显示的是"实际状态"**，两者不一致时把原话贴在下面，而不是把开关回弹。
  /// 回弹会让他以为没点上而再点一次（结果一样），而"已开但起不来"才是可诊断的那句话。
  Future<void> _toggleReceive(bool value) async {
    final settings = _settings;
    if (settings == null || _busy) return;
    final l10n = AppLocalizations.of(context);
    // 开关那一格跟着**写进 prefs 的那一份**走：先落库再改口，界面与 prefs 不会各说一段。
    setState(() {
      _busy = true;
      _enabled = value;
    });
    await settings.setReceiveEnabled(value);
    if (value) {
      final result = await _coordinator.startIfEnabled();
      if (!mounted) return;
      setState(() {
        _running = _coordinator.isRunning;
        // 「没同意中转」是本片新增的那一档，机器理由 `not-consented` 用户读不懂 ⇒ 换成
        // 人话。其余理由沿用原样（既有那些都已是面向用户的短词）。
        _startNote = result.started
            ? null
            : (result.reason == 'not-consented'
                  ? l10n.fnthinkConsentNotGranted
                  : result.reason);
        _busy = false;
      });
      // 开关翻开 ⇒ 协调者刚排过闹钟（或刚因为起不来撤过）：那一行必须跟着重读，
      // 否则它会一直显示翻开之前的样子，而这一行的全部意义就是"现在到底醒没醒"。
      // 不 await：这是显示刷新，开关那一发该做的已经做完了（读口自己吞异常）。
      unawaited(_readPresence());
      return;
    }
    _coordinator.stop();
    if (!mounted) return;
    setState(() {
      _running = false;
      _startNote = null;
      _busy = false;
    });
    unawaited(_readPresence());
  }

  Future<void> _receiveNow() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final report = await _coordinator.receiveOnce();
    if (!mounted) return;
    setState(() {
      _running = _coordinator.isRunning;
      if (report == null) {
        _roundNote = l10n.fnthinkReceiveDisabled;
        _lastRound = null;
      } else if (report.skipped) {
        _roundNote = l10n.fnthinkReceiveSkipped;
      } else {
        _roundNote = null;
        // summary 只有计数（没有标题、正文与消息 id），所以可以直接上界面。
        _lastRound = report.summary;
        _startNote = null;
      }
      _busy = false;
    });
    // 手动那一轮跑完也会续排（`_noteRound`）：读回来，别让这一行停在上一轮的时间点上。
    await _readPresence();
  }

  Future<void> _copy(String text) async {
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.fnthinkCopied),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  /// 换一枚地址码。**唯一一处**执行它的地方就在确认之后（T06 那条纪律）。
  Future<void> _resetAddressCode() async {
    final credentials = _credentials;
    if (credentials == null || _busy) return;
    final l10n = AppLocalizations.of(context);
    final ok = await IosDialogActions.askConfirm(
      context,
      title: l10n.fnthinkResetCodeTitle,
      message: l10n.fnthinkResetCodeMsg,
      // 确认键不复用 tile 那句"重置地址码"：弹层里外两句一模一样，用户分不清自己点的是哪一个，
      // 而测试里 `find.text` 也会一次抓到两个。
      confirmText: l10n.confirm,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final fresh = await credentials.resetAddressCode();
    // ⚠ 循环带着的是**启动那一刻**定型的地址码：换了码还让它继续跑，签出去的 target
    // 与本轮要 ack 的那条就不是同一台设备。所以重启，而不是"下次自然生效"。
    if (_running) {
      _coordinator.stop();
      await _coordinator.startIfEnabled();
    }
    if (!mounted) return;
    setState(() {
      _addressCode = fresh.value;
      _running = _coordinator.isRunning;
      _credentialError = null;
      _busy = false;
    });
  }

  /// 挂出一枚一次性配对口令。每次点都是新的一枚（契约 `singleUse=true`）。
  Future<void> _armPairingCode() async {
    final credentials = _credentials;
    if (credentials == null || _busy) return;
    setState(() => _busy = true);
    FnthinkArmedPairingCode armed;
    try {
      armed = await credentials.armPairingCode();
    } on FnthinkCredentialCorrupted catch (e) {
      if (!mounted) return;
      setState(() {
        _credentialError = e.reason;
        _busy = false;
      });
      return;
    }
    // 口令是"要被人抄走"的那一件：如果地址码还没生成，此刻补上，否则对方拿着口令
    // 却不知道往哪台设备上配。
    final code = await credentials.ensureAddressCode();
    if (!mounted) return;
    setState(() {
      _pairing = armed;
      _addressCode = code.value;
      _credentialError = null;
      // 刚挂的那一发还没问过服务器：先按"不知道"显示，别沿用上一枚的确认状态。
      _pairingAcked = null;
      _pairingPublishNote = null;
      _busy = false;
    });
    // 本机写完了，还要服务器也认这枚口令 —— 那才是对端能不能配上唯一取决于的东西。
    await _publishPairingCode(armed.code.value);
  }

  /// 把刚挂好的那枚口令发到服务器，并把结论**如实**落成三态之一。
  /// 失败时不清空口令、不回弹：那串码在本机确实还有效（倒计时也在走），用户看到的
  /// 应该是"只有这台知道它"，而不是"什么都没发生过"。
  ///
  /// 这一条被砸过什么（报告在本地 outputs/_page_publish_falsify.report.txt，按约定不入库）：
  ///  - 不发出那一发 ⇒ 红在「服务器回了过期时间 ⇒ 明说"服务器已收到"」；
  ///  - 不问结果、一律 `_pairingAcked = true` ⇒ 红在「服务器没确认 ⇒ 说"只有这台记下了"」；
  ///  - 把"不知道"那一态去掉 ⇒ 红在「进页面读到本机存着一枚 ⇒ 说'没问过服务器'」。
  /// 三条各自点名、逐字节还原。
  Future<void> _publishPairingCode(String pairingCode) async {
    final result = await _coordinator.publishPairingCode(pairingCode);
    if (!mounted) return;
    setState(() {
      _pairingAcked = result.ok;
      _pairingPublishNote = result.ok ? null : (result.reason ?? 'no-answer');
    });
  }

  /// 答复一条待确认的配对请求。**同意那一下一定过二次确认** —— 契约把这一步定为
  /// `confirmRequired=true / autoApprove=false`，它存在的意义就是有人看过并点过一次。
  ///
  /// 页面交给协调者的**只有一个布尔**：答复词与档位都由协调者从契约取。弹层上写的那一档是
  /// 契约算出来的（`grantableLevel`），不是对方请求的那一档 —— 让用户在他以为的档位上按下同意，
  /// 而实际授出去的是另一档，那一下点得就没有意义。
  ///
  /// ⚠ 参数写成位置式是给 T06 那条守卫留一个不带 `{` 的签名锚点：`blockAfter` 会停在
  ///    命名参数表那个花括号上，取到的是参数表而不是函数体（这条在收件守卫上砸过一次）。
  Future<void> _answer(FnthinkPairRequest request, bool approve) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final willGrant = _contract?.grantableLevel(request.level) ?? request.level;
    if (approve) {
      final ok = await IosDialogActions.askConfirm(
        context,
        title: l10n.fnthinkPairAskTitle,
        message: l10n.fnthinkPairAskMsg(request.requester, willGrant),
        // 确认键不复用列表里那句"同意"：弹层内外两句一模一样，用户分不清自己点的是哪一个，
        // 而 `find.text` 会一次抓到两个。
        confirmText: l10n.confirm,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    final answer = await _coordinator.confirmPairing(
      request: request,
      approve: approve,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _pairAnswer = (request: request, approve: approve, answer: answer);
    });
    // 名单是这一发的**后果**：不重读一次，用户点完同意，下面那格还是旧的（而它的存在意义
    // 正是"我同意过谁"）。重读走的是同一个读咽喉，不是页面自己数一遍。
    await _loadPeers();
  }

  /// 最近一次答复的结论。⚠ 档位那一格用的是**服务端回的** `grantedLevel`，不是用户点的那一档：
  /// 封顶（`pairConfirm.levelCeilingFrom`）在服务端那侧也判一次，本机以为给到了而对面记低了
  /// 是完全可能的，而名单以后就是按这一列显示"我给过谁哪一档"的。
  String _pairAnswerText(
    AppLocalizations l10n,
    ({FnthinkPairRequest request, bool approve, FnthinkPairAnswer answer})
    entry,
  ) {
    final answer = entry.answer;
    if (!answer.ok) return l10n.fnthinkPairFailed(answer.reason ?? 'no-answer');
    final peer = entry.request.requester;
    if (!entry.approve) return l10n.fnthinkPairDenied(peer);
    final skipped = answer.skipped;
    if (skipped == FnthinkPeerSkip.grantedLevelUnusable) {
      return l10n.fnthinkPairNoGrantedLevel;
    }
    if (skipped == FnthinkPeerSkip.storeUnavailable) {
      return l10n.fnthinkPeerStoreUnavailable;
    }
    if (skipped == FnthinkPeerSkip.writeFailed) {
      return l10n.fnthinkPeerWriteFailed;
    }
    if (answer.wrote == FnthinkPeerWrite.keySwapped) {
      return l10n.fnthinkPairKeySwapped(peer);
    }
    final granted = answer.result.grantedLevel;
    if (granted == null) return l10n.fnthinkPairNoGrantedLevel;
    return l10n.fnthinkPairApproved(peer, granted);
  }

  /// 划掉名单里的一台（T31 B 片那一发的入口）。
  ///
  /// ⚠ 参数写成位置式，与 [_answer] 同一条理由：T06 那条守卫的锚点要不带 `{` 的签名
  ///    （`blockAfter` 会停在命名参数表那个花括号上，取到的是参数表而不是函数体）。
  /// ⚠ 页面**只交一个 bool 之外的东西都没有**：撤谁、先后怎么做、`revoked:false` 算不算成，
  ///    全在协调者那一处。页面自己先删行再发请求的话，"授权还在而来源消失"那一种就长在界面里了。
  Future<void> _revoke(FnthinkPeer peer) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final ok = await IosDialogActions.askConfirm(
      context,
      title: l10n.fnthinkRevokeAskTitle,
      message: l10n.fnthinkRevokeAskMsg(peer.peerAddress),
      // 弹层里的确认键不写"撤销"：那与列表里那个按钮同词，`find.text` 一次抓到两个，
      // 而用户也分不清自己点的是"要撤"还是"只是打开了弹层"。
      confirmText: l10n.confirm,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final revoke = await _coordinator.revokePeer(peer);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _peerRevoke = (peer: peer, revoke: revoke);
    });
    // 撤成了那一行就不该再显示；没撤成也要重读一次，因为界面那句结论说的是"此刻名单什么样"。
    // 重读走同一个读咽喉，不是页面自己数一遍（那会长出第二个排序/时间口径）。
    await _loadPeers();
  }

  /// 撤销那一发的结论。⚠ `revoked:false` 走的是**成功**那一路：撤销是幂等的
  /// （契约 `clientEvents.pairRevoke._why`），把它显示成失败会让人再点一次，而那一行一直在。
  String _peerRevokeText(
    AppLocalizations l10n,
    ({FnthinkPeer peer, FnthinkPeerRevoke revoke}) entry,
  ) {
    final revoke = entry.revoke;
    if (!revoke.ok) {
      return l10n.fnthinkRevokeFailed(revoke.reason ?? 'no-revoke');
    }
    final skipped = revoke.skipped;
    if (skipped == FnthinkPeerRemoveSkip.storeUnavailable) {
      return l10n.fnthinkRevokeStoreUnavailable;
    }
    if (skipped == FnthinkPeerRemoveSkip.removeFailed) {
      return l10n.fnthinkRevokeRowRemains;
    }
    final peer = entry.peer.peerAddress;
    if (revoke.result.revoked != true) {
      return l10n.fnthinkRevokeAlreadyGone(peer);
    }
    return l10n.fnthinkRevoked(peer);
  }

  /// 发一条给名单里那一台（§4-10 片2b）。
  ///
  /// 两件事按本仓既有纪律摆：
  ///  - **取消 ⇒ 一个字节都不发**：`showDialog` 返回 null 就早退。这一条不是想当然 ——
  ///    取消那一路是本格唯一没有"服务器帮我把关"的路径，写错的表现是"我明明点了取消"。
  ///  - **弹层的 controller 归弹层自己**（与 `_HostDialog` 同一理由）：调用方在 `await` 一返回
  ///    就 dispose，会打在还在跑退场动画的 TextField 上，而那种错只在"真点过一次"时现形。
  ///  - 页面**不判协议**：这里只把 `FnthinkSendStatus` 翻成一句人话。授权、配对、去重、
  ///    时间容差都在内核与服务端判过并反证过；页面再判一遍就是第二份实现。
  Future<void> _sendTo(FnthinkPeer peer) async {
    if (_busy) return;
    final draft = await showFnthinkSendDialog(
      context: context,
      peerAddress: peer.peerAddress,
    );
    if (draft == null || !mounted) return;
    setState(() => _busy = true);
    final result = await _coordinator.sendNotice(
      peer: peer.peerAddress,
      title: draft.title,
      text: draft.text,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _sendNote = (peer: peer, result: result);
    });
  }

  /// 建一条接入端点（T42 第七片那一发）。名字用本地化里那句默认外号，这里**不给输入框**：
  /// 这一发的价值全在"回一把只出现一次的口令"，外号是管理面那列可以以后改的东西，
  /// 而为一个非关键输入开一个弹层，就把这个页面变成了表单生命周期那类事故的发生地。
  Future<void> _createEndpoint() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final result = await _coordinator.createEndpoint(
      name: l10n.fnthinkEndpointDefaultName,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _endpoint = result;
    });
    // 建成之后，这一格**已经读过**的话立刻重读：留着"2 把"显示而实际是 3 把，与留着"3 把"
    // 而实际是 2 把说的是同一句假话，只是方向反了。还没读过就**不凭空开始读** ——
    // 那一支的界面该说的是"还没看过"，不是刚编出来的一份列表。
    if (result.ok && _endpointList != null) await _readEndpoints();
  }

  /// 读一次"这台设备名下有哪几把入口"（`/endpoint-list`，#157 第二片）。
  ///
  /// 只有按这一下才读：**不在 `initState` 里读**。那一刻服务地址与本机身份还没就位，
  /// 读回来的多半是一句失败，而界面会把"还没法读"画成屏幕上第一句话 —— 用户第一次翻开
  /// 这一格看到的反而是错误。空着并写着"还没看过"才是那一刻的真话。
  Future<void> _readEndpoints() async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await _coordinator.listEndpoints();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _endpointList = result;
    });
  }

  /// 关掉一把入口（`/endpoint-revoke`，#157 第四片）。
  ///
  /// 按 T06 那条规矩：**关掉一个东西一律二次确认**，而弹层释放之后才发那一发。
  /// 确认之后要做的事只有一件 —— 把结论记下来，然后**重新读一次列表**：
  /// 屏幕跟上服务端，而不是自己把那一行就地画灰（本机若有一份"我把它标成停了"的账，
  /// 下一次读之前它就是唯一的一份真值，而那份真值可能是错的）。
  /// 还没读过就不重读：没看过的东西不凭空生成一份列表（与 `_createEndpoint` 同一条口径）。
  ///
  /// 这一格被砸过什么（`outputs/_eprv2.report.txt` + `_eprv2b.report.txt`）：
  ///  - **SA6** `if (!ok || !mounted) return;` 摘掉（= 取消也发）⇒ 红在「弹层上点取消 ⇒ 那一发不发」。
  ///    ⚠ 这条第一次跑是 **NO FAILURE**：原来那两条只走"确定"那一支，而 `askConfirm` 本身是
  ///    await 的，摘掉早退在它们身上完全看不出来 —— 二次确认这道闸的可观察点在**取消那一路**，
  ///    于是补了这条用例再反证（不是把植入改巧一点就算完）；
  ///  - **SA7** 已停的那一行也给"关掉"按钮（`if (row.usable)` 摘掉）⇒ 红在「已经停了的那一把不再给」；
  ///  - **SA8** 关掉之后不重读 ⇒ 红在「关掉之后重读一次列表」；
  ///  - **SA9** 幂等那一句倒向"没关掉"（`if (result.revoked == false)` 摘掉）⇒
  ///    红在「那边本来就不收了 ⇒ 走成功那一路」。
  Future<void> _revokeEndpoint(FnthinkEndpointSummary row) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final ok = await IosDialogActions.askConfirm(
      context,
      title: l10n.fnthinkEndpointRevokeAskTitle,
      message: l10n.fnthinkEndpointRevokeAskMsg(row.id),
      // 弹层里的确认键不写"关掉"：与列表里那个按钮同词时，`find.text` 一次抓到两个，
      // 而用户也分不清自己点的是"要关"还是"只是打开了弹层"。
      confirmText: l10n.confirm,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final result = await _coordinator.revokeEndpoint(endpointId: row.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _endpointRevoked = result;
    });
    if (_endpointList != null) await _readEndpoints();
  }

  /// 吊销那一发的结论。⚠ `revoked:false` 走**成功**那一路（幂等：那把本来就不收了）——
  /// 报成失败会让人再点一次，而第二次换来的还是一句 200。
  String _endpointRevokeText(AppLocalizations l10n) {
    final result = _endpointRevoked;
    if (result == null) return '';
    if (!result.ok) {
      return l10n.fnthinkEndpointRevokeFailed(
        result.reason ?? 'no-endpoint-revoke',
      );
    }
    if (result.revoked == false) {
      return l10n.fnthinkEndpointRevokeAlreadyGone(result.endpointId);
    }
    return l10n.fnthinkEndpointRevoked(result.endpointId);
  }

  /// 换那把入口的口令（`/endpoint-rotate`，#157 第六片）。
  ///
  /// 也走二次确认（T06 那条规矩的另一种情形：这一发不删东西，但它**会让一把别人正在用的口令
  /// 开始倒计时** —— 手滑的代价在 NAS 那头，与删一条通道同级）。
  /// 换完之后同样重新读一次列表：`rotatingUntil` 那一行是服务端的事实，不在本机留副本。
  ///
  /// 这一格被砸过什么（`outputs/_erot2.report.txt`，RC6–RC10 全 named+restored）：
  ///  - **RC6** 二次确认那道早退摘掉（取消也发）⇒ 红在「弹层上点取消 ⇒ 那一发不发」。
  ///    ⚠ 与 SA6 同一条教训：这条用例**必须先有"取消"那一支**才谈得上可观察，
  ///    只走"确定"的用例对 `askConfirm` 的 await 是无感的；
  ///  - **RC7** 换成那一支不再显示新口令 ⇒ 红在「新口令那一行就是这一把」；
  ///  - **RC8** `rotatingUntil` 没回也硬显示 ⇒ 红在「那一行根本不出现（不编一个截止时间）」；
  ///  - **RC9** 三档文案合一（那把已停也说成失败）⇒ 红在「说"没给它换"，不出现口令行」；
  ///  - **RC10** 已停的那一行也给两下按钮 ⇒ 红在「"关掉"与"换一把"两下都不给」。
  Future<void> _rotateEndpoint(FnthinkEndpointSummary row) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final ok = await IosDialogActions.askConfirm(
      context,
      title: l10n.fnthinkEndpointRotateAskTitle,
      message: l10n.fnthinkEndpointRotateAskMsg,
      confirmText: l10n.confirm,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final result = await _coordinator.rotateEndpoint(endpointId: row.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _endpointRotated = result;
    });
    if (_endpointList != null) await _readEndpoints();
  }

  /// 换口令那一发的结论。**三档必须分开说**：换成了（新口令在上面）、那一把已经不收信了
  /// （所以没换，这不是失败）、以及真失败。把第二档并进"没换成"，用户会去再点一次，
  /// 而那一发换来的是"给一个已经不工作的端点换口令" —— 一句体面的 no-op。
  String _endpointRotateText(AppLocalizations l10n) {
    final result = _endpointRotated;
    if (result == null) return '';
    if (!result.ok) {
      return l10n.fnthinkEndpointRotateFailed(
        result.reason ?? 'no-endpoint-rotate',
      );
    }
    if (result.rotated == false) {
      return l10n.fnthinkEndpointRotateNotRotated(result.endpointId);
    }
    return l10n.fnthinkEndpointRotated(result.endpointId);
  }

  /// 待确认的配对请求那一格。
  ///
  /// 列表**跟着协调者那份账走**（`pairRequestsListenable`）：用户挂出口令之后是盯着屏幕等对面来配的，
  /// 后台每轮带回来的东西要自己上界面。页面不重新 poll（那会长出第二个"这一轮有没有货"的读法），
  /// 也不自己定定时器去翻（那种"什么时候该看"的口径一漏，表现就是列表看着看着不再更新）。
  /// 空列表**不画这一格** —— 一张永远空的表等于让界面猜；但答过一条之后要留着：那一条已经
  /// 从列表里摘掉了，如果连结论一起消失，用户回头就看不出自己刚才到底是同意还是被拒了。
  Widget _buildPairRequests(AppLocalizations l10n) {
    return ListenableBuilder(
      listenable: _coordinator.pairRequestsListenable,
      builder: (context, _) {
        final requests = _coordinator.pendingPairRequests;
        final answer = _pairAnswer;
        if (requests.isEmpty && answer == null) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: _Card(
            title: l10n.fnthinkPairRequests,
            children: [
              for (final request in requests)
                ..._pairRequestRows(l10n, request),
              if (answer != null)
                _Note(
                  keyName: 'fnthink-pair-answer',
                  text: _pairAnswerText(l10n, answer),
                ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _pairRequestRows(
    AppLocalizations l10n,
    FnthinkPairRequest request,
  ) {
    // 这一档是不是本机够得着的：`grantableLevel` 回 null 就是词表里没有那个词。
    // 词表里没有 ⇒ **同意不许点**（协调者那一发也不会发出去，但把按钮灰掉比让用户点下去
    // 再读一句 `unknown-level:xxx` 诚实），拒绝仍然可以 —— 划掉一条看不懂的请求不需要档位。
    final grantable = _contract?.grantableLevel(request.level);
    final capped = grantable != null && grantable != request.level;
    return [
      _Note(
        keyName: 'fnthink-pair-request-${request.requestId}',
        text: l10n.fnthinkPairRequestLine(request.requester, request.level),
      ),
      if (capped)
        _Note(
          keyName: 'fnthink-pair-will-grant-${request.requestId}',
          text: l10n.fnthinkPairWillGrant(grantable),
        ),
      if (grantable == null)
        _Note(
          keyName: 'fnthink-pair-unknown-level-${request.requestId}',
          text: l10n.fnthinkPairUnknownLevel(request.level),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              key: ValueKey('fnthink-pair-approve-${request.requestId}'),
              onPressed: grantable == null || _busy
                  ? null
                  : () => _answer(request, true),
              child: Text(l10n.fnthinkPairApprove),
            ),
            TextButton(
              key: ValueKey('fnthink-pair-deny-${request.requestId}'),
              onPressed: _busy ? null : () => _answer(request, false),
              child: Text(l10n.fnthinkPairDeny),
            ),
          ],
        ),
      ),
    ];
  }

  /// 本机配对名单那一格（T42「配对名单」）。
  ///
  /// 与待确认列表不同，**这一格总是画**：待确认那张表在没有作者时永远是空的（所以不摆），
  /// 而名单已经有人写了（第五片），此时"还没有配对过任何设备"是一句可行动的真话。
  /// 但"读不出来"与"一条都没有"必须是两句不同的话（见 `_peers` 的注释）。
  ///
  /// ⚠ 底下那句边界不是客套：这一格记的是**本机同意过谁**，而「撤销」撤的是服务端那份授权
  /// （契约 `pairing.relationshipStoredOn`）。顺序是**先撤服务端、再删本机这一行**，反过来做
  /// 会出现"授权还在而来源从屏幕上消失"那一种最难发现的静默；已经收到的通知不在这一发的范围里
  /// （契约 revocation 那一节：撤销只停投递，不删历史）；而对面那台给本机的许可，只有它自己能撤。
  ///
  /// 这一格被砸过什么（读那一半的报告在 `outputs/_peers_falsify.report.txt`，撤销那一半在
  /// `outputs/_revokepeer.report.txt`，按约定不入库）：
  ///  - 渲染层把"读失败"当成空表 ⇒ 红在「名单读不出来 ⇒ 贴原话，不许显示成"还没有配对过任何设备"」；
  ///  - 读失败时 `_loadPeers` 退回 `const []` ⇒ 红在同一条（两处都能把假话说圆，所以都钉）；
  ///  - 答复之后不重读名单 ⇒ 红在「同意之后名单重读一次」；
  ///  - 边界那句被换成另一句话 ⇒ 红在「边界那句在场」（那条断言比的是**这一句**，不是"有个非空 Text"）；
  ///  - `grantedAt=0` 被格式化 ⇒ 红在「那一行写"—"，不写成 1970 年」。
  /// 撤销那两下被砸过什么（`outputs/_revokepeer.report.txt`）：
  ///  - **U1** 撤成之后不重读名单 ⇒ 红在「撤成 ⇒ 那一行从格子里消失」；
  ///  - **U4** 把 `askConfirm` 那一段整个摘掉 ⇒ 红在「点了不等于撤了」（第一版植入只改条件
  ///    `if (!ok …)` ⇒ 全场仍绿，因为 `await askConfirm` 还在那儿挡着：弹层仍然会开，
  ///    用例点确认后一切照旧。植入要改的是**调用本身**，不是它的返回值）。
  /// ⚠ R1 的第一版植入（`if (rows == null)` 改成 `if (false)`）**编译不过**：摘掉那个分支后
  ///    `rows.isEmpty` 的空接收者就是错误。那属于"植入本身无效"，不能算这条判据没效果 ——
  ///    换成 `_peers ?? const <FnthinkPeer>[]` 才是它的合法植入。
  Widget _buildPeersCard(AppLocalizations l10n) {
    final rows = _peers;
    final revokeEntry = _peerRevoke;
    return _Card(
      title: l10n.fnthinkPeersTitle,
      children: [
        if (rows == null)
          _Note(
            keyName: 'fnthink-peers-error',
            text: l10n.fnthinkPeersError(_peersError ?? ''),
          )
        else if (rows.isEmpty)
          _Note(keyName: 'fnthink-peers-empty', text: l10n.fnthinkPeersEmpty)
        else
          for (final peer in rows) ...[
            _Note(
              keyName: 'fnthink-peer-${peer.peerAddress}',
              text: l10n.fnthinkPeerLine(
                peer.peerAddress,
                peer.level,
                _formatTime(peer.grantedAt),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: ValueKey('fnthink-peer-revoke-${peer.peerAddress}'),
                // 撤销那一发要能连点两下都不出事（服务端幂等），但 `_busy` 仍然拦：
                // 拦的不是"撤两次"，是"两次删行撞在一起"——那种时候界面显示的是哪一次？
                onPressed: _busy ? null : () => _revoke(peer),
                child: Text(l10n.fnthinkPeerRevoke),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: ValueKey('fnthink-peer-send-${peer.peerAddress}'),
                // 「发一条」挂在**这一行**上而不是页面顶部一个通用按钮：收件人只能是本机
                // 同意过的那几台（名单就是候选全集），让人先在行里选中那台再填内容，
                // 比在弹层里再挑一次少一处可能填错的地址（填错了服务端只会回一句同形的 403）。
                onPressed: _busy ? null : () => _sendTo(peer),
                child: Text(l10n.fnthinkPeerSend),
              ),
            ),
          ],
        if (_sendNote != null)
          _Note(
            keyName: 'fnthink-send-note',
            text: _sendNote == null
                ? ''
                : fnthinkSendResultText(l10n, _sendNote!.result),
          ),
        if (revokeEntry != null)
          _Note(
            keyName: 'fnthink-peer-revoke-note',
            text: _peerRevokeText(l10n, revokeEntry),
          ),
        const SizedBox(height: 8),
        _Note(
          keyName: 'fnthink-peers-boundary',
          text: l10n.fnthinkPeersBoundary,
        ),
      ],
    );
  }

  /// 接入端点那一格（T42 第七片建、#157 第二片读）。
  ///
  /// 为什么这一格值得存在：以前只有管理面能建端点，自部署的用户要给自家 NAS 铸一把入口，
  /// 得先拿出那把能做远多于这件事的 admin token。
  /// 现在这一格是**建 + 读 + 关 + 换**：四件事全走设备面签名事件（self-only），
  /// 所以"我建过哪些、哪把还不收信、这把我要关掉、这把口令要换"都能在手机上说完，不必碰管理面。
  /// ⚠ 「换」与其余三件有一处根本不同：它**留下一段两把口令同时有效的时间**
  /// （契约 `endpoint.rotation.graceSeconds`）。所以界面必须把"旧的那把到什么时候算死"一起说清楚 ——
  /// 只报新口令不报截止日期，等于让人在不知道后果的情况下排自己的活儿。那一行只在服务端回了
  /// `rotatingUntil` 时出现；没回就不编。
  /// ⚠ 口令那一行只在这次 `setState` 之后存在：不写 prefs、不写表、不进日志（见 `_endpoint`）。
  /// 读回来的那份也不写：端点表的真值在服务端，本机留副本就是一本会漂的账。
  ///
  /// 这一格被砸过什么（`outputs/_endpntpeer.report.txt`）：
  ///  - **X4** 把"成功那一支"的判定从 `created.ok` 换成 `created != null` ⇒ 红在
  ///    「没建成 ⇒ 贴原话，且不出现口令行」（两支各红一条，另一支是"读不出口令"那一条）；
  ///  - **X5** 上限那句写死 `10` ⇒ 红在「上限那句里的数来自契约」。⚠ 这条用例第一版是**假绿**的：
  ///    它拿 `contract.endpointMaxPerDevice` 去比界面 —— 两边读同一个数，写死与读契约当场分不出来。
  ///    改成"喂一份 `perDeviceMax: 3` 的契约进去，断言界面说 3"，才是真的在断"读过"。
  ///  - 读那半被砸过什么（`outputs/_eplist2.report.txt`、`_eplist2b.report.txt`）：
  ///    **Z6** 建成之后不看"有没有读过"就重读 ⇒ 红在「还没读过就建一把 ⇒ 不凭空开始读」；
  ///    **Z7** `else if (!listing.ok)` 反了 ⇒ 三条一起红（"确实没有"与"这次没读到"是同一支的
  ///    两面，翻倒之后两头都在说谎）；
  ///    **Z8** 把"还没读过"那一支的 keyName 换掉 ⇒ 红在「只是翻开页面 ⇒ ...而界面说的是"还没读过"」。
  ///    ⚠ Z8 第一次的写法是 `if (false)`，那是**语法不过**（`listing` 没被提升成非空，
  ///    后面的 `listing.ok` 报 receiver 可为 null），不能读成"这条断言没覆盖"。
  Widget _buildEndpointCard(AppLocalizations l10n) {
    final created = _endpoint;
    final listing = _endpointList;
    final rotated = _endpointRotated;
    // 上限那个数从契约读（页面不写 10）：它改小的时候这句解释不能跟着说谎。
    final cap = _contract?.endpointMaxPerDevice;
    return _Card(
      title: l10n.fnthinkEndpointTitle,
      children: [
        _Note(keyName: 'fnthink-endpoint-why', text: l10n.fnthinkEndpointWhy),
        if (cap != null)
          _Note(
            keyName: 'fnthink-endpoint-cap',
            text: l10n.fnthinkEndpointCap(cap),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const ValueKey('fnthink-endpoint-create'),
            onPressed: _busy ? null : () => _createEndpoint(),
            child: Text(l10n.fnthinkEndpointCreate),
          ),
        ),
        if (created != null)
          if (created.ok) ...[
            _Note(
              keyName: 'fnthink-endpoint-id',
              text: l10n.fnthinkEndpointId(created.endpointId!),
            ),
            SelectableText(
              l10n.fnthinkEndpointSecret(created.secret!),
              key: const ValueKey('fnthink-endpoint-secret'),
            ),
            _Note(
              keyName: 'fnthink-endpoint-once',
              text: l10n.fnthinkEndpointOnce,
            ),
          ] else
            _Note(
              keyName: 'fnthink-endpoint-error',
              text: l10n.fnthinkEndpointFailed(created.reason ?? 'no-endpoint'),
            ),
        // ↓↓↓ 读的那半。三种"没有列表"必须分开说：还没读、读了但没读到、读到了确实没有。
        // 把它们合成一句"你还没有端点"，用户就会在第一次读失败那天下 NAS 的定时任务。
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const ValueKey('fnthink-endpoint-read'),
            onPressed: _busy ? null : _readEndpoints,
            child: Text(l10n.fnthinkEndpointListRead),
          ),
        ),
        if (listing == null)
          _Note(
            keyName: 'fnthink-endpoint-list-pending',
            text: l10n.fnthinkEndpointListPending,
          )
        else if (!listing.ok)
          _Note(
            keyName: 'fnthink-endpoint-list-failed',
            text: l10n.fnthinkEndpointListFailed(
              listing.reason ?? 'no-endpoint-list',
            ),
          )
        else if (listing.endpoints!.isEmpty)
          _Note(
            keyName: 'fnthink-endpoint-list-none',
            text: l10n.fnthinkEndpointNone,
          )
        else
          for (final row in listing.endpoints!) ...[
            _Note(
              keyName: 'fnthink-endpoint-row-${row.id}',
              text:
                  '${row.name.isEmpty ? l10n.fnthinkEndpointRowUnnamed(row.id) : l10n.fnthinkEndpointRowNamed(row.name, row.id)}'
                  ' · '
                  '${row.usable ? l10n.fnthinkEndpointUsable : l10n.fnthinkEndpointNotUsable(row.status)}',
            ),
            // 已经不收信的那一把**不再给"关掉"或"换一把"那两下**：那一行没有可操作的东西了，
            // 而给它一个按下去只会拿到一句幂等答复的按钮，等于在界面上摆一个假动作。
            // （真要再对外提供一个入口，正确动作是上面那一下"建一个端点"。）
            if (row.usable) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: ValueKey('fnthink-endpoint-revoke-${row.id}'),
                  onPressed: _busy ? null : () => _revokeEndpoint(row),
                  child: Text(l10n.fnthinkEndpointRevoke),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: ValueKey('fnthink-endpoint-rotate-${row.id}'),
                  onPressed: _busy ? null : () => _rotateEndpoint(row),
                  child: Text(l10n.fnthinkEndpointRotate),
                ),
              ),
            ],
          ],
        if (_endpointRevoked != null)
          _Note(
            keyName: 'fnthink-endpoint-revoke-note',
            text: _endpointRevokeText(l10n),
          ),
        if (rotated != null) ...[
          // ⚠ 这两行是这一格第二处"明文只出现一次"：口令不落盘、不缓存，这一格翻过去就没了。
          // 键名刻意与创建那一次的分开（同一份 children 里两个同值 ValueKey 会直接抛）。
          if (rotated.exchanged) ...[
            SelectableText(
              l10n.fnthinkEndpointSecret(rotated.secret!),
              key: const ValueKey('fnthink-endpoint-rotated-secret'),
            ),
            _Note(
              keyName: 'fnthink-endpoint-rotated-once',
              text: l10n.fnthinkEndpointOnce,
            ),
            // "旧的那把什么时候算死"：没回就不猜 —— 编一个时间会让人按错的节奏去改 NAS。
            if (rotated.rotatingUntil != null)
              _Note(
                keyName: 'fnthink-endpoint-rotate-grace',
                text: l10n.fnthinkEndpointRotateGrace(
                  _formatTime(rotated.rotatingUntil!),
                ),
              ),
          ],
          _Note(
            keyName: 'fnthink-endpoint-rotate-note',
            text: _endpointRotateText(l10n),
          ),
        ],
      ],
    );
  }

  /// 名单上那一行的时刻。`grantedAt` 是本机写下的那一刻（服务端另有一份，不回给设备）。
  /// 0/负数 ⇒ '—'：显示 1970-01-01 会把"这一行没有时间"伪装成"很久以前同意过"。
  String _formatTime(int ms) {
    if (ms <= 0) return '—';
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  Future<void> _clearPairingCode() async {
    final credentials = _credentials;
    if (credentials == null) return;
    await credentials.clearPairingCode();
    if (!mounted) return;
    setState(() {
      _pairing = null;
      // 撤掉之后再进这一页，"服务器收没收"又回到"不知道"：留着上一次的确认会变成假信息。
      _pairingAcked = null;
      _pairingPublishNote = null;
    });
  }

  Future<void> _editHost() async {
    final settings = _settings;
    if (settings == null) return;
    // controller 由弹层自己持有：在 `await showDialog` 返回的那一刻 dispose 会打在有
    // 退场动画的 TextField 上（实测报 "A TextEditingController was used after being
    // disposed"，而且这条只在真点一次的时候才现形，写页面时看不出任何问题）。
    final input = await showDialog<String>(
      context: context,
      builder: (context) => _HostDialog(initial: _host),
    );
    if (input == null || !mounted) return;
    try {
      await settings.setHost(input);
      // 界面上显示的是**读回来**的那一份，不是用户敲进去的那一份（setHost 会归一小写）。
      final stored = await settings.host;
      // ⚠ 换了地址必须重启循环 —— 与上面"重置地址码"那一条同一个理由：循环握的是**启动那一刻
      //   定型的 baseUri**，不重启就是"屏幕上写着新地址，而货还在从旧地址取"（症状是"地址明明改了
      //   却连不上"，而改回来的那一下又"没反应"）。排在 mounted 判断之前：值已经改了，
      //   页面关没关都不该把循环留在旧地址上。
      if (_running) {
        _coordinator.stop();
        await _coordinator.startIfEnabled();
      }
      if (!mounted) return;
      setState(() {
        _host = stored;
        _hostError = null;
        _running = _coordinator.isRunning;
      });
    } on FnthinkSettingsInvalid catch (e) {
      // 不改值、只把那句话贴出来：校验的唯一出处在 FnthinkSettings，这里不自己判一遍。
      if (!mounted) return;
      setState(() => _hostError = e.reason);
    }
  }

  Future<void> _restoreDefaultHost() async {
    final settings = _settings;
    if (settings == null) return;
    try {
      await settings.setHost(settings.defaultHost);
      final stored = await settings.host;
      // 恢复默认也是换地址 ⇒ 同一个重启（理由见上面 `_editHost` 那一段）
      if (_running) {
        _coordinator.stop();
        await _coordinator.startIfEnabled();
      }
      if (!mounted) return;
      setState(() {
        _host = stored;
        _hostError = null;
      });
    } on FnthinkSettingsInvalid catch (e) {
      if (!mounted) return;
      setState(() => _hostError = e.reason);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(
        title: Text(
          l10n.fnthinkPush,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (_contractError != null)
            _buildNoteCard(
              keyName: 'fnthink-contract-error',
              icon: Icons.info_outline,
              text: l10n.fnthinkContractUnavailable(_contractError!),
            )
          else ...[
            _buildReceiveCard(l10n),
            const SizedBox(height: 12),
            _buildIdentityCard(l10n),
            // 待确认的配对请求（画不画由它自己按协调者那份账判，见 `_buildPairRequests`）。
            _buildPairRequests(l10n),
            const SizedBox(height: 12),
            _buildPeersCard(l10n),
            const SizedBox(height: 12),
            _buildEndpointCard(l10n),
            const SizedBox(height: 12),
            _buildServerCard(l10n),
            const SizedBox(height: 12),
            _buildBoundaryCard(l10n),
          ],
        ],
      ),
    );
  }

  Widget _buildReceiveCard(AppLocalizations l10n) {
    return _Card(
      title: l10n.fnthinkReceive,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.fnthinkReceiveDesc,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
            ),
            // onChanged 传 null 就是灰态：契约拿不到时这一格不许被翻开。
            CupertinoSwitch(
              key: const ValueKey('fnthink-receive-switch'),
              value: _enabled,
              onChanged: _contractError == null && !_busy
                  ? _toggleReceive
                  : null,
            ),
          ],
        ),
        _StatusRow(
          keyName: 'fnthink-receive-status',
          dot: _running,
          text: _running ? l10n.fnthinkStatusRunning : l10n.fnthinkStatusIdle,
        ),
        // 同意门（T56）：**开着开关也不等于同意中转**。这一行在没同意时始终在场，
        // 并把三情形说明摆在按钮后面 —— 用户要能一眼看出"关掉接收"与"不让人中转内容"
        // 是两件不同的事，而后者没有任何一处会自动替他做。
        if (!_consented) ...[
          _Note(
            keyName: 'fnthink-consent-pending',
            text: l10n.fnthinkConsentPending,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: CupertinoButton.filled(
              key: const ValueKey('fnthink-consent-agree'),
              onPressed: _busy ? null : _grantConsent,
              child: Text(l10n.fnthinkConsentTitle),
            ),
          ),
        ] else
          _Note(
            keyName: 'fnthink-consent-granted',
            text: l10n.fnthinkConsentGranted,
          ),
        // T60（approach B）：这一台对着当前服务器最近一次发送通没通过。
        // 只在同意之后画 —— 没同意时任何一发都在本机就被挡下（没有"服务器通不通"这回事），
        // 画出来只会把"还没同意"错读成"服务器坏了"。
        if (_consented)
          _Note(
            keyName: 'fnthink-server-health',
            text: _serverHealthText(l10n),
          ),
        // 「被杀之后还有没有人去问一次货」（T33 第二片 / §4-9）：这一行读的是**原生那份排程**。
        // 收货循环活着 ≠ 闹钟排着（进程被杀之后正是"循环没了而闹钟还在"），所以两行必须分开说。
        // 还没有读到（读口抛过、或这一页刚起来）时**不画这一行** —— 画一句"没在醒着"是假话。
        if (_presence != null)
          _Note(keyName: 'fnthink-presence-next', text: _presenceText(l10n)),
        if (_startNote != null)
          _Note(keyName: 'fnthink-start-note', text: _startNote!),
        if (_roundNote != null)
          _Note(keyName: 'fnthink-round-note', text: _roundNote!),
        if (_lastRound != null)
          _Note(keyName: 'fnthink-last-round', text: _lastRound!),
        Align(
          alignment: Alignment.centerLeft,
          child: CupertinoButton(
            key: const ValueKey('fnthink-receive-now'),
            onPressed: _enabled && !_busy ? _receiveNow : null,
            child: Text(l10n.fnthinkReceiveNow),
          ),
        ),
      ],
    );
  }

  Widget _buildIdentityCard(AppLocalizations l10n) {
    final code = _addressCode;
    final pairing = _pairing;
    return _Card(
      title: l10n.fnthinkIdentitySection,
      children: [
        _RowLabel(
          label: l10n.fnthinkAddressCode,
          keyName: 'fnthink-address-code',
        ),
        Row(
          children: [
            Expanded(
              child: SelectableText(
                code ?? l10n.fnthinkAddressCodeNone,
                key: const ValueKey('fnthink-address-code-value'),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 15,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            if (code != null)
              TextButton(
                onPressed: () => _copy(code),
                child: Text(l10n.fnthinkCopy),
              ),
            TextButton(
              key: const ValueKey('fnthink-reset-code'),
              onPressed: code == null ? null : _resetAddressCode,
              child: Text(l10n.fnthinkResetCode),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _RowLabel(
          label: l10n.fnthinkPairingCode,
          keyName: 'fnthink-pairing-code',
        ),
        if (pairing == null)
          Text(
            l10n.fnthinkPairingNone,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.secondaryLabel(context),
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  pairing.code.value,
                  key: const ValueKey('fnthink-pairing-code-value'),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 15,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _copy(pairing.code.value),
                child: Text(l10n.fnthinkCopy),
              ),
            ],
          ),
        if (pairing != null)
          _Note(
            keyName: 'fnthink-pairing-age',
            text: l10n.fnthinkPairingHeld(_heldSeconds(pairing)),
          ),
        // 「已挂出」那一句说的是本机的倒计时；这一句才回答"对端能不能拿它来配"。
        // 三态分开写：没问过服务器与问过但没成，是两种完全不同的用户动作（等一等 vs 重来一次）。
        if (pairing != null && _pairingAcked == true)
          _Note(
            keyName: 'fnthink-pairing-acked',
            text: l10n.fnthinkPairingAcked,
          ),
        if (pairing != null && _pairingAcked == false)
          _Note(
            keyName: 'fnthink-pairing-local-only',
            text: l10n.fnthinkPairingLocalOnly(_pairingPublishNote ?? ''),
          ),
        if (pairing != null && _pairingAcked == null)
          _Note(
            keyName: 'fnthink-pairing-unknown',
            text: l10n.fnthinkPairingAckUnknown,
          ),
        if (pairing != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('fnthink-revoke-pairing'),
              onPressed: _clearPairingCode,
              child: Text(l10n.fnthinkRevokePairing),
            ),
          ),
        TextButton(
          key: const ValueKey('fnthink-arm-pairing'),
          onPressed: _armPairingCode,
          child: Text(l10n.fnthinkArmPairing),
        ),
        Text(
          l10n.fnthinkPairingExpireNote,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.secondaryLabel(context),
          ),
        ),
        if (_credentialError != null)
          _Note(keyName: 'fnthink-credential-error', text: _credentialError!),
        const SizedBox(height: 8),
        _RowLabel(
          label: l10n.fnthinkIdentityKey,
          keyName: 'fnthink-identity-key',
        ),
        Text(
          _identityText(l10n),
          key: const ValueKey('fnthink-identity-key-value'),
          style: TextStyle(
            fontSize: 13,
            fontFamily: 'monospace',
            color: _identityUnavailable
                ? AppColors.red
                : AppColors.primaryLabel(context),
          ),
        ),
      ],
    );
  }

  String _identityText(AppLocalizations l10n) {
    final identity = _identity;
    if (identity == null) return l10n.fnthinkKeystoreUnknown;
    final backed = identity.keystoreBacked
        ? l10n.fnthinkKeystoreOn
        : l10n.fnthinkKeystoreOff;
    // 公钥整串抄进界面没有意义（用户读不了一串 base64），只留前 8 位当"是不是同一把"的比对。
    final key = identity.publicKey;
    final short = key.length <= 8 ? key : '${key.substring(0, 8)}…';
    return '$short · $backed';
  }

  /// "挂了多久"。时间戳缺失/不是整数时显示「未知」而不是 0 秒 ——
  /// 0 秒的字面意思是"刚挂上"，那是另一个结论。
  String _heldSeconds(FnthinkArmedPairingCode pairing) {
    final age = pairing.ageMs(DateTime.now().toUtc().millisecondsSinceEpoch);
    if (age == null) return AppLocalizations.of(context).unknown;
    return '${(age / 1000).floor()}s';
  }

  Widget _buildServerCard(AppLocalizations l10n) {
    return _Card(
      title: l10n.fnthinkServerSection,
      children: [
        _RowLabel(label: l10n.fnthinkHost, keyName: 'fnthink-host'),
        Row(
          children: [
            Expanded(
              child: Text(
                _host.isEmpty ? '—' : _host,
                key: const ValueKey('fnthink-host-value'),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
              ),
            ),
            TextButton(onPressed: _editHost, child: Text(l10n.edit)),
            TextButton(
              key: const ValueKey('fnthink-host-default'),
              onPressed: _restoreDefaultHost,
              child: Text(l10n.fnthinkHostReset),
            ),
          ],
        ),
        Text(
          l10n.fnthinkHostDesc,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.secondaryLabel(context),
          ),
        ),
        if (_hostError != null)
          _Note(keyName: 'fnthink-host-error', text: _hostError!),
      ],
    );
  }

  Widget _buildBoundaryCard(AppLocalizations l10n) {
    return _buildNoteCard(
      keyName: 'fnthink-boundary',
      icon: Icons.privacy_tip_outlined,
      text: l10n.fnthinkBoundary,
    );
  }

  Widget _buildNoteCard({
    required String keyName,
    required IconData icon,
    required String text,
  }) {
    return Container(
      key: ValueKey(keyName),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AppColors.primaryLabel(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一张卡：标题 + 若干行（版式与电量/温度那几页同形）。
class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryLabel(context),
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

/// 运行状态那一行：圆点 + 一句话。点亮的颜色**只**跟着 `isRunning`。
class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.keyName,
    required this.dot,
    required this.text,
  });

  final String keyName;
  final bool dot;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            key: ValueKey('$keyName-dot'),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dot ? AppColors.green : AppColors.secondaryLabel(context),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              key: ValueKey(keyName),
              style: TextStyle(
                fontSize: 13,
                color: AppColors.secondaryLabel(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RowLabel extends StatelessWidget {
  const _RowLabel({required this.label, required this.keyName});

  final String label;
  final String keyName;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        label,
        key: ValueKey(keyName),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.secondaryLabel(context),
        ),
      ),
    );
  }
}

/// 页面里那些"原话贴出来"的行（启停原因、上一轮的账、校验失败）。
class _Note extends StatelessWidget {
  const _Note({required this.keyName, required this.text});

  final String keyName;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        text,
        key: ValueKey(keyName),
        style: TextStyle(
          fontSize: 12,
          height: 1.4,
          color: AppColors.secondaryLabel(context),
        ),
      ),
    );
  }
}

/// 改服务地址那一格用的输入弹层。**controller 归它自己管**（initState 建、dispose 释放）。
///
/// 为什么不是调用方建好 controller 传进来：调用方在 `await showDialog` 一返回就 dispose，
/// 而那时刻退场动画还在跑、TextField 还要再建一帧 —— 实测报
/// `A TextEditingController was used after being disposed`。这类形状的错误只在"真的点过一次"
/// 时现形，静态读代码看不出来，所以让它跟着路由一起生老病死。
class _HostDialog extends StatefulWidget {
  const _HostDialog({required this.initial});

  final String initial;

  @override
  State<_HostDialog> createState() => _HostDialogState();
}

class _HostDialogState extends State<_HostDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      backgroundColor: AppColors.cardBg(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(l10n.fnthinkHostEditTitle),
      content: TextField(
        key: const ValueKey('fnthink-host-input'),
        controller: _controller,
        autocorrect: false,
        decoration: InputDecoration(hintText: l10n.fnthinkHostDesc),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
