import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/webhook_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/platform_channel.dart';
import '../theme/app_colors.dart';

// R3 拆分：通道卡片构建巨型方法迁出（extension 共享 State 私有成员）
part 'webhook_settings_item.dart';

class WebhookSettingsPage extends StatefulWidget {
  final List<Map<String, dynamic>> webhookChannels;

  const WebhookSettingsPage({super.key, required this.webhookChannels});

  @override
  State<WebhookSettingsPage> createState() => _WebhookSettingsPageState();
}

class _WebhookSettingsPageState extends State<WebhookSettingsPage> {
  static const _channel = AppChannels.notification;

  late List<TextEditingController> _webhookControllers;
  late List<TextEditingController> _nameControllers;
  late List<TextEditingController> _secretControllers;
  late List<TextEditingController> _templateControllers;
  // 企业微信自建应用扩展参数（corpid/agentid/touser），非 wecom_app 通道不显示
  late List<TextEditingController> _corpidControllers;
  late List<TextEditingController> _agentidControllers;
  late List<TextEditingController> _touserControllers;
  late List<bool> _webhookEnabled;
  late List<bool> _secretVisible;
  late List<WebhookMessageFormat> _messageFormats;
  // 渠道类型：'auto' 表示自动识别（按 URL host 探测），否则为用户手动指定的类型值
  late List<String> _channelTypes;
  bool _isTesting = false;
  // 通道健康探测（P2）：channelId → {reachable, latencyMs, httpCode, probedAt}
  Map<String, Map<String, dynamic>> _healthResults = {};
  bool _probing = false;
  String? _testResult;
  bool? _testSuccess;
  bool? _testSigned;
  int? _testIndex;
  bool _isSaving = false;

  /// 通道的有效类型：手动指定优先，'auto' 时按 URL 探测
  WebhookChannelType _effectiveType(int index) {
    final manual = _channelTypes[index];
    if (manual.isNotEmpty && manual != 'auto') {
      return WebhookChannelType.values.firstWhere(
        (t) => t.value == manual,
        orElse: () =>
            WebhookChannel.detectTypeFromUrl(_webhookControllers[index].text),
      );
    }
    return WebhookChannel.detectTypeFromUrl(_webhookControllers[index].text);
  }

  /// 渠道类型图标与品牌色（与 URL 识别提示一致）
  (IconData, Color) _typeVisual(WebhookChannelType type) {
    switch (type) {
      case WebhookChannelType.wechatWork:
        return (Icons.chat, const Color(0xFF07C160));
      case WebhookChannelType.dingtalk:
        return (Icons.work, const Color(0xFF1677FF));
      case WebhookChannelType.feishu:
        return (Icons.flight, AppColors.blue);
      case WebhookChannelType.telegram:
        return (Icons.send, const Color(0xFF0088CC));
      case WebhookChannelType.bark:
        return (Icons.notifications_active, const Color(0xFFE6A23C));
      case WebhookChannelType.serverChan:
        return (Icons.forward_to_inbox, const Color(0xFF4E5969));
      case WebhookChannelType.pushPlus:
        return (Icons.bolt, const Color(0xFF00B96B));
      case WebhookChannelType.ntfy:
        return (Icons.cell_tower, const Color(0xFF33B18A));
      case WebhookChannelType.gotify:
        return (Icons.inbox, const Color(0xFF00A0E9));
      case WebhookChannelType.slack:
        return (Icons.tag, const Color(0xFF4A154B));
      case WebhookChannelType.discord:
        return (Icons.forum, const Color(0xFF5865F2));
      case WebhookChannelType.generic:
        return (Icons.code, const Color(0xFFFF9500));
    }
  }

  /// 渠道类型本地化名称（替代模型层的静态中文 label）
  String _channelTypeLabel(BuildContext context, WebhookChannelType type) {
    final l10n = AppLocalizations.of(context);
    switch (type) {
      case WebhookChannelType.generic:
        return l10n.channelTypeGeneric;
      case WebhookChannelType.wechatWork:
        return l10n.channelTypeWechat;
      case WebhookChannelType.dingtalk:
        return l10n.channelTypeDingtalk;
      case WebhookChannelType.feishu:
        return l10n.channelTypeFeishu;
      case WebhookChannelType.telegram:
        return l10n.channelTypeTelegram;
      case WebhookChannelType.bark:
        return l10n.channelTypeBark;
      case WebhookChannelType.serverChan:
        return l10n.channelTypeServerChan;
      case WebhookChannelType.pushPlus:
        return l10n.channelTypePushPlus;
      case WebhookChannelType.ntfy:
        return l10n.channelTypeNtfy;
      case WebhookChannelType.gotify:
        return l10n.channelTypeGotify;
      case WebhookChannelType.slack:
        return l10n.channelTypeSlack;
      case WebhookChannelType.discord:
        return l10n.channelTypeDiscord;
    }
  }

  /// 消息格式本地化名称（品牌/格式名无需翻译）
  String _messageFormatLabel(BuildContext context, WebhookMessageFormat fmt) {
    final l10n = AppLocalizations.of(context);
    switch (fmt) {
      case WebhookMessageFormat.defaultFormat:
        return l10n.msgFormatDefault;
      case WebhookMessageFormat.text:
        return l10n.msgFormatText;
      case WebhookMessageFormat.markdown:
        return 'Markdown';
      case WebhookMessageFormat.json:
        return 'JSON';
      case WebhookMessageFormat.xml:
        return 'XML';
    }
  }

  /// 渠道类型选择器：iOS 风格输入框样式 + 弹窗选择（替代 Material DropdownButton）
  Widget _buildChannelTypeSelector(int index, BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final manual = _channelTypes[index];
    final detected = WebhookChannel.detectTypeFromUrl(
      _webhookControllers[index].text,
    );
    final isAuto = manual.isEmpty || manual == 'auto';
    final currentType = isAuto
        ? detected
        : WebhookChannelType.values.firstWhere(
            (t) => t.value == manual,
            orElse: () => detected,
          );
    final display = isAuto
        ? (detected == WebhookChannelType.generic
              ? l10n.channelTypeAuto
              : l10n.channelTypeAutoWith(_channelTypeLabel(context, detected)))
        : _channelTypeLabel(context, currentType);
    final visual = _typeVisual(currentType);

    return InkWell(
      onTap: () => _showChannelTypePicker(index, context),
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
            Icon(visual.$1, size: 16, color: visual.$2),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                display,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.primaryLabel(context),
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

  /// 渠道类型选择弹窗（与主题/语言选择同款 iOS 风格）
  void _showChannelTypePicker(int index, BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final detected = WebhookChannel.detectTypeFromUrl(
      _webhookControllers[index].text,
    );
    final current = _channelTypes[index];

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.cardBg(context),
        title: Text(
          l10n.selectChannelType,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryLabel(context),
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 4),
                _buildTypeOption(
                  context,
                  icon: Icons.auto_awesome,
                  color: AppColors.blue,
                  label: detected == WebhookChannelType.generic
                      ? l10n.channelTypeAuto
                      : l10n.channelTypeAutoWith(
                          _channelTypeLabel(context, detected),
                        ),
                  selected: current.isEmpty || current == 'auto',
                  onTap: () {
                    setState(() => _channelTypes[index] = 'auto');
                    Navigator.pop(dialogContext);
                  },
                ),
                ...WebhookChannelType.values.map((t) {
                  final visual = _typeVisual(t);
                  return _buildTypeOption(
                    context,
                    icon: visual.$1,
                    color: visual.$2,
                    label: _channelTypeLabel(context, t),
                    selected: current == t.value,
                    onTap: () {
                      setState(() => _channelTypes[index] = t.value);
                      Navigator.pop(dialogContext);
                    },
                  );
                }),
              ],
            ),
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Widget _buildTypeOption(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      dense: true,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        label,
        style: TextStyle(fontSize: 15, color: AppColors.primaryLabel(context)),
      ),
      trailing: selected
          ? const Icon(Icons.check, color: AppColors.blue)
          : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  @override
  void initState() {
    super.initState();
    _webhookControllers = widget.webhookChannels
        .map((c) => TextEditingController(text: c['url'] as String? ?? ''))
        .toList();
    _nameControllers = widget.webhookChannels
        .map((c) => TextEditingController(text: c['name'] as String? ?? ''))
        .toList();
    _secretControllers = widget.webhookChannels
        .map((c) => TextEditingController(text: c['secret'] as String? ?? ''))
        .toList();
    _templateControllers = widget.webhookChannels
        .map(
          (c) => TextEditingController(
            text: c['message_template'] as String? ?? '',
          ),
        )
        .toList();
    _corpidControllers = widget.webhookChannels
        .map(
          (c) => TextEditingController(
            text: ((c['extra_config'] as Map?)?['corpid'] ?? '')!.toString(),
          ),
        )
        .toList();
    _agentidControllers = widget.webhookChannels
        .map(
          (c) => TextEditingController(
            text: ((c['extra_config'] as Map?)?['agentid'] ?? '')!.toString(),
          ),
        )
        .toList();
    _touserControllers = widget.webhookChannels
        .map(
          (c) => TextEditingController(
            text: ((c['extra_config'] as Map?)?['touser'] ?? '')!.toString(),
          ),
        )
        .toList();
    _webhookEnabled = widget.webhookChannels
        .map((c) => c['enabled'] as bool? ?? true)
        .toList();
    _secretVisible = widget.webhookChannels.map((c) => false).toList();
    _messageFormats = widget.webhookChannels
        .map(
          (c) => WebhookMessageFormat.fromValue(
            (c['message_format'] as String?) ?? (c['messageFormat'] as String?),
          ),
        )
        .toList();
    // 已有通道保留原类型；空值的新通道默认自动识别
    _channelTypes = widget.webhookChannels.map((c) {
      final t =
          c['channelType']?.toString() ??
          c['type']?.toString() ??
          c['channel_type']?.toString() ??
          'auto';
      return t.isEmpty ? 'auto' : t;
    }).toList();
    if (_webhookControllers.isEmpty) {
      _webhookControllers.add(TextEditingController());
      _nameControllers.add(TextEditingController());
      _secretControllers.add(TextEditingController());
      _templateControllers.add(TextEditingController());
      _corpidControllers.add(TextEditingController());
      _agentidControllers.add(TextEditingController());
      _touserControllers.add(TextEditingController());
      _webhookEnabled.add(true);
      _secretVisible.add(false);
      _messageFormats.add(WebhookMessageFormat.defaultFormat);
      _channelTypes.add('auto');
    }
    // 进入设置页即读取缓存健康状态；启用的通道超 6 小时未探测则后台刷新
    _loadHealthCache();
  }

  /// 读取持久化的上次探测结果（SharedPreferences，key: `channel_health_<id>`）
  Future<void> _loadHealthCache() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final results = <String, Map<String, dynamic>>{};
    for (final c in widget.webhookChannels) {
      final id = c['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final raw = prefs.getString('channel_health_$id');
      if (raw == null) continue;
      try {
        results[id] = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {}
    }
    setState(() => _healthResults = results);
    _probeStaleChannels();
  }

  /// 启用通道超过 6 小时未探测 → 后台逐个探测并持久化
  Future<void> _probeStaleChannels() async {
    if (_probing) return;
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    final stale = widget.webhookChannels.where((c) {
      if (c['enabled'] != true) return false;
      final id = c['id']?.toString() ?? '';
      final cached = _healthResults[id];
      final probedAt = (cached?['probedAt'] as num?)?.toInt() ?? 0;
      return now - probedAt > const Duration(hours: 6).inMilliseconds;
    }).toList();
    if (stale.isEmpty) return;
    _probing = true;
    for (final c in stale) {
      final id = c['id']?.toString() ?? '';
      final url = c['url']?.toString() ?? '';
      if (id.isEmpty || url.isEmpty) continue;
      try {
        final r = await _channel.invokeMethod('probeChannelHealth', {
          'url': url,
        });
        final entry = <String, dynamic>{
          'reachable': r['reachable'] as bool? ?? false,
          'latencyMs': (r['latencyMs'] as num?)?.toInt() ?? 0,
          'httpCode': (r['httpCode'] as num?)?.toInt() ?? 0,
          'probedAt': DateTime.now().millisecondsSinceEpoch,
        };
        _healthResults[id] = entry;
        await prefs.setString('channel_health_$id', jsonEncode(entry));
        if (mounted) setState(() {});
      } catch (_) {}
    }
    _probing = false;
  }

  void _addWebhookField() {
    setState(() {
      _webhookControllers.add(TextEditingController());
      _nameControllers.add(TextEditingController());
      _secretControllers.add(TextEditingController());
      _templateControllers.add(TextEditingController());
      _corpidControllers.add(TextEditingController());
      _agentidControllers.add(TextEditingController());
      _touserControllers.add(TextEditingController());
      _webhookEnabled.add(true);
      _secretVisible.add(false);
      _messageFormats.add(WebhookMessageFormat.defaultFormat);
      _channelTypes.add('auto');
    });
  }

  void _removeWebhookField(int index) {
    setState(() {
      _webhookControllers[index].dispose();
      _nameControllers[index].dispose();
      _secretControllers[index].dispose();
      _templateControllers[index].dispose();
      _webhookControllers.removeAt(index);
      _nameControllers.removeAt(index);
      _secretControllers.removeAt(index);
      _templateControllers.removeAt(index);
      _corpidControllers.removeAt(index);
      _agentidControllers.removeAt(index);
      _touserControllers.removeAt(index);
      _webhookEnabled.removeAt(index);
      _secretVisible.removeAt(index);
      _messageFormats.removeAt(index);
      _channelTypes.removeAt(index);
      if (_webhookControllers.isEmpty) {
        _webhookControllers.add(TextEditingController());
        _nameControllers.add(TextEditingController());
        _secretControllers.add(TextEditingController());
        _templateControllers.add(TextEditingController());
        _corpidControllers.add(TextEditingController());
        _agentidControllers.add(TextEditingController());
        _touserControllers.add(TextEditingController());
        _webhookEnabled.add(true);
        _secretVisible.add(false);
        _messageFormats.add(WebhookMessageFormat.defaultFormat);
        _channelTypes.add('auto');
      }
    });
  }

  void _toggleWebhookEnabled(int index) {
    setState(() {
      _webhookEnabled[index] = !_webhookEnabled[index];
    });
  }

  void _toggleSecretVisible(int index) {
    setState(() {
      _secretVisible[index] = !_secretVisible[index];
    });
  }

  Future<void> _saveAndBack() async {
    setState(() {
      _isSaving = true;
    });
    final channels = <Map<String, dynamic>>[];
    for (int i = 0; i < _webhookControllers.length; i++) {
      final url = _webhookControllers[i].text.trim();
      final name = _nameControllers[i].text.trim();
      final secret = _secretControllers[i].text.trim();
      if (url.isNotEmpty) {
        // 保留已有通道 id（webhook_channels.id 是 PRIMARY KEY，缺失会被 replace 覆盖）
        final existingId = i < widget.webhookChannels.length
            ? widget.webhookChannels[i]['id'] as String?
            : null;
        // 渠道类型：手动指定优先（自建 Telegram/Bark 代理等场景），'auto' 才按 URL host 探测
        final manualType = _channelTypes[i];
        final channelType = (manualType == 'auto' || manualType.isEmpty)
            ? WebhookChannel.detectTypeFromUrl(url).value
            : manualType;
        // 企业微信自建应用：携带扩展参数（corpid/agentid/touser）
        Map<String, dynamic>? extraConfig;
        final template = _templateControllers[i].text.trim();
        channels.add({
          'id': (existingId != null && existingId.isNotEmpty)
              ? existingId
              : 'wh_${DateTime.now().millisecondsSinceEpoch}_$i',
          'url': url,
          'name': name,
          'channelType': channelType,
          'enabled': _webhookEnabled[i],
          if (secret.isNotEmpty) 'secret': secret,
          'message_format': _messageFormats[i].value,
          if (template.isNotEmpty) 'message_template': template,
          'extra_config': ?extraConfig,
        });
      }
    }
    if (!mounted) return;
    Navigator.pop(context, channels);
  }

  Future<void> _testWebhook(int index) async {
    final l10n = AppLocalizations.of(context);
    final url = _webhookControllers[index].text.trim();
    final secret = _secretControllers[index].text.trim();
    if (url.isEmpty) {
      setState(() {
        _testSuccess = false;
        _testResult = l10n.webhookUrlRequired;
        _testIndex = index;
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
      _testSuccess = null;
      _testSigned = null;
      _testIndex = index;
    });

    try {
      // 传递 secret 让原生端做签名验证，返回真实送达结果（含状态/HTTP码/签名标识）
      final result = await _channel.invokeMethod('testWebhook', {
        'url': url,
        if (secret.isNotEmpty) 'secret': secret,
      });
      final success = result['success'] as bool? ?? false;
      final message = result['message'] as String? ?? l10n.unknownError;
      final signed = result['signed'] as bool? ?? false;

      setState(() {
        _isTesting = false;
        _testSuccess = success;
        _testResult = message;
        _testSigned = signed;
      });
    } catch (e) {
      setState(() {
        _isTesting = false;
        _testSuccess = false;
        _testSigned = false;
        _testResult = l10n.testFailedMsg(e.toString());
      });
    }
  }

  /// 当前通道是否显示 secret 输入框。
  /// Telegram 用 Bot Token、Bark 用设备 Key、Slack/Discord 用 Webhook URL 本身
  /// 鉴权，不显示签名密钥输入框；其余平台（ntfy/gotify 的访问令牌、通用 webhook
  /// 的 X-Signature 头等）可按需填写。
  bool _supportsSigning(int index) {
    final type = _effectiveType(index);
    return type != WebhookChannelType.telegram &&
        type != WebhookChannelType.bark &&
        type != WebhookChannelType.serverChan &&
        type != WebhookChannelType.pushPlus &&
        type != WebhookChannelType.slack &&
        type != WebhookChannelType.discord;
  }

  String _signingHint(BuildContext context, WebhookChannelType type) {
    final l10n = AppLocalizations.of(context);
    switch (type) {
      case WebhookChannelType.wechatWork:
        return l10n.signingHintWechat;
      case WebhookChannelType.dingtalk:
        return l10n.signingHintDingtalk;
      case WebhookChannelType.feishu:
        return l10n.signingHintFeishu;
      case WebhookChannelType.telegram:
        return l10n.signingHintTelegram;
      case WebhookChannelType.bark:
        return l10n.signingHintBark;
      case WebhookChannelType.serverChan:
        return l10n.signingHintServerChan;
      case WebhookChannelType.pushPlus:
        return l10n.signingHintPushPlus;
      case WebhookChannelType.ntfy:
        return l10n.signingHintNtfy;
      case WebhookChannelType.gotify:
        return l10n.signingHintGotify;
      case WebhookChannelType.slack:
        return l10n.signingHintSlack;
      case WebhookChannelType.discord:
        return l10n.signingHintDiscord;
      case WebhookChannelType.generic:
        return l10n.signingHintGeneric;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(
        title: Text(l10n.webhookSettingsTitle),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveAndBack,
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    l10n.save,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _buildSectionHeader(l10n.channelList, context),
          _buildGroup([
            ...List.generate(_webhookControllers.length, (index) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (index > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Divider(
                        height: 0.5,
                        thickness: 0.5,
                        color: AppColors.separator(context),
                      ),
                    ),
                  _buildChannelItem(index, context),
                ],
              );
            }),
          ], context),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppColors.cardBg(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _addWebhookField,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.add_circle_outline,
                      size: 20,
                      color: AppColors.blue,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n.addChannel,
                      style: const TextStyle(
                        fontSize: 16,
                        color: AppColors.blue,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader(l10n.notes, context),
          _buildGroup([
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DescRow(text: l10n.webhookDesc1, context: context),
                  const SizedBox(height: 8),
                  _DescRow(text: l10n.webhookDesc2, context: context),
                  const SizedBox(height: 8),
                  _DescRow(text: l10n.webhookDesc3, context: context),
                ],
              ),
            ),
          ], context),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.secondaryLabel(context),
        ),
      ),
    );
  }

  Widget _buildGroup(List<Widget> children, BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  /// URL 识别提示区。
  /// 尊重手动指定的通道类型（自建 ntfy/Gotify 服务器 host 不可枚举，
  /// 纯 URL 探测会把手动选择的类型误显示为「通用 Webhook」，误导用户）；
  /// 仅当处于「自动识别」模式时才按 URL host 探测。
  Widget _buildWebhookTypeHint(int index, String urlStr, BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final url = urlStr.trim();
    final type = _effectiveType(index);
    String typeName;
    IconData icon;
    Color color;
    String desc;

    if (url.isEmpty) {
      typeName = l10n.urlEmpty;
      icon = Icons.link_off;
      color = const Color(0xFF8E8E93);
      desc = l10n.urlPlaceholder;
    } else {
      switch (type) {
        case WebhookChannelType.wechatWork:
          typeName = l10n.platformWechat;
          icon = Icons.chat;
          color = const Color(0xFF07C160);
          desc = l10n.platformWechatDesc;
        case WebhookChannelType.dingtalk:
          typeName = l10n.platformDingtalk;
          icon = Icons.work;
          color = const Color(0xFF1677FF);
          desc = l10n.platformWechatDesc;
        case WebhookChannelType.feishu:
          typeName = l10n.platformFeishu;
          icon = Icons.flight;
          color = AppColors.blue;
          desc = l10n.platformWechatDesc;
        case WebhookChannelType.telegram:
          typeName = 'Telegram';
          icon = Icons.send;
          color = const Color(0xFF0088CC);
          desc = l10n.platformWechatDesc;
        case WebhookChannelType.bark:
          typeName = 'Bark';
          icon = Icons.notifications_active;
          color = const Color(0xFFE6A23C);
          desc = l10n.platformWechatDesc;
        case WebhookChannelType.serverChan:
          typeName = l10n.channelTypeServerChan;
          icon = Icons.forward_to_inbox;
          color = const Color(0xFF4E5969);
          desc = l10n.platformWechatDesc;
        case WebhookChannelType.pushPlus:
          typeName = 'PushPlus';
          icon = Icons.bolt;
          color = const Color(0xFF00B96B);
          desc = l10n.platformWechatDesc;
        case WebhookChannelType.ntfy:
          typeName = l10n.channelTypeNtfy;
          icon = Icons.cell_tower;
          color = const Color(0xFF33B18A);
          desc = l10n.platformNtfyDesc;
        case WebhookChannelType.gotify:
          typeName = l10n.channelTypeGotify;
          icon = Icons.inbox;
          color = const Color(0xFF00A0E9);
          desc = l10n.platformGotifyDesc;
        case WebhookChannelType.slack:
          typeName = 'Slack';
          icon = Icons.tag;
          color = const Color(0xFF4A154B);
          desc = l10n.platformSlackDesc;
        case WebhookChannelType.discord:
          typeName = 'Discord';
          icon = Icons.forum;
          color = const Color(0xFF5865F2);
          desc = l10n.platformDiscordDesc;
        case WebhookChannelType.generic:
          typeName = l10n.platformGeneric;
          icon = Icons.code;
          color = const Color(0xFFFF9500);
          desc = l10n.platformGenericDesc;
      }
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  typeName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: color,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    for (final controller in _webhookControllers) {
      controller.dispose();
    }
    for (final controller in _nameControllers) {
      controller.dispose();
    }
    for (final controller in _secretControllers) {
      controller.dispose();
    }
    for (final controller in _templateControllers) {
      controller.dispose();
    }
    super.dispose();
  }
}

class _DescRow extends StatelessWidget {
  final String text;
  final BuildContext context;
  const _DescRow({required this.text, required this.context});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 4),
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: AppColors.tertiaryLabel(this.context),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: AppColors.secondaryLabel(this.context),
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}
