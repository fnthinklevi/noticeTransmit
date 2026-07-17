import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';

class WebhookSettingsPage extends StatefulWidget {
  final List<Map<String, dynamic>> webhookChannels;

  const WebhookSettingsPage({super.key, required this.webhookChannels});

  @override
  State<WebhookSettingsPage> createState() => _WebhookSettingsPageState();
}

class _WebhookSettingsPageState extends State<WebhookSettingsPage> {
  static const platform = MethodChannel('com.fnthink.notice/notification');

  late List<TextEditingController> _webhookControllers;
  late List<bool> _webhookEnabled;
  bool _isTesting = false;
  String? _testResult;
  bool? _testSuccess;
  int? _testIndex;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _webhookControllers = widget.webhookChannels
        .map((c) => TextEditingController(text: c['url'] as String? ?? ''))
        .toList();
    _webhookEnabled = widget.webhookChannels
        .map((c) => c['enabled'] as bool? ?? true)
        .toList();
    if (_webhookControllers.isEmpty) {
      _webhookControllers.add(TextEditingController());
      _webhookEnabled.add(true);
    }
  }

  void _addWebhookField() {
    setState(() {
      _webhookControllers.add(TextEditingController());
      _webhookEnabled.add(true);
    });
  }

  void _removeWebhookField(int index) {
    setState(() {
      _webhookControllers[index].dispose();
      _webhookControllers.removeAt(index);
      _webhookEnabled.removeAt(index);
      if (_webhookControllers.isEmpty) {
        _webhookControllers.add(TextEditingController());
        _webhookEnabled.add(true);
      }
    });
  }

  void _toggleWebhookEnabled(int index) {
    setState(() {
      _webhookEnabled[index] = !_webhookEnabled[index];
    });
  }

  Future<void> _saveAndBack() async {
    setState(() {
      _isSaving = true;
    });
    final channels = <Map<String, dynamic>>[];
    for (int i = 0; i < _webhookControllers.length; i++) {
      final url = _webhookControllers[i].text.trim();
      if (url.isNotEmpty) {
        channels.add({'url': url, 'enabled': _webhookEnabled[i]});
      }
    }
    if (!mounted) return;
    Navigator.pop(context, channels);
  }

  Future<void> _testWebhook(int index) async {
    final url = _webhookControllers[index].text.trim();
    if (url.isEmpty) {
      setState(() {
        _testSuccess = false;
        _testResult = '请先输入 Webhook URL';
        _testIndex = index;
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
      _testSuccess = null;
      _testIndex = index;
    });

    try {
      final result = await platform.invokeMethod('testWebhook', {'url': url});
      final success = result['success'] as bool? ?? false;
      final message = result['message'] as String? ?? '未知错误';

      setState(() {
        _isTesting = false;
        _testSuccess = success;
        _testResult = message;
      });
    } catch (e) {
      setState(() {
        _isTesting = false;
        _testSuccess = false;
        _testResult = '测试失败: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(
        title: const Text('Webhook 推送通道'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveAndBack,
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    '保存',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _buildSectionHeader('通道列表', context),
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
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_circle_outline,
                      size: 20,
                      color: AppColors.blue,
                    ),
                    SizedBox(width: 6),
                    Text(
                      '添加通道',
                      style: TextStyle(
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
          _buildSectionHeader('说明', context),
          _buildGroup([
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DescRow(
                    text: '支持同时配置多个 Webhook 通道，每个通道可独立开关',
                    context: context,
                  ),
                  const SizedBox(height: 8),
                  _DescRow(text: '自动识别企业微信、钉钉、飞书等平台格式', context: context),
                  const SizedBox(height: 8),
                  _DescRow(text: '新添加的通道默认启用', context: context),
                ],
              ),
            ),
          ], context),
        ],
      ),
    );
  }

  Widget _buildChannelItem(int index, BuildContext context) {
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
                  '通道 ${index + 1}',
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
            controller: _webhookControllers[index],
            decoration: InputDecoration(
              hintText: 'https://example.com/webhook',
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
                    (_isTesting && _testIndex == index) ? '测试中' : '测试',
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
                    child: Text(
                      _testResult!,
                      style: TextStyle(
                        fontSize: 12,
                        color: _testSuccess == true
                            ? AppColors.green
                            : AppColors.red,
                      ),
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
    final url = urlStr.trim().toLowerCase();
    String typeName;
    IconData icon;
    Color color;
    String desc;

    if (url.contains('qyapi.weixin.qq.com') || url.contains('weixin.qq.com')) {
      typeName = '企业微信';
      icon = Icons.chat;
      color = const Color(0xFF07C160);
      desc = '文本格式推送';
    } else if (url.contains('oapi.dingtalk.com') || url.contains('dingtalk')) {
      typeName = '钉钉';
      icon = Icons.work;
      color = const Color(0xFF1677FF);
      desc = '文本格式推送';
    } else if (url.contains('feishu.cn') || url.contains('larksuite.com')) {
      typeName = '飞书';
      icon = Icons.flight;
      color = AppColors.blue;
      desc = '文本格式推送';
    } else if (url.isEmpty) {
      typeName = '待输入';
      icon = Icons.link_off;
      color = const Color(0xFF8E8E93);
      desc = '请输入 Webhook URL';
    } else {
      typeName = '通用 JSON';
      icon = Icons.code;
      color = const Color(0xFFFF9500);
      desc = '自定义 JSON 格式';
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
