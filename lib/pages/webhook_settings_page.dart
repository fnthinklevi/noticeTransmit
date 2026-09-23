import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../l10n/app_localizations.dart';
import '../models/webhook_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/channel_descriptor_service.dart';
import '../services/platform_channel.dart';
import '../theme/app_colors.dart';
import '../widgets/app_text_selection_menu.dart';
import '../widgets/channel_visuals.dart';

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

  /// 通道描述符（原生表）：secret/模板显隐、类型候选列表与名称都按它渲染
  late final ChannelDescriptorService _descriptors;
  late List<TextEditingController> _webhookControllers;
  late List<TextEditingController> _nameControllers;
  late List<TextEditingController> _secretControllers;
  late List<TextEditingController> _templateControllers;
  late List<bool> _webhookEnabled;
  late List<bool> _secretVisible;
  late List<WebhookMessageFormat> _messageFormats;
  // 渠道类型：'auto' 表示自动识别（按 URL host 探测），否则为用户手动指定的类型值
  late List<String> _channelTypes;
  // 各行的既有通道 id，与上面所有列表**并行同下标**。删除行时必须同步 removeAt：
  // widget.webhookChannels 是 final 输入、不会随删除收缩，按其下标取 id 会让
  // 删掉第 1 条后其余各行继承错位的 id（保存走 delete+insert，健康缓存/送达归属全错）。
  late List<String?> _channelIds;
  bool _isTesting = false;
  // 通道健康探测（P2）：channelId → {reachable, latencyMs, httpCode, probedAt}
  Map<String, Map<String, dynamic>> _healthResults = {};
  bool _probing = false;
  String? _testResult;
  bool? _testSuccess;
  bool? _testSigned;
  int? _testIndex;
  bool _isSaving = false;

  /// 当前行的**有效类型 slug**：手动指定优先，'auto' 时按 URL host 探测。
  ///
  /// 以前这里返回 Dart 枚举，于是「Dart 有没有登记这个平台」会决定界面能不能显示它。
  /// 第 5 步起一律用 slug（与原生描述符的 `key`、送达键 `chan:<slug>` 同一口径），
  /// 原生新增通道时 Dart 不再需要跟着加枚举臂。
  String _effectiveSlug(int index) {
    final manual = _channelTypes[index];
    if (manual.isNotEmpty && manual != 'auto') return manual;
    return WebhookChannel.detectTypeFromUrl(
      _webhookControllers[index].text,
    ).value;
  }

  /// 该行的描述符（原生表）；描述符未拉到时 null，调用方按"不收窄"处理。
  ChannelDescriptor? _descriptorFor(int index) =>
      _descriptors.byKey(_effectiveSlug(index));

  /// 渠道类型图标与品牌色
  ChannelVisual _typeVisual(String slug) => channelVisual(slug);

  /// 渠道类型本地化名称：描述符的 labelKey 优先，Dart slug 表兜底，最后原样显示 slug
  String _channelTypeLabel(BuildContext context, String slug) {
    final l10n = AppLocalizations.of(context);
    final descriptor = _descriptors.byKey(slug);
    return descriptor == null
        ? channelDisplayNameFor(l10n, slug)
        : channelNameOf(l10n, descriptor);
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
    final isAuto = manual.isEmpty || manual == 'auto';
    final detectedSlug = WebhookChannel.detectTypeFromUrl(
      _webhookControllers[index].text,
    ).value;
    final currentSlug = isAuto ? detectedSlug : manual;
    final display = isAuto
        ? (detectedSlug == 'generic'
              ? l10n.channelTypeAuto
              : l10n.channelTypeAutoWith(
                  _channelTypeLabel(context, detectedSlug),
                ))
        : _channelTypeLabel(context, currentSlug);
    final visual = _typeVisual(currentSlug);

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
            Icon(visual.icon, size: 16, color: visual.color),
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

  /// 类型下拉的候选项：**描述符列表**（原生表为准）。
  /// 描述符没拉到时退回 Dart 枚举（12 个），保证离线也能改类型。
  List<String> _typeSlugs() {
    final descriptors = _descriptors.webhook;
    if (descriptors.isNotEmpty) {
      return descriptors.map((d) => d.key).toList(growable: false);
    }
    return WebhookChannelType.values
        .map((t) => t.value)
        .toList(growable: false);
  }

  /// 渠道类型选择弹窗（与主题/语言选择同款 iOS 风格）
  void _showChannelTypePicker(int index, BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final detectedSlug = WebhookChannel.detectTypeFromUrl(
      _webhookControllers[index].text,
    ).value;
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
                  label: detectedSlug == 'generic'
                      ? l10n.channelTypeAuto
                      : l10n.channelTypeAutoWith(
                          _channelTypeLabel(context, detectedSlug),
                        ),
                  selected: current.isEmpty || current == 'auto',
                  onTap: () {
                    setState(() => _channelTypes[index] = 'auto');
                    Navigator.pop(dialogContext);
                  },
                ),
                ..._typeSlugs().map((slug) {
                  final visual = _typeVisual(slug);
                  return _buildTypeOption(
                    context,
                    icon: visual.icon,
                    color: visual.color,
                    label: _channelTypeLabel(context, slug),
                    selected: current == slug,
                    onTap: () {
                      setState(() => _channelTypes[index] = slug);
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
    _descriptors = GetIt.instance<ChannelDescriptorService>();
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
    _channelIds = widget.webhookChannels
        .map((c) => c['id'] as String?)
        .toList();
    if (_webhookControllers.isEmpty) {
      _webhookControllers.add(TextEditingController());
      _nameControllers.add(TextEditingController());
      _secretControllers.add(TextEditingController());
      _templateControllers.add(TextEditingController());
      _webhookEnabled.add(true);
      _secretVisible.add(false);
      _messageFormats.add(WebhookMessageFormat.defaultFormat);
      _channelTypes.add('auto');
      _channelIds.add(null);
    }
    // 进入设置页即读取缓存健康状态；启用的通道超 6 小时未探测则后台刷新
    _loadHealthCache();
    // splash 那次没拉成功时兜底重取：到手后重建，否则显隐判断会一直停在"按显示处理"
    _descriptors.load().then((_) {
      if (mounted) setState(() {});
    });
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
      _webhookEnabled.add(true);
      _secretVisible.add(false);
      _messageFormats.add(WebhookMessageFormat.defaultFormat);
      _channelTypes.add('auto');
      _channelIds.add(null);
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
      _webhookEnabled.removeAt(index);
      _secretVisible.removeAt(index);
      _messageFormats.removeAt(index);
      _channelTypes.removeAt(index);
      _channelIds.removeAt(index);
      if (_webhookControllers.isEmpty) {
        _webhookControllers.add(TextEditingController());
        _nameControllers.add(TextEditingController());
        _secretControllers.add(TextEditingController());
        _templateControllers.add(TextEditingController());
        _webhookEnabled.add(true);
        _secretVisible.add(false);
        _messageFormats.add(WebhookMessageFormat.defaultFormat);
        _channelTypes.add('auto');
        _channelIds.add(null);
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
        // 取并行列表 _channelIds —— 不能按 i 读 widget.webhookChannels：那是 final
        // 输入、不随删除收缩，删过一行后其余行会继承错位的 id（保存走 delete+insert，
        // 健康缓存 channel_health_<id> 与送达归属会整体串台）。
        final existingId = i < _channelIds.length ? _channelIds[i] : null;
        // 渠道类型：手动指定优先（自建 Telegram/Bark 代理等场景），'auto' 才按 URL host 探测
        final manualType = _channelTypes[i];
        final channelType = (manualType == 'auto' || manualType.isEmpty)
            ? WebhookChannel.detectTypeFromUrl(url).value
            : manualType;
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
        // 把用户在通道上选过的类型一起传过去：只给 URL 时，自建 Gotify / 私有 ntfy
        // 会被原生按 host 降级成通用 webhook 判定，测试按钮的结论与真实推送不一致。
        'channelType': _channelTypes[index],
      });
      final success = result['success'] as bool? ?? false;
      final message = result['message'] as String? ?? l10n.unknownError;
      final signed = result['signed'] as bool? ?? false;

      if (!mounted) return;
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
  ///
  /// 判据来自描述符的 `secretUsed` 能力位（= 原生签名表 + 传输事实派生：
  /// 有签名方案 / secret 走 Bearer 头 / secret 作为 URL token）。此前这里是本页
  /// 自带的一份「排除 6 个平台」黑名单 —— 原生加一个签名方案时这边不会跟着变，
  /// 表现就是"能签名却没地方填密钥"。
  /// 描述符没拉到时**按显示处理**：宁可多给一个入口，也不能让凭据没地方填。
  bool _supportsSigning(int index) =>
      _descriptorFor(index)?.usesSecretField ?? true;

  /// 「消息格式 / 自定义模板」对该通道是否生效（不生效时不给入口）。
  /// Server酱 / PushPlus 有实发正文覆写，ntfy / gotify / slack / discord 没有平台
  /// 模板包装 —— 用户选了格式也不会进正文，以前照样给一整排选择器。
  bool _supportsCustomTemplate(int index) =>
      _descriptorFor(index)?.supportsCustomTemplate ?? true;

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
    if (url.isEmpty) {
      // 未填 URL：没有类型可识别，用中性样式（不冒充某个平台的名字和颜色）
      return _typeHintChip(
        context,
        name: l10n.urlEmpty,
        desc: l10n.urlPlaceholder,
        icon: Icons.link_off,
        color: const Color(0xFF8E8E93),
      );
    }
    final visual = _typeVisual(_effectiveSlug(index));
    return _typeHintChip(
      context,
      name: channelHintNameFor(l10n, visual),
      desc: channelDescFor(l10n, visual),
      icon: visual.icon,
      color: visual.color,
    );
  }

  /// 「URL 识别」提示卡片：图标 + 平台名 + 一句说明。
  Widget _typeHintChip(
    BuildContext context, {
    required String name,
    required String desc,
    required IconData icon,
    required Color color,
  }) {
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
                  name,
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
