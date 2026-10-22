import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:get_it/get_it.dart';

import '../l10n/app_localizations.dart';
import '../services/active_channels.dart';
import '../services/channel_display.dart';
import '../services/channel_health_store.dart';
import '../services/fnthink_contract_loader.dart';
import '../services/fnthink_credential_store.dart';
import '../services/fnthink_endpoint_probe.dart';
import '../services/fnthink_identity_service.dart';
import '../services/fnthink_pairing_ack.dart';
import '../services/fnthink_receive_coordinator.dart';
import '../services/fnthink_settings.dart';
import '../services/fnthink_relay_consent.dart';
import '../theme/app_colors.dart';
import '../widgets/app_info_note_box.dart';
import '../widgets/channel_health_badge.dart';
import '../widgets/fnthink_card.dart';
import '../widgets/fnthink_outcome.dart';
import '../widgets/primary_action_button.dart';
import '../widgets/ios_dialog_actions.dart';
import '../widgets/ios_input_dialog.dart';
import '../widgets/ios_option_picker.dart';

/// 页面要用到的那一小包依赖。
///
/// 为什么不直接散着 `GetIt.instance<X>()` 取：这一页要同时碰契约、开关、凭证、身份、
/// 启停五件事，测试里必须能把它们一起换成替身（否则"点开关 ⇒ 写 prefs ⇒ 起循环 ⇒ 起不来就
/// 把原话显示出来"这条只能靠真机回答）。
class FnthinkSettingsDeps {
  FnthinkSettingsDeps({
    required this.contracts,
    required this.coordinator,
    required this.identity,
    this.healthOf,
    this.reachabilityOf,
    this.probeHosts,
    this.onHealthBody,
    this.recordHealth,
  });

  factory FnthinkSettingsDeps.fromLocator() => FnthinkSettingsDeps(
    contracts: GetIt.instance<FnthinkContractLoader>(),
    coordinator: GetIt.instance<FnthinkReceiveCoordinator>(),
    identity: FnthinkIdentityService(),
    // T60（approach B）／T157：这一格是**协议面**——协调者拿到/没拿到幻念协议请求的响应。
    // 它不再与 `/health` 探针共用一份记录（探针写下面那个族）。
    healthOf: (host) =>
        GetIt.instance<ChannelHealthStore>().of(kFnthinkServerFamily, host),
    // T157：`/health` 只管"这台机器上有没有进程在答 HTTP"，与协议面分开读。
    reachabilityOf: (host) => GetIt.instance<ChannelHealthStore>().of(
      kFnthinkReachabilityFamily,
      host,
    ),
    // T95 片5：打开「切换服务」那一格时**两台各探一次**。走 `/health` 那一发非侵入探测
    // （`measureEndpointLatency`），不往任何一台发真消息。T157：它写的是**可达性**族，
    // 不许再盖掉协议面那一格。
    probeHosts: measureEndpointLatency,
    recordHealth: ({required host, required reachable, required latencyMs}) =>
        GetIt.instance<ChannelHealthStore>().record(
          kFnthinkReachabilityFamily,
          host,
          reachable: reachable,
          latencyMs: latencyMs,
        ),
  );

  final FnthinkContractLoader contracts;
  final FnthinkReceiveCoordinator coordinator;
  final FnthinkIdentityService identity;

  /// 读某台服务器的**协议面**健康度（null = 还没有协议请求的读数）。
  final ChannelHealth? Function(String host)? healthOf;

  /// 读某台服务器的**可达性**（`/health` 探针，T157）。null = 这个族没接。
  final ChannelHealth? Function(String host)? reachabilityOf;

  /// 探这几台，回到得了的那些的时延。
  ///
  /// ⚠ [onHealthBody] 是**可选**的第二个口（T155 加的）：主判据的返回值形状一个字没动，
  /// 而"顺便从 `/health` 正文里看见的东西"另走一条。往返回值里加第二个维度就得改
  /// 所有调用方与所有用例 —— 而顺带看见的东西不该逼着主判据改形状。
  final Future<Map<String, Duration>> Function(
    List<String> hosts, {
    void Function(String host, Map<String, Object?> body)? onHealthBody,
  })?
  probeHosts;

  /// T155：探测期间顺手把 `/health` 正文交给页面（`onHealthBody` 那个口）。
  /// ⚠ **单独一个口，不塞进 [probeHosts] 的返回值**：那一发已经有一个契约形状
  /// （`Map<host, Duration>`），往里加第二个维度就得改所有调用方与所有用例 ——
  /// 而「顺带看见的东西」不该逼着主判据改形状。
  /// null = 不接（界面据���**不画**那一格，而不是画一句"一致"）。
  final void Function(String host, Map<String, Object?> body)? onHealthBody;

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

/// 幻念推送**设置页**（T97 片A。前身是 T44/T42 那张什么都往这里放的混合页）。
///
/// 这一页只管**这台设备自己**：它是谁（地址码 / 配对口令 / 身份密钥）、它对着哪台服务器
/// （地址 + 双地域 + 健康度）。
///
/// ⚠ 入口在 T107 换了地方：这里原本写着「入口只有通道列表页右上角那枚齿轮 —— 维护者
/// 2026-10-06 定的『设置从列表页右上齿轮进，不在推送分组里再长第二格』」，那句已被
/// 2026-10-08 的第 1 条**推翻**（原话留着，因为它是"为什么这一页当时不放进推送分组"的证据）：
/// 幻念那一族后来在通知引擎里已经有四行，齿轮那条路就成了同一件事的两棵树 ——
/// 现在入口是「通知引擎 → 幻念推送 → 幻念推送设置」（`engine-fnthink-settings`），
/// 通道列表页右上角那枚齿轮与本页那行「接入端点」都真删了，不留兼容跳转。
///
/// ⚠ 主语不同的两件事**不在这里**：「绑定哪几台」与「怎么收、要不要听远程」各自的页
/// 在「通知引擎 → 幻念推送」下面（`engine-fnthink-peers` / `engine-fnthink-receive`）。
/// 这里原来各有一行入口，T97 片A 删掉了：同一个决定有两个入口，改了一处就会忘了另一处，
/// 而两行卡片本身不携带任何只有它才有的信息。
///
/// ⚠ 页面上刻意没有的东西，都不是忘了：
///  - **名单本身、逐行那一下「撤销」、以及"一键全部撤销"**：都在绑定页那一页。
///    这一页只负责把口令挂出去（要让人配它，得在这里），而"切断哪一台"是对一台一台做的决定。
///    「全部撤销」至今没有，也不是忘了：它得先有一句"这会切断 N 台"的二次确认（T31 的另一档）。
///  - **大陆那台预设地址**：`transport.endpoints.mainland` 今天**已部署**（#137 走"先把它部署起来"收口，
///    两个域名的能力等价有外网实测），但这一页仍然不给那一档 —— 缺的已经不是地址，而是
///    **"什么时候该建议切"的判据**：契约的 `suggestSwitchOnMainlandNetwork` 要靠网络测量，
///    而设备侧没有任何测量口径（那半属于 T44 ①，未做）。摆两个都能用的地址却不给选择的依据，
///    等于把决策甩回给用户，而且他一旦选错，症状是"网络好好的却连不上"。
///  - **收件未读数**：它属于 T48 那张入口卡与历史页筛选，不是这一页的责任。
class FnthinkSettingsPage extends StatefulWidget {
  const FnthinkSettingsPage({super.key, this.deps});

  final FnthinkSettingsDeps? deps;

  @override
  State<FnthinkSettingsPage> createState() => _FnthinkSettingsPageState();
}

class _FnthinkSettingsPageState extends State<FnthinkSettingsPage> {
  late final FnthinkSettingsDeps _deps;
  late final FnthinkReceiveCoordinator _coordinator;

  FnthinkSettings? _settings;

  /// 「经服务器中转」同没同意（T119：这一页是撤销那一步的两个入口之一）。
  bool _consented = false;

  /// 撤销那一发的结论（null = 这一页还没撤销过）。
  String? _consentResult;
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

  FnthinkDeviceIdentity? _identity;
  bool _identityUnavailable = false;

  String _host = '';

  /// 收件保留那一档（T47）。缺省值住 FnthinkSettings（唯一作者），这里只存画面上的读数。
  int _retentionDays = FnthinkSettings.retentionDefaultDays;

  /// T155：服务器报上来的「客户端契约版本」那一格结论。
  /// ⚠ `null` 有**两个**来路（都没收到过 / 没装配 `onHealthBody`），而界面上
  ///   **都不画**那一格 —— 分开它们对用户没有意义，而把"没有读数"画成"一致"
  ///   才是凭空报功。
  String? _contractVerdict;

  /// 每一台候选的 `/health` 契约版本读数（T157：协议面那一格只用**当前 host** 的那一份，
  /// 不许拿另一台探到的版本来替当前这台说"未验证"）。
  final Map<String, String> _hostVerdicts = {};

  /// 改地址失败的原因（校验在 `FnthinkSettings` 那一处，这里只显示）。
  String? _hostError;
  bool _busy = false;

  /// 只给「测延迟」那一枚用。⚠ **不复用 `_busy`**：那一枚是"这台正在改东西"
  /// （改地址码／撤销口令／重置地址），把它借给一次只读探测会让按钮在**别的**操作
  /// 进行中显示「正在测延迟…」—— 那是一句屏幕上正在撒的谎。
  bool _probingHost = false;

  @override
  void initState() {
    super.initState();
    _deps = widget.deps ?? FnthinkSettingsDeps.fromLocator();
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
    // T119：这一页也要说得出"这台同没同意中转"，因为它现在是撤销那一步的两个入口之一。
    // 读的是 prefs 那一枚版本号（与协调者、接收页同一个判据），不在这里另算一遍。
    final consented = await settings.hasRelayConsent();
    final retentionDays = await settings.retentionDays();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _credentials = credentials;
      _host = host;
      _retentionDays = retentionDays;
      _addressCode = addressCode;
      _pairing = pairing;
      _identity = identity;
      _identityUnavailable = identity == null;
      _consented = consented;
    });
    // 开关的真值**只**从 prefs 读：它是用户做过的那个决定。契约那边没有任何一项能替代它
    // （契约管的是节奏与档位，不是"这台设备同不同意被中转"）。
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
    // T126 片2：这一发是"当场要看得见"最典型的一处 —— 口令没上到服务器时，对端扫码只会
    // 拿到"口令不存在"，而屏幕上写着"已挂出 5 分钟"。格子里那三态留着（事后还要在），
    // 这里补一次弹层，句子与格子**同一个作者**（`fnthinkPairingAckText`），不另拼一句。
    if (!mounted) return;
    await showFnthinkOutcome(
      context,
      ok: result.ok,
      detail: fnthinkPairingAckText(
        AppLocalizations.of(context),
        acked: _pairingAcked,
        note: _pairingPublishNote,
      ),
    );
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
      // 用例按这把 key 点这一格（test/widgets/fnthink_settings_page_test.dart 四处）⇒ 沿用旧 key。
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
    // T155：顺手收下 `/health` 正文里那一格（**只在探当前这台时**记 ——
    // 别人的那台上有什么，与这台屏幕上的那一格无关）。
    final sink = _deps.onHealthBody;
    // ⚠ **对候选里的每一台都记**，不只记当前那台 —— 这一格说的是
    //   「刚才探过的那些服务器里，有没有一份拿着旧协议」，而打开「切换服务」
    //   那一格探的就是**候选全集**（§6 的口径：不按探不通过滤，
    //   探测不通该显示"不可用"而不是把那一档从候选里拿走）。
    //   只记 `_host` 那一台的话：① 用户还没换地址、而当前那台不在候选里（自部署
    //   填的第三个地址）⇒ 永远记不到；② 两台里只有一台旧的话什么都说不出 ——
    //   而那恰恰是最该说的话（用户正要挑一台换过去）。
    // ⚠ 取**最坏**那一档而不是最后一档：候选的遍历顺序是契约声明顺序，
    //   「最后读到的那台」只是声明顺序里的最后一个，与严重程度无关。
    void capture(String host, Map<String, Object?> body) {
      sink?.call(host, body);
      // 键名由**手上已经握着契约的那一侧**交进来（`_settings.contract`），页面
      // 自己在 `_load()` 里读过它 —— 探针不自己找一份（`readFile` 那条路在设备
      // 沙箱里不存在，见 `readClientContractVerdict` 的注释）。
      final healthKey = _settings?.contract.versionEchoHealthKey ?? '';
      final verdict = readClientContractVerdict(body, healthKey);
      if (verdict == null) return;
      final text = '$verdict';
      _hostVerdicts[host] = text;
      _contractVerdict = _worseVerdict(_contractVerdict, text);
    }

    try {
      latencies = await probe(hosts, onHealthBody: capture);
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

  /// 手动测一次**当前这台**服务器的延迟（T168：「测延迟」那一枚）。
  ///
  /// ⚠ **只测、不改**：这一发不写 `fnthink.host`、不调 `_applyHost`、也不重启收件循环
  ///   （重启是"地址变了"的副作用，见 `_applyHost` 那一段）。它改的只有健康度那一份读数。
  /// ⚠ **与「切换服务」共用 `_probeDeclaredHosts`**：先记账、后刷新这条顺序只有一个作者。
  ///   另起一条"探完直接 setState"的副本，就会出现一条把结论漏记的入口（§6 同族）。
  /// ⚠ 地址为空（只可能出现在契约那一格没读出来的路上，那时整页已被错误卡顶掉）时，
  ///   把**空列表**交给 `_probeDeclaredHosts` —— "什么都不做"那一支仍然只有那一个作者，
  ///   这里不再自己判一遍、也不多一条没被测到的 return。
  Future<void> _probeCurrentHost() async {
    if (_probingHost) return;
    setState(() => _probingHost = true);
    try {
      await _probeDeclaredHosts(_host.isEmpty ? const [] : [_host]);
    } finally {
      if (mounted) setState(() => _probingHost = false);
    }
  }

  /// 两档合并成**更坏**的那一档（T155，纯函数）。
  ///
  /// ⚠ 顺序有讲究：`unreadable` 比 `mismatch` 更坏吗？—— **更坏**。
  /// `mismatch` 说的是"确知不一致"（用户能照它做事：等运维上传新契约）；
  /// `unreadable` 说的是"连它是什么都读不出来"（连这句话都不可信）。
  /// ⚠ `null` 是"还没见过"，比两者都轻 —— 它不该把已知的结论抹掉。
  /// ⚠ 同档返回 `a`（输入顺序不影响结果）—— 免得"探的顺序"变成一个隐形维度。
  String? _worseVerdict(String? current, String incoming) {
    // ⚠ `match` 与 `null` 都不在表里：`match` 是"没事"（不该覆盖已知的坏消息），
    //   `null` 是"还没见过"（同上，且比"没事"更轻）。
    const rank = {'unreadable': 2, 'mismatch': 1};
    final mine = rank.containsKey(current ?? '') ? rank[current!]! : 0;
    final theirs = rank[incoming];
    if (theirs == null || mine >= theirs) return current;
    return incoming;
  }

  /// 「切换服务」选项上那一句「这一台今天能不能用」—— T157 起它只回答**可达性**
  /// （`/health` 探针写的那一族），不冒充协议面。过期那档必须带时间（T115），
  /// 不许只说"状态正常"。
  String _healthWord(AppLocalizations l10n, String host) {
    final health = _deps.reachabilityOf?.call(host);
    final ago = channelHealthAgoLabel(l10n, health?.probedAt);
    return switch (channelHealthStateForDisplay(health)) {
      ChannelHealthState.ok => l10n.healthReachable(health!.latencyMs),
      ChannelHealthState.error => l10n.healthUnreachable,
      ChannelHealthState.stale => ago ?? l10n.statusUnknown,
      ChannelHealthState.unknown => l10n.statusUnknown,
    };
  }

  /// 服务可达那一格（T157）。只读 `/health` 探针写的那一族；没有读数就说没有。
  String _reachabilityWord(AppLocalizations l10n, String host) {
    final health = _deps.reachabilityOf?.call(host);
    final ago = fnthinkAgoLabel(l10n, health?.probedAt);
    return switch (channelHealthStateForDisplay(health)) {
      ChannelHealthState.ok => l10n.fnthinkReachabilityOk(
        health!.latencyMs,
        ago ?? '—',
      ),
      ChannelHealthState.error => l10n.fnthinkReachabilityFailed(ago ?? '—'),
      ChannelHealthState.stale => l10n.fnthinkReachabilityStale(ago ?? '—'),
      ChannelHealthState.unknown => l10n.fnthinkReachabilityNever,
    };
  }

  /// 协议面那一格（T157）。结论只由**协议请求**写入的 `kFnthinkServerFamily` 给；
  /// `/health` 的契约版本只算**一半**——没有协议请求成功过时只能说"未验证/未知"。
  String _protocolWord(AppLocalizations l10n, String host) {
    final health = _deps.healthOf?.call(host);
    final ago = fnthinkAgoLabel(l10n, health?.probedAt);
    return switch (channelHealthStateForDisplay(health)) {
      ChannelHealthState.ok => l10n.fnthinkProtocolReadyShort(ago ?? '—'),
      ChannelHealthState.error => l10n.fnthinkProtocolFailedShort(ago ?? '—'),
      ChannelHealthState.stale => l10n.fnthinkProtocolStale(ago ?? '—'),
      ChannelHealthState.unknown =>
        _hostVerdicts[host] == null
            ? l10n.fnthinkProtocolNever
            : l10n.fnthinkProtocolUnverified,
    };
  }

  /// 服务器卡上的一行读数：左边是主语，右边是结论（`keyName` 落在结论那枚 Text 上）。
  Widget _hostReadout({
    required String keyName,
    required String label,
    required String text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.secondaryLabel(context),
              ),
            ),
          ),
          Flexible(
            child: Text(
              text,
              key: ValueKey(keyName),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.secondaryLabel(context),
              ),
            ),
          ),
        ],
      ),
    );
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
          l10n.fnthinkSettingsTitle,
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
            const SizedBox(height: 12),
            _buildServerCard(l10n),
            const SizedBox(height: 20),
            _buildConsentCard(l10n),
            const SizedBox(height: 20),
            // 隐私边界那句从“一张卡里一段小字”改成底部一行（§1 已定口径：页面里的提醒
            // 只有两种去处 —— 底部无序列表 / 右上问号弹层）。它不是状态读数，所以不是例外。
            Text(
              '• ${l10n.fnthinkBoundary}',
              key: const ValueKey('fnthink-boundary'),
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: AppColors.secondaryLabel(context),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 「接入端点」**不在这一页里了**（T107）：那一页的入口与本页的入口都在
  /// 「通知引擎 → 幻念推送」那一块（`engine-fnthink-endpoint` / `engine-fnthink-settings`）。
  /// 原先这里留着一行跳转卡，是维护者 2026-10-07 拍的「端点归设置 → 高级」；T107 把整族收成
  /// 一棵树之后，那一行就成了同一页的两个入口 —— 少一个，路径不短（都在通知引擎里）。

  /// 「经服务器中转」这一档许可（T119）。这一格只做两件事：**说清现在是什么状态**，
  /// 以及在已同意时给一枚**撤销**。
  ///
  /// ⚠ 这里**不给"同意"那一枚按钮**（刻意不对称）：同意是一次显式动作，全产品只该有一个
  ///   落点（接收页那一屏，带着三情形说明与"同意前可读全文"那条不变量）。在这一页再放一枚
  ///   同意，就把同一段披露抄成了两份 —— 那是 T56 之后本仓最容易被撕开的口子。
  ///   没同意时这一格只说一句"还没同意，经服务器的收发全部停着"，并指回那一屏。
  Widget _buildConsentCard(AppLocalizations l10n) {
    return FnthinkCard(
      title: l10n.fnthinkRelayConsentSection,
      children: [
        if (_consented) ...[
          FnthinkRowLabel(
            label: l10n.fnthinkConsentGranted,
            keyName: 'fnthink-consent-granted',
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FnthinkInlineAction(
              key: const ValueKey('fnthink-consent-revoke'),
              label: l10n.fnthinkConsentRevoke,
              tone: FnthinkActionTone.destructive,
              onPressed: _busy ? null : _revokeConsent,
            ),
          ),
        ] else
          FnthinkRowLabel(
            label: l10n.fnthinkConsentPending,
            keyName: 'fnthink-consent-pending',
          ),
        if (_consentResult case final String note)
          FnthinkNote(keyName: 'fnthink-consent-result', text: note),
      ],
    );
  }

  /// 撤销（T119）。两处入口共用 `confirmAndRevokeRelayConsent` 那一个实现 ——
  /// 各写一遍就会有一处清了键而另一处还显示"已同意"。
  Future<void> _revokeConsent() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context);
    final revoked = await confirmAndRevokeRelayConsent(
      context: context,
      settings: _settings,
    );
    if (!mounted) return;
    if (!revoked) {
      setState(() => _busy = false);
      return;
    }
    setState(() {
      _consented = false;
      _consentResult = l10n.fnthinkConsentRevokeDone;
      _busy = false;
    });
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
              FnthinkInlineAction(
                label: l10n.fnthinkCopy,
                tone: FnthinkActionTone.neutral,
                onPressed: () => fnthinkCopyNotice(context, code),
              ),
            FnthinkInlineAction(
              key: const ValueKey('fnthink-reset-code'),
              label: l10n.fnthinkResetCode,
              tone: FnthinkActionTone.destructive,
              onPressed: code == null ? null : _resetAddressCode,
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
              FnthinkInlineAction(
                label: l10n.fnthinkCopy,
                tone: FnthinkActionTone.neutral,
                onPressed: () => fnthinkCopyNotice(context, pairing.code.value),
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
        // T126 片2：哪一态说哪句话、那一格挂哪个 key，两个映射都在 `fnthink_pairing_ack.dart`
        // 那一处 —— 页面不再自己写三遍 `if`，而当场弹的那一层（`_publishPairingCode` 末尾）
        // 与这一格读的是同一个函数，不会出现"弹层说一套、格子说另一套"。
        if (pairing != null)
          FnthinkNote(
            keyName: 'fnthink-pairing-${fnthinkPairingAckKey(_pairingAcked)}',
            text: fnthinkPairingAckText(
              l10n,
              acked: _pairingAcked,
              note: _pairingPublishNote,
            ),
          ),
        if (pairing != null)
          Align(
            alignment: Alignment.centerLeft,
            child: FnthinkInlineAction(
              key: const ValueKey('fnthink-revoke-pairing'),
              label: l10n.fnthinkRevokePairing,
              tone: FnthinkActionTone.destructive,
              onPressed: _clearPairingCode,
            ),
          ),
        PrimaryActionButton(
          key: const ValueKey('fnthink-arm-pairing'),
          label: l10n.fnthinkArmPairing,
          onPressed: _armPairingCode,
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

  /// T47：收件保留的选档弹层（与换服务器同一件形状：标题 + 若干行 + 选中回一个值）。
  /// 取消 ⇒ 什么都不写；写到盘的是"选过那一档"，非法值在 settings 那一格当场抛。
  Future<void> _pickRetention() async {
    final l10n = AppLocalizations.of(context);
    final settings = _settings;
    if (settings == null) return;
    final current = await settings.retentionDays();
    if (!mounted) return;
    final picked = await showIosOptionPicker<int>(
      context,
      title: l10n.fnthinkRetentionLabel,
      selectedValue: current,
      options: [
        for (final d in FnthinkSettings.retentionChoices)
          IosPickerOption<int>(
            value: d,
            label: '$d${l10n.fnthinkRetentionDaysUnit}',
            description: d == FnthinkSettings.retentionDefaultDays
                ? l10n.fnthinkRetentionDefault
                : null,
          ),
      ],
    );
    if (picked == null || !mounted) return;
    await settings.setRetentionDays(picked);
    if (!mounted) return;
    setState(() => _retentionDays = picked);
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
            FnthinkInlineAction(label: l10n.edit, onPressed: _editHost),
            // T76 双地域：在契约声明的两台里选一台（与上面"手动填"并存 ——
            // 自部署要填的是契约里没有的第三个地址）。
            FnthinkInlineAction(
              key: const ValueKey('fnthink-host-switch'),
              label: l10n.fnthinkHostSwitch,
              onPressed: _pickHostRegion,
            ),
            FnthinkInlineAction(
              key: const ValueKey('fnthink-host-default'),
              label: l10n.fnthinkHostReset,
              tone: FnthinkActionTone.neutral,
              onPressed: _restoreDefaultHost,
            ),
          ],
        ),
        // T168：手动测一次延迟。T95 片5 那一发只在**打开「切换服务」时**探，
        // 所以"我不换、只想知道这台现在多少毫秒"没有入口 —— 而这一格下面两行读数
        // 恰恰是探测写出来的。按钮摆在读数正上方，谁刷新谁。
        Row(
          children: [
            FnthinkInlineAction(
              key: const ValueKey('fnthink-host-probe'),
              label: _probingHost
                  ? l10n.fnthinkHostProbing
                  : l10n.fnthinkHostProbeNow,
              // 中性档：它是"再看一眼"，不是"往前走一步"（与「恢复默认」同档）。
              tone: FnthinkActionTone.neutral,
              onPressed: _probingHost ? null : _probeCurrentHost,
            ),
            if (_probingHost) ...[
              const SizedBox(width: 8),
              const SizedBox(
                width: 16,
                height: 16,
                child: CupertinoActivityIndicator(radius: 7),
              ),
            ],
          ],
        ),
        // T157：这一格拆成两行 —— **服务可达**只读 `/health` 探针写的那一族；
        // **协议面**只读协议请求写的那一族。两者不共用一份记录：一次 `/health` 200
        // 不许把协议面的失败盖成"有应答"（那正是"界面在线、功能全废"的来源）。
        _hostReadout(
          keyName: 'fnthink-host-reachability',
          label: l10n.fnthinkReachabilityLabel,
          text: _reachabilityWord(l10n, _host),
        ),
        _hostReadout(
          keyName: 'fnthink-host-protocol',
          label: l10n.fnthinkProtocolLabel,
          text: _protocolWord(l10n, _host),
        ),
        // T47：收件保留。天数进界面（四档，缺省 30），条数是资源闸不进 ——
        // 见 FnthinkSettings 那两条常量与它们的注释。
        FnthinkRowLabel(
          label: l10n.fnthinkRetentionLabel,
          keyName: 'fnthink-retention',
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                '$_retentionDays${l10n.fnthinkRetentionDaysUnit}',
                key: const ValueKey('fnthink-retention-value'),
                style: const TextStyle(fontSize: 14),
              ),
            ),
            FnthinkInlineAction(
              key: const ValueKey('fnthink-retention-pick'),
              // ⚠ 不用 l10n.edit：那一句是宿主行（改地址）那枚的 —— 同页两句「编辑」
              //   既让按文案找的用例撞 Too many elements，也让读者分不清哪枚改哪格。
              label: l10n.fnthinkRetentionPick,
              onPressed: _pickRetention,
            ),
          ],
        ),
        // T155：服务器手上的契约是**旧的那一份**时，那一句在这里。
        // ⚠ 只在 `mismatch` / `unreadable` 两档画 —— 一致与"还没收到过带版本的请求"
        //   **都不画**：后者是"没有读数"，画一句"一致"就是凭空报功
        //   （与本仓那三件「没读到／还没看／真的没有」的同一族纪律）。
        // ⚠ 这句话是给**维护者**看的那种技术事实，不是用户能自己解决的事：
        //   它由服务端答，而服务端只能靠重新上传 `protocol/` 修好。
        if (_contractVerdict == 'mismatch' || _contractVerdict == 'unreadable')
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: FnthinkStatusRow(
              // ⚠ 换签名时把这一枚 key 掉了，页面级用例因此一直是"找不到那一格"
              //   —— 而正向与负向一起红，正是"判据量的是一件不存在的东西"的形状。
              //   教训与本仓同族那几次一致：**换构造签名时逐字对一遍参数表**。
              key: const ValueKey('fnthink-contract-version-row'),
              keyName: 'fnthink-contract-version',
              // ⚠ 灰点（`dot: false`），不是红点 —— 这一枚公共件只有绿/灰两色，
              //   而绿在本页读作「正常」。对一个在说「服务器那份协议是旧的」的行
              //   画绿点就是撒谎，而把它扩成三色是给公共件加功能（另一件事）。
              // ⚠ 代价如实登记：灰点与「没读数」（那一档根本不画这一格）在外形上
              //   区分度不高 ⇒ 真正的区分靠那行字本身，不靠圆点。
              dot: false,
              text: _contractVerdict == 'mismatch'
                  ? l10n.fnthinkContractVersionMismatch
                  : l10n.fnthinkContractVersionUnreadable,
            ),
          ),
        AppInfoNoteBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.fnthinkHostDesc,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
              const SizedBox(height: 8),
              // T76 ⓐ：更新通道不跟随这一格，必须在界面上写明（不改主机名）。
              Text(
                l10n.fnthinkHostUpdateNote,
                key: const ValueKey('fnthink-host-update-note'),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
            ],
          ),
        ),
        if (_hostError != null)
          FnthinkNote(keyName: 'fnthink-host-error', text: _hostError!),
      ],
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
        border: Border.all(color: AppColors.separator(context)),
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
