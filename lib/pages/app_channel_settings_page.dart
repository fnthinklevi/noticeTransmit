import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../services/app_channel_service.dart';
import '../services/platform_channel.dart';
import '../theme/app_colors.dart';
import '../widgets/app_text_selection_menu.dart';

/// 自建应用通道设置页（应用通道体系，管理完善度与 Webhook 通道对齐）。
///
/// 支持：企业微信自建应用（corpid/agentid/touser 定向）、飞书自建应用
/// （app_id/receive_id），每通道独立开关、测试发送、健康探测徽标、删除；
/// 保存后经 MethodChannel 同步原生（AppChannelSender 两阶段推送）。
class AppChannelSettingsPage extends StatefulWidget {
  const AppChannelSettingsPage({super.key});

  @override
  State<AppChannelSettingsPage> createState() => _AppChannelSettingsPageState();
}

class _AppChannelSettingsPageState extends State<AppChannelSettingsPage> {
  static const _channel = AppChannels.notification;

  late List<Map<String, dynamic>> _channels;
  final Map<String, TextEditingController> _controllers = {};
  bool _saving = false;
  String? _testingId;
  final Map<String, Map<String, dynamic>> _health = {};

  @override
  void initState() {
    super.initState();
    final service = GetIt.instance<AppChannelService>();
    _channels = List<Map<String, dynamic>>.from(service.channels);
    if (_channels.isEmpty) _addChannel('wecom_app');
    for (final c in _channels) {
      _bindControllers(c);
    }
    _loadHealthCache();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _bindControllers(Map<String, dynamic> c) {
    final id = c['id'] as String;
    // 基础字段控制器：渲染（名称/地址/密钥输入框）与保存（_channelPayload）
    // 都读取这三个控制器。缺失时输入框空白、且保存会把 baseUrl 清空、secret 置 null
    //（凭据丢失）——回归守卫见 app_channel_settings_page_test「保存不丢字段」。
    _controllers['$id.name'] ??= TextEditingController(
      text: c['name']?.toString() ?? '',
    );
    _controllers['$id.baseUrl'] ??= TextEditingController(
      text: c['baseUrl']?.toString() ?? '',
    );
    _controllers['$id.secret'] ??= TextEditingController(
      text: c['secret']?.toString() ?? '',
    );
    final config = (c['config'] as Map?) ?? const {};
    for (final key in const [
      'corpid',
      'agentid',
      'touser',
      'app_id',
      'receive_id_type',
      'receive_id',
    ]) {
      _controllers['$id.$key'] ??= TextEditingController(
        text: config[key]?.toString() ?? '',
      );
    }
  }

  Map<String, TextEditingController> _field(String id) => {
    'corpid': _controllers['$id.corpid']!,
    'agentid': _controllers['$id.agentid']!,
    'touser': _controllers['$id.touser']!,
    'app_id': _controllers['$id.app_id']!,
    'receive_id_type': _controllers['$id.receive_id_type']!,
    'receive_id': _controllers['$id.receive_id']!,
  };

  /// 点击 + 后弹出 iOS 底部弹层选择通道类型
  void _showAddTypePicker(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: AppColors.cardBg(sheetContext),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.separator(sheetContext),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.business, color: AppColors.blue),
                title: Text(
                  l10n.appChannelAddWecom,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primaryLabel(sheetContext),
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _addChannel('wecom_app');
                },
              ),
              ListTile(
                leading: const Icon(Icons.link, color: AppColors.blue),
                title: Text(
                  l10n.appChannelAddFeishu,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primaryLabel(sheetContext),
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _addChannel('feishu_app');
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _addChannel(String appType) {
    final id = 'app_${DateTime.now().millisecondsSinceEpoch}';
    _channels.add({
      'id': id,
      'name': '',
      'appType': appType,
      'baseUrl': appType == 'wecom_app'
          ? 'https://qyapi.weixin.qq.com'
          : 'https://open.feishu.cn',
      'secret': null,
      'config': <String, dynamic>{},
      'message_format': 'default',
      'enabled': true,
    });
    _bindControllers(_channels.last);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(
        title: Text(l10n.appChannelTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l10n.appChannelAddWecom,
            onPressed: () => _showAddTypePicker(context),
          ),
          TextButton(
            onPressed: _saving ? null : _saveAll,
            child: Text(
              l10n.save,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.blue,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            l10n.appChannelPageDesc,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: AppColors.secondaryLabel(context),
            ),
          ),
          const SizedBox(height: 8),
          // 接入引导入口（v1.59）：详细步骤见 _showSetupGuide
          InkWell(
            onTap: () => _showSetupGuide(context, 'wecom_app'),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(
                    Icons.help_outline,
                    size: 14,
                    color: AppColors.blue,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      l10n.appChannelGuideEntry,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.blue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < _channels.length; i++)
            _buildChannelCard(context, i, l10n),
        ],
      ),
    );
  }

  Widget _buildChannelCard(
    BuildContext context,
    int index,
    AppLocalizations l10n,
  ) {
    final c = _channels[index];
    final id = c['id'] as String;
    final enabled = c['enabled'] == true;
    final health = _health[id];
    final fields = _field(id);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
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
              Text(
                l10n.appChannelN(index + 1),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.blue,
                ),
              ),
              // 按当前类型打开对应接入引导（v1.59）
              IconButton(
                icon: const Icon(
                  Icons.help_outline,
                  size: 18,
                  color: AppColors.blue,
                ),
                tooltip: l10n.appChannelGuideOpen,
                visualDensity: VisualDensity.compact,
                onPressed: () => _showSetupGuide(
                  context,
                  c['appType']?.toString() ?? 'wecom_app',
                ),
              ),
              const Spacer(),
              Switch(
                value: enabled,
                activeThumbColor: AppColors.blue,
                onChanged: (v) =>
                    setState(() => _channels[index]['enabled'] = v),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            contextMenuBuilder: AppTextSelectionMenu.editableText,
            controller: _controllers['$id.name'],
            style: TextStyle(color: AppColors.primaryLabel(context)),
            decoration: _decoration(context, l10n.appChannelNameLabel),
          ),
          const SizedBox(height: 10),
          _typeSelector(index, context),
          const SizedBox(height: 10),
          TextField(
            contextMenuBuilder: AppTextSelectionMenu.editableText,
            controller: _controllers['$id.baseUrl'],
            style: TextStyle(color: AppColors.primaryLabel(context)),
            decoration: _decoration(context, l10n.appChannelBaseUrlHint),
          ),
          const SizedBox(height: 10),
          TextField(
            contextMenuBuilder: AppTextSelectionMenu.editableText,
            controller: _controllers['$id.secret'],
            obscureText: true,
            style: TextStyle(color: AppColors.primaryLabel(context)),
            decoration: _decoration(
              context,
              c['appType'] == 'feishu_app'
                  ? l10n.appChannelSecretFeishuHint
                  : l10n.appChannelSecretWecomHint,
            ),
          ),
          // 扩展参数（按类型渲染）
          for (final field in _configFields(c['appType'] as String)) ...[
            const SizedBox(height: 10),
            TextField(
              contextMenuBuilder: AppTextSelectionMenu.editableText,
              controller: fields[field.$1],
              keyboardType: field.$2 == 'number' ? TextInputType.number : null,
              style: TextStyle(color: AppColors.primaryLabel(context)),
              decoration: _decoration(context, field.$3),
            ),
          ],
          if (health != null) ...[
            const SizedBox(height: 10),
            _healthBadge(health, l10n),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (_testingId == id)
                  ? null
                  : () => _testChannel(index, c),
              icon: (_testingId == id)
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send, size: 16),
              label: Text(
                (_testingId == id) ? l10n.testing : l10n.test,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.appChannelDeleteHint,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.secondaryLabel(context),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                setState(() => _channels.removeAt(index));
              },
              icon: const Icon(Icons.delete_outline, size: 16),
              label: Text(l10n.delete, style: const TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  /// 接入步骤引导（v1.59）：按通道类型展示详细参数获取步骤 + 注意事项。
  /// iOS 底部弹层，与页面其他弹层风格一致。
  void _showSetupGuide(BuildContext context, String appType) {
    final l10n = AppLocalizations.of(context);
    final isWecom = appType != 'feishu_app';
    final title = isWecom
        ? l10n.appChannelGuideTitleWecom
        : l10n.appChannelGuideTitleFeishu;
    final prep = isWecom
        ? l10n.appChannelGuidePrepWecom
        : l10n.appChannelGuidePrepFeishu;
    final steps = isWecom
        ? <(String, String)>[
            (l10n.appChannelGuideWecomS1, l10n.appChannelGuideWecomS1Desc),
            (l10n.appChannelGuideWecomS2, l10n.appChannelGuideWecomS2Desc),
            (l10n.appChannelGuideWecomS3, l10n.appChannelGuideWecomS3Desc),
            (l10n.appChannelGuideWecomS4, l10n.appChannelGuideWecomS4Desc),
            (l10n.appChannelGuideWecomS5, l10n.appChannelGuideWecomS5Desc),
            (l10n.appChannelGuideWecomS6, l10n.appChannelGuideWecomS6Desc),
          ]
        : <(String, String)>[
            (l10n.appChannelGuideFeishuS1, l10n.appChannelGuideFeishuS1Desc),
            (l10n.appChannelGuideFeishuS2, l10n.appChannelGuideFeishuS2Desc),
            (l10n.appChannelGuideFeishuS3, l10n.appChannelGuideFeishuS3Desc),
            (l10n.appChannelGuideFeishuS4, l10n.appChannelGuideFeishuS4Desc),
            (l10n.appChannelGuideFeishuS5, l10n.appChannelGuideFeishuS5Desc),
            (l10n.appChannelGuideFeishuS6, l10n.appChannelGuideFeishuS6Desc),
          ];
    final notes = <String>[
      l10n.appChannelGuideNote1,
      l10n.appChannelGuideNote2,
      l10n.appChannelGuideNote3,
      l10n.appChannelGuideNote4,
      l10n.appChannelGuideNote5,
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: AppColors.cardBg(sheetContext),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.separator(sheetContext),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryLabel(sheetContext),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.inputBg(sheetContext),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          prep,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.45,
                            color: AppColors.primaryLabel(sheetContext),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      for (var i = 0; i < steps.length; i++) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: AppColors.blue,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${i + 1}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    steps[i].$1,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.primaryLabel(
                                        sheetContext,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    steps[i].$2,
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.5,
                                      color: AppColors.secondaryLabel(
                                        sheetContext,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (i != steps.length - 1) const SizedBox(height: 12),
                      ],
                      const SizedBox(height: 16),
                      Container(
                        height: 0.5,
                        color: AppColors.separator(sheetContext),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l10n.appChannelGuideNoteTitle,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.secondaryLabel(sheetContext),
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final note in notes)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                margin: const EdgeInsets.only(top: 6),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.secondaryLabel(sheetContext),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  note,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.5,
                                    color: AppColors.secondaryLabel(
                                      sheetContext,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              Container(height: 0.5, color: AppColors.separator(sheetContext)),
              // ⚠ 不用 ListTile：它要求最近的 Material 祖先绘制 ink，被带背景色的
              // Container 包裹时会触发 "ink splashes may be invisible" 调试断言
              InkWell(
                onTap: () => Navigator.pop(sheetContext),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      l10n.appChannelGuideClose,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.blue,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<(String, String, String)> _configFields(String appType) {
    final l10n = AppLocalizations.of(context);
    if (appType == 'wecom_app') {
      return [
        ('corpid', 'text', l10n.appChannelCorpidLabel),
        ('agentid', 'number', l10n.appChannelAgentidLabel),
        ('touser', 'text', l10n.appChannelTouserLabel),
      ];
    }
    if (appType == 'feishu_app') {
      return [
        ('app_id', 'text', l10n.appChannelAppidLabel),
        ('receive_id_type', 'text', l10n.appChannelReceiveIdTypeLabel),
        ('receive_id', 'text', l10n.appChannelReceiveIdLabel),
      ];
    }
    return const [];
  }

  InputDecoration _decoration(BuildContext context, String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        fontSize: 12,
        color: AppColors.tertiaryLabel(context),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.separator(context)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      isDense: true,
      filled: true,
      fillColor: AppColors.inputBg(context),
    );
  }

  Widget _typeSelector(int index, BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = _channels[index];
    final type = c['appType'] as String;
    final label = type == 'wecom_app'
        ? l10n.channelTypeWecomApp
        : type == 'feishu_app'
        ? l10n.channelTypeFeishuApp
        : type;
    return InkWell(
      onTap: () => _pickType(index, context),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.inputBg(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.separator(context)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  color: AppColors.primaryLabel(context),
                ),
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

  Future<void> _pickType(int index, BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final current = _channels[index]['appType'] as String;
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg(ctx),
        title: Text(
          l10n.selectChannelType,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryLabel(ctx),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _typeOption(ctx, index, 'wecom_app', l10n.channelTypeWecomApp),
            _typeOption(ctx, index, 'feishu_app', l10n.channelTypeFeishuApp),
          ],
        ),
      ),
    );
    if (picked != null && picked != current) {
      setState(() => _channels[index]['appType'] = picked);
    }
  }

  Widget _typeOption(BuildContext ctx, int index, String type, String label) {
    final selected = _channels[index]['appType'] == type;
    return ListTile(
      dense: true,
      title: Text(
        label,
        style: TextStyle(fontSize: 15, color: AppColors.primaryLabel(ctx)),
      ),
      trailing: selected
          ? const Icon(Icons.check, color: AppColors.blue)
          : null,
      onTap: () => Navigator.pop(ctx, type),
    );
  }

  // ── 测试 / 保存 ──────────────────────────────────────────────────────

  Map<String, dynamic> _collectConfig(int index) {
    final c = _channels[index];
    final id = c['id'] as String;
    final appType = c['appType'] as String;
    final config = <String, dynamic>{};
    if (appType == 'wecom_app') {
      config['corpid'] = _controllers['$id.corpid']?.text.trim() ?? '';
      config['agentid'] =
          int.tryParse(_controllers['$id.agentid']?.text.trim() ?? '') ?? 0;
      config['touser'] = _controllers['$id.touser']?.text.trim() ?? '@all';
    } else {
      config['app_id'] = _controllers['$id.app_id']?.text.trim() ?? '';
      config['receive_id_type'] =
          _controllers['$id.receive_id_type']?.text.trim() ?? 'chat_id';
      config['receive_id'] = _controllers['$id.receive_id']?.text.trim() ?? '';
    }
    return config;
  }

  Map<String, dynamic> _channelPayload(int index, {bool forTest = false}) {
    final c = _channels[index];
    final id = c['id'] as String;
    return {
      'appType': c['appType'],
      // 控制器缺失时保留原值（防空值覆盖导致 baseUrl/secret 丢失）
      'baseUrl':
          _controllers['$id.baseUrl']?.text.trim() ??
          (c['baseUrl']?.toString() ?? ''),
      'secret': _controllers['$id.secret']?.text.trim() ?? c['secret'],
      'config': _collectConfig(index),
      if (!forTest) 'message_format': c['message_format'] ?? 'default',
      if (!forTest) 'enabled': c['enabled'] == true,
    };
  }

  Future<void> _testChannel(int index, Map<String, dynamic> c) async {
    final l10n = AppLocalizations.of(context);
    final id = c['id'] as String;
    setState(() => _testingId = id);
    try {
      final result = await _channel.invokeMethod('testAppChannel', {
        ..._channelPayload(index, forTest: true),
        'appType': c['appType'],
      });
      final success = result['success'] as bool? ?? false;
      final message = result['message'] as String? ?? '';
      _showToast(
        '${success ? l10n.test : l10n.testFailedMsg(message)} $message',
        success,
      );
    } catch (e) {
      _showToast('${l10n.appChannelTestFailed}$e', false);
    } finally {
      if (mounted) setState(() => _testingId = null);
    }
  }

  Future<void> _saveAll() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      final service = GetIt.instance<AppChannelService>();
      final payload = <Map<String, dynamic>>[];
      for (var i = 0; i < _channels.length; i++) {
        payload.add({..._channels[i], ..._channelPayload(i)});
      }
      await service.saveChannels(payload);
      if (!mounted) return;
      _showToast(l10n.appChannelSaveOk, true);
    } catch (e) {
      _showToast('${l10n.appChannelSaveFailed}$e', false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _loadHealthCache() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    for (final c in _channels) {
      final id = c['id'] as String;
      final raw = prefs.getString('channel_health_$id');
      if (raw == null) continue;
      try {
        _health[id] = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  Widget _healthBadge(Map<String, dynamic> health, AppLocalizations l10n) {
    final reachable = health['reachable'] == true;
    final latency = (health['latencyMs'] as num?)?.toInt() ?? 0;
    final probedAt = (health['probedAt'] as num?)?.toInt() ?? 0;
    final ago = DateTime.now().millisecondsSinceEpoch - probedAt;
    final agoText = ago < 60 * 60 * 1000
        ? l10n.healthProbedMinutes(ago ~/ (60 * 1000))
        : l10n.healthProbedHours(ago ~/ (60 * 60 * 1000));
    return Row(
      children: [
        Icon(
          reachable ? Icons.check_circle : Icons.cancel,
          size: 14,
          color: reachable ? AppColors.green : AppColors.red,
        ),
        const SizedBox(width: 5),
        Text(
          reachable ? l10n.healthReachable(latency) : l10n.healthUnreachable,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: reachable ? AppColors.green : AppColors.red,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          agoText,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.secondaryLabel(context),
          ),
        ),
      ],
    );
  }

  void _showToast(String message, bool ok) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: ok ? AppColors.green : AppColors.red,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
