import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:get_it/get_it.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../l10n/app_localizations.dart';
import '../services/fnthink_contract_loader.dart';
import '../services/fnthink_remote_settings.dart';
import '../services/remote_credential_store.dart';
import '../theme/app_colors.dart';
import '../widgets/fnthink_card.dart';
import '../widgets/help_note_button.dart';
import '../widgets/ios_dialog_actions.dart';
import '../widgets/ios_input_dialog.dart';
import 'app_filter_page.dart';

/// 远程执行的**凭据设置页**（片3b-2）。
///
/// 这一页只有两件事：总开关、凭据。**延时窗口那一格也在这里**（契约把它算成远程执行的
/// 一件设置），但它属于「决定」而不是「秘密」，落盘走 `FnthinkRemoteSettings`。
///
/// ## 三件明文只出现一次
/// 高级密钥与 TOTP 种子的**明文**都在这一页显示一次，然后只留在页面的内存里：
/// 不写 prefs、不写日志、不进任何回执。⚠ 这是有意的取舍 —— 留一份「方便回去再看」的副本
/// 等于把长期凭证放进一个会跟着备份走、又不加密的地方，而对面只存了哈希/不知道种子。
/// 所以这一页离开时那串就没了；用户没抄走就再生成一把（那一把旧的当场作废）。
///
/// ## 为什么生成/撤回都要二次确认
/// 撤掉 = 对面手里那把立刻作废（他们不会收到任何通知）—— 与 T06「删除一律二次确认」
/// 同一纪律；而「生成」不确认，因为它**不动**对面任何东西（对面要拿到新值才受影响），
/// 但界面上必须有一句「只出现一次」。
class RemoteCredentialSettingsPage extends StatefulWidget {
  const RemoteCredentialSettingsPage({super.key, this.deps});

  final RemoteCredentialDeps? deps;

  @override
  State<RemoteCredentialSettingsPage> createState() =>
      _RemoteCredentialSettingsPageState();
}

/// 页面要碰的那一小包依赖（测试里整体换成替身，否则 KeyStore 与真契约进不了 widget 测试）。
class RemoteCredentialDeps {
  RemoteCredentialDeps({
    required this.contracts,
    required this.settings,
    required this.credentials,
    required this.addressCode,
  });

  factory RemoteCredentialDeps.fromLocator() {
    final contracts = GetIt.instance<FnthinkContractLoader>();
    return RemoteCredentialDeps(
      contracts: contracts,
      settings: null,
      credentials: null,
      addressCode: null,
    );
  }

  final FnthinkContractLoader contracts;
  final FnthinkRemoteSettings? settings;
  final RemoteCredentialStore? credentials;
  final Future<String?> Function()? addressCode;
}

class _RemoteCredentialSettingsPageState
    extends State<RemoteCredentialSettingsPage> {
  RemoteCredentialDeps? _deps;
  FnthinkRemoteSettings? _settings;
  RemoteCredentialStore? _store;
  FnthinkContract? _contract;

  /// 契约读不到时的原话。整页只显示这一条：凭据的**长度下限**与**TOTP 位数/步长**
  /// 都从契约来，拿不到契约还让人设凭据，等于把值写进一个说不清含义的地方。
  String? _contractError;

  RemoteCredentialState? _state;
  FnthinkRemoteDelaySetting? _delay;

  /// 「本机通知触发」那两格（T145，维护者 2026-10-12 裁定 4）：开关 + 可触发的应用清单。
  ///
  /// ⚠ 这一页**只画它、不判它**：判据在 `RemoteCommandRecognizer.judge` 那一处，
  ///   这里读的是同一个 `FnthinkRemoteSettings` 的读口。页面自己再判一次就是第二个读者。
  bool _localTrigger = false;
  FnthinkLocalTriggerFilter? _localTriggerFilter;

  /// 刚生成的那一把 / 那一枚。**只活在这个字段里**（见类注释那三件明文）。
  RemoteCredentialIssue? _freshKey;
  RemoteTotpIssue? _freshTotp;

  /// 界面上那句"生成/撤掉的那一发成了没有"。
  String? _note;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _deps = widget.deps;
    unawaited(_load());
  }

  Future<void> _load() async {
    final deps = _deps;
    final FnthinkContract contract;
    try {
      contract =
          await (deps?.contracts ?? GetIt.instance<FnthinkContractLoader>())
              .load();
    } on FnthinkContractUnavailable catch (e) {
      if (mounted) setState(() => _contractError = e.reason);
      return;
    }
    final settings =
        deps?.settings ?? FnthinkRemoteSettings(contract: contract);
    final store =
        deps?.credentials ?? RemoteCredentialStore(contract: contract);
    FnthinkRemoteDelaySetting? delay;
    String? delayError;
    try {
      delay = await settings.delaySetting();
    } on FnthinkRemoteSettingsInvalid catch (e) {
      delayError = e.reason;
    }
    if (!mounted) return;
    setState(() {
      _contract = contract;
      _settings = settings;
      _store = store;
      _delay = delay;
      if (delayError != null) _note = delayError;
    });
    await _refresh();
  }

  Future<void> _refresh() async {
    final settings = _settings;
    final store = _store;
    if (settings == null || store == null) return;
    final values = await Future.wait<Object>([
      settings.enabled,
      settings.effectiveDelaySeconds(),
      settings.localTriggerEnabled,
      settings.localTriggerFilter(),
    ]);
    if (!mounted) return;
    final state = await store.state(
      enabled: values[0] as bool,
      delaySeconds: values[1] as int,
    );
    if (!mounted) return;
    setState(() {
      _localTrigger = values[2] as bool;
      _localTriggerFilter = values[3] as FnthinkLocalTriggerFilter;
      _state = state;
      // 重读之后**旧的那份明文不再显示**：用户已经抄走（或没抄走），而留着它
      // 等于给一个"这是刚才那把"的假保证。
      _freshKey = null;
      _freshTotp = null;
    });
  }

  Future<void> _toggle(bool value) async {
    final settings = _settings;
    if (settings == null || _busy) return;
    setState(() => _busy = true);
    await settings.setEnabled(value);
    await _refresh();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _saveDelay(int seconds) async {
    final settings = _settings;
    if (settings == null || _busy) return;
    setState(() => _busy = true);
    String? error;
    try {
      await settings.setDelaySeconds(seconds);
    } on FnthinkRemoteSettingsInvalid catch (e) {
      error = e.reason;
    }
    await _refresh();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _note = error;
    });
  }

  Future<void> _resetDelay() async {
    final settings = _settings;
    if (settings == null || _busy) return;
    setState(() => _busy = true);
    await settings.clearDelaySeconds();
    await _refresh();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _generateKey() async {
    final store = _store;
    if (store == null || _busy) return;
    setState(() => _busy = true);
    final issue = await store.generateKey();
    await _refresh();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _freshKey = issue;
      _freshTotp = null;
    });
  }

  Future<void> _customKey() async {
    final store = _store;
    final contract = _contract;
    if (store == null || contract == null || _busy) return;
    final l10n = AppLocalizations.of(context);
    final input = await showIosInputDialog(
      context,
      title: l10n.remoteCredKeyCustom,
      hintText: l10n.remoteCredKeyMin(contract.remoteExecutionKeyMinLength),
      fieldKeyValue: 'remote-cred-key-input',
      // 这一串是**口令**：不许被自动纠错改成别的词（改错了对面那边一直说凭据不对）。
      autocorrect: false,
      // 不给眼睛看：这一页的另外两处明文是给人抄走的，而这一处用户自己知道。
      obscureText: true,
    );
    if (input == null || !mounted) return;
    setState(() => _busy = true);
    String? error;
    try {
      await store.setCustomKey(input);
    } on RemoteCredentialInvalid catch (e) {
      error = e.reason;
    }
    await _refresh();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _note = error;
    });
  }

  Future<void> _resetKey() async {
    final store = _store;
    if (store == null || _busy) return;
    final l10n = AppLocalizations.of(context);
    final ok = await IosDialogActions.askConfirm(
      context,
      title: l10n.remoteCredKeyReset,
      message: l10n.remoteCredKeyResetAsk,
      confirmText: l10n.confirm,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    await store.clearKey();
    await _refresh();
    if (!mounted) return;
    setState(() => _busy = false);
  }

  Future<void> _generateTotp() async {
    final store = _store;
    final deps = _deps;
    if (store == null || _busy) return;
    setState(() => _busy = true);
    // 账号名 = 本机地址码（拿不到就退成空串，而链接里的 label 少一个字段不影响验证器录入）。
    var account = '';
    try {
      account = await deps?.addressCode?.call() ?? '';
    } catch (_) {
      account = '';
    }
    final issue = await store.generateTotp(account: account);
    await _refresh();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _freshTotp = issue;
      _freshKey = null;
    });
  }

  Future<void> _clearTotp() async {
    final store = _store;
    if (store == null || _busy) return;
    setState(() => _busy = true);
    await store.clearTotp();
    await _refresh();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _freshTotp = null;
    });
  }

  Future<void> _resetAll() async {
    final store = _store;
    if (store == null || _busy) return;
    final l10n = AppLocalizations.of(context);
    final ok = await IosDialogActions.askConfirm(
      context,
      title: l10n.remoteCredResetAll,
      message: l10n.remoteCredResetAllAsk,
      confirmText: l10n.confirm,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    await store.clearAll();
    await _refresh();
    if (!mounted) return;
    setState(() => _busy = false);
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(
        title: Text(
          l10n.remoteExecOpenSettings,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (_contractError != null)
            FnthinkNote(
              keyName: 'remote-cred-contract-error',
              text: l10n.fnthinkContractUnavailable(_contractError!),
            )
          else if (_state == null)
            const SizedBox(height: 40)
          else ...[
            _buildSwitchCard(l10n),
            const SizedBox(height: 12),
            _buildLocalTriggerCard(l10n),
            const SizedBox(height: 12),
            _buildDelayCard(l10n),
            const SizedBox(height: 12),
            _buildKeyCard(l10n),
            const SizedBox(height: 12),
            _buildTotpCard(l10n),
            if (_note != null) ...[
              const SizedBox(height: 12),
              FnthinkNote(keyName: 'remote-cred-note', text: _note!),
            ],
          ],
        ],
      ),
    );
  }

  /// 「本机通知触发」那颗开关（T145，维护者 2026-10-12 裁定 4 的第一颗）。
  Future<void> _toggleLocalTrigger(bool value) async {
    final settings = _settings;
    if (settings == null) return;
    _busy = true;
    await settings.setLocalTriggerEnabled(value);
    if (!mounted) return;
    setState(() {
      _localTrigger = value;
      _busy = false;
    });
  }

  /// 「可触发的应用」那一格：**页复用、表不复用**。
  ///
  /// ⚠ 写进 `FnthinkRemoteSettings` 自己的三份键，不碰 `enabled_packages` ——
  ///   那一份的语义是「要转发的应用」，往它上面挂这一判，等于用户收窄
  ///   「谁的通知能动这台设备」时顺手改了推送名单（一次操作改两件事）。
  Future<void> _openLocalTriggerApps() async {
    final settings = _settings;
    if (settings == null) return;
    final current = _localTriggerFilter ?? await settings.localTriggerFilter();
    if (!mounted) return;
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      CupertinoPageRoute<Map<String, dynamic>>(
        builder: (_) => AppFilterPage(
          installedApps: const [],
          initialMode: current.mode,
          enabledPackages: current.packages.toList(),
        ),
      ),
    );
    if (result == null) return;
    final mode = result['mode'] as String? ?? 'allow';
    final packages = List<String>.from(result['packages'] ?? const []);
    await settings.setLocalTriggerFilter(mode: mode, packages: packages);
    if (!mounted) return;
    // ⚠ 回读走**同一个解析器**：直接拿 result 拼一份界面值，就把"写进去的形状"
    //   与"判定读出来的形状"分成两套 —— 而这两套必须逐字同形。
    setState(() {
      _localTriggerFilter = parseLocalTriggerFilter(
        mode: mode,
        rawPackages: jsonEncode(packages),
      );
    });
  }

  Widget _buildLocalTriggerCard(AppLocalizations l10n) {
    final filter = _localTriggerFilter;
    if (filter == null) return const SizedBox.shrink();
    final count = filter.packages.length;
    final blocking = filter.mode == 'block';
    return _Card(
      title: l10n.remoteExecLocalTriggerSection,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.remoteExecLocalTriggerShort,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
            ),
            HelpNoteButton(
              keyName: 'remote-exec-local-trigger-help',
              title: l10n.remoteExecLocalTriggerWhyTitle,
              body: l10n.remoteExecLocalTriggerWhy,
            ),
            CupertinoSwitch(
              key: const ValueKey('remote-exec-local-trigger-switch'),
              value: _localTrigger,
              onChanged: _busy ? null : _toggleLocalTrigger,
            ),
          ],
        ),
        FnthinkStatusRow(
          // T152 片D：那颗开关的当前状态（关着时必须说"任何通知正文都不会被执行"）——
          // 它是读数，所以走带点亮那一枚的公共件；词仍是 `On`/`Off` 那两句原话。
          keyName: 'remote-exec-local-trigger-state',
          dot: _localTrigger,
          text: _localTrigger
              ? l10n.remoteExecLocalTriggerOn
              : l10n.remoteExecLocalTriggerOff,
        ),
        FnthinkInlineAction(
          key: const ValueKey('remote-exec-local-trigger-apps'),
          label: l10n.remoteExecLocalTriggerApps,
          onPressed: _busy ? null : _openLocalTriggerApps,
        ),
        // ⚠ 空清单那一句**必须画出来**：这一路的「允许 0 个」是真的都不许（fail-closed），
        //   不说它，用户看到的就是「我开了怎么没用」而查不出原因。
        FnthinkNote(
          keyName: 'remote-exec-local-trigger-count',
          text: blocking
              ? l10n.remoteExecLocalTriggerBlockCount(count)
              : count == 0
              ? l10n.remoteExecLocalTriggerAllowNone
              : l10n.remoteExecLocalTriggerAllowCount(count),
        ),
      ],
    );
  }

  Widget _buildSwitchCard(AppLocalizations l10n) {
    final state = _state!;
    return _Card(
      title: l10n.remoteExecSection,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                // 原来这一行是 56 字的整段说明。现在只留一句短说，问号点开看全文
                //（维护者 2026-10-06：页面里不许成段堆小字）。长文一个字没删。
                l10n.remoteExecShort,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
            ),
            HelpNoteButton(
              keyName: 'remote-exec-switch-help',
              title: l10n.remoteExecWhyTitle,
              body: l10n.remoteExecWhy,
            ),
            CupertinoSwitch(
              key: const ValueKey('remote-exec-switch'),
              value: state.enabled,
              onChanged: _busy ? null : _toggle,
            ),
          ],
        ),
        FnthinkStatusRow(
          // T152 片D：开关的当前状态是**读数**，不是说明 ⇒ 点亮那一枚跟着那一个真值走。
          keyName: 'remote-exec-switch-state',
          dot: state.enabled,
          text: state.enabled
              ? l10n.remoteExecEnabledOn
              : l10n.remoteExecEnabledOff,
        ),
        // ⚠ 这一行不是提醒，是**L3 一条都进不来**这件事的事实：契约 l3Requires=true。
        //   不说它的后果是用户开完开关去发一条，然后不知道为什么被拒。
        if (state.l3Unreachable)
          FnthinkNote(
            keyName: 'remote-exec-needs-credential',
            text: l10n.remoteExecNeedsCredential,
          ),
      ],
    );
  }

  Widget _buildDelayCard(AppLocalizations l10n) {
    final delay = _delay;
    if (delay == null) return const SizedBox.shrink();
    return _Card(
      title: l10n.remoteExecDelayTitle,
      children: [
        FnthinkNote(
          keyName: 'remote-exec-delay-value',
          text: delay.chosen == null
              ? l10n.remoteExecDelayUsingDefault(delay.effective)
              : l10n.remoteExecDelayChosen(delay.effective),
        ),
        CupertinoSlider(
          key: const ValueKey('remote-exec-delay-slider'),
          value: delay.effective
              .clamp(delay.range.min.toDouble(), delay.range.max.toDouble())
              .toDouble(),
          min: delay.range.min.toDouble(),
          max: delay.range.max.toDouble(),
          divisions: delay.range.max - delay.range.min,
          onChanged: _busy ? null : (v) => _saveDelay(v.round()),
        ),
        FnthinkNote(
          keyName: 'remote-exec-delay-range',
          text: l10n.remoteExecDelayRange(delay.range.min, delay.range.max),
        ),
        if (delay.problem != null)
          FnthinkNote(
            keyName: 'remote-exec-delay-problem',
            text: l10n.remoteExecDelayInvalid(delay.problem!),
          ),
        if (delay.chosen != null)
          Align(
            alignment: Alignment.centerLeft,
            child: CupertinoButton(
              key: const ValueKey('remote-exec-delay-reset'),
              onPressed: _busy ? null : _resetDelay,
              child: Text(l10n.remoteExecDelayReset),
            ),
          ),
      ],
    );
  }

  Widget _buildKeyCard(AppLocalizations l10n) {
    final state = _state!;
    final fresh = _freshKey;
    return _Card(
      title: l10n.remoteCredKeySection,
      children: [
        HelpNoteRow(
          noteKey: 'remote-cred-why',
          helpKey: 'remote-cred-why-help',
          text: l10n.remoteCredShort,
          helpTitle: l10n.remoteCredWhyTitle,
          // 「两把钥匙」那句区别不能只留标题 —— 它是这一格唯一说明"为什么换了密钥还要重设凭据"的话。
          helpBody: l10n.remoteCredWhy,
        ),
        // ⚠ 三档分开：**没设** / **设了且有指纹（显示打点的那一格）** /
        //   **设了但没有指纹**（存量设备：指纹是后加的那一项）。第三档写成
        //   "已设一把"是**假承诺** —— 它让人以为看得见是哪一把。
        FnthinkStatusRow(
          // T152 片D：这一句是**这台有没有那把长期密钥**的读数 ⇒ 换成带点亮那一枚的公共件。
          // ⚠ 点只跟 `state.hasKey` 这一个真值走；三档原话（没设／设了有指纹／设了但没指纹）
          //   仍由 `_note` 那一位作者给 —— 点不亮不等于"坏了"，那一层区分在文字里。
          keyName: 'remote-cred-key-state',
          dot: state.hasKey,
          text: !state.hasKey
              ? l10n.remoteCredKeyNone
              : (state.entry?.maskedKey == null
                    ? l10n.remoteCredKeySetNoFingerprint
                    : l10n.remoteCredKeySet(state.entry!.maskedKey!)),
        ),
        // ⚠ 明文那一格**只在刚生成这一次**在：重读一次就没了（见类注释）。
        if (fresh != null) ...[
          SelectableText(
            fresh.key,
            key: const ValueKey('remote-cred-key-fresh'),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              letterSpacing: 1.1,
            ),
          ),
          // T149 片3：这一整段（68 字：只出现一次、关掉就只剩哈希、谁都看不回来）
          // 摊在明文下面读不动 —— 收成一行短说 + 问号，**正文一字没删**（维护者
          // 2026-10-12 第 4 条）。这一句是"错过就没了"的承诺，删掉比搬走更坏。
          HelpNoteRow(
            noteKey: 'remote-cred-key-once',
            helpKey: 'remote-cred-key-once-help',
            text: l10n.remoteCredKeyOnceShort,
            helpTitle: l10n.remoteCredKeySection,
            helpBody: l10n.remoteCredKeyOnce,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: CupertinoButton(
              key: const ValueKey('remote-cred-key-copy'),
              onPressed: () => _copy(fresh.key),
              child: Text(l10n.fnthinkCopy),
            ),
          ),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: CupertinoButton(
            key: const ValueKey('remote-cred-key-generate'),
            onPressed: _busy ? null : _generateKey,
            child: Text(l10n.remoteCredKeyGenerate),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: CupertinoButton(
            key: const ValueKey('remote-cred-key-custom'),
            onPressed: _busy ? null : _customKey,
            child: Text(l10n.remoteCredKeyCustom),
          ),
        ),
        if (state.hasKey)
          Align(
            alignment: Alignment.centerLeft,
            child: CupertinoButton(
              key: const ValueKey('remote-cred-key-reset'),
              onPressed: _busy ? null : _resetKey,
              child: Text(l10n.remoteCredKeyReset),
            ),
          ),
      ],
    );
  }

  Widget _buildTotpCard(AppLocalizations l10n) {
    final state = _state!;
    final fresh = _freshTotp;
    return _Card(
      title: l10n.remoteCredTotpSection,
      children: [
        if (state.problem != null)
          FnthinkNote(
            keyName: 'remote-cred-problem',
            text: l10n.remoteCredProblem(state.problem!),
          ),
        FnthinkNote(
          keyName: 'remote-cred-totp-state',
          text: state.hasTotp
              ? l10n.remoteCredTotpSet
              : l10n.remoteCredTotpNone,
        ),
        if (fresh != null) ...[
          FnthinkNote(
            keyName: 'remote-cred-totp-link-label',
            text: l10n.remoteCredTotpLink,
          ),
          // ⚠ **二维码画的就是上面那串链接，同一份 `fresh.uri`** —— 不另拼一遍：
          //   两处各拼一次的话，某天改了链接的拼法而忘了这一处，用户扫出来的
          //   就是一条**指向别处的**链接，而界面看上去完全正常。
          // ⚠ 用 `PrettyQrView.data`（不是已废弃的 `PrettyQr` 构造）：它按数据长度**自动选版本**，
          //   而版本选错的表现是"扫出来是一坨看不懂的东西"而界面完全正常。
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: SizedBox(
                width: 220,
                height: 220,
                child: PrettyQrView.data(
                  data: fresh.uri,
                  key: const ValueKey('remote-cred-totp-qr'),
                  // 纠错等级取 M（不是默认的 L）：这一段是屏幕显示而不是打印，
                  // 中等纠错在 220px 上更耐得住反光与轻微变形。
                  errorCorrectLevel: QrErrorCorrectLevel.M,
                ),
              ),
            ),
          ),
          SelectableText(
            fresh.uri,
            key: const ValueKey('remote-cred-totp-uri'),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: CupertinoButton(
              key: const ValueKey('remote-cred-totp-copy-link'),
              onPressed: () => _copy(fresh.uri),
              child: Text(l10n.fnthinkCopy),
            ),
          ),
          FnthinkNote(
            keyName: 'remote-cred-totp-secret-label',
            text: l10n.remoteCredTotpSecret,
          ),
          SelectableText(
            fresh.secret,
            key: const ValueKey('remote-cred-totp-secret'),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              letterSpacing: 1.1,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: CupertinoButton(
              key: const ValueKey('remote-cred-totp-copy-secret'),
              onPressed: () => _copy(fresh.secret),
              child: Text(l10n.fnthinkCopy),
            ),
          ),
          HelpNoteRow(
            noteKey: 'remote-cred-totp-once',
            helpKey: 'remote-cred-totp-once-help',
            text: l10n.remoteCredTotpOnceShort,
            helpTitle: l10n.remoteCredTotpSection,
            // T149 片3：80 字那一段（只出现一次、只存接收端、不经过任何服务器）整段进问号，
            // **正文一字没删** —— 那句"不经过服务器"是要紧的承诺，删掉比搬走更坏。
            helpBody: l10n.remoteCredTotpOnce,
          ),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: CupertinoButton(
            key: const ValueKey('remote-cred-totp-generate'),
            onPressed: _busy ? null : _generateTotp,
            child: Text(l10n.remoteCredTotpGenerate),
          ),
        ),
        if (state.hasTotp)
          Align(
            alignment: Alignment.centerLeft,
            child: CupertinoButton(
              key: const ValueKey('remote-cred-totp-clear'),
              onPressed: _busy ? null : _clearTotp,
              child: Text(l10n.remoteCredTotpClear),
            ),
          ),
        if (state.hasKey || state.hasTotp)
          Align(
            alignment: Alignment.centerLeft,
            child: CupertinoButton(
              key: const ValueKey('remote-cred-reset-all'),
              onPressed: _busy ? null : _resetAll,
              child: Text(l10n.remoteCredResetAll),
            ),
          ),
      ],
    );
  }
}

/// 一张卡（版式与幻念推送页那几格同形）。
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
