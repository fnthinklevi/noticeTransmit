import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../l10n/app_localizations.dart';
import '../services/device_state_service.dart';
import '../theme/app_colors.dart';
import '../widgets/card_action_sheet.dart';
import '../widgets/ios_dialog_actions.dart';

/// 设备状态告警页（T24）：亮度与网络两类**设备态触发源**的规则都在这里。
///
/// 形状与 `BatteryPage` / `TemperaturePage` 一致（订阅服务，不传快照 —— 本页是路由推进去的，
/// 父页 `setState` 到不了它，T16 的病灶）。两族放在一起是刻意的：它们问的是同一个问题
/// （"设备到了某个状态要不要提醒我"），而引擎按 type 路由、存储也只有一族 ——
/// 拆成两页就会多出一份镜像键、一条重载链路与两份"30 分钟内不重复"的解释。
///
/// 触发语义（跨越才算事件、冷却、读不到不判定）**不在这里实现**，页面只负责把规则
/// 递进 `engine_rules` 表；判据只有 `NotificationEngine` 那一份（T19/T21 的结论）。
class DeviceStatePage extends StatefulWidget {
  const DeviceStatePage({super.key});

  @override
  State<DeviceStatePage> createState() => _DeviceStatePageState();
}

class _DeviceStatePageState extends State<DeviceStatePage> {
  final DeviceStateService _service = GetIt.instance<DeviceStateService>();

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    // 服务是 GetIt 里的长生命周期单例：只摘监听，不 dispose。
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rules = _service.rules;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.deviceStateEntry),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l10n.addRule,
            onPressed: _service.notifyEnabled
                ? () => _showRuleDialog(null)
                : null,
          ),
        ],
      ),
      body: rules.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  // 不用 `noRules` —— 那条文案明写"暂无温度规则"，借过来会告诉用户
                  // 他们在温度页上没配过东西（本页是亮度与网络）。
                  l10n.noDeviceStateRules,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text(
                  l10n.deviceStateDesc,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
                const SizedBox(height: 12),
                for (final rule in rules) _ruleCard(l10n, rule),
              ],
            ),
    );
  }

  Widget _ruleCard(AppLocalizations l10n, Map<String, dynamic> rule) {
    final id = rule['id']?.toString() ?? '';
    final type = rule['type']?.toString() ?? '';
    final title = rule['title']?.toString() ?? '';
    final enabled = rule['enabled'] == true;
    final isBrightness = DeviceStateService.brightnessTypes.contains(type);
    final label = title.isNotEmpty ? title : _typeLabel(l10n, type);
    // 副标题只放"这一条还带什么信息"：亮度型是阈值，网络型没有第二个数字可写。
    // 拿类型名当副标题会让同一句话在一张卡里出现两遍（列表里就是两行同样的字）。
    final subtitle = isBrightness ? '阈值 ${rule['value'] ?? 0}%' : null;
    return Container(
      // 按标题定位控件在"改了名"或"两条同名"时会一次打中两个 ⇒ 每行给一个稳定 key。
      key: ValueKey('device-state-row-$id'),
      margin: const EdgeInsets.only(bottom: 8),
      // 底色与边框必须挂在 **Material 自己**身上，不能放在外层 Container 的
      // BoxDecoration 里：ListTile 的 ink 只画在最近的**不透明 Material** 上，
      // 中间夹一层带色 DecoratedBox 就是把水波纹画到背景之下
      // （本仓库撞过两次，见 [CardActionSheet] 与 app_channel_settings_page）。
      child: Material(
        color: AppColors.cardBg(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.separator(context)),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: () => _showRuleDialog(rule),
          onLongPress: () => _showRuleActions(rule, id, label, enabled),
          // 亮度/网络是**设备态**触发，没有"某个应用"的图标可显示 ⇒ 用类型图标代替。
          leading: Icon(_icon(type), color: _iconColor(type)),
          title: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              color: enabled
                  ? AppColors.primaryLabel(context)
                  : AppColors.secondaryLabel(context),
            ),
          ),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
          trailing: CupertinoSwitch(
            value: enabled,
            activeTrackColor: AppColors.blue,
            onChanged: (v) => _service.toggleRule(id, v),
          ),
        ),
      ),
    );
  }

  Future<void> _showRuleActions(
    Map<String, dynamic> rule,
    String id,
    String label,
    bool enabled,
  ) async {
    final l10n = AppLocalizations.of(context);
    await CardActionSheet.show(
      context,
      title: label,
      actions: [
        CardAction(
          icon: Icons.settings_outlined,
          label: l10n.edit,
          onTap: () => _showRuleDialog(rule),
        ),
        CardAction(
          icon: Icons.copy,
          label: l10n.duplicate,
          onTap: () => _duplicateRule(rule, label),
        ),
        CardAction(
          icon: enabled ? Icons.pause : Icons.play_arrow,
          label: enabled ? l10n.disable : l10n.enable,
          iconColor: enabled ? AppColors.orange : AppColors.green,
          onTap: () => _service.toggleRule(id, !enabled),
        ),
        CardAction(
          icon: Icons.delete_outline,
          label: l10n.delete,
          danger: true,
          onTap: () => _confirmDeleteRule(id, label),
        ),
      ],
    );
  }

  /// 删除一律二次确认（T06）：阈值是拖滑块调出来的，重建一次并不便宜。
  Future<void> _confirmDeleteRule(String id, String label) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await IosDialogActions.askConfirm(
      context,
      title: l10n.confirmDeleteRule,
      message: l10n.confirmDeleteRuleMsg(label),
      confirmText: l10n.delete,
    );
    if (!confirmed) return;
    await _service.deleteRule(id);
  }

  /// 复制必须换 id：`updateRule` / `deleteRule` 都按 id 找，两条同 id 会一次改中两条。
  void _duplicateRule(Map<String, dynamic> rule, String label) {
    final l10n = AppLocalizations.of(context);
    _service.addRule({
      ...rule,
      'id': 'device_rule_${DateTime.now().millisecondsSinceEpoch}',
      'title': l10n.copyOfName(label),
    });
  }

  // ── 类型标签 / 图标 ────────────────────────────────────────────────

  String _typeLabel(AppLocalizations l10n, String type) => switch (type) {
    'brightness_below' => l10n.brightnessBelow,
    'brightness_above' => l10n.brightnessAbove,
    'network_connected' => l10n.networkConnected,
    'network_disconnected' => l10n.networkDisconnected,
    // 未知类型原样显示：宁可显示黑话，也不要凭空套一个不相干的标签
    // （引擎认识新类型而这里没跟上时，这条就是现场）。
    _ => type,
  };

  IconData _icon(String type) => switch (type) {
    'brightness_below' => Icons.brightness_low,
    'brightness_above' => Icons.brightness_high,
    'network_connected' => Icons.wifi,
    'network_disconnected' => Icons.wifi_off,
    _ => Icons.help_outline,
  };

  Color _iconColor(String type) =>
      DeviceStateService.brightnessTypes.contains(type)
      ? AppColors.orange
      : AppColors.blue;

  // ── 添加 / 编辑规则弹窗 ─────────────────────────────────────────────

  void _showRuleDialog(Map<String, dynamic>? existingRule) {
    final l10n = AppLocalizations.of(context);
    final isEdit = existingRule != null;
    final titleController = TextEditingController(
      text: existingRule?['title'] ?? '',
    );
    String selectedType = existingRule?['type'] ?? 'brightness_below';
    int selectedValue =
        existingRule?['value'] ?? DeviceStateService.minBrightness * 2;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isBrightness = DeviceStateService.brightnessTypes.contains(
            selectedType,
          );
          return AlertDialog(
            backgroundColor: AppColors.cardBg(context),
            title: Text(isEdit ? l10n.editRule : l10n.addRule),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final type in const [
                        'brightness_below',
                        'brightness_above',
                        'network_disconnected',
                        'network_connected',
                      ])
                        ChoiceChip(
                          label: Text(_typeLabel(l10n, type)),
                          selected: selectedType == type,
                          onSelected: (_) => setDialogState(() {
                            selectedType = type;
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (isBrightness) ...[
                    Text(
                      l10n.deviceStateValueLabel,
                      style: const TextStyle(fontSize: 13),
                    ),
                    Slider(
                      value: selectedValue
                          .clamp(
                            DeviceStateService.minBrightness,
                            DeviceStateService.maxBrightness,
                          )
                          .toDouble(),
                      min: DeviceStateService.minBrightness.toDouble(),
                      max: DeviceStateService.maxBrightness.toDouble(),
                      divisions:
                          DeviceStateService.maxBrightness -
                          DeviceStateService.minBrightness,
                      label: '$selectedValue%',
                      onChanged: (v) =>
                          setDialogState(() => selectedValue = v.round()),
                    ),
                  ] else
                    Text(
                      l10n.deviceStateNoValue,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.secondaryLabel(context),
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      hintText: l10n.customTitleHint,
                      hintStyle: TextStyle(
                        color: AppColors.secondaryLabel(context),
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l10n.cancel),
              ),
              TextButton(
                onPressed: () => _submit(dialogContext, existingRule, {
                  'type': selectedType,
                  // 网络型没有阈值概念，但存储列不接受 null ⇒ 恒 0（引擎也不看它）
                  'value': isBrightness ? selectedValue : 0,
                  'title': titleController.text.trim(),
                }),
                child: Text(l10n.confirm),
              ),
            ],
          );
        },
      ),
    );
  }

  void _submit(
    BuildContext dialogContext,
    Map<String, dynamic>? existingRule,
    Map<String, dynamic> fields,
  ) {
    final id =
        existingRule?['id']?.toString() ??
        'device_rule_${DateTime.now().millisecondsSinceEpoch}';
    final next = <String, dynamic>{
      'id': id,
      'enabled': existingRule?['enabled'] ?? true,
      'content': existingRule?['content'] ?? '',
      ...fields,
    };
    final editing = existingRule != null;
    Navigator.of(dialogContext).pop();
    if (editing) {
      _service.updateRule(id, next);
    } else {
      _service.addRule(next);
    }
  }
}
