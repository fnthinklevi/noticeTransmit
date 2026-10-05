import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:get_it/get_it.dart';
import '../l10n/app_localizations.dart';
import '../models/temperature_preview.dart';
import '../models/device_snapshot.dart';
import '../services/device_info_service.dart';
import '../services/temperature_service.dart';
import '../theme/app_colors.dart';
import '../widgets/ios_dialog_actions.dart';
import '../widgets/ios_form_dialog.dart';
import '../widgets/app_text_selection_menu.dart';
import '../widgets/card_action_sheet.dart';
import '../widgets/engine_page_sections.dart';
import '../widgets/pull_to_refresh_list.dart';

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
  final DeviceInfoService _device = GetIt.instance<DeviceInfoService>();

  /// 顶部那块实时读数（T17 的 `getDeviceSnapshot`，**一次调用**拿全）。
  /// null = 这次没读到（通道失败/超时）⇒ 界面必须明说"读不到"，不许画 0℃。
  DeviceSnapshot? _snap;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
    _loadReading();
  }

  /// 读数只服务于一行显示：拿不到就把旧值留着（下拉刷新与进页都各算一次尝试），
  /// 失败本身由 `unreadableField` 那句话表达，不额外弹窗。
  Future<void> _loadReading() async {
    final snap = await _device.getDeviceSnapshot();
    if (!mounted || snap == null) return;
    setState(() => _snap = snap);
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
    final temp = _snap?.batteryTemperatureC;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.temperatureTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.science_outlined),
            tooltip: l10n.tempTestEntry,
            // 空列表也允许点：原生会回 NO_RULES，界面就能说清"为什么一条都不会响"
            onPressed: () => _runPreview(_service.rules),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l10n.addRule,
            onPressed: _service.notifyEnabled ? _showAddRuleDialog : null,
          ),
        ],
      ),
      // 版式与电量页同构（顶部大读数 → 提醒设置 → 通知规则 → 说明）：
      // 三页本来各长各的，看着像三个产品。共用组件见 `widgets/engine_page_sections.dart`。
      body: PullToRefreshList(
        onRefresh: _loadReading,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const SizedBox(height: 16),
          EngineReadoutHeader(
            icon: Icons.thermostat,
            iconColor: _readingColor(context, temp),
            value: temp == null
                ? l10n.unreadableField
                : l10n.snapshotBatteryTempValue(temp.toStringAsFixed(1)),
            // 明写是**电池温度**：本页规则有三个维度，而快照只给得出这一路的实时值。
            // 顶着一个"当前温度"的名号显示别的传感器的数，比不显示更容易骗人。
            caption: l10n.snapshotBatteryTemp,
          ),
          const SizedBox(height: 32),
          EngineSection(
            title: l10n.reminderSettings,
            children: [
              EngineSwitchRow(
                icon: Icons.power_settings_new,
                iconColor: AppColors.blue,
                title: l10n.temperatureNotifyEnabled,
                subtitle: l10n.notifToggleDesc,
                value: _service.notifyEnabled,
                onChanged: (v) => _service.saveNotifyEnabled(v),
                context: context,
              ),
            ],
          ),
          const SizedBox(height: 24),
          EngineSection(
            title: l10n.notifRules,
            divided: rules.isNotEmpty,
            children: [
              if (rules.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    l10n.noRules,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.secondaryLabel(context),
                    ),
                  ),
                ),
              for (final rule in rules) _buildRuleTile(context, rule, l10n),
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
                    EngineNoteRow(
                      text: l10n.temperatureNotes1,
                      context: context,
                    ),
                    const SizedBox(height: 8),
                    EngineNoteRow(
                      text: l10n.temperatureNotes2,
                      context: context,
                    ),
                    const SizedBox(height: 8),
                    EngineNoteRow(
                      text: l10n.temperatureNotes3,
                      context: context,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 读数颜色只表达"热不热"，不重复规则的判据（阈值是用户自己配的）。
  /// 读不到时给中性色：红/绿都会把一个"没有数"的格子说成"安全"或"超限"。
  static Color _readingColor(BuildContext context, double? c) {
    if (c == null) return AppColors.tertiaryLabel(context);
    if (c >= 45) return AppColors.red;
    if (c >= 40) return AppColors.orange;
    return AppColors.green;
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
            onPressed: (_) =>
                _confirmDeleteRule(id, title.isNotEmpty ? title : dimLabel),
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
  Future<void> _showRuleActions(Map<String, dynamic> rule) async {
    final l10n = AppLocalizations.of(context);
    final id = rule['id']?.toString() ?? '';
    final enabled = rule['enabled'] == true;
    final title = rule['title']?.toString() ?? '';
    // 确认框与弹层标题都点名"是哪一条"：规则名可以留空（默认按维度显示）
    final label = title.isNotEmpty
        ? title
        : _dimLabel(rule['type']?.toString() ?? '', l10n);
    await CardActionSheet.show(
      context,
      title: label,
      actions: [
        CardAction(
          icon: Icons.settings_outlined,
          label: l10n.edit,
          onTap: () => _showEditRuleDialog(rule),
        ),
        CardAction(
          // T25：单条试跑 —— 判据在原生那一份里跑，这里只渲染结果。
          icon: Icons.science_outlined,
          label: l10n.tempTestEntry,
          onTap: () => _runPreview([rule]),
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
          onTap: () => _confirmDeleteRule(id, label),
        ),
      ],
    );
  }

  /// T25：把这一组规则交给原生试跑一次，结果显示在一个只读弹层里。
  Future<void> _runPreview(List<Map<String, dynamic>> rules) async {
    final l10n = AppLocalizations.of(context);
    final preview = await _service.previewTest(rules);
    if (!mounted) return;
    // T90 片28：Material `AlertDialog` 台账上的**最后一枚**，收进
    // `IosDialogActions.showExplainer`（片26 为规则引导建的那一枚）。
    // ⚠ **为什么不是 `showInfo`**：那一族的正文只能是一句（`Text(message)`），而这里是一段
    // 多行读数 —— 压进去就得给 `message` 开 `Widget?` 口，那会让 `showInfo` 不再是「只读说明框」。
    // 动作文案经 `gotItText` 从默认的「好的」换成「关闭」（这一枚原来就是「关闭」）。
    // `barrierDismissible` 两边默认都是可点穿（Material `showDialog` 与这一族一致），没变。
    await IosDialogActions.showExplainer(
      context,
      title: l10n.tempTestTitle,
      gotItText: l10n.close,
      // ⚠ 旧形状 content 里那层 `SingleChildScrollView` **删掉了**：`CupertinoAlertDialog`
      // 自己就把 title+content 整组包进 `SingleChildScrollView`（flutter/cupertino/dialog.dart:2042）
      // ⇒ 留着就是滚动视图套滚动视图。同 PK5/FM1 那两次的结论：能判定为冗余的就删。
      body: Text(
        _previewBody(l10n, preview),
        key: const ValueKey('temp-preview-body'),
        style: TextStyle(fontSize: 14, color: AppColors.primaryLabel(context)),
      ),
    );
  }

  /// 结果正文。三种结局**必须分得开**：会触发 / 不会触发（附原因）/ 没测成。
  /// 把"没测成"显示成"不会触发"是这里最坏的一种错法 —— 用户会去改阈值，而问题在传感器。
  String _previewBody(AppLocalizations l10n, TemperaturePreview? preview) {
    if (preview == null || preview.failed) {
      final error = preview?.error;
      return error == null
          ? l10n.tempTestFailed
          : '${l10n.tempTestFailed}\n$error';
    }
    final lines = <String>[];
    if (preview.temps.isEmpty) {
      lines.add(l10n.tempTestNoDims);
    } else {
      final dims = preview.temps.entries
          .map(
            (e) => '${_dimLabel(e.key, l10n)} ${e.value.toStringAsFixed(1)}℃',
          )
          .join('、');
      lines.add('${l10n.tempTestReadings}$dims');
    }
    if (preview.steps.isNotEmpty) {
      lines.add(
        '${l10n.tempTestSteps}${preview.steps.map((s) => _outcomeLabel(s.outcome, l10n)).join(' → ')}',
      );
    }
    if (preview.fired) {
      lines.add('${l10n.tempTestFired}${preview.title ?? ''}');
      final content = preview.content;
      if (content != null && content.isNotEmpty) lines.add(content);
    } else {
      lines.add(
        '${l10n.tempTestSilent}${_outcomeLabel(preview.silence ?? '', l10n)}',
      );
    }
    return lines.join('\n');
  }

  /// 原生 `Silence` 枚举名 / `FIRE` → 本地化说明。**必须覆盖原生那侧的全部枚举值**：
  /// 原生新增原因而这里没跟上时，界面会退回显示原始枚举名（用户读不懂），
  /// 由 test/architecture/temperature_preview_contract_test.dart 钉成红。
  String _outcomeLabel(String outcome, AppLocalizations l10n) =>
      switch (outcome) {
        'FIRE' => l10n.tempOutcomeFire,
        'NO_RULES' => l10n.tempSilenceNoRules,
        'NO_READING' => l10n.tempSilenceNoReading,
        'NOT_TRIGGERED' => l10n.tempSilenceNotTriggered,
        'NOT_CROSSING' => l10n.tempSilenceNotCrossing,
        'BASELINE' => l10n.tempSilenceBaseline,
        'IN_COOLDOWN' => l10n.tempSilenceInCooldown,
        'DISABLED' => l10n.tempSilenceDisabled,
        _ => outcome,
      };

  /// 删除规则 —— **滑出按钮与长按菜单共用这一条**（T06 的单一咽喉）。
  /// 这一族以前两条路都是"点一下就没了"，而阈值规则是拖滑块调出来的，重建一次并不便宜。
  Future<void> _confirmDeleteRule(String id, String title) async {
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
            // T90 片14：三页阈值框的形状原本各抄一遍（圆角、标题 17/w600、取消/添加两颗 16/w600/blue），
            // 现在外壳只有一个作者；字段内容与「默认标题怎么兜」这些判据仍留在本页。
            return IosFormDialog(
              title: isEdit ? l10n.editRule : l10n.addRule,
              cancelText: l10n.cancel,
              submitText: isEdit ? l10n.save : l10n.add,
              onSubmit: () {
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
              fields: [
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
                              valueController.text = selectedValue.toString();
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
