part of 'rule_edit_page.dart';

// R3 拆分：规则编辑页的辅助组件与条件/动作编辑对话框（part 共享私有类名）
// ignore_for_file: invalid_use_of_protected_member

/// iOS 风格选择器选项
class _IosOption<T> {
  final T value;
  final String label;
  final String? description;

  const _IosOption(this.value, this.label, [this.description]);
}

/// iOS 风格选择器：输入框样式 + 弹窗单选（替代 Material DropdownButton）
class _IosSelectField<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<_IosOption<T>> options;
  final ValueChanged<T?> onChanged;

  const _IosSelectField({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final current = options.where((o) => o.value == value).firstOrNull;
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
        InkWell(
          onTap: () => _showPicker(context),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.inputBg(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.separator(context)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    current?.label ?? l10n.ruleSelect,
                    style: TextStyle(
                      fontSize: 16,
                      color: current == null
                          ? AppColors.secondaryLabel(context)
                          : AppColors.primaryLabel(context),
                    ),
                    overflow: TextOverflow.ellipsis,
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
    );
  }

  void _showPicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.cardBg(context),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryLabel(context),
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 4),
                ...options.map((option) {
                  final selected = option.value == value;
                  return ListTile(
                    onTap: () {
                      onChanged(option.value);
                      Navigator.pop(dialogContext);
                    },
                    dense: true,
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          option.label,
                          style: TextStyle(
                            fontSize: 15,
                            color: AppColors.primaryLabel(context),
                          ),
                        ),
                        if (option.description != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            option.description!,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.secondaryLabel(context),
                            ),
                          ),
                        ],
                      ],
                    ),
                    trailing: selected
                        ? const Icon(Icons.check, color: AppColors.blue)
                        : null,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  );
                }),
              ],
            ),
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
    final l10n = AppLocalizations.of(context);
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
                          l10n.logicLabel(condition.logic),
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
                      l10n.conditionTypeLabel(condition.type),
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

  /// 生成延迟推送参数摘要文本（与原生 RuleEngine 参数键保持一致）
  String _delayParamsText(BuildContext context, RuleAction action) {
    final l10n = AppLocalizations.of(context);
    final parts = <String>[];
    final delaySeconds = action.params['delaySeconds'];
    if (delaySeconds is int && delaySeconds > 0) {
      if (delaySeconds % 60 == 0) {
        parts.add(l10n.ruleDelayMinute(delaySeconds ~/ 60));
      } else {
        parts.add(l10n.ruleDelaySecond(delaySeconds));
      }
    }
    final scheduleTime = action.params['scheduleTime']?.toString() ?? '';
    if (scheduleTime.isNotEmpty) {
      parts.add(l10n.ruleScheduleAt(scheduleTime));
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
                  l10n.actionTypeLabel(action.type),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryLabel(context),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    l10n.actionTypeDesc(action.type),
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.secondaryLabel(context),
                    ),
                  ),
                ),
                if (action.type == ActionType.delay && action.params.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _delayParamsText(context, action),
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.systemBlue(context),
                        fontWeight: FontWeight.w500,
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
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      backgroundColor: AppColors.cardBg(context),
      title: Text(
        l10n.ruleAddConditionTitle,
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
            _IosSelectField<ConditionType>(
              label: l10n.ruleConditionType,
              value: _selectedType,
              options: ConditionType.values
                  .map((t) => _IosOption(t, l10n.conditionTypeLabel(t)))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedType = value;
                });
              },
            ),
            const SizedBox(height: 16),
            _buildTextFieldSection(
              context,
              l10n.ruleConditionValue,
              _selectedType != null
                  ? l10n.conditionTypeHint(_selectedType!)
                  : '',
              (value) => _value = value,
              _valueController,
            ),
            const SizedBox(height: 16),
            _IosSelectField<LogicOperator>(
              label: l10n.ruleLogic,
              value: _logic,
              options: LogicOperator.values
                  .map((l) => _IosOption(l, l10n.logicLabel(l)))
                  .toList(),
              onChanged: (value) {
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
            l10n.cancel,
            style: TextStyle(
              fontSize: 16,
              color: AppColors.secondaryLabel(context),
            ),
          ),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(
            l10n.add,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.blue,
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
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      backgroundColor: AppColors.cardBg(context),
      title: Text(
        l10n.ruleEditCondition,
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
            _IosSelectField<ConditionType>(
              label: l10n.ruleConditionType,
              value: _type,
              options: ConditionType.values
                  .map((t) => _IosOption(t, l10n.conditionTypeLabel(t)))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _type = value!;
                });
              },
            ),
            const SizedBox(height: 16),
            _buildTextFieldSection(
              context,
              l10n.ruleConditionValue,
              l10n.conditionTypeHint(_type),
              (value) => _value = value,
              _valueController,
            ),
            const SizedBox(height: 16),
            _IosSelectField<LogicOperator>(
              label: l10n.ruleLogic,
              value: _logic,
              options: LogicOperator.values
                  .map((l) => _IosOption(l, l10n.logicLabel(l)))
                  .toList(),
              onChanged: (value) {
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
            l10n.cancel,
            style: TextStyle(
              fontSize: 16,
              color: AppColors.secondaryLabel(context),
            ),
          ),
        ),
        TextButton(
          onPressed: _submit,
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
  final TextEditingController _delaySecondsController = TextEditingController();
  final TextEditingController _scheduleTimeController = TextEditingController();

  @override
  void dispose() {
    _delaySecondsController.dispose();
    _scheduleTimeController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_selectedType != null) {
      widget.onAdd(
        RuleAction(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          type: _selectedType!,
          params: _buildParams(),
        ),
      );
      Navigator.pop(context);
    }
  }

  /// 延迟推送动作参数：delaySeconds（延迟秒数）/ scheduleTime（HH:mm 定时），
  /// 与原生 RuleEngine.computeFireAt 保持一致。
  Map<String, dynamic> _buildParams() {
    if (_selectedType != ActionType.delay) return const {};
    final params = <String, dynamic>{};
    final delaySeconds = int.tryParse(_delaySecondsController.text.trim());
    if (delaySeconds != null && delaySeconds > 0) {
      params['delaySeconds'] = delaySeconds;
    }
    final scheduleTime = _scheduleTimeController.text.trim();
    if (scheduleTime.isNotEmpty) {
      params['scheduleTime'] = scheduleTime;
    }
    return params;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      backgroundColor: AppColors.cardBg(context),
      title: Text(
        l10n.ruleAddActionTitle,
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
            _IosSelectField<ActionType>(
              label: l10n.ruleActionType,
              value: _selectedType,
              options: ActionType.values
                  .map(
                    (t) => _IosOption(
                      t,
                      l10n.actionTypeLabel(t),
                      l10n.actionTypeDesc(t),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedType = value;
                });
              },
            ),
            if (_selectedType == ActionType.delay) ...[
              const SizedBox(height: 16),
              _DelayParamsFields(
                delaySecondsController: _delaySecondsController,
                scheduleTimeController: _scheduleTimeController,
              ),
            ],
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
              color: AppColors.secondaryLabel(context),
            ),
          ),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(
            l10n.add,
            style: const TextStyle(
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
  final TextEditingController _delaySecondsController = TextEditingController();
  final TextEditingController _scheduleTimeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _type = widget.action.type;
    final params = widget.action.params;
    final delaySeconds = params['delaySeconds'];
    if (delaySeconds is int && delaySeconds > 0) {
      _delaySecondsController.text = delaySeconds.toString();
    }
    final scheduleTime = params['scheduleTime']?.toString() ?? '';
    if (scheduleTime.isNotEmpty) {
      _scheduleTimeController.text = scheduleTime;
    }
  }

  @override
  void dispose() {
    _delaySecondsController.dispose();
    _scheduleTimeController.dispose();
    super.dispose();
  }

  void _submit() {
    final params = <String, dynamic>{};
    if (_type == ActionType.delay) {
      final delaySeconds = int.tryParse(_delaySecondsController.text.trim());
      if (delaySeconds != null && delaySeconds > 0) {
        params['delaySeconds'] = delaySeconds;
      }
      final scheduleTime = _scheduleTimeController.text.trim();
      if (scheduleTime.isNotEmpty) {
        params['scheduleTime'] = scheduleTime;
      }
    }
    widget.onSave(widget.action.copyWith(type: _type, params: params));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      backgroundColor: AppColors.cardBg(context),
      title: Text(
        l10n.ruleEditAction,
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
            _IosSelectField<ActionType>(
              label: l10n.ruleActionType,
              value: _type,
              options: ActionType.values
                  .map(
                    (t) => _IosOption(
                      t,
                      l10n.actionTypeLabel(t),
                      l10n.actionTypeDesc(t),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _type = value!;
                });
              },
            ),
            if (_type == ActionType.delay) ...[
              const SizedBox(height: 16),
              _DelayParamsFields(
                delaySecondsController: _delaySecondsController,
                scheduleTimeController: _scheduleTimeController,
              ),
            ],
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
              color: AppColors.secondaryLabel(context),
            ),
          ),
        ),
        TextButton(
          onPressed: _submit,
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
    );
  }
}

/// 延迟推送动作的参数输入区（延迟秒数 + 定时时间），Add/Edit 对话框共用。
class _DelayParamsFields extends StatelessWidget {
  final TextEditingController delaySecondsController;
  final TextEditingController scheduleTimeController;

  const _DelayParamsFields({
    required this.delaySecondsController,
    required this.scheduleTimeController,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            l10n.ruleDelayTitle,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.secondaryLabel(context),
            ),
          ),
        ),
        TextField(
          controller: delaySecondsController,
          keyboardType: TextInputType.number,
          style: TextStyle(color: AppColors.primaryLabel(context)),
          decoration: InputDecoration(
            labelText: l10n.ruleDelaySeconds,
            hintText: l10n.ruleDelaySecondsHint,
            labelStyle: TextStyle(color: AppColors.secondaryLabel(context)),
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
        const SizedBox(height: 12),
        TextField(
          controller: scheduleTimeController,
          keyboardType: TextInputType.datetime,
          style: TextStyle(color: AppColors.primaryLabel(context)),
          decoration: InputDecoration(
            labelText: l10n.ruleScheduleTime,
            hintText: l10n.ruleScheduleTimeHint,
            labelStyle: TextStyle(color: AppColors.secondaryLabel(context)),
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
