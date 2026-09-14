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

  /// 已授权但扫描结果为空（区分于无权限：空态提示可返回重试，而非引导授权）
  bool _showSystemApps = false;
  // 权限提醒弹窗每次进入页面只弹一次：从系统设置返回（resumed 重查）不再弹
  bool _permissionDialogShown = false;
  bool _refreshing = false;

  String _pkg(Map<String, dynamic> app) => app['packageName'] as String? ?? '';

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
        // 必须显式声明 List<dynamic>：invokeMethod 无上下文时 T 推断为 dynamic，
        // 若用 final 无类型接收，后续在 dynamic 接收器上动态调用泛型 map 时
        // 类型参数会被实例化为 dynamic，toList() 得到 List<dynamic>，
        // 再赋给 List<Map<String, dynamic>>? 触发隐式 downcast 抛异常
        // （List<dynamic> is not a subtype of List<Map<String,dynamic>>?），
        // 表现为应用列表恒为空（与应用筛选页写法保持一致）。
        final List<dynamic> cached = await _channel.invokeMethod(
          'getCachedInstalledApps',
        );
        if (cached.isNotEmpty) {
          apps = cached.map((e) => Map<String, dynamic>.from(e)).toList();
        }
      } catch (e) {
        debugPrint('加载缓存应用列表失败: $e');
      }
      try {
        final List<dynamic> fresh = await _channel.invokeMethod(
          'getInstalledApps',
        );
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
      // N9 修复：判定与列表空解耦。原「_hasPermission = granted && 列表非空」
      // 会把「已授权但扫描为空」（ROM 包可见性限制/缓存缺失）误判为无权限 →
      // 每次进入都弹授权引导，形成「一直请求权限 + 显示无权限」的死循环
      // （与应用筛选页表现不一致的根因——筛选页判定只看权限本身）。
      _hasPermission = granted;
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
          IconButton(
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.blue,
                    ),
                  )
                : const Icon(Icons.refresh, color: AppColors.blue),
            onPressed: _refreshing ? null : _manualRefreshApps,
            tooltip: l10n.refreshAppList,
          ),
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

  /// 手动刷新：force 绕过缓存强制重扫（Flyme 等机型扫描不全的兜底，
  /// 与应用筛选页 _manualRefreshApps 一致）。
  Future<void> _manualRefreshApps() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      // 显式 List<dynamic>：同 _initLoad，避免动态泛型 map 产出 List<dynamic>
      // 赋给 _allApps 时 downcast 失败导致手动刷新静默无效
      final List<dynamic> result = await _channel.invokeMethod(
        'getInstalledApps',
        {'force': true},
      );
      final newApps = result.map((e) => Map<String, dynamic>.from(e)).toList();
      if (!mounted) return;
      setState(() => _allApps = newApps);
    } catch (e) {
      debugPrint('刷新应用列表失败: $e');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Widget _buildList(BuildContext context, AppLocalizations l10n) {
    final query = _searchController.text.trim().toLowerCase();
    final searchMatched = _allApps
        .where((a) => _matchesSearch(a, query))
        .toList();

    // ── 快速选择分组：主流通讯/邮箱类 APP ──
    // 命中内置目录且用户确实已安装才展示；不受「显示系统应用」开关影响
    // （短信/电话本身是系统应用，默认隐藏系统应用时仍须能快速选择）。
    // 系统短信/电话组件各自聚合为单行（短信/电话），不逐条展示
    // 「信息/通话界面/电话服务/短信存储」等用户不可感知的系统组件名。
    final quickSms = <Map<String, dynamic>>[];
    final quickPhone = <Map<String, dynamic>>[];
    final quickComm = <Map<String, dynamic>>[];
    final quickMail = <Map<String, dynamic>>[];
    final quickPkgs = <String>{};
    void collectQuick(
      Map<String, dynamic> a,
      List<Map<String, dynamic>> bucket,
    ) {
      bucket.add(a);
      quickPkgs.add(_pkg(a));
    }

    for (final a in searchMatched) {
      final p = _pkg(a);
      if (_kQuickSmsIndex.containsKey(p)) {
        collectQuick(a, quickSms);
      } else if (_kQuickPhoneIndex.containsKey(p)) {
        collectQuick(a, quickPhone);
      } else if (_kQuickCommIndex.containsKey(p)) {
        collectQuick(a, quickComm);
      } else if (_kQuickMailIndex.containsKey(p)) {
        collectQuick(a, quickMail);
      }
    }
    quickSms.sort(
      (a, b) => _kQuickSmsIndex[_pkg(a)]! - _kQuickSmsIndex[_pkg(b)]!,
    );
    quickPhone.sort(
      (a, b) => _kQuickPhoneIndex[_pkg(a)]! - _kQuickPhoneIndex[_pkg(b)]!,
    );
    quickComm.sort(
      (a, b) => _kQuickCommIndex[_pkg(a)]! - _kQuickCommIndex[_pkg(b)]!,
    );
    quickMail.sort(
      (a, b) => _kQuickMailIndex[_pkg(a)]! - _kQuickMailIndex[_pkg(b)]!,
    );

    // 其他应用：非快速目录，沿用「默认隐藏系统应用」过滤
    final visible = searchMatched
        .where((a) => !quickPkgs.contains(_pkg(a)))
        .where((a) => _showSystemApps || !(a['isSystemApp'] as bool? ?? false))
        .toList();
    // 当前屏幕上所有可操作应用（快速选择 + 其他），全选/清空/反选作用于此集合
    final visibleTarget = [
      ...quickSms,
      ...quickPhone,
      ...quickComm,
      ...quickMail,
      ...visible,
    ];
    final appliedApps = visible
        .where((a) => !_excluded.contains(_pkg(a)))
        .toList();
    final excludedApps = visible
        .where((a) => _excluded.contains(_pkg(a)))
        .toList();
    final appliedCount = _allApps
        .where((a) => !_excluded.contains(_pkg(a)))
        .length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
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
        // 快捷操作栏（与应用筛选页一致）：全选（全部适用）/ 全不适用 / 反选 + 计数
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              _quickAction(
                context,
                l10n.selectAll,
                AppColors.blue,
                () => setState(
                  () => _excluded.removeAll(visibleTarget.map(_pkg)),
                ),
              ),
              const SizedBox(width: 8),
              _quickAction(
                context,
                l10n.deselectAll,
                AppColors.secondaryLabel(context),
                () => setState(() => _excluded.addAll(visibleTarget.map(_pkg))),
              ),
              const SizedBox(width: 8),
              _quickAction(
                context,
                l10n.invertSelection,
                AppColors.secondaryLabel(context),
                () => setState(() {
                  // 仅翻转当前可见集合，保留不在视图内的应用既有排除状态
                  final pkgs = visibleTarget.map(_pkg).toSet();
                  final flipped = pkgs.where((p) => !_excluded.contains(p));
                  _excluded.removeAll(pkgs);
                  _excluded.addAll(flipped);
                }),
              ),
              const Spacer(),
              Text(
                l10n.selectedCount(appliedCount),
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: visibleTarget.isEmpty
              ? Center(
                  child: Text(
                    l10n.noAppsFound,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.secondaryLabel(context),
                    ),
                  ),
                )
              : _buildAppList(
                  context,
                  l10n,
                  quickSms,
                  quickPhone,
                  quickComm,
                  quickMail,
                  appliedApps,
                  excludedApps,
                ),
        ),
      ],
    );
  }

  Widget _quickAction(
    BuildContext context,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color == AppColors.secondaryLabel(context)
                ? AppColors.secondaryLabel(context)
                : color,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  /// 应用列表：
  /// 1) 顶部「快速选择」卡——已安装的主流通讯/邮箱类（短信、电话、微信、QQ、
  ///    X、Telegram、WhatsApp、Gmail、Outlook 等），通讯/邮箱两个小区块；
  /// 2) 其他应用：有排除时按「适用（置顶）/ 已排除」分组，无排除时平铺。
  Widget _buildAppList(
    BuildContext context,
    AppLocalizations l10n,
    List<Map<String, dynamic>> quickSms,
    List<Map<String, dynamic>> quickPhone,
    List<Map<String, dynamic>> quickComm,
    List<Map<String, dynamic>> quickMail,
    List<Map<String, dynamic>> appliedApps,
    List<Map<String, dynamic>> excludedApps,
  ) {
    final hasQuick =
        quickSms.isNotEmpty ||
        quickPhone.isNotEmpty ||
        quickComm.isNotEmpty ||
        quickMail.isNotEmpty;
    final items = <_ScopeListItem>[];
    void addApps(List<Map<String, dynamic>> apps) {
      for (var i = 0; i < apps.length; i++) {
        items.add(
          _ScopeListItem.app(
            apps[i],
            isFirstInGroup: i == 0,
            isLastInGroup: i == apps.length - 1,
          ),
        );
      }
    }

    if (hasQuick) {
      items.add(_ScopeListItem.header(l10n.ruleAppQuickSelect));
      items.add(
        _ScopeListItem.quickCard(quickSms, quickPhone, quickComm, quickMail),
      );
    }

    if (hasQuick) {
      // 有快速选择卡时，其余应用统一归入「其他应用」；
      // 仅当其他应用自身出现排除项时才按「适用/已排除」拆分显示
      final others = [...appliedApps, ...excludedApps];
      if (others.isNotEmpty && excludedApps.isEmpty) {
        items.add(
          _ScopeListItem.header(l10n.ruleAppGroupOthersN(others.length)),
        );
        addApps(others);
      } else {
        if (appliedApps.isNotEmpty) {
          items.add(
            _ScopeListItem.header(l10n.ruleAppGroupApplied(appliedApps.length)),
          );
          addApps(appliedApps);
        }
        if (excludedApps.isNotEmpty) {
          items.add(
            _ScopeListItem.header(
              l10n.ruleAppGroupExcludedN(excludedApps.length),
            ),
          );
          addApps(excludedApps);
        }
      }
    } else if (_excluded.isEmpty) {
      addApps(appliedApps);
    } else {
      if (appliedApps.isNotEmpty) {
        items.add(
          _ScopeListItem.header(l10n.ruleAppGroupApplied(appliedApps.length)),
        );
        addApps(appliedApps);
      }
      if (excludedApps.isNotEmpty) {
        items.add(
          _ScopeListItem.header(
            l10n.ruleAppGroupExcludedN(excludedApps.length),
          ),
        );
        addApps(excludedApps);
      }
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        if (item.header != null) {
          return Padding(
            padding: const EdgeInsets.only(left: 4, top: 8, bottom: 6),
            child: Text(
              item.header!,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.secondaryLabel(context),
              ),
            ),
          );
        }
        if (item.isQuickCard) {
          return _buildQuickCard(
            context,
            l10n,
            item.quickSms,
            item.quickPhone,
            item.quickComm,
            item.quickMail,
          );
        }
        final app = item.app!;
        final showDivider = index > 0 && items[index - 1].app != null;
        return Container(
          decoration: BoxDecoration(
            color: AppColors.cardBg(context),
            borderRadius: BorderRadius.only(
              topLeft: item.isFirstInGroup
                  ? const Radius.circular(12)
                  : Radius.zero,
              topRight: item.isFirstInGroup
                  ? const Radius.circular(12)
                  : Radius.zero,
              bottomLeft: item.isLastInGroup
                  ? const Radius.circular(12)
                  : Radius.zero,
              bottomRight: item.isLastInGroup
                  ? const Radius.circular(12)
                  : Radius.zero,
            ),
          ),
          child: Column(
            children: [
              if (showDivider) _rowDivider(context),
              _appTile(context, app),
            ],
          ),
        );
      },
    );
  }

  /// 快速选择卡：
  /// - 通讯区块：短信（系统短信组件聚合行）、电话（系统电话组件聚合行）、
  ///   第三方即时通讯 APP（逐行）；
  /// - 邮箱区块：已安装的邮箱类 APP（逐行）。
  Widget _buildQuickCard(
    BuildContext context,
    AppLocalizations l10n,
    List<Map<String, dynamic>> sms,
    List<Map<String, dynamic>> phone,
    List<Map<String, dynamic>> comm,
    List<Map<String, dynamic>> mail,
  ) {
    final children = <Widget>[];
    var rowIndex = 0;

    void addRow(Widget tile) {
      children.add(_rowDivider(context, indent: 60, show: rowIndex != 0));
      children.add(tile);
      rowIndex++;
    }

    void addSectionLabel(String label) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 9, 16, 3),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.tertiaryLabel(context),
            ),
          ),
        ),
      );
    }

    // 通讯区块（至少有一个通讯类条目时才显示区块名）
    if (sms.isNotEmpty || phone.isNotEmpty || comm.isNotEmpty) {
      addSectionLabel(l10n.ruleAppQuickComm);
      if (sms.isNotEmpty) {
        addRow(
          _groupTile(
            context,
            l10n.ruleAppQuickSms,
            l10n.ruleAppQuickSmsSub,
            Icons.sms_outlined,
            sms,
          ),
        );
      }
      if (phone.isNotEmpty) {
        addRow(
          _groupTile(
            context,
            l10n.ruleAppQuickPhone,
            l10n.ruleAppQuickPhoneSub,
            Icons.call_outlined,
            phone,
          ),
        );
      }
      for (final app in comm) {
        addRow(_appTile(context, app));
      }
    }

    // 邮箱区块
    if (mail.isNotEmpty) {
      addSectionLabel(l10n.ruleAppQuickMail);
      for (final app in mail) {
        addRow(_appTile(context, app));
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: children),
    );
  }

  /// 系统组件聚合行：多个系统包（如拨号器/通话界面/电话服务）合并为一行，
  /// 状态三态：全部适用（绿勾）/ 全部排除（灰圈）/ 部分适用（蓝横）。
  /// 点击：全部适用时整组排除，其余情况整组恢复适用。
  Widget _groupTile(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    List<Map<String, dynamic>> apps,
  ) {
    final pkgs = apps.map(_pkg).toSet();
    final appliedCount = pkgs.where((p) => !_excluded.contains(p)).length;
    final allApplied = appliedCount == pkgs.length;
    final noneApplied = appliedCount == 0;

    final Color stateColor = allApplied
        ? AppColors.green
        : (noneApplied ? AppColors.tertiaryLabel(context) : AppColors.blue);
    final IconData stateIcon = allApplied
        ? Icons.check_circle
        : (noneApplied ? Icons.circle_outlined : Icons.remove_circle_outline);

    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.blue, size: 20),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 15,
            color: AppColors.primaryLabel(context),
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.secondaryLabel(context),
          ),
        ),
        trailing: Icon(stateIcon, color: stateColor, size: 24),
        onTap: () => _toggleGroup(pkgs, allApplied),
      ),
    );
  }

  /// 聚合组整组切换：allApplied=true → 整组排除；否则整组恢复适用
  void _toggleGroup(Set<String> pkgs, bool allApplied) {
    setState(() {
      if (allApplied) {
        _excluded.addAll(pkgs);
      } else {
        _excluded.removeAll(pkgs);
      }
    });
  }

  /// 应用行分隔线（与应用筛选页一致：左侧留出图标区域）
  Widget _rowDivider(
    BuildContext context, {
    double indent = 60,
    bool show = true,
  }) {
    if (!show) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: Divider(
        height: 0.5,
        thickness: 0.5,
        color: AppColors.separator(context),
      ),
    );
  }

  /// 单个应用行：图标 + 名称/包名 + 适用状态，点击切换是否适用
  Widget _appTile(BuildContext context, Map<String, dynamic> app) {
    final pkg = _pkg(app);
    final applies = !_excluded.contains(pkg);
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: (applies ? AppColors.blue : AppColors.tertiaryLabel(context))
                .withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.android,
            color: applies ? AppColors.blue : AppColors.tertiaryLabel(context),
            size: 22,
          ),
        ),
        title: Text(
          app['appName'] as String? ?? pkg,
          style: TextStyle(
            fontSize: 15,
            color: AppColors.primaryLabel(context),
          ),
        ),
        subtitle: Text(
          pkg,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.secondaryLabel(context),
          ),
        ),
        trailing: Icon(
          applies ? Icons.check_circle : Icons.circle_outlined,
          color: applies ? AppColors.green : AppColors.tertiaryLabel(context),
          size: 24,
        ),
        onTap: () => _toggle(pkg, !applies),
      ),
    );
  }
}

/// 应用列表条目：组头 / 应用行 / 快速选择整卡
class _ScopeListItem {
  final String? header;
  final Map<String, dynamic>? app;
  final bool isFirstInGroup;
  final bool isLastInGroup;

  /// 快速选择卡（短信/电话聚合行 + 第三方通讯 + 邮箱）
  final bool isQuickCard;
  final List<Map<String, dynamic>> quickSms;
  final List<Map<String, dynamic>> quickPhone;
  final List<Map<String, dynamic>> quickComm;
  final List<Map<String, dynamic>> quickMail;

  const _ScopeListItem.header(this.header)
    : app = null,
      isFirstInGroup = false,
      isLastInGroup = false,
      isQuickCard = false,
      quickSms = const [],
      quickPhone = const [],
      quickComm = const [],
      quickMail = const [];

  const _ScopeListItem.app(
    this.app, {
    required this.isFirstInGroup,
    required this.isLastInGroup,
  }) : header = null,
       isQuickCard = false,
       quickSms = const [],
       quickPhone = const [],
       quickComm = const [],
       quickMail = const [];

  const _ScopeListItem.quickCard(
    this.quickSms,
    this.quickPhone,
    this.quickComm,
    this.quickMail,
  ) : header = null,
      app = null,
      isFirstInGroup = false,
      isLastInGroup = false,
      isQuickCard = true;
}

/// 快速选择目录：系统短信类包名（信息/短信应用 + 短信存储）。
/// 多个系统组件（如「信息」「短信存储」）在 UI 聚合为单行「短信」。
const List<String> _kQuickSmsPackages = [
  'com.android.mms',
  'com.android.messaging',
  'com.google.android.apps.messaging',
  'com.samsung.android.messaging',
  'com.miui.sms',
  'com.coloros.mms',
  'com.heytap.mms',
  'com.vivo.mms',
  'com.huawei.message',
  'com.android.providers.telephony', // 短信存储
];

/// 快速选择目录：系统电话类包名（拨号器 + 通话界面 + 电话服务）。
/// 多个系统组件（如「电话」「通话界面」「电话服务」）在 UI 聚合为单行「电话」。
const List<String> _kQuickPhonePackages = [
  'com.android.dialer',
  'com.android.incallui',
  'com.google.android.dialer',
  'com.samsung.android.dialer',
  'com.android.phone',
  'com.android.server.telecom',
];

/// 快速选择目录：第三方即时通讯/社交/办公类 APP 包名（顺序即展示顺序）。
const List<String> _kQuickCommPackages = [
  // 国内即时通讯/办公
  'com.tencent.mm', // 微信
  'com.tencent.mobileqq', // QQ
  'com.tencent.tim', // TIM
  'com.tencent.wework', // 企业微信
  'com.ss.android.lark', // 飞书
  'com.larksuite.suite', // Lark
  'com.alibaba.android.rimet', // 钉钉
  // 国际即时通讯/社交
  'org.telegram.messenger', // Telegram
  'org.telegram.messenger.web', // Telegram X
  'com.twitter.android', // X
  'com.whatsapp', // WhatsApp
  'com.whatsapp.w4b', // WhatsApp Business
  'com.facebook.orca', // Messenger
  'com.instagram.android', // Instagram
  'jp.naver.line.android', // LINE
  'org.thoughtcrime.securesms', // Signal
  'com.viber.voip', // Viber
  'com.skype.raider', // Skype
  'com.discord', // Discord
  'com.Slack', // Slack
  'com.zing.zalo', // Zalo
  'com.kakao.talk', // KakaoTalk
  'com.snapchat.android', // Snapchat
];

/// 快速选择目录：主流邮箱类 APP 包名。
const List<String> _kQuickMailPackages = [
  'com.google.android.gm', // Gmail
  'com.microsoft.office.outlook', // Outlook
  'com.tencent.androidqqmail', // QQ 邮箱
  'com.netease.mail', // 网易邮箱大师
  'com.netease.mobimail', // 网易邮箱
  'com.samsung.android.email.provider', // Samsung Email
  'com.yahoo.mobile.client.android.mail', // Yahoo Mail
  'ch.protonmail.android', // Proton Mail
  'readdle.com.sparkmailinbox', // Spark
  'net.thunderbird.android', // Thunderbird
  'me.bluemail.mail', // BlueMail
  'com.easilydo.mail', // Edison Mail
  'com.ninefolders.hd3', // Nine
];

/// 包名 → 目录序号（用于按目录顺序排序已安装的命中应用）
Map<String, int> _indexOf(List<String> packages) => {
  for (var i = 0; i < packages.length; i++) packages[i]: i,
};

final Map<String, int> _kQuickSmsIndex = _indexOf(_kQuickSmsPackages);
final Map<String, int> _kQuickPhoneIndex = _indexOf(_kQuickPhonePackages);
final Map<String, int> _kQuickCommIndex = _indexOf(_kQuickCommPackages);
final Map<String, int> _kQuickMailIndex = _indexOf(_kQuickMailPackages);
