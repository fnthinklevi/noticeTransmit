import 'package:flutter/material.dart';
import '../models/notification_rule.dart';
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

  @override
  void initState() {
    super.initState();
    _rules = List<NotificationRule>.from(widget.rules);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('规则管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addRule,
            tooltip: '添加规则',
          ),
        ],
      ),
      body: _rules.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.filter_list_off,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  const Text('暂无规则'),
                  const SizedBox(height: 8),
                  TextButton(onPressed: _addRule, child: const Text('添加第一条规则')),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _rules.length,
              itemBuilder: (context, index) {
                final rule = _rules[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: Switch(
                      value: rule.enabled,
                      onChanged: (_) => _toggleRule(rule),
                    ),
                    title: Text(
                      rule.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: rule.enabled ? null : Colors.grey,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (rule.description.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(rule.description),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(_getConditionSummary(rule)),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(_getActionSummary(rule)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _editRule(rule),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () => _deleteRule(rule),
                          color: Colors.red,
                        ),
                      ],
                    ),
                    onTap: () => _editRule(rule),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addRule,
        child: const Icon(Icons.add),
      ),
    );
  }
}
