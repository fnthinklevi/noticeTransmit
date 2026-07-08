import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/notification_rule.dart';
import '../theme/app_colors.dart';
import 'rule_edit_page.dart';

class RuleListPage extends StatefulWidget {
  final List<NotificationRule> rules;
  final Function(List<NotificationRule>) onSave;

  const RuleListPage({super.key, required this.rules, required this.onSave});

  @override
  State<RuleListPage> createState() => _RuleListPageState();
}

class _RuleListPageState extends State<RuleListPage> {
  late List<NotificationRule> _rules;
  bool _showGuide = false;

  @override
  void initState() {
    super.initState();
    _rules = List<NotificationRule>.from(widget.rules);
    _checkFirstTime();
  }

  Future<void> _checkFirstTime() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenGuide = prefs.getBool('rule_engine_guide_seen') ?? false;
    if (!hasSeenGuide) {
      setState(() => _showGuide = true);
      await prefs.setBool('rule_engine_guide_seen', true);
    }
  }

  void _addRule() async {
    final newRule = NotificationRule(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: '新规则',
      description: '',
      enabled: true,
      priority: _rules.length,
      conditions: [],
      actions: [RuleAction(id: 'a1', type: ActionType.push)],
    );

    final result = await Navigator.push<NotificationRule>(
      context,
      MaterialPageRoute(builder: (context) => RuleEditPage(rule: newRule)),
    );

    if (result != null) {
      setState(() {
        _rules.add(result);
      });
      _saveRules();
    }
  }

  void _editRule(NotificationRule rule) async {
    final result = await Navigator.push<NotificationRule>(
      context,
      MaterialPageRoute(builder: (context) => RuleEditPage(rule: rule)),
    );

    if (result != null) {
      setState(() {
        final index = _rules.indexWhere((r) => r.id == rule.id);
        if (index != -1) {
          _rules[index] = result;
        }
      });
      _saveRules();
    }
  }

  void _toggleRule(NotificationRule rule) {
    setState(() {
      final index = _rules.indexWhere((r) => r.id == rule.id);
      if (index != -1) {
        _rules[index] = rule.copyWith(enabled: !rule.enabled);
      }
    });
    _saveRules();
  }

  void _deleteRule(NotificationRule rule) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除规则「${rule.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _rules.removeWhere((r) => r.id == rule.id);
              });
              _saveRules();
              Navigator.pop(context);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _saveRules() {
    _rules.sort((a, b) => b.priority.compareTo(a.priority));
    widget.onSave(_rules);
  }

  String _getConditionSummary(NotificationRule rule) {
    if (rule.conditions.isEmpty) {
      return '无条件';
    }
    return rule.conditions.map((c) => c.type.label).join(' 且 ');
  }

  String _getActionSummary(NotificationRule rule) {
    if (rule.actions.isEmpty) {
      return '无动作';
    }
    return rule.actions.map((a) => a.type.label).join(' → ');
  }

  Widget _buildRuleList() {
    return _rules.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.systemGray(context),
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: Icon(
                    Icons.filter_list_off,
                    size: 40,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '暂无规则',
                  style: TextStyle(
                    fontSize: 17,
                    color: AppColors.primaryLabel(context),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _addRule,
                  child: Text(
                    '添加第一条规则',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF007AFF),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: _rules.length,
            itemBuilder: (context, index) {
              final rule = _rules[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
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
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            CupertinoSwitch(
                              value: rule.enabled,
                              onChanged: (_) => _toggleRule(rule),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    rule.name,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: rule.enabled
                                          ? AppColors.primaryLabel(context)
                                          : AppColors.secondaryLabel(context),
                                    ),
                                  ),
                                  if (rule.description.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        rule.description,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: AppColors.secondaryLabel(
                                            context,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.systemBlue(
                                  context,
                                ).withAlpha(20),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _getConditionSummary(rule),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.systemBlue(context),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.systemGreen(
                                  context,
                                ).withAlpha(20),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _getActionSummary(rule),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.systemGreen(context),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.systemGray(context),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '优先级 ${rule.priority + 1}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.secondaryLabel(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        color: AppColors.separator(context),
                        height: 0.5,
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => _editRule(rule),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                              child: Text(
                                '编辑',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: AppColors.systemBlue(context),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                          Container(
                            color: AppColors.separator(context),
                            width: 0.5,
                            height: 24,
                          ),
                          Expanded(
                            child: TextButton(
                              onPressed: () => _deleteRule(rule),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                              child: Text(
                                '删除',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: AppColors.systemRed(context),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_showGuide) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showGuideDialog();
        setState(() => _showGuide = false);
      });
    }
  }

  void _showGuideDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.lightbulb_outline,
              color: AppColors.systemYellow(context),
            ),
            const SizedBox(width: 8),
            const Text('规则引擎介绍'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              _buildGuideItem(
                context,
                Icons.plus_one,
                AppColors.systemBlue(context),
                '添加规则',
                '点击右上角「+」或右下角浮动按钮创建新规则',
              ),
              const SizedBox(height: 16),
              _buildGuideItem(
                context,
                Icons.filter_alt,
                AppColors.systemOrange(context),
                '设置条件',
                '配置触发规则的条件（IF），如应用包名、关键词、时间等',
              ),
              const SizedBox(height: 16),
              _buildGuideItem(
                context,
                Icons.play_arrow,
                AppColors.systemGreen(context),
                '执行动作',
                '设置满足条件后执行的动作（THEN），如推送通知、静默忽略等',
              ),
              const SizedBox(height: 16),
              _buildGuideItem(
                context,
                Icons.toggle_on,
                AppColors.systemPurple(context),
                '启用规则',
                '通过开关控制规则是否生效，未启用的规则不会执行',
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.systemBlue(context).withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '提示：规则按优先级顺序执行，匹配第一条规则后即停止。可通过编辑规则调整优先级。',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Widget _buildGuideItem(
    BuildContext context,
    IconData icon,
    Color iconColor,
    String title,
    String description,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: iconColor.withAlpha(20),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('规则管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: _showGuideDialog,
            tooltip: '使用帮助',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addRule,
            tooltip: '添加规则',
          ),
        ],
      ),
      body: _buildRuleList(),
      floatingActionButton: FloatingActionButton(
        onPressed: _addRule,
        backgroundColor: const Color(0xFF007AFF),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
