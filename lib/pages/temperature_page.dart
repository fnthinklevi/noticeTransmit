import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:get_it/get_it.dart';
import '../l10n/app_localizations.dart';
import '../services/temperature_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_text_selection_menu.dart';
import '../widgets/card_action_sheet.dart';

/// 自建应用通道体系的温度规则设置页（与 BatteryPage 同级独立入口）。
///
/// 支持三种温度维度规则：电池温度 / 设备整体温度 / 屏幕温度。
/// 阈值滑块 30-90℃，crossing + 30 分钟冷却防抖。
///
/// ⚠ 数据源是 [TemperatureService] 本身（订阅），**不是构造时传进来的列表**：
/// 本页是路由推进去的，父页 setState 重建不到它，而服务的写操作是整体换新列表 ——
/// 传快照的结果就是"保存后不刷新、开关点完弹回"（T16 的病灶）。
class TemperaturePage extends StatefulWidget {
  const TemperaturePage({super.key});

  @override
  State<TemperaturePage> createState() => _TemperaturePageState();
}

class _TemperaturePageState extends State<TemperaturePage> {
  final TemperatureService _service = GetIt.instance<TemperatureService>();

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    // 服务是 GetIt 里的长生命周期单例：只摘监听，不 dispose
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
        title: Text(l10n.temperatureTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l10n.addRule,
            onPressed: _service.notifyEnabled ? _showAddRuleDialog : null,
          ),
        ],
      ),
      body: rules.isEmpty
          ? Center(
              child: Text(
                l10n.noRules,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
            )
          : ListView.builder(
              itemCount: rules.length,
              itemBuilder: (context, index) =>
                  _buildRuleTile(context, rules[index], l10n),
            ),
    );
  }

  Widget _buildRuleTile(
    BuildContext context,
    Map<String, dynamic> rule,
    AppLocalizations l10n,
  ) {
    final enabled = rule['enabled'] == true;
    final title = rule['title']?.toString() ?? '';
    final type = rule['type']?.toString() ?? '';
    final value = rule['value'] ?? 0;
    final dimLabel = _dimLabel(type, l10n);
    final id = rule['id']?.toString() ?? '';

    return Slidable(
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        children: [
          SlidableAction(
            onPressed: (_) => _service.deleteRule(id),
            backgroundColor: AppColors.red,
            foregroundColor: Colors.white,
            icon: Icons.delete_outline,
            label: l10n.delete,
          ),
          SlidableAction(
            onPressed: (_) => _service.toggleRule(id, !enabled),
            backgroundColor: AppColors.blue,
            foregroundColor: Colors.white,
            icon: enabled ? Icons.pause : Icons.play_arrow,
            label: enabled ? l10n.disable : l10n.enable,
          ),
        ],
      ),
      child: ListTile(
        onTap: () => _showEditRuleDialog(rule),
        // T05：滑出动作要先横向拖一下才看得见，长按菜单把同一批动作摆到一个
        // 不用发现的入口里（共用组件见 [CardActionSheet]）
        onLongPress: () => _showRuleActions(rule),
        title: Text(
          title.isNotEmpty ? title : dimLabel,
          style: TextStyle(
            fontSize: 15,
            color: enabled
                ? AppColors.primaryLabel(context)
                : AppColors.secondaryLabel(context),
          ),
        ),
        subtitle: Text(
          '$dimLabel ≥ $value℃',
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
    );
  }

  /// T05 长按菜单：修改 / 复制 / 暂停|恢复 / 删除（任务书里"温度规则再加暂停"那条）。
  ///
  /// ⚠ 「删除」走的是与滑出按钮同一条 service 调用，**都还没有二次确认**；
  /// 把两类通道的删除统一成"一律二次确认"是 T06（届时这两个入口一起改，不留半成品）。
  Future<void> _showRuleActions(Map<String, dynamic> rule) async {
    final l10n = AppLocalizations.of(context);
    final id = rule['id']?.toString() ?? '';
    final enabled = rule['enabled'] == true;
    final title = rule['title']?.toString() ?? '';
    await CardActionSheet.show(
      context,
      title: title.isEmpty
          ? _dimLabel(rule['type']?.toString() ?? '', l10n)
          : title,
      actions: [
        CardAction(
          icon: Icons.settings_outlined,
          label: l10n.edit,
          onTap: () => _showEditRuleDialog(rule),
        ),
        CardAction(
          icon: Icons.copy,
          label: l10n.duplicate,
          onTap: () => _duplicateRule(rule, title),
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
          onTap: () => _service.deleteRule(id),
        ),
      ],
    );
  }

  /// 复制规则：**换新 id**（`updateRule`/`deleteRule` 都按 id 找，两条同 id 会一次改中两条）。
  void _duplicateRule(Map<String, dynamic> rule, String title) {
    final l10n = AppLocalizations.of(context);
    _service.addRule({
      ...rule,
      'id': 'temp_rule_${DateTime.now().millisecondsSinceEpoch}',
      'title': l10n.copyOfName(title),
    });
  }

  String _dimLabel(String type, AppLocalizations l10n) {
    switch (type) {
      case 'battery_temp_above':
        return l10n.batteryTempAbove;
      case 'screen_temp_above':
        return l10n.screenTempAbove;
      case 'device_temp_above':
        return l10n.deviceTempAbove;
      default:
        return type;
    }
  }

  // ── 添加 / 编辑规则弹窗 ──────────────────────────────────────────────

  void _showAddRuleDialog() {
    _showRuleDialog(null);
  }

  void _showEditRuleDialog(Map<String, dynamic> rule) {
    _showRuleDialog(rule);
  }

  void _showRuleDialog(Map<String, dynamic>? existingRule) {
    final l10n = AppLocalizations.of(context);
    final isEdit = existingRule != null;
    final valueController = TextEditingController(
      text: (existingRule?['value'] ?? 45).toString(),
    );
    final titleController = TextEditingController(
      text: existingRule?['title'] ?? '',
    );
    String selectedType = existingRule?['type'] ?? 'battery_temp_above';
    int selectedValue = existingRule?['value'] ?? 45;
    // 温度维度固定为温度类型 → 滑块始终 ℃ 30-90

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.cardBg(context),
              title: Text(
                isEdit ? l10n.editRule : l10n.addRule,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryLabel(context),
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        l10n.ruleType,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.secondaryLabel(context),
                        ),
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildTypeChip(
                          'battery_temp_above',
                          l10n.batteryTempAbove,
                          selectedType,
                          setDialogState,
                          (v) => selectedType = v,
                          context,
                        ),
                        _buildTypeChip(
                          'device_temp_above',
                          l10n.deviceTempAbove,
                          selectedType,
                          setDialogState,
                          (v) => selectedType = v,
                          context,
                        ),
                        _buildTypeChip(
                          'screen_temp_above',
                          l10n.screenTempAbove,
                          selectedType,
                          setDialogState,
                          (v) => selectedType = v,
                          context,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        l10n.tempThreshold,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.secondaryLabel(context),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.inputBg(context),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Slider(
                              value: selectedValue.toDouble(),
                              min: 30,
                              max: 90,
                              divisions: 60,
                              label: '$selectedValue℃',
                              activeColor: AppColors.blue,
                              onChanged: (v) {
                                setDialogState(() {
                                  selectedValue = v.round();
                                  valueController.text = selectedValue
                                      .toString();
                                });
                              },
                            ),
                          ),
                          SizedBox(
                            width: 50,
                            child: Text(
                              '$selectedValue℃',
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primaryLabel(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        l10n.customTitle,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.secondaryLabel(context),
                        ),
                      ),
                    ),
                    TextField(
                      contextMenuBuilder: AppTextSelectionMenu.editableText,
                      controller: titleController,
                      decoration: InputDecoration(
                        hintText: l10n.customTitleHint,
                        hintStyle: TextStyle(
                          color: AppColors.secondaryLabel(context),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: AppColors.separator(context),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppColors.blue),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      style: TextStyle(color: AppColors.primaryLabel(context)),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    l10n.cancel,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.secondaryLabel(context),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    final id = isEdit
                        ? existingRule['id'] as String? ?? ''
                        : 'temp_rule_${DateTime.now().millisecondsSinceEpoch}';
                    final newRule = {
                      'id': id,
                      'type': selectedType,
                      'value': selectedValue,
                      'enabled': existingRule?['enabled'] ?? true,
                      'title': titleController.text.trim().isNotEmpty
                          ? titleController.text.trim()
                          : _defaultTitleForType(selectedType, selectedValue),
                      'content': '',
                    };
                    if (isEdit) {
                      _service.updateRule(id, newRule);
                    } else {
                      _service.addRule(newRule);
                    }
                    Navigator.pop(context);
                  },
                  child: Text(
                    isEdit ? l10n.save : l10n.add,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.blue,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildTypeChip(
    String type,
    String label,
    String selectedType,
    StateSetter setDialogState,
    void Function(String) onTypeChanged,
    BuildContext context,
  ) {
    final isSelected = selectedType == type;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.blue : AppColors.inputBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? AppColors.blue : AppColors.separator(context),
        ),
      ),
      child: TextButton(
        onPressed: () {
          setDialogState(() {
            onTypeChanged(type);
          });
        },
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: isSelected ? Colors.white : AppColors.primaryLabel(context),
          ),
        ),
      ),
    );
  }

  String _defaultTitleForType(String type, int value) {
    final l10n = AppLocalizations.of(context);
    switch (type) {
      case 'battery_temp_above':
        return l10n.ruleBatteryTempAbove(value);
      case 'device_temp_above':
        return l10n.ruleDeviceTempAbove(value);
      case 'screen_temp_above':
        return l10n.ruleScreenTempAbove(value);
      default:
        return l10n.batteryReminder;
    }
  }
}
