import 'dart:async';

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
    this.probeHosts,
    this.recordHealth,
  });

  factory FnthinkSettingsDeps.fromLocator() => FnthinkSettingsDeps(
    contracts: GetIt.instance<FnthinkContractLoader>(),
    coordinator: GetIt.instance<FnthinkReceiveCoordinator>(),
    identity: FnthinkIdentityService(),
    // T60（approach B）：对着某台服务器的最近一次发送健康度。读源与写源（协调者 recordHealth
    // 落到 ChannelHealthStore）都认 `kFnthinkServerFamily` 这一个 family（T104 片①：以前它与
    // 通道健康度共用 `fnthink`，两种主语挤在一个族名里），页面不自己 new 读写实现。
    healthOf: (host) =>
        GetIt.instance<ChannelHealthStore>().of(kFnthinkServerFamily, host),
    // T95 片5：打开「切换服务」那一格时**两台各探一次**。走 `/health` 那一发非侵入探测
    // （`measureEndpointLatency`），不往任何一台发真消息。
    probeHosts: measureEndpointLatency,
    recordHealth: ({required host, required reachable, required latencyMs}) =>
        GetIt.instance<ChannelHealthStore>().record(
          kFnthinkServerFamily,
          host,
          reachable: reachable,
          latencyMs: latencyMs,
        ),
  );

  final FnthinkContractLoader contracts;
  final FnthinkReceiveCoordinator coordinator;
  final FnthinkIdentityService identity;

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

  /// 改地址失败的原因（校验在 `FnthinkSettings` 那一处，这里只显示）。
  String? _hostError;
  bool _busy = false;

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
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _credentials = credentials;
      _host = host;
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

  /// 这一台今天怎么样 —— 与徽标**同一条判定**（`channelHealthStateForDisplay`）。
  /// 页面自己再判一次 `reachable` 就是第二份口径：T01 那次"设置页说正常、首页说未知"
  /// 就是这么来的。
  /// 过期那一档在这里只说结论词：同一格右边那枚徽标一直在说"上次探测于 X 前"
  /// （`ChannelHealthBadge`），这一行再说一遍只是把同一句挂两次。
  String _healthWord(AppLocalizations l10n, String host) {
    final health = _deps.healthOf?.call(host);
    return switch (channelHealthStateForDisplay(health)) {
      ChannelHealthState.ok => l10n.healthReachable(health!.latencyMs),
      ChannelHealthState.error => l10n.healthUnreachable,
      ChannelHealthState.stale => l10n.statusOk,
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
