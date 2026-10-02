import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:get_it/get_it.dart';
import '../l10n/app_localizations.dart';
import '../services/battery_service.dart';
import '../services/platform_channel.dart';
import '../services/temperature_service.dart';
import '../theme/app_colors.dart';
import '../widgets/card_action_sheet.dart';
import '../widgets/engine_page_sections.dart';
import '../widgets/ios_dialog_actions.dart';
import '../widgets/pull_to_refresh_list.dart';
import '../widgets/app_text_selection_menu.dart';

/// 电量告警设置页（「通知引擎」tab 的一个入口，规则列表 + 当前电量）。
///
/// ⚠ 数据源是 [BatteryService] 本身（订阅），**不是构造时传进来的快照**：
/// 本页现在是骨架页 push 出去的子页，父页 setState 重建不到它，而服务的写操作是
/// 整体换新列表 —— 传快照的结果就是"保存后不刷新、开关点完弹回"（T16 的病灶）。
/// 电量读数的色调档位。**纯函数**：色调是"这一眼该让人看出什么"，与界面无关，
/// 所以要能脱离 widget 树测（三页统一版式时立下的判据：读不到 ≠ 危险）。
enum BatteryTone { unknown, good, warn, critical }

/// `level < 0` 是"这台设备读不到电量"，必须走 [BatteryTone.unknown]。
/// 以前它顺着 `>= 20` 一路掉进红色档 ⇒ 顶部写着「未知」、图标与数字却是"电量已低于阈值"的红，
/// 等于把"没有数"报成"出事了"（1.5.76 实拍三页时发现的，温度页当时已按中性色改）。
BatteryTone batteryToneOf(int level) {
  if (level < 0) return BatteryTone.unknown;
  if (level >= 50) return BatteryTone.good;
  if (level >= 20) return BatteryTone.warn;
  return BatteryTone.critical;
}

class BatteryPage extends StatefulWidget {
  const BatteryPage({super.key});

  @override
  State<BatteryPage> createState() => _BatteryPageState();
}

class _BatteryPageState extends State<BatteryPage> {
  final BatteryService _service = GetIt.instance<BatteryService>();

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
    final batteryColor = switch (batteryToneOf(_service.currentLevel)) {
      BatteryTone.unknown => AppColors.tertiaryLabel(context),
      BatteryTone.good => AppColors.green,
      BatteryTone.warn => AppColors.orange,
      BatteryTone.critical => AppColors.red,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.batteryTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l10n.addRule,
            onPressed: _service.notifyEnabled ? _showAddRuleDialog : null,
          ),
        ],
      ),
      body: PullToRefreshList(
        onRefresh: _service.refreshStatus,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const SizedBox(height: 16),
          EngineReadoutHeader(
            icon: _service.currentIsCharging
                ? Icons.battery_charging_full
                : Icons.battery_full,
            iconColor: batteryColor,
            value: _service.currentLevel < 0
                ? l10n.unknown
                : '${_service.currentLevel}%',
            caption: _service.currentIsCharging
                ? l10n.charging
                : l10n.notCharging,
          ),
          const SizedBox(height: 32),
          EngineSection(
            title: l10n.reminderSettings,
            children: [
              EngineSwitchRow(
                icon: Icons.power_settings_new,
                iconColor: AppColors.blue,
                title: l10n.batteryNotifToggle,
                subtitle: l10n.notifToggleDesc,
                value: _service.notifyEnabled,
                onChanged: _handleToggleNotify,
                context: context,
              ),
            ],
          ),
          const SizedBox(height: 24),
          EngineSection(
            title: l10n.notifRules,
            divided: true,
            children: [
              for (final rule in _service.rules) _buildRuleTile(rule, context),
            ],
          ),
          const SizedBox(height: 24),
          EngineSection(
            title: l10n.notes,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EngineNoteRow(text: l10n.batteryNotes1, context: context),
                    const SizedBox(height: 8),
                    EngineNoteRow(text: l10n.batteryNotes2, context: context),
                    const SizedBox(height: 8),
                    EngineNoteRow(text: l10n.batteryNotes3, context: context),
                    const SizedBox(height: 8),
                    EngineNoteRow(text: l10n.batteryNotes4, context: context),
                  ],
                ),
              ),
            ],
          ),
        ],
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
    _service.saveNotifyEnabled(v);
  }

  void _handleToggleRule(String id, bool v) {
    if (v) _maybePromptBatteryOptimization();
    _service.toggleRule(id, v);
  }

  void _handleAddRule(Map<String, dynamic> rule) {
    _maybePromptBatteryOptimization();
    _service.addRule(rule);
  }

  Future<void> _showBatteryOptimizationDialog() async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    // T90 片13：外壳换成唯一装配点。顺序与换件前一致 —— 拿到答案之后才发那一发，
    // 「暂不」和「点外面」都是不发（`barrierDismissible: true` 照 Material 旧默认保留）。
    final goSettings = await IosDialogActions.askConfirm(
      context,
      title: l10n.closeBatteryOpt,
      message: l10n.batteryOptDesc,
      confirmText: l10n.goSettings,
      cancelText: l10n.notNow,
      destructive: false,
      barrierDismissible: true,
    );
    if (!goSettings) return;
    AppChannels.notification.invokeMethod('requestBatteryOptimization');
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
            onPressed: (_) => _confirmDeleteRule(ruleId, title),
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
          onTap: _service.notifyEnabled && enabled
              ? () => _showEditRuleDialog(rule)
              : null,
          onLongPress: _service.notifyEnabled
              ? () => _showRuleActions(rule, ruleId, title, enabled)
              : null,
          child: EngineSwitchRow(
            icon: icon,
            iconColor: iconColor,
            title: title,
            subtitle: subtitle,
            value: enabled,
            onChanged: _service.notifyEnabled
                ? (v) => _handleToggleRule(ruleId, v)
                : null,
            context: context,
          ),
        ),
      ),
    );
  }

  void _showAddRuleDialog() {
    _showRuleDialog(null);
  }

  /// T05 长按菜单（共用组件见 [CardActionSheet]）。此前长按直接弹删除确认，
  /// 等于把"长按 = 一整套动作"这条约定用掉了一次就没了。
  ///
  /// ⚠ 「删除」这里走的是既有的确认框（本页本来就有）；滑出删除按钮走的是**另一条**
  /// 没确认的路径 —— 两条统一到"删除一律二次确认"是 T06 的活，不在本批半途改。
  Future<void> _showRuleActions(
    Map<String, dynamic> rule,
    String ruleId,
    String title,
    bool enabled,
  ) async {
    final l10n = AppLocalizations.of(context);
    final canEdit = enabled;
    await CardActionSheet.show(
      context,
      title: title.isEmpty ? null : title,
      actions: [
        CardAction(
          icon: Icons.settings_outlined,
          label: l10n.edit,
          // 已停用的规则没有"编辑"入口（与整行 onTap 的既门口径一致）⇒ 置灰不藏
          onTap: canEdit ? () => _showEditRuleDialog(rule) : null,
        ),
        CardAction(
          icon: Icons.copy,
          label: l10n.duplicate,
          onTap: () => _duplicateRule(rule, title),
        ),
        CardAction(
          icon: enabled ? Icons.toggle_off : Icons.toggle_on,
          label: enabled ? l10n.turnOff : l10n.turnOn,
          iconColor: enabled ? AppColors.orange : AppColors.green,
          onTap: () => _handleToggleRule(ruleId, !enabled),
        ),
        CardAction(
          icon: Icons.delete_outline,
          label: l10n.delete,
          danger: true,
          onTap: () => _confirmDeleteRule(ruleId, title),
        ),
      ],
    );
  }

  /// 复制规则：**换新 id**（两条同 id 会让 `updateRule`/`deleteRule` 一次改中两条）。
  void _duplicateRule(Map<String, dynamic> rule, String title) {
    final l10n = AppLocalizations.of(context);
    _service.addRule({
      ...rule,
      'id': 'rule_${DateTime.now().millisecondsSinceEpoch}',
      'title': l10n.copyOfName(title),
    });
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
    // v1.59 温度维度：温度类型用 ℃ 滑块（30-90℃），电量类型用 % 滑块
    // 类型集合取 TemperatureService.tempRuleTypes（Dart 侧唯一定义处，与原生同字面量）
    final isTempType = TemperatureService.tempRuleTypes.contains(selectedType);

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
                                min: isTempType ? 30 : 1,
                                max: isTempType ? 90 : 100,
                                divisions: isTempType ? 60 : 99,
                                label: isTempType
                                    ? '$selectedValue℃'
                                    : '$selectedValue%',
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
                                isTempType
                                    ? '$selectedValue℃'
                                    : '$selectedValue%',
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
                      _service.updateRule(id, newRule);
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

  /// 删除规则 —— **滑出按钮与长按菜单共用这一条**（T06 的单一咽喉）。
  ///
  /// 以前这里是两份确认框，而且**措辞不同**：滑出的那条会点名是哪条规则，长按那条只说
  /// "确定删除此规则吗"。合并成一条，并取信息量大的那份（点名规则名）。
  Future<void> _confirmDeleteRule(String id, String title) async {
    if (!_service.notifyEnabled) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await IosDialogActions.askConfirm(
      context,
      title: l10n.confirmDeleteRule,
      message: l10n.confirmDeleteRuleMsg(title),
      confirmText: l10n.delete,
    );
    if (!confirmed) return;
    await _service.deleteRule(id);
  }

  // 版式（顶部大读数 / 分区标题 / 卡片分组 / 开关行 / 说明条目）已抽到
  // `widgets/engine_page_sections.dart`，由电量 / 温度 / 设备状态三页共用。
}
