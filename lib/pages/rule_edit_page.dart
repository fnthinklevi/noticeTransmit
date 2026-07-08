import 'package:flutter/material.dart';
import '../models/notification_rule.dart';

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
      appBar: AppBar(
        title: const Text('编辑规则'),
        actions: [TextButton(onPressed: _save, child: const Text('保存'))],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: '规则名称',
                        hintText: '输入规则名称',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: '规则描述',
                        hintText: '描述规则的作用',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('启用规则'),
                        Switch(
                          value: _rule.enabled,
                          onChanged: (value) {
                            setState(() {
                              _rule = _rule.copyWith(enabled: value);
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '触发条件 (IF)',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextButton(
                          onPressed: _addCondition,
                          child: const Text('添加条件'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_rule.conditions.isEmpty)
                      const Center(child: Text('暂无条件，点击添加'))
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
                  ],
                ),
              ),
            ),
            Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '执行动作 (THEN)',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextButton(
                          onPressed: _addAction,
                          child: const Text('添加动作'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_rule.actions.isEmpty)
                      const Center(child: Text('暂无动作，点击添加'))
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
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
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
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
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
                                ? Colors.blue
                                : Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    Text(
                      condition.type.label,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(condition.value),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit, size: 20),
                onPressed: onEdit,
              ),
              IconButton(
                icon: const Icon(Icons.delete, size: 20, color: Colors.red),
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
        border: Border.all(color: Colors.green.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action.type.label,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(action.type.description),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit, size: 20),
                onPressed: onEdit,
              ),
              IconButton(
                icon: const Icon(Icons.delete, size: 20, color: Colors.red),
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
      title: const Text('添加条件'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<ConditionType>(
              initialValue: _selectedType,
              hint: const Text('选择条件类型'),
              items: ConditionType.values.map((type) {
                return DropdownMenuItem(value: type, child: Text(type.label));
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedType = value;
                });
              },
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              onChanged: (value) => _value = value,
              decoration: InputDecoration(
                labelText: '条件值',
                hintText: _selectedType?.hint ?? '',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<LogicOperator>(
              initialValue: _logic,
              items: LogicOperator.values.map((logic) {
                return DropdownMenuItem(value: logic, child: Text(logic.label));
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _logic = value!;
                });
              },
              decoration: const InputDecoration(
                labelText: '逻辑运算符',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(onPressed: _submit, child: const Text('添加')),
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

  @override
  void initState() {
    super.initState();
    _type = widget.condition.type;
    _value = widget.condition.value;
    _logic = widget.condition.logic;
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
      title: const Text('编辑条件'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<ConditionType>(
              initialValue: _type,
              items: ConditionType.values.map((type) {
                return DropdownMenuItem(value: type, child: Text(type.label));
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _type = value!;
                });
              },
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              onChanged: (value) => _value = value,
              controller: TextEditingController(text: _value),
              decoration: InputDecoration(
                labelText: '条件值',
                hintText: _type.hint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<LogicOperator>(
              initialValue: _logic,
              items: LogicOperator.values.map((logic) {
                return DropdownMenuItem(value: logic, child: Text(logic.label));
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _logic = value!;
                });
              },
              decoration: const InputDecoration(
                labelText: '逻辑运算符',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(onPressed: _submit, child: const Text('保存')),
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
      title: const Text('添加动作'),
      content: DropdownButtonFormField<ActionType>(
        initialValue: _selectedType,
        hint: const Text('选择动作类型'),
        items: ActionType.values.map((type) {
          return DropdownMenuItem(
            value: type,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(type.label),
                Text(
                  type.description,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
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
        decoration: const InputDecoration(border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(onPressed: _submit, child: const Text('添加')),
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
      title: const Text('编辑动作'),
      content: DropdownButtonFormField<ActionType>(
        initialValue: _type,
        items: ActionType.values.map((type) {
          return DropdownMenuItem(
            value: type,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(type.label),
                Text(
                  type.description,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
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
        decoration: const InputDecoration(border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}
