import 'dart:async';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/webhook_channel.dart';
import '../services/platform_channel.dart';
import '../theme/app_colors.dart';

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
  late List<bool> _webhookEnabled;
  late List<bool> _secretVisible;
  late List<WebhookMessageFormat> _messageFormats;
  // 渠道类型：'auto' 表示自动识别（按 URL host 探测），否则为用户手动指定的类型值
  late List<String> _channelTypes;
  bool _isTesting = false;
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

  /// 渠道类型下拉选项：'auto' 自动识别 + 各平台手动指定
  List<DropdownMenuItem<String>> _channelTypeOptions(int index) {
    final detected = WebhookChannel.detectTypeFromUrl(
      _webhookControllers[index].text,
    );
    return [
      DropdownMenuItem(
        value: 'auto',
        child: Text(
          detected == WebhookChannelType.generic
              ? '自动识别'
              : '自动识别（${detected.label}）',
          style: const TextStyle(fontSize: 14),
        ),
      ),
      ...WebhookChannelType.values.map(
        (t) => DropdownMenuItem(
          value: t.value,
          child: Text(t.label, style: const TextStyle(fontSize: 14)),
        ),
      ),
    ];
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
      _webhookEnabled.add(true);
      _secretVisible.add(false);
      _messageFormats.add(WebhookMessageFormat.defaultFormat);
      _channelTypes.add('auto');
    }
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
      if (_webhookControllers.isEmpty) {
        _webhookControllers.add(TextEditingController());
        _nameControllers.add(TextEditingController());
        _secretControllers.add(TextEditingController());
        _templateControllers.add(TextEditingController());
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

  /// 当前通道是否支持服务端签名密钥（用于决定是否显示 secret 输入框）。
  /// Telegram 用 Bot Token、Bark 用设备 Key 鉴权，不支持签名密钥；
  /// 其余平台（含通用 webhook 的 X-Signature 头）可按需填写。
  bool _supportsSigning(int index) {
    final type = _effectiveType(index);
    return type != WebhookChannelType.telegram && type != WebhookChannelType.bark;
  }

  String _signingHint(WebhookChannelType type) {
    switch (type) {
      case WebhookChannelType.wechatWork:
        return '企业微信群机器人开启「签名校验」后生成的密钥';
      case WebhookChannelType.dingtalk:
        return '钉钉机器人开启「加签」后生成的密钥（SEC 开头）';
      case WebhookChannelType.feishu:
        return '飞书自定义机器人开启「签名校验」后的密钥';
      case WebhookChannelType.telegram:
        return 'Telegram 使用 Bot Token 鉴权，无需签名密钥';
      case WebhookChannelType.bark:
        return 'Bark 使用设备 Key 鉴权，无需签名密钥';
      case WebhookChannelType.generic:
        return '自建服务端校验签名用的密钥（通过 X-Signature 头传递）';
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

  Widget _buildChannelItem(int index, BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  l10n.channelN(index + 1),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.blue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              Switch(
                value: _webhookEnabled[index],
                onChanged: (_) => _toggleWebhookEnabled(index),
              ),
              if (_webhookControllers.length > 1)
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: AppColors.red,
                  ),
                  onPressed: () => _removeWebhookField(index),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _nameControllers[index],
            decoration: InputDecoration(
              hintText: l10n.channelNameOptional,
              hintStyle: TextStyle(
                fontSize: 13,
                color: AppColors.tertiaryLabel(context),
              ),
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
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              isDense: true,
            ),
            style: TextStyle(
              fontSize: 14,
              color: AppColors.primaryLabel(context),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _webhookControllers[index],
            decoration: InputDecoration(
              hintText: l10n.webhookUrlPlaceholder,
              hintStyle: TextStyle(color: AppColors.tertiaryLabel(context)),
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
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              isDense: true,
              filled: true,
              fillColor: AppColors.inputBg(context),
            ),
            style: TextStyle(
              fontSize: 15,
              color: AppColors.primaryLabel(context),
            ),
            maxLines: 1,
            onChanged: (_) {
              setState(() {});
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '渠道类型',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.secondaryLabel(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButton<String>(
                  value: _channelTypes[index],
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.primaryLabel(context),
                  ),
                  items: _channelTypeOptions(index),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        _channelTypes[index] = v;
                      });
                    }
                  },
                ),
              ),
            ],
          ),
          if (_supportsSigning(index)) ...[
            const SizedBox(height: 10),
            Text(
              l10n.webhookSecretLabel,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.secondaryLabel(context),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _secretControllers[index],
              obscureText: !_secretVisible[index],
              decoration: InputDecoration(
                hintText: _signingHint(_effectiveType(index)),
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: AppColors.tertiaryLabel(context),
                ),
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
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                isDense: true,
                filled: true,
                fillColor: AppColors.inputBg(context),
                suffixIcon: IconButton(
                  icon: Icon(
                    _secretVisible[index]
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 18,
                    color: AppColors.tertiaryLabel(context),
                  ),
                  onPressed: () => _toggleSecretVisible(index),
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ),
              style: TextStyle(
                fontSize: 15,
                color: AppColors.primaryLabel(context),
              ),
              maxLines: 1,
            ),
          ],
          const SizedBox(height: 10),
          // 消息格式选择器：default / text / markdown / json / xml
          Row(
            children: [
              Text(
                l10n.webhookFormatLabel,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.secondaryLabel(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: WebhookMessageFormat.values.map((fmt) {
                      final selected = _messageFormats[index] == fmt;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _messageFormats[index] = fmt;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.blue.withValues(alpha: 0.12)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: selected
                                    ? AppColors.blue
                                    : AppColors.separator(context),
                              ),
                            ),
                            child: Text(
                              fmt.label,
                              style: TextStyle(
                                fontSize: 12,
                                color: selected
                                    ? AppColors.blue
                                    : AppColors.secondaryLabel(context),
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
          // 飞书 markdown 降级提示
          if (_messageFormats[index] == WebhookMessageFormat.markdown &&
              (_webhookControllers[index].text.toLowerCase().contains(
                    'feishu',
                  ) ||
                  _webhookControllers[index].text.toLowerCase().contains(
                    'larksuite',
                  ))) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 14,
                    color: Colors.orange[700],
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.feishuMarkdownDowngradeHint,
                      style: TextStyle(fontSize: 11, color: Colors.orange[700]),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // 模板编辑器：仅当 format != default 时显示
          if (_messageFormats[index] != WebhookMessageFormat.defaultFormat) ...[
            const SizedBox(height: 10),
            Text(
              l10n.webhookTemplateLabel,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.secondaryLabel(context),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${l10n.webhookTemplateHint} %appName% %title% %content% %subText% %time% %deviceName% %packageName% %notifyType% %simInfo% %sender% %phoneNumber% %durationStr% %callState% %timestamp%',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.tertiaryLabel(context),
              ),
            ),
            const SizedBox(height: 6),
            // 变量插入按钮
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children:
                  [
                    '%appName%',
                    '%title%',
                    '%content%',
                    '%time%',
                    '%deviceName%',
                    '%notifyType%',
                  ].map((v) {
                    return ActionChip(
                      label: Text(
                        v,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.blue,
                        ),
                      ),
                      backgroundColor: AppColors.blue.withValues(alpha: 0.08),
                      side: BorderSide.none,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 0,
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        final controller = _templateControllers[index];
                        final sel = controller.selection;
                        final text = controller.text;
                        final newText = sel.start >= 0
                            ? text.replaceRange(
                                sel.start,
                                sel.end >= 0 ? sel.end : sel.start,
                                v,
                              )
                            : text + v;
                        controller.text = newText;
                        controller.selection = TextSelection.collapsed(
                          offset:
                              (sel.start >= 0 ? sel.start : text.length) +
                              v.length,
                        );
                        setState(() {});
                      },
                    );
                  }).toList(),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _templateControllers[index],
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(
                hintText: _messageFormats[index] == WebhookMessageFormat.json
                    ? '{"title":"%title%","content":"%content%"}'
                    : _messageFormats[index] == WebhookMessageFormat.xml
                    ? '<notification><title>%title%</title></notification>'
                    : '## %title%\n%content%',
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: AppColors.tertiaryLabel(context),
                  fontFamily: 'monospace',
                ),
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
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                isDense: true,
                filled: true,
                fillColor: AppColors.inputBg(context),
              ),
              style: TextStyle(
                fontSize: 13,
                color: AppColors.primaryLabel(context),
                fontFamily: 'monospace',
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildWebhookTypeHint(
                  _webhookControllers[index].text,
                  context,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 36,
                child: TextButton.icon(
                  onPressed: (_isTesting && _testIndex == index)
                      ? null
                      : () => _testWebhook(index),
                  icon: (_isTesting && _testIndex == index)
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send, size: 16),
                  label: Text(
                    (_isTesting && _testIndex == index)
                        ? l10n.testing
                        : l10n.test,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.blue,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_testResult != null && _testIndex == index) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (_testSuccess ?? false)
                    ? AppColors.green.withValues(alpha: 0.1)
                    : AppColors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _testSuccess == true ? Icons.check_circle : Icons.error,
                    color: _testSuccess == true
                        ? AppColors.green
                        : AppColors.red,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _testResult!,
                          style: TextStyle(
                            fontSize: 12,
                            color: _testSuccess == true
                                ? AppColors.green
                                : AppColors.red,
                          ),
                        ),
                        if (_testSigned == true) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.blue.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.verified_user_outlined,
                                  size: 11,
                                  color: AppColors.blue,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  l10n.webhookSigned,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.blue,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
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

  Widget _buildWebhookTypeHint(String urlStr, BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final url = urlStr.trim();
    final type = WebhookChannel.detectTypeFromUrl(url);
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
