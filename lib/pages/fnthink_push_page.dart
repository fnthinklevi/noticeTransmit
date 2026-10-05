import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:get_it/get_it.dart';

import '../l10n/app_localizations.dart';
import '../models/fnthink_peer.dart';
import 'remote_credential_settings_page.dart';
import 'remote_history_page.dart';
import 'fnthink_peers_page.dart';
import 'remote_send_page.dart';
import '../services/channel_display.dart';
import '../services/channel_health_store.dart';
import '../services/fnthink_contract_loader.dart';
import '../services/fnthink_credential_store.dart';
import '../services/fnthink_endpoint_guide.dart';
import '../services/fnthink_identity_service.dart';
import '../services/fnthink_peer_service.dart';
import '../services/fnthink_presence_scheduler.dart';
import '../services/fnthink_receive_coordinator.dart';
import '../services/fnthink_settings.dart';
import '../theme/app_colors.dart';
import '../widgets/fnthink_card.dart';
import '../widgets/ios_dialog_actions.dart';
import '../widgets/ios_input_dialog.dart';
import '../widgets/ios_option_picker.dart';
import '../update_manager.dart' show AppUpdateManager;

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
  const FnthinkPushPage({super.key, this.deps, this.peersDeps});

  final FnthinkPushDeps? deps;

  /// 「已配对的设备」那一行要推的那张页的依赖（T94）。
  /// 缺省走 `FnthinkPeersDeps.fromLocator()`；测试里传一份替身——
  /// 否则「可以点」那一下会在没注册那些单例的测试里直接抛，
  /// 而一个入口行的判据正是「点得动」，不能因为装配点缺失就无法被测。
  final FnthinkPeersDeps? peersDeps;

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

  /// 「多久问一次货」那一格（T88）。整格从 `settings.pollSetting()` 一次读齐 ——
  /// 范围来自契约，页面不写任何一个节奏数字（守卫钉的就是这条）。
  FnthinkPollSetting? _poll;

  /// 拖拽中的那一档（只有拖动过程用，松手才落盘）。null = 没在拖。
  double? _pollDrag;

  /// 保存这一格失败时那句"协议不允许"（写了 `_poll.problem` 之外的另一种失败：用户刚犯的）。
  String? _pollError;

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
    unawaited(_load());
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
    await Future.wait<void>([_readEnabled(), _readPresence(), _readPoll()]);
  }

  /// 读「收取间隔」那一格（T88）。
  ///
  /// 范围与生效值都从 `FnthinkSettings` 那一个合成处来，页面自己不碰契约那个字段 ——
  /// 那是守卫钉的（页面成为第二个节奏作者时，改契约那一刀不会有任何东西报错）。
  /// 读失败（契约缺 min/max、或 prefs 里灌回来一个坏值）时**整格不画**并留下那句原话，
  /// 而不是退到一个猜出来的秒数上。
  Future<void> _readPoll() async {
    final settings = _settings;
    if (settings == null) return;
    FnthinkPollSetting? poll;
    String? error;
    try {
      poll = await settings.pollSetting();
    } on FnthinkSettingsInvalid catch (e) {
      error = e.reason;
    }
    if (!mounted) return;
    setState(() {
      _poll = poll;
      _pollError = error;
    });
  }

  /// 落一盘这一格（松手那一刻调，不是每像素一次）。
  ///
  /// ⚠ 写完必须重启循环：`FnthinkLoopSpec` 是**启动那一刻的快照**，与改地址同一条纪律 ——
  /// 不重启的表现是"屏幕上写着新间隔，而货还在按旧间隔取"，用户唯一的线索就是那个数字。
  Future<void> _savePollSeconds(int seconds) async {
    final settings = _settings;
    if (settings == null) return;
    setState(() => _busy = true);
    var saved = false;
    try {
      await settings.setPollSeconds(seconds);
      _pollError = null;
      saved = true;
    } on FnthinkSettingsInvalid catch (e) {
      // 越界不写、也**不重启**：什么都没改变断一次线，等于把"改了没反应"做成
      // "每改一次断一次"（那一句话要留在屏幕上，所以这里不重读、只把忙态摘掉）。
      _pollError = e.reason;
    }
    if (!saved) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    await _restartLoopAndReread();
  }

  /// 抹掉"用户选过"这件事 ⇒ 回到协议默认那一档（不是把默认值写进去，见 `clearPollSeconds`）。
  Future<void> _resetPollSeconds() async {
    final settings = _settings;
    if (settings == null) return;
    setState(() => _busy = true);
    await settings.clearPollSeconds();
    _pollError = null;
    await _restartLoopAndReread();
  }

  Future<void> _restartLoopAndReread() async {
    _coordinator.stop();
    await _coordinator.startIfEnabled();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _pollDrag = null;
      _running = _coordinator.isRunning;
    });
    await Future.wait<void>([_readPoll(), _readPresence()]);
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
    // T76 ⓑ 首启选路：**在同意之后**选一次（T76 §6 ③ 的次序），不在这之前 ——
    // 选路要发一次 HTTPS 请求，而"用户还没同意把内容交给服务器中转"那一刻连字节都不该出机。
    // 选完落盘 ⇒ 之后无论探测怎么变都不再自动改（§6 ⑤）。
    // ⚠ 探不到就落契约 default（`ensureFirstRunHost` 内部已兜），这一格不许因为探测失败
    //   而把"同意"这一步卡住 —— 用户已经点了同意，卡住他的后果比选错服务器更糟。
    await settings.ensureFirstRunHost();
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
    return FnthinkCard(
      title: l10n.fnthinkEndpointTitle,
      children: [
        FnthinkNote(
          keyName: 'fnthink-endpoint-why',
          text: l10n.fnthinkEndpointWhy,
        ),
        if (cap != null)
          FnthinkNote(
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
            FnthinkNote(
              keyName: 'fnthink-endpoint-id',
              text: l10n.fnthinkEndpointId(created.endpointId!),
            ),
            SelectableText(
              l10n.fnthinkEndpointSecret(created.secret!),
              key: const ValueKey('fnthink-endpoint-secret'),
            ),
            FnthinkNote(
              keyName: 'fnthink-endpoint-once',
              text: l10n.fnthinkEndpointOnce,
            ),
          ] else
            FnthinkNote(
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
          FnthinkNote(
            keyName: 'fnthink-endpoint-list-pending',
            text: l10n.fnthinkEndpointListPending,
          )
        else if (!listing.ok)
          FnthinkNote(
            keyName: 'fnthink-endpoint-list-failed',
            text: l10n.fnthinkEndpointListFailed(
              listing.reason ?? 'no-endpoint-list',
            ),
          )
        else if (listing.endpoints!.isEmpty)
          FnthinkNote(
            keyName: 'fnthink-endpoint-list-none',
            text: l10n.fnthinkEndpointNone,
          )
        else
          for (final row in listing.endpoints!) ...[
            FnthinkNote(
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
          FnthinkNote(
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
            FnthinkNote(
              keyName: 'fnthink-endpoint-rotated-once',
              text: l10n.fnthinkEndpointOnce,
            ),
            // "旧的那把什么时候算死"：没回就不猜 —— 编一个时间会让人按错的节奏去改 NAS。
            if (rotated.rotatingUntil != null)
              FnthinkNote(
                keyName: 'fnthink-endpoint-rotate-grace',
                text: l10n.fnthinkEndpointRotateGrace(
                  fnthinkFormatTime(rotated.rotatingUntil!),
                ),
              ),
          ],
          FnthinkNote(
            keyName: 'fnthink-endpoint-rotate-note',
            text: _endpointRotateText(l10n),
          ),
        ],
        // ── T87：怎么调用这一把（教程 + 三枚复制）──
        // 出现条件按页面既有三态判：**真用过**才给教程。`listing == null` 是"还没读"，
        // 不是"没有" —— 把"还没读"当"没有"，这一格就在用户第一次读失败那天安静消失。
        if (_endpointUsed(created, rotated, listing))
          ..._buildEndpointTutorial(l10n, created, rotated),
      ],
    );
  }

  /// 真用过 = 这一页刚建成 / 刚换过一把，或读过列表且名下确实有端点。
  /// ⚠ 三种"没有列表"里只有"读到且为空"算没用过；"还没读"与"没读到"都不把这一格点亮 ——
  ///   前者是没发生过，后者是服务器那边刚出过事，两种情况下教程都会误导人去改 NAS。
  bool _endpointUsed(
    FnthinkEndpointCreateResult? created,
    FnthinkEndpointRotateResult? rotated,
    FnthinkEndpointListResult? listing,
  ) {
    if (created?.ok ?? false) return true;
    if (rotated?.exchanged ?? false) return true;
    return listing?.ok == true && (listing?.endpoints?.isNotEmpty ?? false);
  }

  /// 教程那一格的 children（T87）。做成"一串 widget"而不是一个弹层：
  /// 口令只活在这一页的内存里，把教程挪进弹层就会让人以为"关掉弹层它还在那儿"。
  ///
  /// ⚠ 网址、命令、字段别名**一律不在这个文件里拼**：全部出自 `FnthinkEndpointGuide`
  ///   （路径与别名的唯一作者是契约）。这里重打一遍 `/api/fnthink/p/…`，服务器换前缀时
  ///   界面会安静地教一条 404 的路径。
  List<Widget> _buildEndpointTutorial(
    AppLocalizations l10n,
    FnthinkEndpointCreateResult? created,
    FnthinkEndpointRotateResult? rotated,
  ) {
    final contract = _contract;
    // 契约读不到就整格不给（不给半条地址）：路径与别名都只有一份作者，缺了就只剩猜。
    if (contract == null) return const [];
    // 手上还有口令明文的只有这两次：创建那一次、轮换那一次。列表那半永远没有。
    final createdOk = created?.ok ?? false;
    final rotatedOk = rotated?.exchanged ?? false;
    final heldId = createdOk
        ? created!.endpointId
        : (rotatedOk ? rotated!.endpointId : null);
    final heldSecret = createdOk
        ? created!.secret
        : (rotatedOk ? rotated!.secret : null);
    final guide = FnthinkEndpointGuide.from(
      host: _host,
      endpointId: heldId ?? '',
      secret: heldSecret,
      contract: contract,
    );
    Widget copyButton(String keyName, String label, String? text) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          key: ValueKey(keyName),
          // 这一页手上没有那一段东西 ⇒ 置灰，而不是复制一条拼了一半的假命令。
          onPressed: _busy || text == null ? null : () => _copy(text),
          child: Text(label),
        ),
      );
    }

    return [
      FnthinkNote(
        keyName: 'fnthink-endpoint-tutorial-title',
        text: l10n.fnthinkEndpointTutorial,
      ),
      if (guide.postUrl.isNotEmpty)
        SelectableText(
          guide.postUrl,
          key: const ValueKey('fnthink-endpoint-post-url'),
        ),
      FnthinkNote(
        keyName: 'fnthink-endpoint-post-why',
        text: l10n.fnthinkEndpointPostWhy,
      ),
      // GET 那一支永远只有形状（口令进 URL ⇒ 进反代 access log；T89 未配之前不给真口令）。
      if (guide.getShape.isNotEmpty)
        SelectableText(
          guide.getShape,
          key: const ValueKey('fnthink-endpoint-get-shape'),
        ),
      FnthinkNote(
        keyName: 'fnthink-endpoint-get-warning',
        text: l10n.fnthinkEndpointGetWarning,
      ),
      FnthinkNote(
        keyName: 'fnthink-endpoint-fields',
        text: l10n.fnthinkEndpointFieldAlias(
          guide.titleAliases.join('、'),
          guide.bodyAliases.join('、'),
        ),
      ),
      copyButton(
        'fnthink-endpoint-copy-id',
        l10n.fnthinkEndpointCopyId,
        heldId,
      ),
      copyButton(
        'fnthink-endpoint-copy-secret',
        l10n.fnthinkEndpointCopySecret,
        heldSecret,
      ),
      copyButton(
        'fnthink-endpoint-copy-command',
        l10n.fnthinkEndpointCopyCommand,
        guide.canCopyCommand ? guide.copyCommand : null,
      ),
      FnthinkNote(
        keyName: 'fnthink-endpoint-copy-hint',
        text: l10n.fnthinkEndpointCopyHint,
      ),
    ];
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
    // controller 归弹层自己管（T90 片8 起 = 共享件里的 Stateful 那一位）：在
    // `await` 返回的那一刻 dispose 会打在还有退场动画的输入框上（实测报
    // "A TextEditingController was used after being disposed"，只在真点一次时才现形）。
    // 原来那枚 `_HostDialog` 就是为这件事存在的，现在由装配点承担 ⇒ 类删掉。
    final l10n = AppLocalizations.of(context);
    final input = await showIosInputDialog(
      context,
      title: l10n.fnthinkHostEditTitle,
      initialText: _host,
      hintText: l10n.fnthinkHostDesc,
      // 用例按这把 key 点这一格（test/widgets/fnthink_push_page_test.dart 四处）⇒ 沿用旧 key。
      fieldKeyValue: 'fnthink-host-input',
      // 主机名不该被自动纠错改成别的词（改错了是"地址明明对却连不上"）。
      autocorrect: false,
    );
    if (input == null || !mounted) return;
    try {
      await _applyHost(input);
    } on FnthinkSettingsInvalid catch (e) {
      if (!mounted) return;
      setState(() => _hostError = e.reason);
    }
  }

  /// T76 双地域：在契约声明的那两台里选一台。
  ///
  /// ⚠ **这一格与"手动填地址"并存，不是替代它**：自部署（T75）要填的是**契约里没有的**
  /// 第三个地址，把它换掉就等于砍掉自部署那条路。
  /// ⚠ 选项恒是契约声明的两台，**不按"探测通不通"过滤**（§6 的口径）：探测不通该显示
  /// "不可用"，而不是把那一档从候选里拿走 —— 拿走之后用户就没有回去的路。
  Future<void> _pickHostRegion() async {
    final settings = _settings;
    if (settings == null) return;
    final l10n = AppLocalizations.of(context);
    final choices = settings.declaredHosts;
    if (choices.isEmpty) {
      if (!mounted) return;
      setState(() => _hostError = l10n.fnthinkHostNoCandidates);
      return;
    }
    // ⚠ 先把当前那台读出来再开弹层：`selectedValue: await settings.host` 写在实参里时，
    //   那个 await 落在 `showIosOptionPicker(context, …)` **之前** ⇒ analyzer 会喊
    //   "BuildContext 跨 async gap"，而它喊的是真问题（页面可能已经走了）。
    final current = await settings.host;
    if (!mounted) return;
    final picked = await showIosOptionPicker<String>(
      context,
      title: l10n.fnthinkHostSwitch,
      // 选中打勾落在"当前这一台"上：换之前先看得见现在连的是哪台。
      selectedValue: current,
      options: [
        for (final c in choices)
          IosPickerOption<String>(
            value: c.host,
            label: c.host,
            description: c.key == 'international'
                ? l10n.fnthinkHostRegionInternational
                : l10n.fnthinkHostRegionMainland,
          ),
      ],
    );
    if (picked == null || !mounted) return;
    try {
      await _applyHost(picked);
    } on FnthinkSettingsInvalid catch (e) {
      if (!mounted) return;
      setState(() => _hostError = e.reason);
    }
  }

  /// 换地址之后的那一套：写值 → 读回 → **重启收货循环** → 刷界面。
  ///
  /// ⚠ 重启不是锦上添花：循环握的是**启动那一刻定型的 baseUri**，不重启就是
  /// "屏幕上写着新地址，而货还在从旧地址取"（症状是"地址明明改了却连不上"，
  /// 而改回来的那一下又没反应）。手工填地址与选两台之一**共用这一段** ——
  /// 抄一份就多一处将来会漏掉重启的地方。
  Future<void> _applyHost(String value) async {
    final settings = _settings;
    if (settings == null) return;
    await settings.setHost(value);
    // 界面上显示的是**读回来**的那一份，不是用户给的那一份（setHost 会归一小写）。
    final stored = await settings.host;
    // 排在 mounted 判断之前：值已经改了，页面关没关都不该把循环留在旧地址上。
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
  }

  Future<void> _restoreDefaultHost() async {
    final settings = _settings;
    if (settings == null) return;
    try {
      await settings.setHost(settings.defaultHost);
      final stored = await settings.host;
      // 恢复默认也是换地址 ⇒ 同一个重启（理由见 `_applyHost`）
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
            _buildPeersEntryCard(l10n),
            const SizedBox(height: 12),
            _buildEndpointCard(l10n),
            const SizedBox(height: 12),
            _buildRemoteExecCard(l10n),
            const SizedBox(height: 12),
            _buildServerCard(l10n),
            const SizedBox(height: 12),
            _buildBoundaryCard(l10n),
          ],
        ],
      ),
    );
  }

  /// 「已配对的设备」那一行入口（T94 片1）。
  ///
  /// 为什么是入口而不是内容：设备绑定是**两台设备之间**的关系，而这一页讲的是**这台设备**
  /// 的身份与服务地址。同一张页里摆两件事，用户配错时看不出自己刚动的是哪一个 ——
  /// 而这两个决定的代价完全不同（换地址码要重新配对，撤销一台只影响那一台）。
  Widget _buildPeersEntryCard(AppLocalizations l10n) {
    return FnthinkCard(
      title: l10n.fnthinkPeersTitle,
      children: [
        FnthinkNote(
          keyName: 'fnthink-peers-entry-desc',
          text: l10n.fnthinkPushPeersDesc,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const ValueKey('fnthink-peers-entry'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => FnthinkPeersPage(deps: widget.peersDeps),
              ),
            ),
            child: Text(l10n.fnthinkPeersGo),
          ),
        ),
      ],
    );
  }

  Widget _buildReceiveCard(AppLocalizations l10n) {
    return FnthinkCard(
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
        FnthinkStatusRow(
          keyName: 'fnthink-receive-status',
          dot: _running,
          text: _running ? l10n.fnthinkStatusRunning : l10n.fnthinkStatusIdle,
        ),
        // 同意门（T56）：**开着开关也不等于同意中转**。这一行在没同意时始终在场，
        // 并把三情形说明摆在按钮后面 —— 用户要能一眼看出"关掉接收"与"不让人中转内容"
        // 是两件不同的事，而后者没有任何一处会自动替他做。
        if (!_consented) ...[
          FnthinkNote(
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
          FnthinkNote(
            keyName: 'fnthink-consent-granted',
            text: l10n.fnthinkConsentGranted,
          ),
        // T60（approach B）：这一台对着当前服务器最近一次发送通没通过。
        // 只在同意之后画 —— 没同意时任何一发都在本机就被挡下（没有"服务器通不通"这回事），
        // 画出来只会把"还没同意"错读成"服务器坏了"。
        if (_consented)
          FnthinkNote(
            keyName: 'fnthink-server-health',
            text: _serverHealthText(l10n),
          ),
        // 「多久问一次货」那一格（T88）。范围与生效值都来自契约经 `FnthinkSettings` 合成后的
        // 那一份 —— 页面一个节奏数字都不写。契约那边给不出范围时**整格不画**：画一根没有
        // 范围的滑杆等于任用户选到协议不许的那一档，而那一档的代价是这台被服务端按额度持续 429。
        if (_poll case final FnthinkPollSetting poll) ...[
          FnthinkNote(
            keyName: 'fnthink-poll-title',
            text: l10n.fnthinkPollIntervalTitle,
          ),
          FnthinkNote(
            keyName: 'fnthink-poll-value',
            text: poll.chosen == null
                ? l10n.fnthinkPollIntervalUsingDefault(poll.effective)
                : l10n.fnthinkPollIntervalChosen(poll.effective),
          ),
          CupertinoSlider(
            key: const ValueKey('fnthink-poll-slider'),
            value: (_pollDrag ?? poll.effective.toDouble()).clamp(
              poll.range.min.toDouble(),
              poll.range.max.toDouble(),
            ),
            min: poll.range.min.toDouble(),
            max: poll.range.max.toDouble(),
            divisions: poll.range.max - poll.range.min,
            // 这一版本 SDK 的 `CupertinoSlider` 没有 `label`（拖动时那颗气泡），
            // 所以拖动过程中界面上那句话仍是**已生效**的那一档 —— 松手落盘并重读之后才跟上。
            // 只由"这一格正在忙"把关，**不由接收开关把关**：这是设置而不是运行状态 ——
            // 开着关着的设备都该能在换机后先把这一档配好。（关掉时下面那发重启本身就是空转。）
            onChanged: _busy ? null : (v) => setState(() => _pollDrag = v),
            onChangeEnd: _busy ? null : (v) => _savePollSeconds(v.round()),
          ),
          FnthinkNote(
            keyName: 'fnthink-poll-range',
            text: l10n.fnthinkPollIntervalRange(poll.range.min, poll.range.max),
          ),
          FnthinkNote(
            keyName: 'fnthink-poll-tradeoff',
            text: l10n.fnthinkPollIntervalTradeoff,
          ),
          // prefs 里存着协议不许的那一档（备份恢复灌回来的那一种）与"刚刚那一盘被拒"是两处，
          // 分开画：前者是历史留下的、后者是这一次做的，用户的下一步动作不一样。
          if (poll.problem case final String problem)
            FnthinkNote(
              keyName: 'fnthink-poll-problem',
              text: l10n.fnthinkPollIntervalInvalid(problem),
            ),
          if (_pollError case final String reason)
            FnthinkNote(
              keyName: 'fnthink-poll-error',
              text: l10n.fnthinkPollIntervalInvalid(reason),
            ),
          if (poll.chosen != null)
            Align(
              alignment: Alignment.centerLeft,
              child: CupertinoButton(
                key: const ValueKey('fnthink-poll-reset'),
                onPressed: _busy ? null : _resetPollSeconds,
                child: Text(l10n.fnthinkPollIntervalReset),
              ),
            ),
        ],
        // 「被杀之后还有没有人去问一次货」（T33 第二片 / §4-9）：这一行读的是**原生那份排程**。
        // 收货循环活着 ≠ 闹钟排着（进程被杀之后正是"循环没了而闹钟还在"），所以两行必须分开说。
        // 还没有读到（读口抛过、或这一页刚起来）时**不画这一行** —— 画一句"没在醒着"是假话。
        if (_presence != null)
          FnthinkNote(
            keyName: 'fnthink-presence-next',
            text: _presenceText(l10n),
          ),
        if (_startNote != null)
          FnthinkNote(keyName: 'fnthink-start-note', text: _startNote!),
        if (_roundNote != null)
          FnthinkNote(keyName: 'fnthink-round-note', text: _roundNote!),
        if (_lastRound != null)
          FnthinkNote(keyName: 'fnthink-last-round', text: _lastRound!),
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
    return FnthinkCard(
      title: l10n.fnthinkIdentitySection,
      children: [
        FnthinkRowLabel(
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
        FnthinkRowLabel(
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
          FnthinkNote(
            keyName: 'fnthink-pairing-age',
            text: l10n.fnthinkPairingHeld(_heldSeconds(pairing)),
          ),
        // 「已挂出」那一句说的是本机的倒计时；这一句才回答"对端能不能拿它来配"。
        // 三态分开写：没问过服务器与问过但没成，是两种完全不同的用户动作（等一等 vs 重来一次）。
        if (pairing != null && _pairingAcked == true)
          FnthinkNote(
            keyName: 'fnthink-pairing-acked',
            text: l10n.fnthinkPairingAcked,
          ),
        if (pairing != null && _pairingAcked == false)
          FnthinkNote(
            keyName: 'fnthink-pairing-local-only',
            text: l10n.fnthinkPairingLocalOnly(_pairingPublishNote ?? ''),
          ),
        if (pairing != null && _pairingAcked == null)
          FnthinkNote(
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
          FnthinkNote(
            keyName: 'fnthink-credential-error',
            text: _credentialError!,
          ),
        const SizedBox(height: 8),
        FnthinkRowLabel(
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

  /// 远程执行那一格（片3b-2）：**三扇门** —— 设置、发送、历史。
  ///
  /// ⚠ 这一格刻意**不给开关**：总开关住在凭据设置页里，和凭据放在一起。
  /// 把开关摆在这一格而凭据在另一格，用户开完就走了，然后 L3 那一条条都被拒 ——
  /// 而他唯一看得到"开了"的地方是这一格。两个入口讲同一件事时，
  /// 界面上要能一眼看出它们是同一件事，所以这一格只给入口，不给状态。
  Widget _buildRemoteExecCard(AppLocalizations l10n) {
    return FnthinkCard(
      title: l10n.remoteExecSection,
      children: [
        FnthinkNote(
          keyName: 'fnthink-remote-exec-why',
          text: l10n.remoteExecWhy,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const ValueKey('fnthink-remote-exec-settings'),
            onPressed: _busy ? null : _openRemoteCredentialSettings,
            child: Text(l10n.remoteExecOpenSettings),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const ValueKey('fnthink-remote-exec-send'),
            onPressed: _busy ? null : _openRemoteSend,
            child: Text(l10n.remoteExecSendPage),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const ValueKey('fnthink-remote-exec-history'),
            onPressed: _busy ? null : _openRemoteHistory,
            child: Text(l10n.remoteExecHistory),
          ),
        ),
      ],
    );
  }

  Future<void> _openRemoteCredentialSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const RemoteCredentialSettingsPage(),
      ),
    );
  }

  Future<void> _openRemoteSend() async {
    final contract = _contract;
    if (contract == null) return;
    final coordinator = _coordinator;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RemoteSendPage(
          // 名单**只**从协调者那条读咽喉取（与本页同一份），
          // 不另开一条读库的路 —— 两处各读一次就会有两个排序口径。
          deps: RemoteSendDeps(
            loadPeers: _deps.loadPeers,
            send:
                ({
                  required String peer,
                  required String title,
                  required String text,
                }) => coordinator.sendNotice(
                  peer: peer,
                  title: title,
                  text: text,
                ),
            contractOf: () async => _deps.contracts.load(),
          ),
        ),
      ),
    );
  }

  Future<void> _openRemoteHistory() async {
    final coordinator = _coordinator;
    final loader = coordinator.loadRemoteExecutions;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RemoteHistoryPage(
          deps: RemoteHistoryDeps(
            loadRecords: (direction) async => await loader?.call(direction),
            removeRecord: (id) async =>
                await coordinator.forgetRemoteExecution?.call(id) ?? false,
            contractOf: () => _deps.contracts.load(),
          ),
        ),
      ),
    );
  }

  Widget _buildServerCard(AppLocalizations l10n) {
    return FnthinkCard(
      title: l10n.fnthinkServerSection,
      children: [
        FnthinkRowLabel(label: l10n.fnthinkHost, keyName: 'fnthink-host'),
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
            // T76 双地域：在契约声明的两台里选一台（与上面"手动填"并存 ——
            // 自部署要填的是契约里没有的第三个地址）。
            TextButton(
              key: const ValueKey('fnthink-host-switch'),
              onPressed: _pickHostRegion,
              child: Text(l10n.fnthinkHostSwitch),
            ),
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
        // T76 ⓐ：更新通道**不跟随**这一格，必须在界面上写明 ——
        // §6 把它列为"不定就会变成隐性双源"的那一件：不写，用户以为切到成都、
        // 实际还在洛杉矶那边收更新，而两边版本可能不一样。
        Text(
          l10n.fnthinkHostUpdateNote(AppUpdateManager.updateServerHost),
          key: const ValueKey('fnthink-host-update-note'),
          style: TextStyle(
            fontSize: 12,
            color: AppColors.secondaryLabel(context),
          ),
        ),
        if (_hostError != null)
          FnthinkNote(keyName: 'fnthink-host-error', text: _hostError!),
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
