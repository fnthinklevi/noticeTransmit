import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../l10n/app_localizations.dart';
import '../services/platform_channel.dart';
import '../theme/app_colors.dart';

class BatteryPage extends StatefulWidget {
  final bool notifyEnabled;
  final List<Map<String, dynamic>> rules;
  final int currentLevel;
  final bool isCharging;
  final ValueChanged<bool> onToggleNotify;
  final void Function(Map<String, dynamic>) onAddRule;
  final void Function(String) onDeleteRule;
  final void Function(String, Map<String, dynamic>) onUpdateRule;
  final void Function(String, bool) onToggleRule;
  final Future<void> Function() onRefresh;

  const BatteryPage({
    super.key,
    required this.notifyEnabled,
    required this.rules,
    required this.currentLevel,
    required this.isCharging,
    required this.onToggleNotify,
    required this.onAddRule,
    required this.onDeleteRule,
    required this.onUpdateRule,
    required this.onToggleRule,
    required this.onRefresh,
  });

  @override
  State<BatteryPage> createState() => _BatteryPageState();
}

class _BatteryPageState extends State<BatteryPage> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final batteryColor = widget.currentLevel >= 50
        ? AppColors.green
        : widget.currentLevel >= 20
        ? const Color(0xFFFF9500)
        : AppColors.red;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.batteryTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l10n.addRule,
            onPressed: widget.notifyEnabled ? _showAddRuleDialog : null,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const SizedBox(height: 16),
            Center(
              child: Column(
                children: [
                  Icon(
                    widget.isCharging
                        ? Icons.battery_charging_full
                        : Icons.battery_full,
                    size: 80,
                    color: batteryColor,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.currentLevel < 0
                        ? l10n.unknown
                        : '${widget.currentLevel}%',
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w300,
                      color: batteryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.isCharging ? l10n.charging : l10n.notCharging,
                    style: TextStyle(
                      fontSize: 15,
                      color: AppColors.secondaryLabel(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            _buildSectionHeader(l10n.reminderSettings, context),
            _buildGroup([
              _buildSwitchRow(
                icon: Icons.power_settings_new,
                iconColor: AppColors.blue,
                title: l10n.batteryNotifToggle,
                subtitle: l10n.batteryNotifToggleDesc,
                value: widget.notifyEnabled,
                onChanged: _handleToggleNotify,
                context: context,
              ),
            ], context),
            const SizedBox(height: 24),
            _buildSectionHeader(l10n.notifRules, context),
            _buildGroup(
              widget.rules.asMap().entries.map((entry) {
                final index = entry.key;
                final rule = entry.value;
                return Column(
                  children: [
                    if (index > 0) _buildDivider(context),
                    _buildRuleTile(rule, context),
                  ],
                );
              }).toList(),
              context,
            ),
            const SizedBox(height: 24),
            _buildSectionHeader(l10n.notes, context),
            _buildGroup([
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DescRow(text: l10n.batteryNotes1, context: context),
                    const SizedBox(height: 8),
                    _DescRow(text: l10n.batteryNotes2, context: context),
                    const SizedBox(height: 8),
                    _DescRow(text: l10n.batteryNotes3, context: context),
                    const SizedBox(height: 8),
                    _DescRow(text: l10n.batteryNotes4, context: context),
                  ],
                ),
              ),
            ], context),
          ],
        ),
      ),
    );
  }

  static const String _batteryOptPromptShownKey = 'battery_opt_prompt_shown';

  /// 首次启用电量通知时，检查是否已被电池优化限制；若未豁免则引导用户关闭。
  Future<void> _maybePromptBatteryOptimization() async {
    try {
      final ignored =
          await AppChannels.notification.invokeMethod<bool>(
            'isIgnoringBatteryOptimizations',
          ) ??
          false;
      if (ignored) return;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_batteryOptPromptShownKey) ?? false) return;
      await prefs.setBool(_batteryOptPromptShownKey, true);
      if (!mounted) return;
      _showBatteryOptimizationDialog();
    } catch (_) {}
  }

  void _handleToggleNotify(bool v) {
    if (v) _maybePromptBatteryOptimization();
    widget.onToggleNotify(v);
  }

  void _handleToggleRule(String id, bool v) {
    if (v) _maybePromptBatteryOptimization();
    widget.onToggleRule(id, v);
  }

  void _handleAddRule(Map<String, dynamic> rule) {
    _maybePromptBatteryOptimization();
    widget.onAddRule(rule);
  }

  void _showBatteryOptimizationDialog() {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.cardBg(context),
          title: Text(
            l10n.closeBatteryOpt,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryLabel(context),
            ),
          ),
          content: Text(
            l10n.batteryOptDesc,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.secondaryLabel(context),
              height: 1.4,
            ),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                l10n.notNow,
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                AppChannels.notification.invokeMethod(
                  'requestBatteryOptimization',
                );
              },
              child: Text(
                l10n.goSettings,
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
  }

  Widget _buildRuleTile(Map<String, dynamic> rule, BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final type = rule['type'] as String? ?? 'unknown';
    final value = rule['value'] as int? ?? 0;
    final enabled = rule['enabled'] as bool? ?? false;
    final title = rule['title'] as String? ?? '';

    IconData icon;
    Color iconColor;
    String subtitle;

    switch (type) {
      case 'charging':
        icon = Icons.battery_charging_full;
        iconColor = AppColors.green;
        subtitle = l10n.ruleStartCharging;
        break;
      case 'discharging':
        icon = Icons.battery_0_bar;
        iconColor = const Color(0xFFFF9500);
        subtitle = l10n.ruleStopCharging;
        break;
      case 'level_above':
        icon = Icons.battery_full;
        iconColor = AppColors.blue;
        subtitle = l10n.ruleAboveThreshold(value);
        break;
      case 'level_below':
        icon = Icons.battery_alert;
        iconColor = AppColors.red;
        subtitle = l10n.ruleBelowThreshold(value);
        break;
      case 'level_equals':
        icon = Icons.equalizer;
        iconColor = const Color(0xFFAF52DE);
        subtitle = l10n.ruleEqualThreshold(value);
        break;
      default:
        icon = Icons.help_outline;
        iconColor = Colors.grey;
        subtitle = l10n.ruleUnknown;
    }

    return _buildSlidableRuleTile(
      rule,
      icon,
      iconColor,
      title,
      subtitle,
      enabled,
    );
  }

  Widget _buildSlidableRuleTile(
    Map<String, dynamic> rule,
    IconData icon,
    Color iconColor,
    String title,
    String subtitle,
    bool enabled,
  ) {
    final l10n = AppLocalizations.of(context);
    final ruleId = rule['id'] as String? ?? '';
    return Slidable(
      key: ValueKey(ruleId),
      // 仅从右侧拖出固定宽度的红色删除按钮，内容只左移按钮宽度，不会整条滑走
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.28,
        children: [
          SlidableAction(
            onPressed: (_) async {
              if (!widget.notifyEnabled) return;
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(l10n.confirmDeleteRule),
                  content: Text(l10n.confirmDeleteRuleMsg(title)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: Text(l10n.cancel),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.red,
                      ),
                      child: Text(l10n.delete),
                    ),
                  ],
                ),
              );
              if (confirmed == true) widget.onDeleteRule(ruleId);
            },
            backgroundColor: AppColors.red,
            foregroundColor: Colors.white,
            icon: Icons.delete_outline,
            label: l10n.delete,
          ),
        ],
      ),
      child: Container(
        color: AppColors.cardBg(context),
        child: InkWell(
          onTap: widget.notifyEnabled && enabled
              ? () => _showEditRuleDialog(rule)
              : null,
          onLongPress: widget.notifyEnabled
              ? () => _showDeleteConfirmDialog(ruleId)
              : null,
          child: _buildSwitchRow(
            icon: icon,
            iconColor: iconColor,
            title: title,
            subtitle: subtitle,
            value: enabled,
            onChanged: widget.notifyEnabled
                ? (v) => _handleToggleRule(ruleId, v)
                : null,
            context: context,
            trailing: null,
          ),
        ),
      ),
    );
  }

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
      text: (existingRule?['value'] ?? 20).toString(),
    );
    final titleController = TextEditingController(
      text: existingRule?['title'] ?? '',
    );
    String selectedType = existingRule?['type'] ?? 'level_below';
    int selectedValue = existingRule?['value'] ?? 20;

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
                          'charging',
                          l10n.startCharging,
                          selectedType,
                          setDialogState,
                          (v) => selectedType = v,
                          context,
                        ),
                        _buildTypeChip(
                          'discharging',
                          l10n.stopCharging,
                          selectedType,
                          setDialogState,
                          (v) => selectedType = v,
                          context,
                        ),
                        _buildTypeChip(
                          'level_below',
                          l10n.belowValue,
                          selectedType,
                          setDialogState,
                          (v) => selectedType = v,
                          context,
                        ),
                        _buildTypeChip(
                          'level_above',
                          l10n.aboveValue,
                          selectedType,
                          setDialogState,
                          (v) => selectedType = v,
                          context,
                        ),
                        _buildTypeChip(
                          'level_equals',
                          l10n.equalValue,
                          selectedType,
                          setDialogState,
                          (v) => selectedType = v,
                          context,
                        ),
                      ],
                    ),
                    if ([
                      'level_below',
                      'level_above',
                      'level_equals',
                    ].contains(selectedType)) ...[
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          l10n.threshold,
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
                                min: 1,
                                max: 100,
                                divisions: 99,
                                label: '$selectedValue%',
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
                                '$selectedValue%',
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
                    ],
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
                        : 'rule_${DateTime.now().millisecondsSinceEpoch}';
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
                      widget.onUpdateRule(id, newRule);
                    } else {
                      _handleAddRule(newRule);
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
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.white : AppColors.primaryLabel(context),
          ),
        ),
      ),
    );
  }

  String _defaultTitleForType(String type, int value) {
    final l10n = AppLocalizations.of(context);
    switch (type) {
      case 'charging':
        return l10n.startCharging;
      case 'discharging':
        return l10n.stopCharging;
      case 'level_above':
        return l10n.ruleAboveThreshold(value);
      case 'level_below':
        return l10n.ruleBelowThreshold(value);
      case 'level_equals':
        return l10n.ruleEqualThreshold(value);
      default:
        return l10n.batteryReminder;
    }
  }

  void _showDeleteConfirmDialog(String id) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.cardBg(context),
          title: Text(
            l10n.deleteRule,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryLabel(context),
            ),
          ),
          content: Text(
            l10n.confirmDeleteThisRule,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.secondaryLabel(context),
            ),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                l10n.cancel,
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.red),
              onPressed: () {
                widget.onDeleteRule(id);
                Navigator.pop(context);
              },
              child: Text(
                l10n.delete,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.red,
                ),
              ),
            ),
          ],
        );
      },
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

  Widget _buildDivider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 52),
      child: Divider(
        height: 0.5,
        thickness: 0.5,
        color: AppColors.separator(context),
      ),
    );
  }

  Widget _buildSwitchRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
    required BuildContext context,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: iconColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.primaryLabel(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
              ],
            ),
          ),
          trailing ?? const SizedBox.shrink(),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
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
