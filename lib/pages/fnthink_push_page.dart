import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:get_it/get_it.dart';

import '../l10n/app_localizations.dart';
import '../models/fnthink_peer.dart';
import 'fnthink_peers_page.dart';
import 'fnthink_receive_page.dart';
import '../services/active_channels.dart';
import '../services/channel_display.dart';
import '../services/channel_health_store.dart';
import '../services/fnthink_contract_loader.dart';
import '../services/fnthink_credential_store.dart';
import '../services/fnthink_endpoint_guide.dart';
import '../services/fnthink_endpoint_probe.dart';
import '../services/fnthink_identity_service.dart';
import '../services/fnthink_peer_service.dart';
import '../services/fnthink_receive_coordinator.dart';
import '../services/fnthink_settings.dart';
import '../theme/app_colors.dart';
import '../widgets/channel_health_badge.dart';
import '../widgets/fnthink_card.dart';
import '../widgets/ios_dialog_actions.dart';
import '../widgets/ios_input_dialog.dart';
import '../widgets/ios_option_picker.dart';

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
    this.healthOf,
    this.probeHosts,
    this.recordHealth,
  });

  factory FnthinkPushDeps.fromLocator() => FnthinkPushDeps(
    contracts: GetIt.instance<FnthinkContractLoader>(),
    coordinator: GetIt.instance<FnthinkReceiveCoordinator>(),
    identity: FnthinkIdentityService(),
    // 名单只从读咽喉取。退回 `DatabaseHelper().loadFnthinkPeers` 的话，页面就会自己长出一份
    // 排序/时间口径，而 `history_page` 那批守卫已经证明过这种分叉是怎么开始的。
    loadPeers: GetIt.instance<FnthinkPeerService>().list,
    // T60（approach B）：对着某台服务器的最近一次发送健康度。读源与写源（协调者 recordHealth
    // 落到 ChannelHealthStore）都认 `kFnthinkChannelSlug` 这一个 family，页面不自己 new 读写实现。
    healthOf: (host) =>
        GetIt.instance<ChannelHealthStore>().of(kFnthinkChannelSlug, host),
    // T95 片5：打开「切换服务」那一格时**两台各探一次**。走 `/health` 那一发非侵入探测
    // （`measureEndpointLatency`），不往任何一台发真消息。
    probeHosts: measureEndpointLatency,
    recordHealth: ({required host, required reachable, required latencyMs}) =>
        GetIt.instance<ChannelHealthStore>().record(
          kFnthinkChannelSlug,
          host,
          reachable: reachable,
          latencyMs: latencyMs,
        ),
  );

  final FnthinkContractLoader contracts;
  final FnthinkReceiveCoordinator coordinator;
  final FnthinkIdentityService identity;
  final Future<List<FnthinkPeer>> Function() loadPeers;

  /// 读某台服务器的健康度（null = 这台没装配健康度链路 ⇒ 那一行不画/显示"从没发过"）。
  final ChannelHealth? Function(String host)? healthOf;

  /// 探这几台，回到得了的那些的时延。
  final Future<Map<String, Duration>> Function(List<String> hosts)? probeHosts;

  /// 把一次探测结果写进健康度单点（与协调者那条 `recordHealth` 同一个口）。
  /// 回 Future 是要被 await 的：换台之前那行徽标必须已经落好，否则界面与 prefs
  /// 会各说一句"上次探到的是…"。
  final Future<void> Function({
    required String host,
    required bool reachable,
    required int latencyMs,
  })?
  recordHealth;
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
  const FnthinkPushPage({
    super.key,
    this.deps,
    this.peersDeps,
    this.receiveDeps,
  });

  final FnthinkPushDeps? deps;

  /// 「已配对的设备」那一行要推的那张页的依赖（T94）。
  /// 缺省走 `FnthinkPeersDeps.fromLocator()`；测试里传一份替身——
  /// 否则「可以点」那一下会在没注册那些单例的测试里直接抛，
  /// 而一个入口行的判据正是「点得动」，不能因为装配点缺失就无法被测。
  final FnthinkPeersDeps? peersDeps;

  /// 「接收与远程执行」那一行要推的那张页的依赖（T94 片 2）。缺省走 `FnthinkReceiveDeps.fromLocator()`；测试里传替身。
  final FnthinkReceiveDeps? receiveDeps;

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
    });
    // 开关的真值**只**从 prefs 读：它是用户做过的那个决定。契约那边没有任何一项能替代它
    // （契约管的是节奏与档位，不是"这台设备同不同意被中转"）。
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
    if (_coordinator.isRunning) {
      _coordinator.stop();
      await _coordinator.startIfEnabled();
    }
    if (!mounted) return;
    setState(() {
      _addressCode = fresh.value;
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
      // T99：给"只有一个 webhook 输入框"的第三方软件用的路径形态。门槛与 copyCommand
      // 同一个（明文不在手就整格不给），所以这一格不会比「复制口令」多泄露一个字。
      if (guide.pushUrl.isNotEmpty) ...[
        SelectableText(
          guide.pushUrl,
          key: const ValueKey('fnthink-endpoint-push-url'),
        ),
        FnthinkNote(
          keyName: 'fnthink-endpoint-push-url-why',
          text: l10n.fnthinkEndpointPushUrlWhy,
        ),
      ],
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
      copyButton(
        'fnthink-endpoint-copy-push-url',
        l10n.fnthinkEndpointCopyPushUrl,
        guide.canCopyPushUrl ? guide.pushUrl : null,
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
    // T95 片5：打开这一格就两台各探一次。选项上那句"能不能用"必须是**这一轮**的实测 ——
    // 徽标那套 30 分钟过期口径是给列表扫一眼用的，不是给"要不要换一台"这个决定用的；
    // 拿十分钟前的数字替用户拍板，错了没人会回来查它是哪一轮探的。
    await _probeDeclaredHosts([for (final c in choices) c.host]);
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
            // 地区 + 这一台今天的可达性。候选**恒两台**（上面 §6 那条口径）：
            // 探不通是把这一行标成"连不上"，不是把它从列表里拿掉。
            description:
                '${c.key == 'international' ? l10n.fnthinkHostRegionInternational : l10n.fnthinkHostRegionMainland}'
                ' · ${_healthWord(l10n, c.host)}',
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

  /// 探这几台并把结论写进健康度单点（读写都走 `_deps` 那两个口，页面不自己 new 实现）。
  ///
  /// ⚠ 没装配探测链路时**什么都不做**：这里不许退化成"没探到就当可用" ——
  ///   那是一次凭空写进去的"可达"，比空白更坏。
  /// ⚠ 探测本身炸了也只记日志：这一发不该把"换服务器"这个动作带崩，
  ///   界面上维持上一轮三态、并仍然把两台摆出来。
  Future<void> _probeDeclaredHosts(List<String> hosts) async {
    final probe = _deps.probeHosts;
    final record = _deps.recordHealth;
    if (probe == null || record == null || hosts.isEmpty) return;
    final Map<String, Duration> latencies;
    try {
      latencies = await probe(hosts);
    } catch (e) {
      debugPrint('幻念推送：切换服务前的健康度探测失败 $e');
      return;
    }
    for (final host in hosts) {
      final hit = latencies[host];
      await record(
        host: host,
        reachable: hit != null,
        latencyMs: hit?.inMilliseconds ?? 0,
      );
    }
    if (!mounted) return;
    // 卡片上那枚徽标读的就是这一轮：不刷新就会画着上一轮的数，而用户刚看着它做完决定。
    setState(() {});
  }

  /// 这一台今天怎么样 —— 与徽标**同一套三态判定**（`channelHealthState`）。
  /// 页面自己再判一次 `reachable` 就是第二份口径：T01 那次"设置页说正常、首页说未知"
  /// 就是这么来的。
  String _healthWord(AppLocalizations l10n, String host) {
    final health = _deps.healthOf?.call(host);
    return switch (channelHealthState(health)) {
      ChannelHealthState.ok => l10n.healthReachable(health!.latencyMs),
      ChannelHealthState.error => l10n.healthUnreachable,
      ChannelHealthState.unknown => l10n.statusUnknown,
    };
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
    if (_coordinator.isRunning) {
      _coordinator.stop();
      await _coordinator.startIfEnabled();
    }
    if (!mounted) return;
    setState(() {
      _host = stored;
      _hostError = null;
    });
  }

  Future<void> _restoreDefaultHost() async {
    final settings = _settings;
    if (settings == null) return;
    try {
      await settings.setHost(settings.defaultHost);
      final stored = await settings.host;
      // 恢复默认也是换地址 ⇒ 同一个重启（理由见 `_applyHost`）
      if (_coordinator.isRunning) {
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
            _buildIdentityCard(l10n),
            _buildPeersEntryCard(l10n),
            const SizedBox(height: 12),
            _buildReceiveEntryCard(l10n),
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

  /// 「已配对的设备」那一行入口（T94 片1）。
  ///
  /// 为什么是入口而不是内容：设备绑定是**两台设备之间**的关系，而这一页讲的是**这台设备**
  /// 的身份与服务地址。同一张页里摆两件事，用户配错时看不出自己刚动的是哪一个 ——
  /// 而这两个决定的代价完全不同（换地址码要重新配对，撤销一台只影响那一台）。
  /// 「接收推送与远程执行」那一行入口（T94 片 2）。
  ///
  /// 两张卡都是「别人对这台设备做什么」：先收下来，再按拿到的命令去做。
  /// 它们不是这台设备自己的渠道信息，所以也一并搬走——拆得功不应该在每一个入口
  /// 重复一份。
  Widget _buildReceiveEntryCard(AppLocalizations l10n) {
    return FnthinkCard(
      title: l10n.fnthinkReceive,
      children: [
        FnthinkNote(
          keyName: 'fnthink-receive-entry-desc',
          text: l10n.fnthinkHubReceiveDesc,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const ValueKey('fnthink-receive-entry'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => FnthinkReceivePage(deps: widget.receiveDeps),
              ),
            ),
            child: Text(l10n.fnthinkReceiveGo),
          ),
        ),
      ],
    );
  }

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
        // T95 片5：这一枚读的是健康度单点。`healthOf` 在 T60 就注入了，但页面从没读过它 ——
        // 于是"接口有、界面没有"，用户换台时手上一个证据都没有。
        // 它说的是"最近一次对着这台试过"：收货链路的真实发送会写它，打开「切换服务」
        // 那一格时的探测也会写它（`_probeDeclaredHosts`）。
        ChannelHealthBadge(health: _deps.healthOf?.call(_host)),
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
        // ⚠ 这句话**不再报出更新服务器的主机名**（T95 之前它是 `{host}`）：
        //   那一台现在也分两档、也可以用户选，写死在提示文案里就等于替用户
        //   宣布一个随时会被他自己改掉的事实。
        Text(
          l10n.fnthinkHostUpdateNote,
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
