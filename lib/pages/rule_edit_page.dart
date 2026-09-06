import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../l10n/app_localizations_enum_helpers.dart';
import '../models/notification_rule.dart';
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
    final options = <_IosOption<int>>[
      _IosOption(0, l10n.rulePDefault),
      _IosOption(50, l10n.rulePLow),
      _IosOption(100, l10n.rulePMedium),
      _IosOption(200, l10n.rulePHigh),
      _IosOption(500, l10n.rulePHighest),
    ];
    // 历史规则可能带有非标准优先级值，保证仍能正确显示
    if (!options.any((o) => o.value == _rule.priority)) {
      options.insert(
        0,
        _IosOption(_rule.priority, l10n.rulePriorityBadge(_rule.priority)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _IosSelectField<int>(
          label: l10n.rulePriority,
          value: _rule.priority,
          options: options,
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _rule = _rule.copyWith(priority: value);
              });
            }
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
}
