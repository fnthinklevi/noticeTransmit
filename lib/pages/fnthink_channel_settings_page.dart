import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:get_it/get_it.dart';

import '../l10n/app_localizations.dart';
import '../models/fnthink_channel.dart';
import '../models/fnthink_peer.dart';
import '../services/channel_display.dart';
import '../services/channel_health_store.dart';
import '../services/fnthink_channel_service.dart';
import '../services/fnthink_receive_coordinator.dart';
import '../theme/app_colors.dart';
import '../widgets/fnthink_card.dart';
import '../widgets/ios_input_dialog.dart';
import '../widgets/ios_option_picker.dart';

/// 一条幻念通道的设置（T94 片3）。
///
/// 三条判据：
/// - **种类只两种**（设备 / webhook）：加第三种就是加一条没有发送实现的路，
///   而界面摆一条点了没反应的行比没有这行更糟。
/// - **设备那一支只能从已勾选的名单里挑**，不是自由输入：自由输入会让"这一台同不同意收"
///   变成界面上的一个字段，而它的真值在名单那一列。
/// - **保存走服务那一处**（[FnthinkChannelService]），校验也只在那里一份：页面再判一遍
///   就会出现两个作者，而它们只在其中一侧被改动时才会分叉。
class FnthinkChannelSettingsPage extends StatefulWidget {
  const FnthinkChannelSettingsPage({
    super.key,
    this.channel,
    this.service,
    this.probe,
  });

  /// null = 新建。
  final FnthinkChannel? channel;

  final FnthinkChannelStore? service;

  /// 「测试这条通道」那两件（#271）。**没接就不画那一枚** ——
  /// 点了没反应的按钮比没有这一枚更糟（本仓那条老判据）。
  final FnthinkChannelProbeDeps? probe;

  @override
  State<FnthinkChannelSettingsPage> createState() =>
      _FnthinkChannelSettingsPageState();
}

/// 「测试这条通道」要的两件（#271）：**真发一条**的那一发 ＋ 记账口。
///
/// 为什么这两件必须成对：幻念这一族**没有非侵入探针**（`presence` 只答本机醒不醒），
/// 所以徽标的语义只能是「最近一次测过」。只给发送不给记账 ⇒ 徽标永远「没测过」；
/// 只给记账不给发送 ⇒ 界面能造出没有发生过的事实。
class FnthinkChannelProbeDeps {
  const FnthinkChannelProbeDeps({required this.send, required this.health});

  /// 生产装配点：列表页 push 详情页时构造一次。
  /// 发送走**既有那一发**（`sendNotice` 的 `requireEnabled: false` 口径）—— 这里不另开
  /// 一条发消息的路；ok 的判据是 `accepted`，其余档位（含「对面没接」）都算没通。
  factory FnthinkChannelProbeDeps.fromLocator() => FnthinkChannelProbeDeps(
    send: ({required peer, required title, required text}) async {
      final result = await GetIt.instance<FnthinkReceiveCoordinator>()
          .sendNotice(peer: peer, title: title, text: text);
      return result.status == FnthinkSendStatus.accepted;
    },
    health: GetIt.instance<ChannelHealthStore>(),
  );

  /// 发一条（ok = 对面收下了这一发）。
  final Future<bool> Function({
    required String peer,
    required String title,
    required String text,
  })
  send;

  /// 记账口（单点）。键写 `(kFnthinkChannelSlug, 通道 id)` —— **不是 host**：
  /// `(fnthink, host)` 那格是「这台对中转服务器最近一次发出去怎样」，两格不许串。
  final ChannelHealthStore health;
}

class _FnthinkChannelSettingsPageState
    extends State<FnthinkChannelSettingsPage> {
  late final FnthinkChannelStore _service;

  final TextEditingController _name = TextEditingController();
  final TextEditingController _target = TextEditingController();

  FnthinkChannelTarget _kind = FnthinkChannelTarget.device;
  bool _enabled = true;
  String _role = 'primary';
  bool _busy = false;

  List<FnthinkPeer>? _targets;

  /// 保存之后的那一句结论（失败也留原话，不折叠成"保存失败"）。
  String? _note;

  /// 「测试这条通道」那一句结论（同样留原话）。
  String? _probeNote;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? FnthinkChannelService();
    final channel = widget.channel;
    if (channel != null) {
      _name.text = channel.name;
      _target.text = channel.target;
      _kind = channel.targetKind;
      _enabled = channel.enabled;
      _role = channel.role;
    }
    _loadTargets();
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _loadTargets() async {
    try {
      final rows = await _service.listForwardTargets();
      if (!mounted) return;
      setState(() => _targets = rows);
    } catch (_) {
      // 读不到时那一支不许自由输入（那正是它存在的意义）：留着 null，界面上说读不到。
      if (mounted) setState(() => _targets = null);
    }
  }

  Future<void> _editName() async {
    final l10n = AppLocalizations.of(context);
    final value = await showIosInputDialog(
      context,
      title: l10n.fnthinkChannelName,
      hintText: l10n.fnthinkChannelNameHint,
      initialText: _name.text,
    );
    if (value == null || !mounted) return;
    setState(() {
      _name.text = value;
      _note = null;
    });
  }

  Future<void> _editWebhookTarget() async {
    final l10n = AppLocalizations.of(context);
    final value = await showIosInputDialog(
      context,
      title: l10n.fnthinkChannelTarget,
      hintText: 'https://',
      initialText: _target.text,
    );
    if (value == null || !mounted) return;
    setState(() {
      _target.text = value;
      _note = null;
    });
  }

  Future<void> _pickDevice() async {
    final rows = _targets ?? const <FnthinkPeer>[];
    if (rows.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    final picked = await showIosOptionPicker<String>(
      context,
      title: l10n.fnthinkChannelTargetKindDevice,
      options: [
        for (final p in rows)
          IosPickerOption<String>(value: p.peerAddress, label: p.peerAddress),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() {
      _target.text = picked;
      _note = null;
    });
  }

  Future<void> _pickRole() async {
    final l10n = AppLocalizations.of(context);
    const roles = ['primary', 'backup', 'none'];
    final picked = await showIosOptionPicker<String>(
      context,
      title: l10n.fnthinkChannelRole,
      options: [
        for (final r in roles) IosPickerOption<String>(value: r, label: r),
      ],
      selectedValue: _role,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _role = picked;
      _note = null;
    });
  }

  /// 「测试这条通道」（#271）：**会真的往它发一条** —— 这一族没有非侵入探针，
  /// 界面在按钮旁写了这句话。发完按结果记账：徽标记的是「最近一次测过」。
  Future<void> _probeChannel() async {
    final probe = widget.probe;
    final channel = widget.channel;
    if (probe == null || channel == null || _busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _probeNote = null;
    });
    final watch = Stopwatch()..start();
    var ok = false;
    String? failure;
    try {
      ok = await probe.send(
        peer: channel.target,
        title: l10n.fnthinkChannelProbeTitle,
        text: l10n.fnthinkChannelProbeBody,
      );
    } catch (e) {
      failure = '$e';
    }
    final ms = watch.elapsedMilliseconds;
    await probe.health.record(
      kFnthinkChannelSlug,
      channel.id,
      reachable: failure == null && ok,
      latencyMs: ms,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _probeNote = failure != null
          ? l10n.fnthinkChannelProbeFail(failure)
          : (ok
                ? l10n.fnthinkChannelProbeOk(ms)
                : l10n.fnthinkChannelProbeRejected);
    });
  }

  Future<void> _save() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final name = _name.text.trim();
    final target = _target.text.trim();
    try {
      if (name.isEmpty) {
        throw ArgumentError(l10n.fnthinkChannelNameEmpty);
      }
      if (target.isEmpty) {
        throw ArgumentError(l10n.fnthinkChannelTargetEmpty);
      }
      final existing = widget.channel;
      if (existing == null) {
        await _service.create(
          id: 'fc_${DateTime.now().millisecondsSinceEpoch}',
          name: name,
          target: target,
          targetKind: _kind,
          role: _role,
        );
      } else {
        await _service.save(
          existing.copyWith(
            name: name,
            target: target,
            targetKind: _kind,
            enabled: _enabled,
            role: _role,
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _note = l10n.fnthinkChannelSaved;
      });
    } catch (e) {
      if (!mounted) return;
      final l10nNow = AppLocalizations.of(context);
      setState(() {
        _busy = false;
        _note = l10nNow.fnthinkChannelSaveFailed(_reasonOf(e, l10nNow));
      });
    }
  }

  /// 把服务抛出来的话翻成界面那句话。**不折叠成「保存失败」**：那一格存在的意义
  /// 就是告诉用户"这一下到底被什么挡住"。
  String _reasonOf(Object e, AppLocalizations l10n) {
    final text = '$e';
    if (text.contains('还没勾选')) return l10n.fnthinkChannelTargetNotChecked;
    if (text.contains('名单里没有')) return l10n.fnthinkChannelTargetNotChecked;
    if (text.contains('https')) return l10n.fnthinkChannelTargetBadScheme;
    if (text.contains('名称')) return l10n.fnthinkChannelNameEmpty;
    if (text.contains('目标')) return l10n.fnthinkChannelTargetEmpty;
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final targets = _targets;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.channel == null
              ? l10n.fnthinkChannelNewTitle
              : l10n.fnthinkChannelTitle,
        ),
      ),
      backgroundColor: AppColors.bgColor(context),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          FnthinkCard(
            title: l10n.fnthinkChannelTitle,
            children: [
              _FieldRow(
                keyName: 'fnthink-channel-name',
                label: l10n.fnthinkChannelName,
                value: _name.text,
                onTap: _editName,
              ),
              _FieldRow(
                keyName: 'fnthink-channel-kind',
                label: l10n.fnthinkChannelTargetKind,
                value: _kind == FnthinkChannelTarget.webhook
                    ? l10n.fnthinkChannelTargetKindWebhook
                    : l10n.fnthinkChannelTargetKindDevice,
                onTap: () => setState(() {
                  _kind = _kind == FnthinkChannelTarget.device
                      ? FnthinkChannelTarget.webhook
                      : FnthinkChannelTarget.device;
                  _target.clear();
                  _note = null;
                }),
              ),
              if (_kind == FnthinkChannelTarget.device)
                _FieldRow(
                  keyName: 'fnthink-channel-target',
                  label: l10n.fnthinkChannelTarget,
                  value: _target.text.isEmpty
                      ? (targets == null
                            ? '—'
                            : (targets.isEmpty
                                  ? l10n.fnthinkChannelNoTargetPicked
                                  : l10n.fnthinkChannelTarget))
                      : _target.text,
                  onTap: targets == null || targets.isEmpty
                      ? null
                      : _pickDevice,
                )
              else
                _FieldRow(
                  keyName: 'fnthink-channel-target',
                  label: l10n.fnthinkChannelTarget,
                  value: _target.text.isEmpty ? 'https://' : _target.text,
                  onTap: _editWebhookTarget,
                ),
              _FieldRow(
                keyName: 'fnthink-channel-role',
                label: l10n.fnthinkChannelRole,
                value: _role,
                onTap: _pickRole,
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.fnthinkChannelEnabled,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  CupertinoSwitch(
                    key: const ValueKey('fnthink-channel-enabled'),
                    value: _enabled,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _enabled = v),
                  ),
                ],
              ),
            ],
          ),
          if (_note != null)
            FnthinkNote(keyName: 'fnthink-channel-note', text: _note!),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: CupertinoButton.filled(
              key: const ValueKey('fnthink-channel-save'),
              onPressed: _busy ? null : _save,
              child: Text(l10n.fnthinkChannelSave),
            ),
          ),
          // #271：只有**设备档**能给这一枚 —— webhook 档的发送实现在原生那侧
          // （NetworkClient），从 Dart 给一枚按钮就是摆一条点了没反应的路。
          if (widget.probe != null &&
              widget.channel != null &&
              _kind == FnthinkChannelTarget.device) ...[
            FnthinkInlineAction(
              key: const ValueKey('fnthink-channel-probe'),
              label: l10n.fnthinkChannelProbe,
              onPressed: _busy ? null : _probeChannel,
            ),
            FnthinkNote(
              keyName: 'fnthink-channel-probe-why',
              text: l10n.fnthinkChannelProbeWhy,
            ),
            if (_probeNote != null)
              FnthinkNote(
                keyName: 'fnthink-channel-probe-note',
                text: _probeNote!,
              ),
          ],
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.keyName,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String keyName;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: CupertinoButton(
        key: ValueKey(keyName),
        padding: EdgeInsets.zero,
        onPressed: onTap,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.primaryLabel(context),
                ),
              ),
            ),
            Flexible(
              child: Text(
                value,
                key: ValueKey('$keyName-value'),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
