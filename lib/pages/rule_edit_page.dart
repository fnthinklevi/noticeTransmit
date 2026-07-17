import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/notification_rule.dart';
import '../theme/app_colors.dart';

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
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(
        title: const Text('编辑规则'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text(
              '保存',
              style: TextStyle(
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
            _buildSectionCard(context, '基本信息', [
              _buildTextField(context, '规则名称', _nameController, hint: '输入规则名称'),
              const SizedBox(height: 12),
              _buildTextField(
                context,
                '规则描述',
                _descriptionController,
                hint: '描述规则的作用',
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              _buildPriorityRow(context),
              const SizedBox(height: 12),
              _buildSwitchRow(context, '启用规则', _rule.enabled, (value) {
                setState(() {
                  _rule = _rule.copyWith(enabled: value);
                });
              }),
            ]),
            const SizedBox(height: 12),
            _buildSectionCard(context, '触发条件 (IF)', [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '触发条件',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryLabel(context),
                    ),
                  ),
                  TextButton(
                    onPressed: _addCondition,
                    child: Text(
                      '添加条件',
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
                    '暂无条件，点击添加',
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
            _buildSectionCard(context, '执行动作 (THEN)', [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '执行动作',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryLabel(context),
                    ),
                  ),
                  TextButton(
                    onPressed: _addAction,
                    child: Text(
                      '添加动作',
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
                    '暂无动作，点击添加',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            '规则优先级',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.secondaryLabel(context),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.inputBg(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.separator(context)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _rule.priority,
              items: const [
                DropdownMenuItem(value: 0, child: Text('默认 (0)')),
                DropdownMenuItem(value: 50, child: Text('低 (50)')),
                DropdownMenuItem(value: 100, child: Text('中 (100)')),
                DropdownMenuItem(value: 200, child: Text('高 (200)')),
                DropdownMenuItem(value: 500, child: Text('最高 (500)')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _rule = _rule.copyWith(priority: value);
                  });
                }
              },
              isExpanded: true,
              underline: const SizedBox(),
              style: TextStyle(
                fontSize: 16,
                color: AppColors.primaryLabel(context),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '优先级越高，规则越先执行。相同优先级按添加顺序执行。',
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

class _ConditionItem extends StatelessWidget {
  final Condition condition;
  final int index;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  const _ConditionItem({
    required this.condition,
    required this.index,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.systemBlue(context).withAlpha(15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (index > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          condition.logic.label,
                          style: TextStyle(
                            color: condition.logic == LogicOperator.and
                                ? AppColors.systemBlue(context)
                                : AppColors.systemOrange(context),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    Text(
                      condition.type.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryLabel(context),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    condition.value,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.secondaryLabel(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  Icons.edit,
                  size: 20,
                  color: AppColors.systemBlue(context),
                ),
                onPressed: onEdit,
              ),
              IconButton(
                icon: Icon(
                  Icons.delete,
                  size: 20,
                  color: AppColors.systemRed(context),
                ),
                onPressed: onRemove,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionItem extends StatelessWidget {
  final RuleAction action;
  final int index;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  const _ActionItem({
    required this.action,
    required this.index,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.systemGreen(context).withAlpha(15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action.type.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryLabel(context),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    action.type.description,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.secondaryLabel(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  Icons.edit,
                  size: 20,
                  color: AppColors.systemBlue(context),
                ),
                onPressed: onEdit,
              ),
              IconButton(
                icon: Icon(
                  Icons.delete,
                  size: 20,
                  color: AppColors.systemRed(context),
                ),
                onPressed: onRemove,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConditionAddDialog extends StatefulWidget {
  final Function(Condition) onAdd;

  const _ConditionAddDialog({required this.onAdd});

  @override
  State<_ConditionAddDialog> createState() => _ConditionAddDialogState();
}

class _ConditionAddDialogState extends State<_ConditionAddDialog> {
  ConditionType? _selectedType;
  String _value = '';
  LogicOperator _logic = LogicOperator.and;
  final TextEditingController _valueController = TextEditingController();

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_selectedType != null && _value.isNotEmpty) {
      widget.onAdd(
        Condition(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          type: _selectedType!,
          value: _value,
          logic: _logic,
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.cardBg(context),
      title: Text(
        '添加条件',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.primaryLabel(context),
        ),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDropdownSection(
              context,
              '条件类型',
              _selectedType,
              ConditionType.values,
              (type) => type.label,
              (value) {
                setState(() {
                  _selectedType = value;
                });
              },
            ),
            const SizedBox(height: 16),
            _buildTextFieldSection(
              context,
              '条件值',
              _selectedType?.hint ?? '',
              (value) => _value = value,
              _valueController,
            ),
            const SizedBox(height: 16),
            _buildDropdownSection(
              context,
              '逻辑运算符',
              _logic,
              LogicOperator.values,
              (logic) => logic.label,
              (value) {
                setState(() {
                  _logic = value!;
                });
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            '取消',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.secondaryLabel(context),
            ),
          ),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text(
            '添加',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.blue,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownSection<T>(
    BuildContext context,
    String label,
    T? value,
    List<T> items,
    String Function(T) labelBuilder,
    ValueChanged<T?> onChanged,
  ) {
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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.inputBg(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.separator(context)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              hint: Text(
                '请选择',
                style: TextStyle(color: AppColors.secondaryLabel(context)),
              ),
              items: items.map((item) {
                return DropdownMenuItem(
                  value: item,
                  child: Text(
                    labelBuilder(item),
                    style: TextStyle(color: AppColors.primaryLabel(context)),
                  ),
                );
              }).toList(),
              onChanged: onChanged,
              isExpanded: true,
              underline: const SizedBox(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextFieldSection(
    BuildContext context,
    String label,
    String hint,
    ValueChanged<String> onChanged,
    TextEditingController controller,
  ) {
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
          onChanged: onChanged,
          controller: controller,
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
}

class _ConditionEditDialog extends StatefulWidget {
  final Condition condition;
  final Function(Condition) onSave;

  const _ConditionEditDialog({required this.condition, required this.onSave});

  @override
  State<_ConditionEditDialog> createState() => _ConditionEditDialogState();
}

class _ConditionEditDialogState extends State<_ConditionEditDialog> {
  late ConditionType _type;
  late String _value;
  late LogicOperator _logic;
  late final TextEditingController _valueController;

  @override
  void initState() {
    super.initState();
    _type = widget.condition.type;
    _value = widget.condition.value;
    _logic = widget.condition.logic;
    _valueController = TextEditingController(text: _value);
  }

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  void _submit() {
    widget.onSave(
      widget.condition.copyWith(type: _type, value: _value, logic: _logic),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.cardBg(context),
      title: Text(
        '编辑条件',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.primaryLabel(context),
        ),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDropdownSection(
              context,
              '条件类型',
              _type,
              ConditionType.values,
              (type) => type.label,
              (value) {
                setState(() {
                  _type = value!;
                });
              },
            ),
            const SizedBox(height: 16),
            _buildTextFieldSection(
              context,
              '条件值',
              _type.hint,
              (value) => _value = value,
              _valueController,
            ),
            const SizedBox(height: 16),
            _buildDropdownSection(
              context,
              '逻辑运算符',
              _logic,
              LogicOperator.values,
              (logic) => logic.label,
              (value) {
                setState(() {
                  _logic = value!;
                });
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            '取消',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.secondaryLabel(context),
            ),
          ),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text(
            '保存',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.blue,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownSection<T>(
    BuildContext context,
    String label,
    T? value,
    List<T> items,
    String Function(T) labelBuilder,
    ValueChanged<T?> onChanged,
  ) {
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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.inputBg(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.separator(context)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              items: items.map((item) {
                return DropdownMenuItem(
                  value: item,
                  child: Text(
                    labelBuilder(item),
                    style: TextStyle(color: AppColors.primaryLabel(context)),
                  ),
                );
              }).toList(),
              onChanged: onChanged,
              isExpanded: true,
              underline: const SizedBox(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextFieldSection(
    BuildContext context,
    String label,
    String hint,
    ValueChanged<String> onChanged,
    TextEditingController controller,
  ) {
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
          onChanged: onChanged,
          controller: controller,
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
}

class _ActionAddDialog extends StatefulWidget {
  final Function(RuleAction) onAdd;

  const _ActionAddDialog({required this.onAdd});

  @override
  State<_ActionAddDialog> createState() => _ActionAddDialogState();
}

class _ActionAddDialogState extends State<_ActionAddDialog> {
  ActionType? _selectedType;

  void _submit() {
    if (_selectedType != null) {
      widget.onAdd(
        RuleAction(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          type: _selectedType!,
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.cardBg(context),
      title: Text(
        '添加动作',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.primaryLabel(context),
        ),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '动作类型',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.inputBg(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.separator(context)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<ActionType>(
                  value: _selectedType,
                  hint: Text(
                    '请选择',
                    style: TextStyle(color: AppColors.secondaryLabel(context)),
                  ),
                  items: ActionType.values.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            type.label,
                            style: TextStyle(
                              color: AppColors.primaryLabel(context),
                            ),
                          ),
                          Text(
                            type.description,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.secondaryLabel(context),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedType = value;
                    });
                  },
                  isExpanded: true,
                  underline: const SizedBox(),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            '取消',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.secondaryLabel(context),
            ),
          ),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text(
            '添加',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.blue,
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionEditDialog extends StatefulWidget {
  final RuleAction action;
  final Function(RuleAction) onSave;

  const _ActionEditDialog({required this.action, required this.onSave});

  @override
  State<_ActionEditDialog> createState() => _ActionEditDialogState();
}

class _ActionEditDialogState extends State<_ActionEditDialog> {
  late ActionType _type;

  @override
  void initState() {
    super.initState();
    _type = widget.action.type;
  }

  void _submit() {
    widget.onSave(widget.action.copyWith(type: _type));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.cardBg(context),
      title: Text(
        '编辑动作',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.primaryLabel(context),
        ),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '动作类型',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.inputBg(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.separator(context)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<ActionType>(
                  value: _type,
                  items: ActionType.values.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            type.label,
                            style: TextStyle(
                              color: AppColors.primaryLabel(context),
                            ),
                          ),
                          Text(
                            type.description,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.secondaryLabel(context),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _type = value!;
                    });
                  },
                  isExpanded: true,
                  underline: const SizedBox(),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            '取消',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.secondaryLabel(context),
            ),
          ),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text(
            '保存',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.blue,
            ),
          ),
        ),
      ],
    );
  }
}
