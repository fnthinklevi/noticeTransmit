import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../models/email_channel.dart';
import '../services/email_service.dart';
import '../theme/app_colors.dart';

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
  int? _testingIndex;
  bool _editorTesting = false;
  final Map<String, bool> _emailTestResults = {};

  @override
  void initState() {
    super.initState();
    _channels = widget.emailChannels
        .map((m) => EmailChannel.fromMap(m))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('邮件转发通道')),
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
                    '暂无邮件通道',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.secondaryLabel(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '点击下方按钮添加',
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
    return ElevatedButton.icon(
      onPressed: _addChannel,
      icon: const Icon(Icons.add),
      label: const Text('添加邮件通道'),
    );
  }

  Widget _buildChannelTile(int index) {
    final channel = _channels[index];
    final isTesting = _testingIndex == index;

    return Column(
      children: [
        ListTile(
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
                style: TextStyle(fontSize: 13, color: AppColors.secondaryLabel(context)),
              ),
              if (_emailTestResults.containsKey(channel.id))
                Text(
                  _emailTestResults[channel.id] == true ? '✅ 验证通过' : '❌ 验证失败',
                  style: TextStyle(
                    fontSize: 11,
                    color: _emailTestResults[channel.id] == true
                        ? AppColors.green
                        : AppColors.red,
                  ),
                ),
            ],
          ),
          trailing: Switch(
            value: channel.enabled,
            onChanged: (v) {
              setState(() {
                _channels[index] = channel.copyWith(enabled: v);
              });
              _save();
            },
          ),
          onTap: () => _editChannel(index),
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
                label: '编辑',
                icon: Icons.settings_outlined,
                color: AppColors.blue,
                onTap: () => _editChannel(index),
              ),
              const SizedBox(width: 8),
              _actionChip(
                label: isTesting ? '测试中...' : '测试',
                icon: Icons.send_outlined,
                color: AppColors.green,
                onTap: isTesting ? null : () => _testChannel(index),
              ),
              const SizedBox(width: 8),
              _actionChip(
                label: '删除',
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

  void _deleteChannel(int index) {
    setState(() {
      _channels.removeAt(index);
      _emailTestResults.remove(_channels[index].id);
    });
    _save();
  }

  Future<void> _saveAndTest({
    required EmailChannel channel,
    required EmailChannel? existing,
    required int? index,
  }) async {
    setState(() {
      if (index != null) {
        _channels[index] = channel;
      } else {
        _channels.add(channel);
      }
    });
    await _save();
    // 自动测试
    final result = await _emailService.testEmail(channel);
    final success = result?['success'] == true;
    final message = result?['message']?.toString() ?? '未知结果';
    _emailTestResults[channel.id] = success;
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(success ? '测试通过，配置已保存' : '验证失败: $message'),
          duration: const Duration(seconds: 3),
        ));
    }
  }

  Future<void> _doEditorTest(EmailChannel channel) async {
    final result = await _emailService.testEmail(channel);
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
    final result = await _emailService.testEmail(_channels[index]);
    if (!mounted) return;
    final success = result?['success'] == true;
    final message = result?['message']?.toString() ?? '未知结果';
    _emailTestResults[_channels[index].id] = success;
    setState(() => _testingIndex = null);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
  }

  void _showEditor({EmailChannel? existing, int? index}) {
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

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(existing != null ? '编辑邮件通道' : '添加邮件通道'),
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
                          label: const Text('测试发送'),
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
                  final channel = EmailChannel(
                    id:
                        existing?.id ??
                        DateTime.now().millisecondsSinceEpoch.toString(),
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
                  _saveAndTest(channel: channel, existing: existing, index: index);
                  Navigator.pop(context);
                },
                child: const Text(
                  '测试并保存',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: StatefulBuilder(
              builder: (ctx, setModalState) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _field(nameCtrl, '通道名称', hint: '如：QQ邮箱'),
                  const SizedBox(height: 12),
                  _field(
                    hostCtrl,
                    'SMTP 服务器',
                    hint: 'smtp.qq.com',
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 12),
                  _field(
                    portCtrl,
                    '端口号',
                    hint: '465 (SSL) 或 587 (STARTTLS)',
                    keyboardType: TextInputType.number,
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
                          'SSL 加密',
                          style: TextStyle(
                            fontSize: 16,
                            color: AppColors.primaryLabel(context),
                          ),
                        ),
                        const Spacer(),
                        Switch(
                          value: useSSL,
                          onChanged: (v) => setModalState(() => useSSL = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _field(
                    usernameCtrl,
                    'SMTP 账号',
                    hint: 'your@email.com',
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  _field(
                    passwordCtrl,
                    '密码/授权码',
                    hint: 'SMTP 授权码（非邮箱密码）',
                    obscure: true,
                  ),
                  const SizedBox(height: 12),
                  _field(
                    fromCtrl,
                    '发件人',
                    hint: 'your@email.com',
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  _field(
                    toCtrl,
                    '收件人',
                    hint: '可多个，逗号分隔',
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  _field(
                    subjectCtrl,
                    '主题模板（可选）',
                    hint: '默认：🔔 %appName% — %title%',
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _presetChip(
                          '默认',
                          '🔔 %appName% — %title%',
                          subjectCtrl,
                        ),
                        _presetChip('简洁', '%appName% — %title%', subjectCtrl),
                        _presetChip(
                          '详细',
                          '%appName% — %title%\n内容：%content%',
                          subjectCtrl,
                        ),
                        _presetChip(
                          '时间',
                          '%time% %appName% — %title%',
                          subjectCtrl,
                        ),
                        _presetChip(
                          '验证码',
                          '[%appName%] 验证码通知 — %title%',
                          subjectCtrl,
                        ),
                        _presetChip(
                          '设备',
                          '[%deviceName%] %appName% — %title%',
                          subjectCtrl,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Text(
                      '可用变量：%appName% %title% %content% %subText% %packageName% %deviceName% %time% %type% %date% %datetime%',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.tertiaryLabel(context),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '正文模板（可选）',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.primaryLabel(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: bodyCtrl,
                    maxLines: 8,
                    decoration: InputDecoration(
                      hintText:
                          '默认：\n【通知转发】\n\n应用：%appName%\n标题：%title%\n内容：%content%\n...',
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
                        _presetChip('默认', '', bodyCtrl),
                        _presetChip(
                          '标准',
                          '应用：%appName%\n标题：%title%\n内容：%content%\n时间：%time%\n设备：%deviceName%',
                          bodyCtrl,
                        ),
                        _presetChip(
                          '完整',
                          '应用：%appName%\n标题：%title%\n内容：%content%\n副标题：%subText%\n包名：%packageName%\n时间：%time%\n设备：%deviceName%',
                          bodyCtrl,
                        ),
                        _presetChip(
                          '验证码',
                          '验证码：%content%\n来源：%appName%(%packageName%)\n时间：%time%',
                          bodyCtrl,
                        ),
                        _presetChip(
                          '极简',
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
  }) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
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
