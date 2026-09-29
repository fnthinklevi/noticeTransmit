import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:get_it/get_it.dart';

import '../l10n/app_localizations.dart';
import '../services/fnthink_contract_loader.dart';
import '../services/fnthink_credential_store.dart';
import '../services/fnthink_identity_service.dart';
import '../services/fnthink_receive_coordinator.dart';
import '../services/fnthink_settings.dart';
import '../theme/app_colors.dart';
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
  });

  factory FnthinkPushDeps.fromLocator() => FnthinkPushDeps(
    contracts: GetIt.instance<FnthinkContractLoader>(),
    coordinator: GetIt.instance<FnthinkReceiveCoordinator>(),
    identity: FnthinkIdentityService(),
  );

  final FnthinkContractLoader contracts;
  final FnthinkReceiveCoordinator coordinator;
  final FnthinkIdentityService identity;
}

/// 幻念推送页（T44 的②③ + T42 的入口那半）。
///
/// 这一页存在的理由是**一条断链**：收货链路（契约→地址码→循环→收件表→通知栏）五片都落完了，
/// 而总开关住在 SharedPreferences 里、默认关，界面上没有任何一处能把它翻开 ——
/// 于是整条链对真实用户是不可达的。顺带把"这台设备是谁"（地址码 / 配对口令 / 身份密钥）
/// 第一次显示给人看：在此之前它们只在日志与测试里出现过。
///
/// ⚠ 页面上刻意没有的东西，都不是忘了：
///  - **配对名单**：poll 的回信里没有对端名字，而"添加设备"那一步（pairArm/pairConfirm 的客户端半）
///    还没接 —— 先放一张永远空的列表等于让界面猜。
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
      _host = host;
      _addressCode = addressCode;
      _pairing = pairing;
      _identity = identity;
      _identityUnavailable = identity == null;
      _running = _coordinator.isRunning;
    });
    // 开关的真值**只**从 prefs 读：它是用户做过的那个决定。契约那边没有任何一项能替代它
    // （契约管的是节奏与档位，不是"这台设备同不同意被中转"）。
    await _readEnabled();
  }

  Future<void> _readEnabled() async {
    final settings = _settings;
    if (settings == null) return;
    final value = await settings.receiveEnabled;
    if (!mounted) return;
    setState(() => _enabled = value);
  }

  /// 开关。⚠ 这里有一个必须写下来的取舍：**开关那一格显示的是"用户要的状态"（prefs 真值），
  /// 运行那一格显示的是"实际状态"**，两者不一致时把原话贴在下面，而不是把开关回弹。
  /// 回弹会让他以为没点上而再点一次（结果一样），而"已开但起不来"才是可诊断的那句话。
  Future<void> _toggleReceive(bool value) async {
    final settings = _settings;
    if (settings == null || _busy) return;
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
        _startNote = result.started ? null : result.reason;
        _busy = false;
      });
      return;
    }
    _coordinator.stop();
    if (!mounted) return;
    setState(() {
      _running = false;
      _startNote = null;
      _busy = false;
    });
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
  Future<void> _publishPairingCode(String pairingCode) async {
    final result = await _coordinator.publishPairingCode(pairingCode);
    if (!mounted) return;
    setState(() {
      _pairingAcked = result.ok;
      _pairingPublishNote = result.ok ? null : (result.reason ?? 'no-answer');
    });
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
      if (!mounted) return;
      setState(() {
        _host = stored;
        _hostError = null;
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
        if (_startNote != null)
          _Note(keyName: 'fnthink-start-note', text: _startNote!),
        if (_roundNote != null)
          _Note(keyName: 'fnthink-round-note', text: _roundNote!),
        if (_lastRound != null)
          _Note(keyName: 'fnthink-last-round', text: _lastRound!),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonal(
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
