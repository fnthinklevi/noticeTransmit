import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:get_it/get_it.dart';

import '../l10n/app_localizations.dart';
import '../models/fnthink_channel.dart';
import '../models/fnthink_peer.dart';
import '../services/channel_config_codec.dart';
import '../services/channel_display.dart';
import '../services/channel_health_store.dart';
import '../services/fnthink_channel_service.dart';
import '../services/fnthink_receive_coordinator.dart';
import '../theme/app_colors.dart';
import '../widgets/app_text_selection_menu.dart';
import '../widgets/channel_health_badge.dart';
import '../widgets/channel_visuals.dart';
import '../widgets/fnthink_card.dart';
import '../widgets/ios_option_picker.dart';
import '../widgets/primary_action_button.dart';

/// 一条幻念通道的设置（T94 片3；2026-10-08 版式对齐另外三族）。
///
/// 三条判据（一条未改）：
/// - **种类只两种**（设备 / webhook）：加第三种就是加一条没有发送实现的路，
///   而界面摆一条点了没反应的行比没有这行更糟。
/// - **设备那一支只能从已勾选的名单里挑**，不是自由输入：自由输入会让"这一台同不同意收"
///   变成界面上的一个字段，而它的真值在名单那一列。
/// - **保存走服务那一处**（[FnthinkChannelService]），校验也只在那里一份：页面再判一遍
///   就会出现两个作者，而它们只在其中一侧被改动时才会分叉。
///
/// 2026-10-08 按维护者点名的四条改了版式（判据一条没动，动的都是"怎么说"）：
/// 1. **必填项当场红字**在字段下面。此前那一句是卡片底下一行 12px 灰字 —— 与"这条
///    通道为什么没存上"那种结论混在一起，等于没说。红字只报字段，服务那侧的原话
///    仍然原样进结论框（判据的作者还是服务那一个）。
/// 2. **页脚两枚成对**：「仅探测」＋「探测并保存」，保存默认带探测。另三族的同一件事
///    叫「仅测试／测试并保存」并且摆在右上角（`webhook_settings_page.dart` T04）——
///    位置按维护者点名的放在页脚，语义与那两枚逐字对齐：测失败不回滚保存。
/// 3. **主备那一档画中文**（`rolePrimary`/`roleBackup`/`roleNone`/`roleUnset`），存的仍是
///    跨语言字符串契约的原值 —— **界面译文与落库字面量是两件事**，此前把 token 直接
///    当 label 画了出来（"primary/backup/none"）。新建的起点同时改成「未设置」，与
///    另外三族一致：全部停在「主」时同一条通知会被重复推送。
/// 4. **整页与另三族同形**：一张卡（图标＋种类＋健康徽标）→ 标签在上、输入框在下 →
///    结论框按绿/红底。之前是「点开弹窗改一行」那套，与同组另外三张新建页差着一个形状。
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

  /// 「测试这条通道」要的两件（#271）。**没接就不画那一枚** ——
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

  /// 新建的起点是「未设置」，不是「主」（与另外三族同一口径：`ChannelConfigCodec.roleUnset`
  /// 只在新建路径写，它不会跟着主通道重复推送，只有一条主通道都没设时才轮到它）。
  String _role = ChannelConfigCodec.roleUnset;
  bool _busy = false;

  List<FnthinkPeer>? _targets;

  /// 通道 id：**在写库之前先发号**（另三族 T04 的同一做法）。没有稳定归属的记账会把
  /// 「最近一次测过」挂到一条还不存在的通道上 —— 于是那一发既丢了、也钉错了地方。
  String? _id;

  /// 已经建过 ⇒ 之后的保存走 update 而不是再 insert 一条（连按两下"探测并保存"
  /// 不该在库里留下两条同名通道）。
  bool _created = false;

  /// 保存那一发的结论（失败留服务那侧的原话，不折叠成"保存失败"）。
  String? _note;
  bool? _noteOk;

  /// 「测试这条通道」那一句结论（同样留原话）。
  String? _probeNote;
  bool? _probeOk;

  /// 字段级红字。为空＝这一项此刻没毛病。
  String? _nameError;
  String? _targetError;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? FnthinkChannelService();
    final channel = widget.channel;
    if (channel != null) {
      _id = channel.id;
      _created = true;
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

  /// 只有**设备档**能从这一页探测：webhook 那一支的发送实现在原生那侧（NetworkClient），
  /// 从 Dart 给一枚按钮就是摆一条点了没反应的路。
  bool get _canProbe =>
      widget.probe != null && _kind == FnthinkChannelTarget.device;

  /// 卡片头上那枚徽标：这一条通道最近一次「测过」怎样。
  /// 没有 probe 依赖（测试／别处构造）就没有账本可读 ⇒ 不画，而不是画一枚绿的。
  ChannelHealth? get _healthInfo {
    final store = widget.probe?.health;
    final id = _id;
    if (store == null || id == null) return null;
    return store.of(kFnthinkChannelSlug, id);
  }

  /// 界面上这一条此刻的样子（未保存的编辑也算）。
  FnthinkChannel _draft() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return FnthinkChannel(
      id: _id ??= 'fc_$now',
      name: _name.text.trim(),
      target: _target.text.trim(),
      targetKind: _kind,
      enabled: _enabled,
      role: _role,
      createdAt: widget.channel?.createdAt ?? now,
      updatedAt: now,
    );
  }

  String _kindLabel(AppLocalizations l10n) =>
      _kind == FnthinkChannelTarget.webhook
      ? l10n.fnthinkChannelTargetKindWebhook
      : l10n.fnthinkChannelTargetKindDevice;

  /// 主备那一档的**译文**。存的仍是 `ChannelConfigCodec` 那几个字面量 —— 认不出来时
  /// 按「主」显示与另三族同口径（`normalizeRole` 在写那一侧也是这个方向）。
  String _roleLabel(AppLocalizations l10n) => switch (_role) {
    ChannelConfigCodec.roleBackup => l10n.roleBackup,
    ChannelConfigCodec.roleNone => l10n.roleNone,
    ChannelConfigCodec.roleUnset => l10n.roleUnset,
    _ => l10n.rolePrimary,
  };

  String _title(AppLocalizations l10n) {
    final name = _name.text.trim();
    // 标题跟着名字走：不重绘就还是「新建幻念通道」，用户认不出自己刚建的那一条。
    if (name.isNotEmpty) return name;
    return _created ? l10n.fnthinkChannelTitle : l10n.fnthinkChannelNewTitle;
  }

  /// 必填项点名到字段（T03 的形状）。这两条与 `FnthinkChannelService._rejectInvalid`
  /// 是同一句话，页面只是**提前**把它说在字段上；真作者仍然是服务那一个 ——
  /// 「https」与「名单里有没有这一台」这两条一律不在这里判，走服务抛出来的原话。
  bool _precheck() {
    final l10n = AppLocalizations.of(context);
    final nameError = _name.text.trim().isEmpty
        ? l10n.fnthinkChannelNameEmpty
        : null;
    final targetError = _target.text.trim().isEmpty
        ? l10n.fnthinkChannelTargetEmpty
        : null;
    setState(() {
      _nameError = nameError;
      _targetError = targetError;
    });
    return nameError == null && targetError == null;
  }

  Future<void> _pickKind() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showIosOptionPicker<FnthinkChannelTarget>(
      context,
      title: l10n.fnthinkChannelTargetKind,
      selectedValue: _kind,
      options: [
        IosPickerOption<FnthinkChannelTarget>(
          value: FnthinkChannelTarget.device,
          icon: Icons.phone_iphone,
          label: l10n.fnthinkChannelTargetKindDevice,
        ),
        IosPickerOption<FnthinkChannelTarget>(
          value: FnthinkChannelTarget.webhook,
          icon: Icons.link,
          label: l10n.fnthinkChannelTargetKindWebhook,
        ),
      ],
    );
    if (picked == null || picked == _kind || !mounted) return;
    setState(() {
      _kind = picked;
      // 两种目标的取值空间不搭（18 位地址码 vs https 地址）：留着上一支的值，
      // 保存时只会得到一句"要以 https:// 开头"，而那句是本可以不必说的。
      _target.clear();
      _targetError = null;
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
      selectedValue: _target.text.isEmpty ? null : _target.text,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _target.text = picked;
      _targetError = null;
      _note = null;
    });
  }

  Future<void> _pickRole() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showIosOptionPicker<String>(
      context,
      title: l10n.fnthinkChannelRole,
      options: [
        // ⚠ 这里**故意没有**「未设置」那一档（与通道状态页 `_roleRow` 同一判据）：
        //   它是新建通道的起点，不是一个可以被选回去的决定；起点上三段都不打勾。
        // label 走译文、value 走跨语言字面量 —— 此前把 token 当 label 画了出来。
        IosPickerOption<String>(
          value: ChannelConfigCodec.rolePrimary,
          label: l10n.rolePrimary,
        ),
        IosPickerOption<String>(
          value: ChannelConfigCodec.roleBackup,
          label: l10n.roleBackup,
        ),
        IosPickerOption<String>(
          value: ChannelConfigCodec.roleNone,
          label: l10n.roleNone,
        ),
      ],
      selectedValue: _role,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _role = picked;
      _note = null;
    });
  }

  /// 「仅探测」（#271）：**会真的往它发一条** —— 这一族没有非侵入探针，
  /// 按钮旁边那句话写的就是这件事。发完按结果记账：徽标记的是「最近一次测过」。
  Future<void> _probe() async {
    final probe = widget.probe;
    if (probe == null || _busy) return;
    if (!_precheck()) return;
    final l10n = AppLocalizations.of(context);
    final channel = _draft();
    setState(() {
      _busy = true;
      _probeNote = null;
      _probeOk = null;
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
      _probeOk = failure == null && ok;
      _probeNote = failure != null
          ? l10n.fnthinkChannelProbeFail(failure)
          : (ok
                ? l10n.fnthinkChannelProbeOk(ms)
                : l10n.fnthinkChannelProbeRejected);
    });
  }

  /// 「探测并保存」：先落库，再按刚存下的那一版测一次。
  ///
  /// 测失败**不回滚**保存（T04 的决策）：配置是对的、只是这一刻连不上，回滚会把用户
  /// 的有效编辑一起吞掉。反过来「没存上」就根本不发探测 —— 那一条通道还不存在。
  Future<void> _save() async {
    if (_busy) return;
    if (!_precheck()) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _note = null;
      _noteOk = null;
    });
    final channel = _draft();
    try {
      if (!_created) {
        await _service.create(
          id: channel.id,
          name: channel.name,
          target: channel.target,
          targetKind: channel.targetKind,
          role: channel.role,
        );
        _created = true;
        // create 的签名里没有启停这一位（库里默认开）：关掉时补一次 save，否则
        // 界面上这条是停的、库里那条是开的，它会照常往外推。
        if (!channel.enabled) await _service.save(channel);
      } else {
        await _service.save(channel);
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _noteOk = true;
        _note = l10n.fnthinkChannelSaved;
      });
    } catch (e) {
      if (!mounted) return;
      final now = AppLocalizations.of(context);
      setState(() {
        _busy = false;
        _noteOk = false;
        _note = now.fnthinkChannelSaveFailed(_reasonOf(e, now));
      });
      return;
    }
    if (_canProbe) await _probe();
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

  InputDecoration _input(
    BuildContext context, {
    required String hint,
    String? errorText,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        fontSize: 13,
        color: AppColors.tertiaryLabel(context),
      ),
      // 红字挂在字段下面，而不是卡片底下那一行灰字（维护者 2026-10-08 第 1 条）。
      errorText: errorText,
      errorStyle: const TextStyle(color: AppColors.red, fontSize: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.separator(context)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.separator(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.blue),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.red),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      isDense: true,
      filled: true,
      fillColor: AppColors.inputBg(context),
    );
  }

  Widget _label(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: AppColors.secondaryLabel(context),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// 结论框：绿/红底 + 图标 + 原话。形状抄 webhook 那一族（`_buildTestResultBox`），
  /// 三族同一页面上"这一发到底怎样"就是同一个东西。
  Widget _resultBox(
    BuildContext context, {
    required String keyName,
    required String text,
    required bool ok,
  }) {
    final color = ok ? AppColors.green : AppColors.red;
    return Container(
      key: ValueKey(keyName),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ok ? Icons.check_circle : Icons.error, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: color, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final targets = _targets;
    final visual = channelVisual(kFnthinkChannelSlug);
    final noTargets = targets == null || targets.isEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(_title(l10n))),
      backgroundColor: AppColors.bgColor(context),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardBg(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.separator(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(visual.icon, size: 18, color: visual.color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _kindLabel(l10n),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryLabel(context),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ChannelHealthBadge(health: _healthInfo),
                  ],
                ),
                const SizedBox(height: 14),
                _label(context, l10n.fnthinkChannelName),
                TextField(
                  key: const ValueKey('fnthink-channel-name'),
                  contextMenuBuilder: AppTextSelectionMenu.editableText,
                  controller: _name,
                  maxLines: 1,
                  decoration: _input(
                    context,
                    hint: l10n.fnthinkChannelNameHint,
                    errorText: _nameError,
                  ),
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.primaryLabel(context),
                  ),
                  onChanged: (_) {
                    // 标题跟着名字走；填了字就把那行红字收掉（否则它赖在那里说假话）。
                    setState(() {
                      if (_name.text.trim().isNotEmpty) _nameError = null;
                    });
                  },
                ),
                const SizedBox(height: 12),
                _label(context, l10n.fnthinkChannelTargetKind),
                _FieldButton(
                  keyName: 'fnthink-channel-kind',
                  icon: _kind == FnthinkChannelTarget.webhook
                      ? Icons.link
                      : Icons.phone_iphone,
                  value: _kindLabel(l10n),
                  onTap: _pickKind,
                ),
                const SizedBox(height: 12),
                _label(context, l10n.fnthinkChannelTarget),
                if (_kind == FnthinkChannelTarget.device) ...[
                  _FieldButton(
                    keyName: 'fnthink-channel-target',
                    icon: Icons.qr_code,
                    value: _target.text.isEmpty
                        ? l10n.fnthinkChannelTargetPick
                        : _target.text,
                    // 没勾选过任何设备 ⇒ 这一格点不动，并在下面说清去哪儿勾。
                    // 自由输入会把"这一台同不同意收"变成一个字段，而它的真值在名单那一列。
                    onTap: noTargets ? null : _pickDevice,
                  ),
                  if (noTargets)
                    FnthinkNote(
                      keyName: 'fnthink-channel-target-empty',
                      text: l10n.fnthinkChannelNoTargetPicked,
                    ),
                ] else
                  TextField(
                    key: const ValueKey('fnthink-channel-target'),
                    contextMenuBuilder: AppTextSelectionMenu.editableText,
                    controller: _target,
                    maxLines: 1,
                    decoration: _input(
                      context,
                      hint: 'https://',
                      errorText: _targetError,
                    ),
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.primaryLabel(context),
                    ),
                    onChanged: (_) {
                      setState(() {
                        if (_target.text.trim().isNotEmpty) _targetError = null;
                      });
                    },
                  ),
                const SizedBox(height: 12),
                _label(context, l10n.fnthinkChannelRole),
                _FieldButton(
                  keyName: 'fnthink-channel-role',
                  icon: Icons.layers_outlined,
                  value: _roleLabel(l10n),
                  onTap: _pickRole,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.fnthinkChannelEnabled,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.primaryLabel(context),
                        ),
                      ),
                    ),
                    CupertinoSwitch(
                      key: const ValueKey('fnthink-channel-enabled'),
                      value: _enabled,
                      activeTrackColor: AppColors.purple,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _enabled = v),
                    ),
                  ],
                ),
                if (_note != null)
                  _resultBox(
                    context,
                    keyName: 'fnthink-channel-note',
                    text: _note!,
                    ok: _noteOk ?? true,
                  ),
                if (_probeNote != null)
                  _resultBox(
                    context,
                    keyName: 'fnthink-channel-probe-note',
                    text: _probeNote!,
                    ok: _probeOk ?? true,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (_canProbe) ...[
                Expanded(
                  child: _OutlineActionButton(
                    keyName: 'fnthink-channel-probe',
                    label: l10n.fnthinkChannelProbeOnly,
                    onPressed: _busy ? null : _probe,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                flex: _canProbe ? 2 : 1,
                // webhook 那一支测不了（发送实现在原生那侧）⇒ 主操作就只说「保存」，
                // 不冒充一个做不到的动作；那一枚「仅探测」也就不画（不是置灰：这一档压根没有）。
                child: PrimaryActionButton(
                  key: const ValueKey('fnthink-channel-save'),
                  label: _canProbe
                      ? l10n.fnthinkChannelProbeAndSave
                      : l10n.fnthinkChannelSave,
                  onPressed: _busy ? null : _save,
                ),
              ),
            ],
          ),
          // 页脚下面那一行说的是"这一枚到底会不会往外发"。它是**动作的边界**，
          // 不是成段说明（§1 例外中的"状态原话"），所以留在一行里、不进问号弹层。
          if (_canProbe)
            FnthinkNote(
              keyName: 'fnthink-channel-probe-why',
              text: l10n.fnthinkChannelProbeWhy,
            )
          else if (widget.probe != null)
            FnthinkNote(
              keyName: 'fnthink-channel-probe-unavailable',
              text: l10n.fnthinkChannelProbeUnavailable,
            ),
        ],
      ),
    );
  }
}

/// 「点开再选／点开再挑」那一类字段（与 webhook 那一族的类型选择框同形：
/// 输入底色 + 行首图标 + 值 + 右箭头）。
///
/// `onTap` 传 null = 此刻挑不动（名单里一台都没勾选过）：**置灰，不是藏起来**。
/// 仍然是 `CupertinoButton`：这一格的禁用态要用例点得中，而用例认的是这一件。
class _FieldButton extends StatelessWidget {
  const _FieldButton({
    required this.keyName,
    required this.icon,
    required this.value,
    required this.onTap,
  });

  final String keyName;
  final IconData icon;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dim = onTap == null;
    return CupertinoButton(
      key: ValueKey(keyName),
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.inputBg(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.separator(context)),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: dim ? AppColors.tertiaryLabel(context) : AppColors.blue,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                key: ValueKey('$keyName-value'),
                style: TextStyle(
                  fontSize: 14,
                  color: dim
                      ? AppColors.tertiaryLabel(context)
                      : AppColors.primaryLabel(context),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.tertiaryLabel(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// 页脚那一对里的**次级**一枚（描边、与主操作同高）。
///
/// 为什么不复用 `FnthinkInlineAction`（蓝字裸文本）：那一枚是"对行里那个值做点什么"
/// （复制、重置），与"这一页的动作"不是同一件事；贴在填充按钮旁边会一高一矮、
/// 一实一虚，而这两枚是同一个决定（测不测）的两个档。
/// 形状与 `PrimaryActionButton` 同：圆角 12、左右 16、上下 12、字号 15／w600。
class _OutlineActionButton extends StatelessWidget {
  const _OutlineActionButton({
    required this.keyName,
    required this.label,
    required this.onPressed,
  });

  final String keyName;
  final String label;

  /// null = 此刻不可用（正在忙）：**置灰，不是藏起来**。
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final dim = onPressed == null;
    return CupertinoButton(
      key: ValueKey(keyName),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: dim
                ? AppColors.separator(context)
                : AppColors.blue.withValues(alpha: 0.45),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: dim ? AppColors.tertiaryLabel(context) : AppColors.blue,
          ),
        ),
      ),
    );
  }
}
