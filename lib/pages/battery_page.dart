import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class Slideable extends StatefulWidget {
  final String ruleId;
  final bool enabled;
  final VoidCallback onDelete;
  final Widget child;

  const Slideable({
    super.key,
    required this.ruleId,
    required this.enabled,
    required this.onDelete,
    required this.child,
  });

  @override
  State<Slideable> createState() => _SlideableState();
}

class _SlideableState extends State<Slideable> {
  double _offset = 0;
  double _startX = 0;
  bool _isDragging = false;
  static const double _maxOffset = -80;

  void _onPanStart(DragStartDetails details) {
    if (!widget.enabled) return;
    _startX = details.globalPosition.dx;
    _isDragging = true;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!widget.enabled || !_isDragging) return;
    final delta = details.globalPosition.dx - _startX;
    setState(() {
      _offset = delta.clamp(_maxOffset, 0);
    });
    _startX = details.globalPosition.dx;
  }

  void _onPanEnd(DragEndDetails details) {
    if (!widget.enabled || !_isDragging) return;
    _isDragging = false;
    setState(() {
      if (_offset < _maxOffset / 2) {
        _offset = _maxOffset;
      } else {
        _offset = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: Transform.translate(
        offset: Offset(_offset, 0),
        child: widget.child,
      ),
    );
  }
}

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
    final batteryColor = widget.currentLevel >= 50
        ? const Color(0xFF34C759)
        : widget.currentLevel >= 20
        ? const Color(0xFFFF9500)
        : const Color(0xFFFF3B30);

    return Scaffold(
      appBar: AppBar(
        title: const Text('电量'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加规则',
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
                    widget.currentLevel < 0 ? '未知' : '${widget.currentLevel}%',
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w300,
                      color: batteryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.isCharging ? '充电中' : '未充电',
                    style: TextStyle(
                      fontSize: 15,
                      color: AppColors.secondaryLabel(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            _buildSectionHeader('提醒设置', context),
            _buildGroup([
              _buildSwitchRow(
                icon: Icons.power_settings_new,
                iconColor: const Color(0xFF007AFF),
                title: '电量通知总开关',
                subtitle: '开启后以下提醒才会生效',
                value: widget.notifyEnabled,
                onChanged: widget.onToggleNotify,
                context: context,
              ),
            ], context),
            const SizedBox(height: 24),
            _buildSectionHeader('通知规则', context),
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
            _buildSectionHeader('说明', context),
            _buildGroup([
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DescRow(text: '低电量提醒仅在非充电状态下触发', context: context),
                    const SizedBox(height: 8),
                    _DescRow(text: '电量回升到阈值以上才会重置提醒状态', context: context),
                    const SizedBox(height: 8),
                    _DescRow(text: '电量通知随通知监听服务一起运行', context: context),
                    const SizedBox(height: 8),
                    _DescRow(text: '点击规则可编辑，左滑或长按可删除', context: context),
                  ],
                ),
              ),
            ], context),
          ],
        ),
      ),
    );
  }

  Widget _buildRuleTile(Map<String, dynamic> rule, BuildContext context) {
    final type = rule['type'] as String;
    final value = rule['value'] as int;
    final enabled = rule['enabled'] as bool;
    final title = rule['title'] as String;

    IconData icon;
    Color iconColor;
    String subtitle;

    switch (type) {
      case 'charging':
        icon = Icons.battery_charging_full;
        iconColor = const Color(0xFF34C759);
        subtitle = '手机接入充电器时推送';
        break;
      case 'discharging':
        icon = Icons.battery_0_bar;
        iconColor = const Color(0xFFFF9500);
        subtitle = '手机断开充电器时推送';
        break;
      case 'level_above':
        icon = Icons.battery_full;
        iconColor = const Color(0xFF007AFF);
        subtitle = '电量达到 $value% 时推送';
        break;
      case 'level_below':
        icon = Icons.battery_alert;
        iconColor = const Color(0xFFFF3B30);
        subtitle = '电量低于 $value% 时推送';
        break;
      case 'level_equals':
        icon = Icons.equalizer;
        iconColor = const Color(0xFFAF52DE);
        subtitle = '电量等于 $value% 时推送';
        break;
      default:
        icon = Icons.help_outline;
        iconColor = Colors.grey;
        subtitle = '未知规则类型';
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
    return Stack(
      children: [
        Positioned.fill(
          right: 0,
          child: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            child: TextButton(
              onPressed: widget.notifyEnabled
                  ? () => _showDeleteConfirmDialog(rule['id'] as String)
                  : null,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: const Color(0xFFFF3B30),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete_outline, size: 20),
                  SizedBox(width: 8),
                  Text('删除'),
                ],
              ),
            ),
          ),
        ),
        Slideable(
          ruleId: rule['id'] as String,
          enabled: widget.notifyEnabled,
          onDelete: () => _showDeleteConfirmDialog(rule['id'] as String),
          child: Container(
            color: AppColors.cardBg(context),
            child: InkWell(
              onTap: widget.notifyEnabled && enabled
                  ? () => _showEditRuleDialog(rule)
                  : null,
              onLongPress: widget.notifyEnabled
                  ? () => _showDeleteConfirmDialog(rule['id'] as String)
                  : null,
              child: _buildSwitchRow(
                icon: icon,
                iconColor: iconColor,
                title: title,
                subtitle: subtitle,
                value: enabled,
                onChanged: widget.notifyEnabled
                    ? (v) => widget.onToggleRule(rule['id'] as String, v)
                    : null,
                context: context,
                trailing: null,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showAddRuleDialog() {
    _showRuleDialog(null);
  }

  void _showEditRuleDialog(Map<String, dynamic> rule) {
    _showRuleDialog(rule);
  }

  void _showRuleDialog(Map<String, dynamic>? existingRule) {
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
                isEdit ? '编辑规则' : '添加规则',
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
                        '规则类型',
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
                          '开始充电',
                          selectedType,
                          setDialogState,
                          (v) => selectedType = v,
                          context,
                        ),
                        _buildTypeChip(
                          'discharging',
                          '断开充电',
                          selectedType,
                          setDialogState,
                          (v) => selectedType = v,
                          context,
                        ),
                        _buildTypeChip(
                          'level_below',
                          '低于某值',
                          selectedType,
                          setDialogState,
                          (v) => selectedType = v,
                          context,
                        ),
                        _buildTypeChip(
                          'level_above',
                          '高于某值',
                          selectedType,
                          setDialogState,
                          (v) => selectedType = v,
                          context,
                        ),
                        _buildTypeChip(
                          'level_equals',
                          '等于某值',
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
                          '电量阈值（%）',
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
                                activeColor: const Color(0xFF007AFF),
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
                        '自定义标题（可选）',
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
                        hintText: '留空则使用默认标题',
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
                          borderSide: const BorderSide(
                            color: Color(0xFF007AFF),
                          ),
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
                    '取消',
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
                        ? existingRule['id'] as String
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
                      widget.onAddRule(newRule);
                    }
                    Navigator.pop(context);
                  },
                  child: Text(
                    isEdit ? '保存' : '添加',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF007AFF),
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
        color: isSelected
            ? const Color(0xFF007AFF)
            : AppColors.inputBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? const Color(0xFF007AFF)
              : AppColors.separator(context),
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
    switch (type) {
      case 'charging':
        return '开始充电';
      case 'discharging':
        return '断开充电';
      case 'level_above':
        return '电量达到$value%';
      case 'level_below':
        return '电量低于$value%';
      case 'level_equals':
        return '电量等于$value%';
      default:
        return '电量提醒';
    }
  }

  void _showDeleteConfirmDialog(String id) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.cardBg(context),
          title: Text(
            '删除规则',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryLabel(context),
            ),
          ),
          content: Text(
            '确定要删除这条通知规则吗？',
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
                '取消',
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFFF3B30),
              ),
              onPressed: () {
                widget.onDeleteRule(id);
                Navigator.pop(context);
              },
              child: Text(
                '删除',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFFF3B30),
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
