import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:get_it/get_it.dart';
import '../l10n/app_localizations.dart';
import '../models/email_channel.dart';
import '../services/active_channels.dart';
import '../services/channel_descriptor_service.dart';
import '../services/channel_health_store.dart';
import '../services/email_service.dart';
import '../services/template_variables.dart';
import '../theme/app_colors.dart';
import '../widgets/card_action_sheet.dart';
import '../widgets/channel_form_renderer.dart';
import '../widgets/channel_visuals.dart';
import '../widgets/ios_dialog_actions.dart';
import '../widgets/app_text_selection_menu.dart';

/// 邮件通道的必填项清单（T03）。
///
/// 表单的**已生效值**（key = 描述符的存储键名）。
///
/// 为什么单列成函数：这三条规则原先埋在弹窗闭包里，测不到 ⇒ 只能靠人记住
/// "新增一个字段要同时加校验"。规则本体现在跟着描述符走：
/// - `kind == 'switch'` → 开/关由开关状态决定，落库是 `'true'/'false'`
/// - `kind == 'secret'` 且该族有 `secretKeepsPrevious` 能力位 → **留空 = 沿用旧值**
///   （邮件授权码不回显明文；这条与 webhook 的"清空白就是清空白"相反，
///   差异只在原生表里可见，页面不按族分支）
/// - 其余留空 → 落 `defaultValue`（端口 465 只在那里定义一次）
Map<String, String> emailEffectiveValues({
  required ChannelDescriptor descriptor,
  required Map<String, String> typed,
  required Map<String, bool> switches,
  String? existingPassword,
}) {
  return <String, String>{
    for (final f in descriptor.fields)
      f.key: switch (f.kind) {
        'switch' => '${switches[f.key] ?? f.defaultValue == 'true'}',
        'secret' =>
          (typed[f.key]?.trim().isNotEmpty ?? false)
              ? typed[f.key]!.trim()
              : (descriptor.secretKeepsPrevious
                    ? (existingPassword ?? '')
                    : ''),
        _ =>
          (typed[f.key]?.trim().isNotEmpty ?? false)
              ? typed[f.key]!.trim()
              : (f.defaultValue ?? ''),
      },
  };
}

/// [effective] = 各键的**已生效值**。返回缺失/非法的键，顺序 = 描述符里的字段顺序
/// = 界面上点名的顺序（页面不再自己排一遍，否则两处顺序会分叉）。
///
/// `kind == 'number'` 额外要求**正整数**：端口填成 0/负数/非数字时原生连不上，
/// 但表现是"保存成功却收不到邮件"，所以必须在保存前点名（SMTP 端口没有 0）。
List<String> missingEmailRequiredFields({
  required ChannelDescriptor descriptor,
  required Map<String, String> effective,
  bool nameMissing = false,
}) {
  final missing = <String>[if (nameMissing) 'name'];
  for (final f in descriptor.fields) {
    if (!f.required) continue;
    final value = (effective[f.key] ?? '').trim();
    if (value.isEmpty || (f.isNumber && (int.tryParse(value) ?? 0) <= 0)) {
      missing.add(f.key);
    }
  }
  return missing;
}

/// 邮件通道设置页
///
/// 管理 SMTP 邮件转发配置：新增 / 编辑 / 删除 / 启停 / 测试邮件通道。
class EmailSettingsPage extends StatefulWidget {
  final List<Map<String, dynamic>> emailChannels;

  const EmailSettingsPage({super.key, required this.emailChannels});

  @override
  State<EmailSettingsPage> createState() => _EmailSettingsPageState();
}

class _EmailSettingsPageState extends State<EmailSettingsPage> {
  late List<EmailChannel> _channels;
  final _emailService = GetIt.instance<EmailService>();

  /// 上次测试的结果**只从健康单点读**（T04）。这里此前另有一份内存 Map ⇒
  /// 重启后列表全变空白，而首页因为单点里有记录仍显示异常，两页互相打脸。
  final ChannelHealthStore _health = GetIt.instance<ChannelHealthStore>();

  /// 测试进行中的通道 id（不是下标）：写操作现在都经过 await，
  /// 下标在等待期间会因为增删而错位。
  String? _testingId;

  /// 列表里的"上次测试"标注：只在**确有结论**时显示（成功但已过期算 unknown ⇒
  /// 不显示，比拿很久以前的一次成功糊弄用户诚实）。
  String? _lastTestLabel(AppLocalizations l10n, String id) {
    final state = channelHealthState(_health.of('email', id));
    return switch (state) {
      ChannelHealthState.ok => l10n.testPassed,
      ChannelHealthState.error => l10n.testFailed,
      ChannelHealthState.unknown => null,
    };
  }

  bool _lastTestOk(String id) =>
      channelHealthState(_health.of('email', id)) == ChannelHealthState.ok;

  @override
  void initState() {
    super.initState();
    _channels = widget.emailChannels
        .map((m) => EmailChannel.fromMap(m))
        .toList();
    // 徽标的数据在 prefs 里：没 load 过就读不到（幂等，splash 已 load 时是空操作）
    _health.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.emailSettingsTitle)),
      body: _channels.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.email_outlined,
                    size: 48,
                    color: AppColors.secondaryLabel(context),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.noEmailChannels,
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.secondaryLabel(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.clickToAdd,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.tertiaryLabel(context),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildAddButton(),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                for (final channel in _channels) _buildChannelTile(channel),
              ],
            ),
      floatingActionButton: _channels.isNotEmpty
          ? FloatingActionButton(
              onPressed: _addChannel,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildAddButton() {
    final l10n = AppLocalizations.of(context);
    return ElevatedButton.icon(
      onPressed: _addChannel,
      icon: const Icon(Icons.add),
      label: Text(l10n.addEmailChannel),
    );
  }

  /// 描述符没到手时的统一出口：**说清楚为什么不能编辑，并且不写任何数据**。
  ///
  /// 这一页的字段清单、必填、默认值、控件形态与预置档位全在描述符里（T08-C2），
  /// 所以"拉不到元数据"不能退化成一张空表单 —— 空表单点保存就是把用户已存的 SMTP
  /// 配置写空（违反"不静默丢失"）。宁可让他重试一次。
  bool _requireDescriptor(AppLocalizations l10n) {
    if (_emailDescriptor != null) return true;
    _toast(l10n.emailMetaUnavailable);
    return false;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
  }

  /// 列表与数据库对齐的**唯一**路径：所有写操作都走服务层单条咽喉，然后重读。
  /// 页面不再按下标改本地副本（旧写法：`_channels[index] = channel` / `removeAt(index)` /
  /// `insert(index + 1, ...)`），所以"测试进行中用户删了一行"这类错位无从发生。
  Future<void> _refresh() async {
    final channels = await _emailService.loadChannels();
    if (!mounted) return;
    setState(() => _channels = channels);
  }

  Widget _buildChannelTile(EmailChannel channel) {
    final l10n = AppLocalizations.of(context);
    final isTesting = _testingId == channel.id;
    // 图标与品牌色取自描述符的 iconKey（`email`）—— 与其余两族同一张判决表
    final visual = channelVisual(_emailDescriptor?.iconKey ?? 'email');

    return Column(
      children: [
        // 左右滑动切换通道启停（与点击开关等效）
        Slidable(
          key: ValueKey('email-channel-${channel.id}'),
          startActionPane: _toggleActionPane(l10n, channel),
          endActionPane: _toggleActionPane(l10n, channel),
          child: ListTile(
            leading: Icon(
              visual.icon,
              color: channel.enabled
                  ? visual.color
                  : AppColors.secondaryLabel(context),
            ),
            title: Text(
              channel.name,
              style: TextStyle(
                color: channel.enabled
                    ? AppColors.primaryLabel(context)
                    : AppColors.secondaryLabel(context),
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${channel.fromEmail} → ${channel.toEmail}',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
                if (_lastTestLabel(l10n, channel.id) != null)
                  Text(
                    _lastTestLabel(l10n, channel.id)!,
                    style: TextStyle(
                      fontSize: 11,
                      color: _lastTestOk(channel.id)
                          ? AppColors.green
                          : AppColors.red,
                    ),
                  ),
              ],
            ),
            trailing: CupertinoSwitch(
              value: channel.enabled,
              onChanged: (v) => _toggleChannel(channel.id, v),
            ),
            onTap: () => _editChannel(channel),
            // T05：列表卡是只读的（改配置要点进表单），所以长按菜单里的三个动作
            // 在这一页**都是真动作** —— 复制尤其省掉重填 7 个必填项。
            onLongPress: () => _showChannelActions(channel),
          ),
        ),
        if (isTesting)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 72, vertical: 4),
            child: LinearProgressIndicator(),
          ),
        Padding(
          padding: const EdgeInsets.only(left: 72, right: 12, bottom: 6),
          child: Row(
            children: [
              _actionChip(
                label: l10n.edit,
                icon: Icons.settings_outlined,
                color: AppColors.blue,
                onTap: () => _editChannel(channel),
              ),
              const SizedBox(width: 8),
              _actionChip(
                label: isTesting ? l10n.testing : l10n.test,
                icon: Icons.send_outlined,
                color: AppColors.green,
                onTap: isTesting ? null : () => _testChannel(channel),
              ),
              const SizedBox(width: 8),
              _actionChip(
                label: l10n.delete,
                icon: Icons.delete_outline,
                color: AppColors.red,
                onTap: () => _deleteChannel(channel),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: AppColors.separator(context)),
      ],
    );
  }

  /// 左右滑出的启停动作面板（开启/停用，松手后自动收起）
  ActionPane _toggleActionPane(AppLocalizations l10n, EmailChannel channel) {
    final enabled = channel.enabled;
    return ActionPane(
      motion: const BehindMotion(),
      extentRatio: 0.22,
      children: [
        SlidableAction(
          onPressed: (_) => _toggleChannel(channel.id, !enabled),
          backgroundColor: enabled ? AppColors.orange : AppColors.green,
          foregroundColor: Colors.white,
          icon: enabled ? Icons.toggle_off : Icons.toggle_on,
          label: enabled ? l10n.turnOff : l10n.turnOn,
        ),
      ],
    );
  }

  /// 切换启停：走服务层 `setEnabled`（只翻这一条），成功后重读列表。
  /// 返回 false = 库里已经没有这条（别处删掉了），此时**不假装成功**。
  Future<void> _toggleChannel(String id, bool v) async {
    if (!await _emailService.setEnabled(id, v)) return;
    await _refresh();
  }

  Widget _actionChip({
    required String label,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addChannel() => _showEditor();
  void _editChannel(EmailChannel channel) => _showEditor(existing: channel);

  /// T05 长按菜单（共用组件见 [CardActionSheet]）。
  ///
  /// 动作顺序按"最常用的排前面"：修改 → 复制 → 删除（删除永远在末位且转红）。
  Future<void> _showChannelActions(EmailChannel channel) async {
    final l10n = AppLocalizations.of(context);
    await CardActionSheet.show(
      context,
      title: channel.name.isEmpty ? null : channel.name,
      actions: [
        CardAction(
          icon: Icons.settings_outlined,
          label: l10n.edit,
          onTap: () => _editChannel(channel),
        ),
        CardAction(
          icon: Icons.copy,
          label: l10n.duplicate,
          onTap: () => _duplicateChannel(channel),
        ),
        CardAction(
          icon: Icons.delete_outline,
          label: l10n.delete,
          danger: true,
          onTap: () => _deleteChannel(channel),
        ),
      ],
    );
  }

  /// 复制出一条同配置通道。**id 必须换**：健康记录（`channel_health_email:<id>`）
  /// 与送达归属都按 id 走，两条同 id 会互相顶掉徽标、送达状态也会写错条目。
  Future<void> _duplicateChannel(EmailChannel src) async {
    final l10n = AppLocalizations.of(context);
    if (!_requireDescriptor(l10n)) return;
    await _emailService.saveChannel(
      src.copyWith(
        id: 'email_${DateTime.now().millisecondsSinceEpoch}',
        name: l10n.copyOfName(src.name),
      ),
    );
    await _refresh();
  }

  /// 删除的**单一咽喉**：卡片按钮与长按菜单都走这里，确认写在真正删数据的地方（T06）。
  Future<void> _deleteChannel(EmailChannel channel) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await IosDialogActions.askConfirm(
      context,
      title: l10n.confirmDelete,
      message: l10n.deleteChannelConfirm(channel.name),
      confirmText: l10n.delete,
    );
    if (!confirmed || !mounted) return;
    if (!await _emailService.deleteChannel(channel.id)) return;
    // 健康缓存一起删：留着它，日后 id 复用（例如从旧备份恢复）时徽标会复活成
    // 上一条通道的状态。
    await _health.remove('email', channel.id);
    await _refresh();
  }

  Future<void> _saveAndTest({required EmailChannel channel}) async {
    final l10n = AppLocalizations.of(context);
    final watch = Stopwatch()..start();
    final result = await _emailService.testEmail(channel);
    final success = result?['success'] == true;
    final message = result?['message']?.toString() ?? l10n.testUnknownResult;
    await _emailService.saveTestResult(
      channel.id,
      success,
      latencyMs: watch.elapsedMilliseconds,
    );
    if (!mounted) return;
    // 徽标从健康单点读，这里只负责触发重建
    setState(() {});
    _toast(success ? l10n.testPassedSaved : l10n.verifyFailed(message));
  }

  Future<void> _doEditorTest(EmailChannel channel) async {
    final l10n = AppLocalizations.of(context);
    final watch = Stopwatch()..start();
    final result = await _emailService.testEmail(channel);
    if (!mounted) return;
    final success = result?['success'] == true;
    // 弹窗里点「测试」测的是**未保存**的表单值，但结论照样要落单点：用户要的就是
    // "这组凭据到底能不能用"，测完退出弹窗也不该让首页退回 unknown。
    await _emailService.saveTestResult(
      channel.id,
      success,
      latencyMs: watch.elapsedMilliseconds,
    );
    if (!mounted) return;
    _toast(result?['message']?.toString() ?? l10n.testUnknownResult);
  }

  Future<void> _testChannel(EmailChannel channel) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _testingId = channel.id);
    final watch = Stopwatch()..start();
    final result = await _emailService.testEmail(channel);
    if (!mounted) return;
    final success = result?['success'] == true;
    // 「仅测试」也必须落健康单点：否则测出失败的通道在首页永远是 unknown，
    // 配置异常冒不上去（T04 的"异常要冒到首页"就是靠这一条链路）。
    await _emailService.saveTestResult(
      channel.id,
      success,
      latencyMs: watch.elapsedMilliseconds,
    );
    if (!mounted) return;
    setState(() => _testingId = null);
    _toast(result?['message']?.toString() ?? l10n.testUnknownResult);
  }

  /// 邮件族的描述符（T08-C2 起：这一页表单事实的唯一来源）。
  ChannelDescriptor? get _emailDescriptor =>
      GetIt.instance<ChannelDescriptorService>().email;

  /// 打开单条编辑器。
  ///
  /// ⚠ 编辑器是一个 **StatefulWidget 路由**，不是 `StatefulBuilder` + 方法内局部
  /// controller。原因是实测到的一个真缺陷：`await Navigator.push(...)` 在路由
  /// **开始**弹出时就完成，而离场动画期间子树还会重建 —— 在 push 之后统一
  /// `dispose()` 会撞上 "A TextEditingController was used after being disposed"。
  /// 生命周期交给路由自己（`State.dispose` 才是"这个页面真的没了"的时刻）。
  Future<void> _showEditor({EmailChannel? existing}) async {
    final l10n = AppLocalizations.of(context);
    final descriptor = _emailDescriptor;
    if (descriptor == null) {
      // 元数据没到手就**不开一张空表单**：填不了任何东西，保存还会把已存配置写空。
      _toast(l10n.emailMetaUnavailable);
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _EmailEditorPage(
          descriptor: descriptor,
          existing: existing,
          onSave: (channel) async {
            await _emailService.saveChannel(channel);
            if (!mounted) return;
            await _refresh();
            if (!mounted) return;
            _saveAndTest(channel: channel);
          },
          onTest: (channel) => _doEditorTest(channel),
        ),
      ),
    );
  }
}

/// 单条编辑器（全屏路由）。字段清单、顺序、标签、提示、控件形态、必填、默认值、
/// 预置档位**全部来自描述符**（T08-C2）。
///
/// 旧版这里是 12 个手写控件 + `kEmailRequiredKeys` + `labelOf` 三份手工同步的事实，
/// 外加 `'smtp.qq.com'` / `'your@email.com'` 两颗硬编码提示、`465` 的两处兜底，
/// 以及「仅测试」与「测试并保存」**各自展开一遍**的 12 字段构造。
class _EmailEditorPage extends StatefulWidget {
  const _EmailEditorPage({
    required this.descriptor,
    required this.onSave,
    required this.onTest,
    this.existing,
  });

  final ChannelDescriptor descriptor;
  final EmailChannel? existing;
  final Future<void> Function(EmailChannel) onSave;
  final Future<void> Function(EmailChannel) onTest;

  @override
  State<_EmailEditorPage> createState() => _EmailEditorPageState();
}

class _EmailEditorPageState extends State<_EmailEditorPage> {
  late final Map<String, TextEditingController> _controllers;
  late final Map<String, bool> _switches;
  Set<String> _invalid = {};
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    // 初值按描述符的键名从"已存的那一条"取；取不到（新增）才落 defaultValue。
    final stored =
        widget.existing?.toMap(includePassword: true) ??
        const <String, dynamic>{};
    _switches = {};
    _controllers = <String, TextEditingController>{
      'name': TextEditingController(text: widget.existing?.name ?? ''),
    };
    for (final f in widget.descriptor.fields) {
      final raw = stored[f.key];
      if (f.isSwitch) {
        _switches[f.key] = raw is bool
            ? raw
            : (raw?.toString() ?? f.defaultValue ?? 'false') == 'true';
      } else {
        _controllers[f.key] = TextEditingController(
          text: raw?.toString() ?? f.defaultValue ?? '',
        );
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _text(String key) => (_controllers[key]?.text ?? '').trim();

  Map<String, String> _effective() => emailEffectiveValues(
    descriptor: widget.descriptor,
    typed: {for (final e in _controllers.entries) e.key: e.value.text},
    switches: _switches,
    existingPassword: widget.existing?.password,
  );

  /// **一条通道只有一个构造函数**。「仅测试」与「测试并保存」共用它，
  /// 否则会出现"测的是 A、存进库的是 B"。
  EmailChannel _compose() {
    final values = _effective();
    return EmailChannel.fromMap(<String, dynamic>{
      'id':
          widget.existing?.id ??
          'email_${DateTime.now().millisecondsSinceEpoch}',
      'name': _text('name'),
      // 启停与主备角色由列表页管，编辑一条不得顺手重置（P7 的教训）
      'enabled': widget.existing?.enabled ?? true,
      'role': widget.existing?.role ?? 'primary',
      for (final f in widget.descriptor.fields)
        f.key: f.isSwitch
            ? (_switches[f.key] ?? false)
            : ((values[f.key]?.isEmpty ?? true) ? null : values[f.key]),
    });
  }

  bool _validate() {
    final lost = missingEmailRequiredFields(
      descriptor: widget.descriptor,
      effective: _effective(),
      nameMissing: _text('name').isEmpty,
    );
    setState(() => _invalid = lost.toSet());
    if (lost.isNotEmpty) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              l10n.fillRequiredFieldsNamed(
                lost.map((k) => _label(l10n, k)).join('\u3001'),
              ),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
    }
    return lost.isEmpty;
  }

  /// 缺失项点名用的显示名：`name` 是本页自有字段，其余按描述符的 labelKey 取译文。
  String _label(AppLocalizations l10n, String key) {
    if (key == 'name') return l10n.channelName;
    final fields = widget.descriptor.fields;
    final f = fields.firstWhere(
      (x) => x.key == key,
      orElse: () => fields.first,
    );
    return channelFormText(l10n, f.labelKey);
  }

  /// kind → 键盘类型。映射只在这里做一次：服务层给的是中立名字，
  /// 这样描述符解析不依赖 flutter/services。
  TextInputType? _keyboardOf(ChannelFieldSpec f) => switch (f.keyboardHint) {
    'number' => TextInputType.number,
    'email' => TextInputType.emailAddress,
    'url' => TextInputType.url,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final descriptor = widget.descriptor;
    // 变量清单是模板类字段共用的说明：挂在第一个带预置档位的字段后面（今天即主题），
    // 不由页面按字段名硬编码"哪一段之后要显示它"。
    final varsAnchorKey = descriptor.fields
        .firstWhere(
          (f) => f.presets.isNotEmpty,
          orElse: () => descriptor.fields.first,
        )
        .key;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing != null
              ? l10n.editEmailChannel
              : l10n.addEmailChannel,
        ),
        actions: [
          if (widget.existing != null)
            _testing
                ? const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: TextButton.icon(
                      icon: const Icon(Icons.send_outlined, size: 16),
                      label: Text(l10n.testOnly),
                      onPressed: () {
                        if (!_validate()) return;
                        final channel = _compose();
                        setState(() => _testing = true);
                        widget.onTest(channel).whenComplete(() {
                          if (mounted) setState(() => _testing = false);
                        });
                      },
                    ),
                  ),
          TextButton(
            onPressed: () async {
              // P5：必填校验未过 ⇒ 标红 + 点名，不写库也不测
              if (!_validate()) return;
              final channel = _compose();
              Navigator.of(context).pop();
              await widget.onSave(channel);
            },
            child: Text(
              l10n.testAndSave,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _field(
              _controllers['name']!,
              l10n.channelName,
              hint: l10n.channelNameHint,
              invalid: _invalid.contains('name'),
            ),
            for (final f in descriptor.fields) ...[
              const SizedBox(height: 12),
              if (f.isSwitch)
                _switchRow(
                  channelFormText(l10n, f.labelKey),
                  _switches[f.key] ?? false,
                  (v) => setState(() => _switches[f.key] = v),
                )
              else
                _field(
                  _controllers[f.key]!,
                  channelFormText(l10n, f.labelKey),
                  hint: f.hintKey == null
                      ? null
                      : channelFormText(l10n, f.hintKey!),
                  keyboardType: _keyboardOf(f),
                  obscure: f.isSecret,
                  maxLines: f.isMultiline ? 8 : 1,
                  invalid: _invalid.contains(f.key),
                ),
              if (f.presets.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final preset in f.presets)
                        ActionChip(
                          label: Text(
                            channelFormText(l10n, preset.labelKey),
                            style: const TextStyle(fontSize: 12),
                          ),
                          // valueKey == null 的语义是「清空 = 交回运行时默认」
                          onPressed: () => _controllers[f.key]!.text =
                              preset.valueKey == null
                              ? ''
                              : channelFormText(l10n, preset.valueKey!),
                          padding: EdgeInsets.zero,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                    ],
                  ),
                ),
              if (f.key == varsAnchorKey)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text(
                    l10n.availableVars(templateVarTokens(emailTemplateVars)),
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.tertiaryLabel(context),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// 开关行（`kind == 'switch'`，今天就是 useSSL）
  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: AppColors.cardBg(context),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              color: AppColors.primaryLabel(context),
            ),
          ),
          const Spacer(),
          CupertinoSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    String? hint,
    TextInputType? keyboardType,
    bool obscure = false,
    int maxLines = 1,
    bool invalid = false,
  }) {
    return TextField(
      contextMenuBuilder: AppTextSelectionMenu.editableText,
      controller: ctrl,
      obscureText: obscure,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        // P5：必填未填时标红（点名在 snackbar 里，见 _validate()）
        errorText: invalid ? AppLocalizations.of(context).fieldRequired : null,
        // P6：显式填充 cardBg（浅色纯白/深色 #1C1C1E）。全局主题的 inputBg
        // 浅色下与页面底色完全相同，导致输入框与页面融为一体
        filled: true,
        fillColor: AppColors.cardBg(context),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
