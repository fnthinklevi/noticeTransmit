import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:get_it/get_it.dart';
import '../l10n/app_localizations.dart';
import '../models/email_channel.dart';
import '../services/active_channels.dart';
import '../services/channel_health_store.dart';
import '../services/email_service.dart';
import '../theme/app_colors.dart';
import '../widgets/card_action_sheet.dart';
import '../widgets/ios_dialog_actions.dart';
import '../widgets/app_text_selection_menu.dart';

/// 邮件通道的必填项清单（T03）。
///
/// 为什么单列成函数：这条规则原先埋在弹窗的闭包里，测不到 ⇒ 只能靠人记住
/// "新增一个字段要同时加校验"。键的顺序 = 表单从上到下的顺序 = 提示里点名的顺序。
///
/// ⚠ 邮件表单还没有描述符（那是要接描述符的活儿），所以这份清单是页面本地的
/// 单一来源：新增字段时改这里 + 给 `labelOf` 加一个同名分支，
/// `email_required_field_test` 会钉住"每个必填键都得有标签"（漏了就把裸键名甩给用户）。
const List<String> kEmailRequiredKeys = <String>[
  'name',
  'host',
  'port',
  'username',
  'password',
  'from',
  'to',
];

/// 编辑场景下授权码的"已生效值"：**留空 = 沿用旧值**（表单从不回显明文）。
/// 单列成函数是为了让这条规则能被直测 —— 页面只负责把输入文本与旧值传进来。
String effectiveEmailPassword({
  required String typed,
  String? existingPassword,
}) => typed.trim().isNotEmpty ? typed : (existingPassword ?? '');

/// [effective] = 各键的**已生效值**（授权码需先经 [effectiveEmailPassword]）。
/// 返回缺失/非法的键；`port` 必须是正整数，其余非空即可。
List<String> missingEmailRequiredFields(Map<String, String> effective) {
  return <String>[
    for (final key in kEmailRequiredKeys)
      if (key == 'port'
          ? (int.tryParse((effective[key] ?? '').trim()) ?? 0) <= 0
          : (effective[key] ?? '').trim().isEmpty)
        key,
  ];
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
  int? _testingIndex;
  bool _editorTesting = false;

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
                for (int i = 0; i < _channels.length; i++) _buildChannelTile(i),
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

  Widget _buildChannelTile(int index) {
    final l10n = AppLocalizations.of(context);
    final channel = _channels[index];
    final isTesting = _testingIndex == index;

    return Column(
      children: [
        // 左右滑动切换通道启停（与点击开关等效）
        Slidable(
          key: ValueKey('email-channel-${channel.id}'),
          startActionPane: _toggleActionPane(l10n, channel.enabled, index),
          endActionPane: _toggleActionPane(l10n, channel.enabled, index),
          child: ListTile(
            leading: Icon(
              channel.enabled ? Icons.email : Icons.email_outlined,
              color: channel.enabled
                  ? AppColors.blue
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
              onChanged: (v) => _toggleChannel(index, v),
            ),
            onTap: () => _editChannel(index),
            // T05：列表卡是只读的（改配置要点进表单），所以长按菜单里的三个动作
            // 在这一页**都是真动作** —— 复制尤其省掉重填 7 个必填项。
            onLongPress: () => _showChannelActions(index),
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
                onTap: () => _editChannel(index),
              ),
              const SizedBox(width: 8),
              _actionChip(
                label: isTesting ? l10n.testing : l10n.test,
                icon: Icons.send_outlined,
                color: AppColors.green,
                onTap: isTesting ? null : () => _testChannel(index),
              ),
              const SizedBox(width: 8),
              _actionChip(
                label: l10n.delete,
                icon: Icons.delete_outline,
                color: AppColors.red,
                onTap: () => _deleteChannel(index),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: AppColors.separator(context)),
      ],
    );
  }

  /// 左右滑出的启停动作面板（开启/停用，松手后自动收起）
  ActionPane _toggleActionPane(AppLocalizations l10n, bool enabled, int index) {
    return ActionPane(
      motion: const BehindMotion(),
      extentRatio: 0.22,
      children: [
        SlidableAction(
          onPressed: (_) => _toggleChannel(index, !enabled),
          backgroundColor: enabled ? AppColors.orange : AppColors.green,
          foregroundColor: Colors.white,
          icon: enabled ? Icons.toggle_off : Icons.toggle_on,
          label: enabled ? l10n.turnOff : l10n.turnOn,
        ),
      ],
    );
  }

  /// 切换通道启停（点击开关与左右滑动共用），即时落库并同步原生
  void _toggleChannel(int index, bool v) {
    setState(() {
      _channels[index] = _channels[index].copyWith(enabled: v);
    });
    _save();
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
  void _editChannel(int index) =>
      _showEditor(existing: _channels[index], index: index);

  /// T05 长按菜单（共用组件见 [CardActionSheet]）。
  ///
  /// 动作顺序按"最常用的排前面"：修改 → 复制 → 删除（删除永远在末位且转红）。
  Future<void> _showChannelActions(int index) async {
    final l10n = AppLocalizations.of(context);
    final channel = _channels[index];
    await CardActionSheet.show(
      context,
      title: channel.name.isEmpty ? null : channel.name,
      actions: [
        CardAction(
          icon: Icons.settings_outlined,
          label: l10n.edit,
          onTap: () => _editChannel(index),
        ),
        CardAction(
          icon: Icons.copy,
          label: l10n.duplicate,
          onTap: () => _duplicateChannel(index),
        ),
        CardAction(
          icon: Icons.delete_outline,
          label: l10n.delete,
          danger: true,
          onTap: () => _deleteChannel(index),
        ),
      ],
    );
  }

  /// 复制出一条同配置通道。**id 必须换**：健康记录（`channel_health_email:<id>`）
  /// 与送达归属都按 id 走，两条同 id 会互相顶掉徽标、送达状态也会写错条目。
  void _duplicateChannel(int index) {
    final l10n = AppLocalizations.of(context);
    final src = _channels[index];
    setState(() {
      _channels.insert(
        index + 1,
        src.copyWith(
          id: 'email_${DateTime.now().millisecondsSinceEpoch}',
          name: l10n.copyOfName(src.name),
        ),
      );
    });
    _save();
  }

  Future<void> _deleteChannel(int index) async {
    final l10n = AppLocalizations.of(context);
    final channel = _channels[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg(ctx),
        title: Text(
          l10n.delete,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryLabel(ctx),
          ),
        ),
        content: Text(
          l10n.deleteEmailChannelConfirm(channel.name),
          style: TextStyle(color: AppColors.primaryLabel(ctx)),
        ),
        actions: IosDialogActions.confirm(
          ctx,
          cancelText: l10n.cancel,
          confirmText: l10n.delete,
          onConfirm: () => Navigator.pop(ctx, true),
          destructive: true,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
    if (confirmed != true || !mounted) return;
    // 先取 id 再移除：删除最后一条时 _channels[index] 已越界，
    // 旧实现访问 _channels[index].id 抛 RangeError 导致 _save() 永不执行，
    // 表现为「删除按钮无效、重进页面通道复活」
    final id = channel.id;
    setState(() {
      _channels.removeAt(index);
    });
    // 健康缓存一起删：留着它，日后 id 复用（例如从旧备份恢复）时徽标会复活成
    // 上一条通道的状态。
    await _health.remove('email', id);
    _save();
  }

  Future<void> _saveAndTest({required EmailChannel channel}) async {
    final l10n = AppLocalizations.of(context);
    await _save();
    // 自动测试（列表更新由编辑页保存按钮的 setState 完成，此处不再重复
    // add/replace，修复新通道被添加两次的问题）
    final watch = Stopwatch()..start();
    final result = await _emailService.testEmail(channel);
    final success = result?['success'] == true;
    final message = result?['message']?.toString() ?? '未知结果';
    await _emailService.saveTestResult(
      channel.id,
      success,
      latencyMs: watch.elapsedMilliseconds,
    );
    if (mounted) {
      // 徽标从健康单点读，这里只负责触发重建
      setState(() {});
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              success ? l10n.testPassedSaved : l10n.verifyFailed(message),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
    }
  }

  Future<void> _doEditorTest(EmailChannel channel) async {
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
    setState(() => _editorTesting = false);
    final message = result?['message']?.toString() ?? '未知结果';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
  }

  Future<void> _testChannel(int index) async {
    setState(() => _testingIndex = index);
    // 先取引用再 await：中途用户删掉一行时，按下标再取一次会取到别的通道
    final channel = _channels[index];
    final watch = Stopwatch()..start();
    final result = await _emailService.testEmail(channel);
    if (!mounted) return;
    final success = result?['success'] == true;
    final message = result?['message']?.toString() ?? '未知结果';
    // 「仅测试」也必须落健康单点：否则测出失败的通道在首页永远是 unknown，
    // 配置异常冒不上去（T04 的"异常要冒到首页"就是靠这一条链路）。
    await _emailService.saveTestResult(
      channel.id,
      success,
      latencyMs: watch.elapsedMilliseconds,
    );
    if (!mounted) return;
    setState(() => _testingIndex = null);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
  }

  void _showEditor({EmailChannel? existing, int? index}) {
    final l10n = AppLocalizations.of(context);
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final hostCtrl = TextEditingController(text: existing?.smtpHost ?? '');
    final portCtrl = TextEditingController(
      text: existing?.smtpPort.toString() ?? '465',
    );
    final usernameCtrl = TextEditingController(text: existing?.username ?? '');
    final passwordCtrl = TextEditingController(text: existing?.password ?? '');
    final fromCtrl = TextEditingController(text: existing?.fromEmail ?? '');
    final toCtrl = TextEditingController(text: existing?.toEmail ?? '');
    final subjectCtrl = TextEditingController(
      text: existing?.subjectTemplate ?? '',
    );
    final bodyCtrl = TextEditingController(text: existing?.bodyTemplate ?? '');
    var useSSL = existing?.useSSL ?? true;
    // P5：必填项校验状态（key → 错误提示），点击「测试并保存」时刷新
    var invalidFields = <String, String>{};

    // SMTP 通道关键信息必填：名称/服务器/端口/账号/授权码/发件人/收件人。
    // 授权码允许留空沿用已有通道的旧值（编辑场景不回显明文）⇒ 传"已生效值"进判定，
    // 规则本体在 `missingEmailRequiredFields`（可测）。
    Map<String, String> effectiveValues() => <String, String>{
      'name': nameCtrl.text,
      'host': hostCtrl.text,
      'port': portCtrl.text,
      'username': usernameCtrl.text,
      'password': effectiveEmailPassword(
        typed: passwordCtrl.text,
        existingPassword: existing?.password,
      ),
      'from': fromCtrl.text,
      'to': toCtrl.text,
    };

    Map<String, String> collectInvalid() {
      return <String, String>{
        for (final key in missingEmailRequiredFields(effectiveValues()))
          key: l10n.fieldRequired,
      };
    }

    // T03：标红之外，提示里还要**点名缺了哪几项**。"请填写所有必填项"等于让用户自己
    // 在 7 个输入框里找漏了哪个；这张表单没有描述符（T08 才接），所以键→标签的
    // 对照表就住在本页，与 collectInvalid 的键集合一一对应（漏一个会露出裸键名）。
    String labelOf(String key) => switch (key) {
      'name' => l10n.channelName,
      'host' => l10n.smtpHost,
      'port' => l10n.smtpPort,
      'username' => l10n.smtpAccount,
      'password' => l10n.smtpPassword,
      'from' => l10n.fromEmail,
      'to' => l10n.toEmail,
      _ => key,
    };

    Navigator.push(
      context,
      MaterialPageRoute(
        // StatefulBuilder 包裹整个页面：AppBar 的「测试并保存」也能
        // 触发 setModalState 更新必填项标红状态（P5）
        builder: (_) => StatefulBuilder(
          builder: (ctx, setModalState) => Scaffold(
            appBar: AppBar(
              title: Text(
                existing != null ? l10n.editEmailChannel : l10n.addEmailChannel,
              ),
              actions: [
                if (existing != null)
                  _editorTesting
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
                              setState(() => _editorTesting = true);
                              final testChannel = EmailChannel(
                                id: existing.id,
                                name: nameCtrl.text.trim(),
                                smtpHost: hostCtrl.text.trim(),
                                smtpPort:
                                    int.tryParse(portCtrl.text.trim()) ?? 465,
                                username: usernameCtrl.text.trim(),
                                password: passwordCtrl.text.trim().isNotEmpty
                                    ? passwordCtrl.text.trim()
                                    : existing.password,
                                fromEmail: fromCtrl.text.trim(),
                                toEmail: toCtrl.text.trim(),
                                useSSL: useSSL,
                                subjectTemplate: subjectCtrl.text.trim().isEmpty
                                    ? null
                                    : subjectCtrl.text.trim(),
                                bodyTemplate: bodyCtrl.text.trim().isEmpty
                                    ? null
                                    : bodyCtrl.text.trim(),
                              );
                              _doEditorTest(testChannel);
                            },
                          ),
                        ),
                TextButton(
                  onPressed: () {
                    // P5：必填校验，未填输入框标红且不执行保存
                    final invalid = collectInvalid();
                    setModalState(() => invalidFields = invalid);
                    if (invalid.isNotEmpty) {
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(
                            content: Text(
                              l10n.fillRequiredFieldsNamed(
                                invalid.keys.map(labelOf).join('、'),
                              ),
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      return;
                    }
                    // P7：保留通道既有启停状态（旧实现未传 enabled，
                    // 每次保存都会把已关闭的通道重置为默认开启）
                    final channel = EmailChannel(
                      id:
                          existing?.id ??
                          DateTime.now().millisecondsSinceEpoch.toString(),
                      enabled: existing?.enabled ?? true,
                      name: nameCtrl.text.trim(),
                      smtpHost: hostCtrl.text.trim(),
                      smtpPort: int.tryParse(portCtrl.text.trim()) ?? 465,
                      username: usernameCtrl.text.trim(),
                      password: passwordCtrl.text.trim().isNotEmpty
                          ? passwordCtrl.text.trim()
                          : existing?.password,
                      fromEmail: fromCtrl.text.trim(),
                      toEmail: toCtrl.text.trim(),
                      useSSL: useSSL,
                      subjectTemplate: subjectCtrl.text.trim().isEmpty
                          ? null
                          : subjectCtrl.text.trim(),
                      bodyTemplate: bodyCtrl.text.trim().isEmpty
                          ? null
                          : bodyCtrl.text.trim(),
                    );
                    setState(() {
                      if (index != null) {
                        _channels[index] = channel;
                      } else {
                        _channels.add(channel);
                      }
                    });
                    _saveAndTest(channel: channel);
                    Navigator.pop(context);
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
                    nameCtrl,
                    l10n.channelName,
                    hint: l10n.channelNameHint,
                    errorText: invalidFields['name'],
                  ),
                  const SizedBox(height: 12),
                  _field(
                    hostCtrl,
                    l10n.smtpHost,
                    hint: 'smtp.qq.com',
                    keyboardType: TextInputType.url,
                    errorText: invalidFields['host'],
                  ),
                  const SizedBox(height: 12),
                  _field(
                    portCtrl,
                    l10n.smtpPort,
                    hint: l10n.emailHintPort,
                    keyboardType: TextInputType.number,
                    errorText: invalidFields['port'],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: AppColors.cardBg(context),
                    ),
                    child: Row(
                      children: [
                        Text(
                          l10n.useSSL,
                          style: TextStyle(
                            fontSize: 16,
                            color: AppColors.primaryLabel(context),
                          ),
                        ),
                        const Spacer(),
                        CupertinoSwitch(
                          value: useSSL,
                          onChanged: (v) => setModalState(() => useSSL = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _field(
                    usernameCtrl,
                    l10n.smtpAccount,
                    hint: 'your@email.com',
                    keyboardType: TextInputType.emailAddress,
                    errorText: invalidFields['username'],
                  ),
                  const SizedBox(height: 12),
                  _field(
                    passwordCtrl,
                    l10n.smtpPassword,
                    hint: l10n.emailHintPassword,
                    obscure: true,
                    errorText: invalidFields['password'],
                  ),
                  const SizedBox(height: 12),
                  _field(
                    fromCtrl,
                    l10n.fromEmail,
                    hint: 'your@email.com',
                    keyboardType: TextInputType.emailAddress,
                    errorText: invalidFields['from'],
                  ),
                  const SizedBox(height: 12),
                  _field(
                    toCtrl,
                    l10n.toEmail,
                    hint: l10n.emailHintRecipients,
                    keyboardType: TextInputType.emailAddress,
                    errorText: invalidFields['to'],
                  ),
                  const SizedBox(height: 12),
                  _field(
                    subjectCtrl,
                    l10n.subjectTemplate,
                    hint: l10n.emailHintSubjectDefault,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _presetChip(
                          l10n.presetDefault,
                          '🔔 %appName% — %title%',
                          subjectCtrl,
                        ),
                        _presetChip(
                          l10n.presetSimple,
                          '%appName% — %title%',
                          subjectCtrl,
                        ),
                        _presetChip(
                          l10n.presetDetailed,
                          '%appName% — %title%\n内容：%content%',
                          subjectCtrl,
                        ),
                        _presetChip(
                          l10n.presetTime,
                          '%time% %appName% — %title%',
                          subjectCtrl,
                        ),
                        _presetChip(
                          l10n.presetCode,
                          '[%appName%] 验证码通知 — %title%',
                          subjectCtrl,
                        ),
                        _presetChip(
                          l10n.presetDevice,
                          '[%deviceName%] %appName% — %title%',
                          subjectCtrl,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Text(
                      l10n.availableVars,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.tertiaryLabel(context),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l10n.bodyTemplate,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.primaryLabel(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    contextMenuBuilder: AppTextSelectionMenu.editableText,
                    controller: bodyCtrl,
                    maxLines: 8,
                    decoration: InputDecoration(
                      hintText: l10n.emailHintBodyDefault,
                      filled: true,
                      fillColor: AppColors.cardBg(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _presetChip(l10n.presetDefault, '', bodyCtrl),
                        _presetChip(
                          l10n.presetStandard,
                          '应用：%appName%\n标题：%title%\n内容：%content%\n时间：%time%\n设备：%deviceName%',
                          bodyCtrl,
                        ),
                        _presetChip(
                          l10n.presetComplete,
                          '应用：%appName%\n标题：%title%\n内容：%content%\n副标题：%subText%\n包名：%packageName%\n时间：%time%\n设备：%deviceName%',
                          bodyCtrl,
                        ),
                        _presetChip(
                          l10n.presetCode,
                          '验证码：%content%\n来源：%appName%(%packageName%)\n时间：%time%',
                          bodyCtrl,
                        ),
                        _presetChip(
                          l10n.presetMinimal,
                          '%appName%：%title%\n%content%',
                          bodyCtrl,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    String? hint,
    TextInputType? keyboardType,
    bool obscure = false,
    String? errorText,
  }) {
    return TextField(
      contextMenuBuilder: AppTextSelectionMenu.editableText,
      controller: ctrl,
      obscureText: obscure,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: errorText,
        // P6：显式填充 cardBg（浅色纯白/深色 #1C1C1E）。全局主题的
        // inputBg 浅色下与页面底色完全相同，导致输入框与页面融为一体
        filled: true,
        fillColor: AppColors.cardBg(context),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _presetChip(
    String label,
    String template,
    TextEditingController ctrl,
  ) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: () => ctrl.text = template,
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Future<void> _save() async {
    await _emailService.saveChannels(_channels);
  }
}
