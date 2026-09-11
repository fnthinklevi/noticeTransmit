import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../l10n/app_localizations_enum_helpers.dart';
import '../models/notification_rule.dart';
import '../services/platform_channel.dart';
import '../theme/app_colors.dart';

// R3 拆分：iOS 选择器/条件行/动作行组件与条件/动作编辑对话框（part 共享私有类名）
part 'rule_edit_widgets.dart';

class RuleEditPage extends StatefulWidget {
  final NotificationRule rule;

  const RuleEditPage({super.key, required this.rule});

  @override
  State<RuleEditPage> createState() => _RuleEditPageState();
}

class _RuleEditPageState extends State<RuleEditPage> {
  late NotificationRule _rule;
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _rule = widget.rule;
    _nameController.text = _rule.name;
    _descriptionController.text = _rule.description;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _save() {
    final updatedRule = _rule.copyWith(
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim(),
    );
    Navigator.pop(context, updatedRule);
  }

  void _addCondition() {
    showDialog(
      context: context,
      builder: (context) => _ConditionAddDialog(
        onAdd: (condition) {
          setState(() {
            _rule = _rule.copyWith(
              conditions: [..._rule.conditions, condition],
            );
          });
        },
      ),
    );
  }

  void _editCondition(Condition condition) {
    showDialog(
      context: context,
      builder: (context) => _ConditionEditDialog(
        condition: condition,
        onSave: (updated) {
          setState(() {
            final conditions = _rule.conditions.map((c) {
              if (c.id == condition.id) return updated;
              return c;
            }).toList();
            _rule = _rule.copyWith(conditions: conditions);
          });
        },
      ),
    );
  }

  void _removeCondition(Condition condition) {
    setState(() {
      _rule = _rule.copyWith(
        conditions: _rule.conditions
            .where((c) => c.id != condition.id)
            .toList(),
      );
    });
  }

  void _addAction() {
    showDialog(
      context: context,
      builder: (context) => _ActionAddDialog(
        onAdd: (action) {
          setState(() {
            _rule = _rule.copyWith(actions: [..._rule.actions, action]);
          });
        },
      ),
    );
  }

  void _editAction(RuleAction action) {
    showDialog(
      context: context,
      builder: (context) => _ActionEditDialog(
        action: action,
        onSave: (updated) {
          setState(() {
            final actions = _rule.actions.map((a) {
              if (a.id == action.id) return updated;
              return a;
            }).toList();
            _rule = _rule.copyWith(actions: actions);
          });
        },
      ),
    );
  }

  void _removeAction(RuleAction action) {
    setState(() {
      _rule = _rule.copyWith(
        actions: _rule.actions.where((a) => a.id != action.id).toList(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(
        title: Text(l10n.ruleEditTitle),
        actions: [
          TextButton(
            onPressed: _save,
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildSectionCard(context, l10n.ruleBasicInfo, [
              _buildTextField(
                context,
                l10n.ruleName,
                _nameController,
                hint: l10n.ruleNameHint,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                context,
                l10n.ruleDescription,
                _descriptionController,
                hint: l10n.ruleDescriptionHint,
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              _buildPriorityRow(context),
              const SizedBox(height: 12),
              _buildSwitchRow(context, l10n.ruleEnableRule, _rule.enabled, (
                value,
              ) {
                setState(() {
                  _rule = _rule.copyWith(enabled: value);
                });
              }),
            ]),
            const SizedBox(height: 12),
            _buildSectionCard(context, l10n.ruleConditions, [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.ruleAddCondition,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryLabel(context),
                    ),
                  ),
                  TextButton(
                    onPressed: _addCondition,
                    child: Text(
                      l10n.add,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.systemBlue(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_rule.conditions.isEmpty)
                Center(
                  child: Text(
                    l10n.ruleEmptyConditions,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.secondaryLabel(context),
                    ),
                  ),
                )
              else
                Column(
                  children: _rule.conditions.asMap().entries.map((entry) {
                    final index = entry.key;
                    final condition = entry.value;
                    return _ConditionItem(
                      condition: condition,
                      index: index,
                      onEdit: () => _editCondition(condition),
                      onRemove: () => _removeCondition(condition),
                    );
                  }).toList(),
                ),
            ]),
            const SizedBox(height: 12),
            _buildSectionCard(context, l10n.ruleAppScope, [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _rule.excludedPackages.isEmpty
                          ? l10n.ruleAppScopeAll
                          : l10n.ruleAppScopeExcluded(
                              _rule.excludedPackages.length,
                            ),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryLabel(context),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _openAppScopePicker,
                    child: Text(
                      l10n.ruleAppPickTitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.systemBlue(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.ruleAppScopeDesc,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            _buildSectionCard(context, l10n.ruleActions, [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.ruleAddAction,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryLabel(context),
                    ),
                  ),
                  TextButton(
                    onPressed: _addAction,
                    child: Text(
                      l10n.add,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.systemBlue(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_rule.actions.isEmpty)
                Center(
                  child: Text(
                    l10n.ruleEmptyActions,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.secondaryLabel(context),
                    ),
                  ),
                )
              else
                Column(
                  children: _rule.actions.asMap().entries.map((entry) {
                    final index = entry.key;
                    final action = entry.value;
                    return _ActionItem(
                      action: action,
                      index: index,
                      onEdit: () => _editAction(action),
                      onRemove: () => _removeAction(action),
                    );
                  }).toList(),
                ),
              if (_mergeAction != null) ...[
                const SizedBox(height: 4),
                // P1：聚合等待时长内联设置（此前藏在动作编辑对话框里不易发现）
                InkWell(
                  onTap: _editMergeWindow,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Text(
                          l10n.ruleMergeWindowRow,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryLabel(context),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _mergeSummaryText(l10n),
                          style: TextStyle(
                            fontSize: 15,
                            color: AppColors.systemBlue(context),
                            fontWeight: FontWeight.w500,
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
                ),
              ],
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context,
    String title,
    List<Widget> children,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(5),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  Widget _buildTextField(
    BuildContext context,
    String label,
    TextEditingController controller, {
    String? hint,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.secondaryLabel(context),
            ),
          ),
        ),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: TextStyle(color: AppColors.primaryLabel(context)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: AppColors.secondaryLabel(context)),
            fillColor: AppColors.inputBg(context),
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.separator(context)),
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
        ),
      ],
    );
  }

  Widget _buildSwitchRow(
    BuildContext context,
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            color: AppColors.primaryLabel(context),
          ),
        ),
        CupertinoSwitch(value: value, onChanged: onChanged),
      ],
    );
  }

  Widget _buildPriorityRow(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // P1-1：快捷档位 + 自定义。标准档位直接选；「自定义…」弹数字输入（0-500）。
    const standardPriorities = [0, 10, 50, 100, 200, 500];
    final options = <_IosOption<int>>[
      _IosOption(0, l10n.rulePDefault),
      // 10：低于「低(50)」，供聚合推送等应让位于营销拦截的规则使用，
      // 避免与 50 撞优先级后按数组顺序误判（默认聚合规则即为 10）。
      _IosOption(10, l10n.rulePriorityBadge(10)),
      _IosOption(50, l10n.rulePLow),
      _IosOption(100, l10n.rulePMedium),
      _IosOption(200, l10n.rulePHigh),
      _IosOption(500, l10n.rulePHighest),
    ];
    // 历史/自定义优先级不在标准档位内 → 追加「自定义 (N)」选项保证回显正确
    if (!standardPriorities.contains(_rule.priority)) {
      options.add(
        _IosOption(
          _rule.priority,
          '${l10n.rulePriorityCustom} (${_rule.priority})',
        ),
      );
    }
    // 自定义入口：-1 为哨兵值，选中时弹输入对话框而非直接赋值
    options.add(_IosOption(-1, l10n.rulePriorityCustom));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _IosSelectField<int>(
          label: l10n.rulePriority,
          value: _rule.priority,
          options: options,
          onChanged: (value) {
            if (value == null) return;
            if (value == -1) {
              _showCustomPriorityDialog();
              return;
            }
            setState(() {
              _rule = _rule.copyWith(priority: value);
            });
          },
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            l10n.rulePriorityNote,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.secondaryLabel(context),
            ),
          ),
        ),
      ],
    );
  }

  /// P1-1：自定义优先级输入（0-500，非法输入就地提示）
  void _showCustomPriorityDialog() {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: '${_rule.priority}');
    String? errorText;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: AppColors.cardBg(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: Text(
            l10n.rulePriorityCustomTitle,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryLabel(context),
            ),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: TextStyle(color: AppColors.primaryLabel(context)),
            decoration: InputDecoration(
              hintText: l10n.rulePriorityCustomHint,
              hintStyle: TextStyle(color: AppColors.secondaryLabel(context)),
              fillColor: AppColors.inputBg(context),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.separator(context)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.blue),
              ),
              isDense: true,
              errorText: errorText,
            ),
            onChanged: (_) => setDialogState(() => errorText = null),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                l10n.cancel,
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                final value = int.tryParse(controller.text.trim());
                if (value == null || value < 0 || value > 500) {
                  setDialogState(() {
                    errorText = l10n.rulePriorityCustomInvalid;
                  });
                  return;
                }
                setState(() {
                  _rule = _rule.copyWith(priority: value);
                });
                Navigator.pop(dialogContext);
              },
              child: Text(
                l10n.confirm,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.blue,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// P1-4：打开「适用应用」选择页，返回排除列表后回写规则
  Future<void> _openAppScopePicker() async {
    final excluded = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _AppScopePickerPage(initialExcluded: _rule.excludedPackages),
      ),
    );
    if (excluded != null) {
      setState(() {
        _rule = _rule.copyWith(excludedPackages: excluded);
      });
    }
  }

  /// 首个合并推送动作（等待时长行的数据源）
  RuleAction? get _mergeAction {
    for (final a in _rule.actions) {
      if (a.type == ActionType.merge) return a;
    }
    return null;
  }

  /// 当前聚合等待秒数（未配置时与原生 DEFAULT_MERGE_WINDOW_MS=60 对应）
  int get _mergeWindowSeconds {
    final params = _mergeAction?.params;
    final v = params?['windowSeconds'];
    return v is int && v > 0 ? v : 60;
  }

  /// F3：满 N 条提前触发（0 = 关闭，等窗口到点）
  int get _mergeMaxItems {
    final v = _mergeAction?.params['maxItems'];
    return v is int && v > 0 ? v : 0;
  }

  /// F3：按会话分组（同应用不同标题分开聚合）
  bool get _mergeGroupByTitle => _mergeAction?.params['groupByTitle'] == true;

  /// F3：聚合参数摘要（等待秒数 · 满 N 条提前 · 按会话分组）
  String _mergeSummaryText(AppLocalizations l10n) {
    final parts = <String>[l10n.ruleMergeWindowSummary(_mergeWindowSeconds)];
    if (_mergeMaxItems > 0) {
      parts.add(l10n.ruleMergeMaxItemsSummary(_mergeMaxItems));
    }
    if (_mergeGroupByTitle) {
      parts.add(l10n.ruleMergeGroupByTitleSummary);
    }
    return parts.join(' · ');
  }

  /// P1/F3：编辑聚合参数（等待秒数 + 满 N 条提前 + 按会话分组；
  /// 窗口下限 5 秒与原生 MIN_MERGE_WINDOW_MS 一致）
  void _editMergeWindow() {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: '$_mergeWindowSeconds');
    final maxItemsController = TextEditingController(
      text: _mergeMaxItems > 0 ? '$_mergeMaxItems' : '',
    );
    var groupByTitle = _mergeGroupByTitle;
    String? errorText;
    const presets = [15, 30, 60, 120, 300];
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: AppColors.cardBg(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: Text(
            l10n.ruleMergeWindowRow,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryLabel(context),
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: TextStyle(color: AppColors.primaryLabel(context)),
                decoration: InputDecoration(
                  labelText: l10n.mergeWindowSeconds,
                  labelStyle: TextStyle(
                    color: AppColors.secondaryLabel(context),
                  ),
                  helperText: l10n.mergeWindowHint,
                  helperMaxLines: 2,
                  fillColor: AppColors.inputBg(context),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.separator(context)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.blue),
                  ),
                  isDense: true,
                  errorText: errorText,
                ),
                onChanged: (_) => setDialogState(() => errorText = null),
              ),
              const SizedBox(height: 10),
              Text(
                l10n.ruleMergeWindowPresets,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: presets
                    .map(
                      (p) => ActionChip(
                        label: Text(
                          l10n.ruleMergeWindowSummary(p),
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.primaryLabel(context),
                          ),
                        ),
                        backgroundColor: AppColors.inputBg(context),
                        side: BorderSide(color: AppColors.separator(context)),
                        onPressed: () {
                          controller.text = '$p';
                          setDialogState(() => errorText = null);
                        },
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 14),
              // F3：满 N 条提前触发
              TextField(
                controller: maxItemsController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: TextStyle(color: AppColors.primaryLabel(context)),
                decoration: InputDecoration(
                  labelText: l10n.mergeMaxItemsLabel,
                  labelStyle: TextStyle(
                    color: AppColors.secondaryLabel(context),
                  ),
                  helperText: l10n.mergeMaxItemsHint,
                  helperMaxLines: 2,
                  fillColor: AppColors.inputBg(context),
                  filled: true,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.separator(context)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // F3：按会话分组
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.mergeGroupByTitleLabel,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.primaryLabel(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.mergeGroupByTitleDesc,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.secondaryLabel(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: groupByTitle,
                    activeThumbColor: AppColors.blue,
                    onChanged: (v) => setDialogState(() => groupByTitle = v),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                l10n.cancel,
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                final value = int.tryParse(controller.text.trim());
                if (value == null || value < 5 || value > 86400) {
                  setDialogState(() {
                    errorText = l10n.ruleMergeWindowInvalid;
                  });
                  return;
                }
                final maxItemsValue = int.tryParse(
                  maxItemsController.text.trim(),
                );
                setState(() {
                  _rule = _rule.copyWith(
                    actions: _rule.actions.map((a) {
                      if (a.type != ActionType.merge) return a;
                      final params = <String, dynamic>{
                        ...a.params,
                        'windowSeconds': value,
                      };
                      if (maxItemsValue != null && maxItemsValue > 0) {
                        params['maxItems'] = maxItemsValue;
                      } else {
                        params.remove('maxItems');
                      }
                      if (groupByTitle) {
                        params['groupByTitle'] = true;
                      } else {
                        params.remove('groupByTitle');
                      }
                      return a.copyWith(params: params);
                    }).toList(),
                  );
                });
                Navigator.pop(dialogContext);
              },
              child: Text(
                l10n.confirm,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.blue,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// P1-4：规则「适用应用」选择页（排除制）。
///
/// 权限与加载逻辑与「应用筛选」页**完全一致**（用户要求）：
/// WidgetsBindingObserver 在从系统设置返回（resumed）后自动重查权限并重载；
/// 未授予时弹「先说明后申请」引导框（allow → requestQueryAllPackagesPermission）；
/// ⚠ ROM 假阳性兜底：部分国产 ROM（如 Flyme）`canQueryAllPackages` 的无副作用探测
/// 恒真，即使未授权也返回 true —— 因此「判定已授予但列表仍为空」时同样走授权引导，
/// 授权返回后 resumed 重载即可出现列表。
/// 交互：默认全部适用（排除列表为空），取消勾选的应用不再适用本规则；
/// 系统短信/电话分组固定在列表顶部（与原生 isSmsPackage/isCallPackage 同源匹配）。
class _AppScopePickerPage extends StatefulWidget {
  final List<String> initialExcluded;

  const _AppScopePickerPage({required this.initialExcluded});

  @override
  State<_AppScopePickerPage> createState() => _AppScopePickerPageState();
}

class _AppScopePickerPageState extends State<_AppScopePickerPage>
    with WidgetsBindingObserver {
  static const _channel = AppChannels.notification;

  List<Map<String, dynamic>> _allApps = [];
  Set<String> _excluded = {};
  final _searchController = TextEditingController();
  bool _loading = true;
  bool _hasPermission = true;
  bool _showSystemApps = false;
  // 权限提醒弹窗每次进入页面只弹一次：从系统设置返回（resumed 重查）不再弹
  bool _permissionDialogShown = false;

  // —— 与原生 NotificationProcessor 相同的分组匹配（保持口径一致）——
  static bool _isSmsApp(String pkg) {
    final p = pkg.toLowerCase();
    return p.startsWith('com.android.mms') ||
        p.startsWith('com.google.android.apps.messaging') ||
        p.startsWith('com.samsung.android.messaging') ||
        p.startsWith('com.huawei.mms') ||
        p.startsWith('com.huawei.android.mms') ||
        p.startsWith('com.vivo.mms') ||
        p.contains('sms') ||
        p.contains('.mms');
  }

  static bool _isCallApp(String pkg) {
    final p = pkg.toLowerCase();
    return p.startsWith('com.android.dialer') ||
        p.startsWith('com.android.incallui') ||
        p.startsWith('com.android.phone') ||
        p.startsWith('com.google.android.dialer') ||
        p.startsWith('com.samsung.android.dialer') ||
        p.startsWith('com.samsung.android.incallui') ||
        p.startsWith('com.huawei.contacts') ||
        p.startsWith('com.oplus.incallui') ||
        p.startsWith('com.coloros.incallui') ||
        p.startsWith('com.bbk.incallui') ||
        p.startsWith('com.vivo.incallui') ||
        p.contains('incallui') ||
        p.contains('dialer');
  }

  String _pkg(Map<String, dynamic> app) => app['packageName'] as String? ?? '';

  List<Map<String, dynamic>> _matchApps(bool Function(String) test) =>
      _allApps.where((a) => test(_pkg(a))).toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _excluded = Set<String>.from(widget.initialExcluded);
    _initLoad();
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 与应用筛选页一致：从系统设置授权返回后自动重查权限并重载列表
    if (state == AppLifecycleState.resumed) {
      _initLoad();
    }
  }

  Future<bool> _checkPermission() async {
    try {
      final result =
          await _channel.invokeMethod('canQueryAllPackages') as bool?;
      return result ?? true;
    } catch (e) {
      debugPrint('检查应用列表权限失败: $e');
      return true;
    }
  }

  /// 无权限进入页面时的提醒弹窗：允许 → 跳系统设置申请；拒绝 → 仅显示提示文案
  /// （与应用筛选页 _showPermissionDialog 相同）
  Future<void> _showPermissionDialog() async {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return AlertDialog(
          backgroundColor: AppColors.cardBg(ctx),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.apps, size: 44, color: AppColors.blue),
              const SizedBox(height: 14),
              Text(
                l10n.appListPermTitle,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryLabel(ctx),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.appListPermMsg,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: AppColors.primaryLabel(ctx),
                ),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.spaceEvenly,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                l10n.reject,
                style: TextStyle(
                  color: AppColors.secondaryLabel(ctx),
                  fontSize: 15,
                ),
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _channel.invokeMethod('requestQueryAllPackagesPermission');
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.blue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(l10n.allow, style: const TextStyle(fontSize: 15)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _initLoad() async {
    if (!mounted) return;
    setState(() => _loading = true);

    final granted = await _checkPermission();

    // 先加载缓存列表，再全量扫描覆盖（与应用筛选页一致）。
    // ⚠ 即使判定为未授予也先试一次：ROM 对权限的判定可能有假阴性。
    List<Map<String, dynamic>>? apps;
    if (granted) {
      try {
        final cached = await _channel.invokeMethod('getCachedInstalledApps');
        if (cached.isNotEmpty) {
          apps = cached.map((e) => Map<String, dynamic>.from(e)).toList();
        }
      } catch (e) {
        debugPrint('加载缓存应用列表失败: $e');
      }
      try {
        final fresh = await _channel.invokeMethod('getInstalledApps');
        final freshList = fresh
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        if (freshList.isNotEmpty) apps = freshList;
      } catch (e) {
        debugPrint('加载应用列表失败: $e');
      }
    }

    if (!mounted) return;
    setState(() {
      _allApps = apps ?? const [];
      _loading = false;
      // ⚠ ROM 假阳性兜底：判定已授予但列表为空（如 Flyme 探测恒真、
      // 原生扫描无权限时静默返回空）→ 同样走授权引导，与应用筛选页体验一致。
      _hasPermission = granted && _allApps.isNotEmpty;
    });

    if (!_hasPermission && !_permissionDialogShown) {
      _permissionDialogShown = true;
      _showPermissionDialog();
    }
  }

  bool _matchesSearch(Map<String, dynamic> app, String query) {
    if (query.isEmpty) return true;
    final name = (app['appName'] as String? ?? '').toLowerCase();
    final pkg = _pkg(app).toLowerCase();
    return name.contains(query) || pkg.contains(query);
  }

  bool _isVisibleApp(Map<String, dynamic> app, String query) {
    // 与应用筛选页一致：默认隐藏系统应用，可用开关显示
    if (!_showSystemApps && (app['isSystemApp'] as bool? ?? false)) {
      return false;
    }
    return _matchesSearch(app, query);
  }

  void _toggle(String pkg, bool applies) {
    setState(() {
      if (applies) {
        _excluded.remove(pkg);
      } else {
        _excluded.add(pkg);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(
        title: Text(l10n.ruleAppPickTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _excluded.toList()),
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_hasPermission
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.ruleAppNoPermission,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
              ),
            )
          : _buildList(context, l10n),
    );
  }

  Widget _buildList(BuildContext context, AppLocalizations l10n) {
    final query = _searchController.text.trim().toLowerCase();
    final smsApps = _matchApps(
      _isSmsApp,
    ).where((a) => _isVisibleApp(a, query)).toList();
    final callApps = _matchApps(
      _isCallApp,
    ).where((a) => _isVisibleApp(a, query)).toList();
    final otherApps = _allApps
        .where((a) {
          final p = _pkg(a);
          return !_isSmsApp(p) && !_isCallApp(p);
        })
        .where((a) => _isVisibleApp(a, query))
        .toList();

    return Column(
      children: [
        // 全选（全部适用 ⇔ 排除列表为空）
        Container(
          color: AppColors.cardBg(context),
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.apps, size: 22, color: AppColors.blue),
            title: Text(
              l10n.ruleAppScopeAll,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryLabel(context),
              ),
            ),
            trailing: Checkbox(
              value: _excluded.isEmpty,
              onChanged: (allApply) {
                setState(() {
                  if (allApply == true) {
                    _excluded.clear();
                  } else {
                    _excluded.addAll(_allApps.map(_pkg));
                  }
                });
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: _searchController,
            style: TextStyle(color: AppColors.primaryLabel(context)),
            decoration: InputDecoration(
              hintText: l10n.searchAppHint,
              hintStyle: TextStyle(color: AppColors.secondaryLabel(context)),
              prefixIcon: Icon(
                Icons.search,
                size: 20,
                color: AppColors.secondaryLabel(context),
              ),
              fillColor: AppColors.inputBg(context),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.separator(context)),
              ),
              isDense: true,
            ),
          ),
        ),
        // 与应用筛选页一致：默认隐藏系统应用
        SizedBox(
          height: 40,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text(
                  l10n.showSystemApps,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
              ),
              Switch(
                value: _showSystemApps,
                activeThumbColor: AppColors.blue,
                onChanged: (v) => setState(() => _showSystemApps = v),
              ),
            ],
          ),
        ),
        Expanded(
          child: otherApps.isEmpty && smsApps.isEmpty && callApps.isEmpty
              ? Center(
                  child: Text(
                    l10n.noAppsFound,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.secondaryLabel(context),
                    ),
                  ),
                )
              : ListView(
                  children: [
                    if (callApps.isNotEmpty) ...[
                      _buildGroupHeader(context, l10n.ruleAppPinnedCall),
                      ...callApps.map((a) => _buildAppRow(context, a)),
                    ],
                    if (smsApps.isNotEmpty) ...[
                      _buildGroupHeader(context, l10n.ruleAppPinnedSms),
                      ...smsApps.map((a) => _buildAppRow(context, a)),
                    ],
                    if (callApps.isNotEmpty || smsApps.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                        child: Text(
                          l10n.ruleAppPinnedNote,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.secondaryLabel(context),
                          ),
                        ),
                      ),
                    _buildGroupHeader(context, l10n.ruleAppScopeAll),
                    ...otherApps.map((a) => _buildAppRow(context, a)),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildGroupHeader(BuildContext context, String title) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      color: AppColors.bgColor(context),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.secondaryLabel(context),
        ),
      ),
    );
  }

  Widget _buildAppRow(BuildContext context, Map<String, dynamic> app) {
    final pkg = _pkg(app);
    final applies = !_excluded.contains(pkg);
    return Container(
      color: AppColors.cardBg(context),
      child: ListTile(
        dense: true,
        title: Text(
          app['appName'] as String? ?? pkg,
          style: TextStyle(
            fontSize: 14,
            color: AppColors.primaryLabel(context),
          ),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          pkg,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.secondaryLabel(context),
          ),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Checkbox(
          value: applies,
          onChanged: (v) => _toggle(pkg, v == true),
        ),
        onTap: () => _toggle(pkg, !applies),
      ),
    );
  }
}
