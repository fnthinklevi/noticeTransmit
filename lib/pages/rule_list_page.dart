import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';
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
    final l10n = AppLocalizations.of(context);
    final newRule = NotificationRule(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: l10n.ruleNew,
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
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.confirmDeleteRule),
        content: Text(l10n.ruleDeleteMsg(rule.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _rules.removeWhere((r) => r.id == rule.id);
              });
              _saveRules();
              Navigator.pop(context);
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  void _saveRules() {
    _rules.sort((a, b) => b.priority.compareTo(a.priority));
    widget.onSave(_rules);
  }

  String _getConditionSummary(BuildContext context, NotificationRule rule) {
    final l10n = AppLocalizations.of(context);
    if (rule.conditions.isEmpty) {
      return l10n.ruleNoCondition;
    }
    return rule.conditions
        .map((c) => l10n.conditionTypeLabel(c.type))
        .join(' ${l10n.logicAnd} ');
  }

  String _getActionSummary(BuildContext context, NotificationRule rule) {
    final l10n = AppLocalizations.of(context);
    if (rule.actions.isEmpty) {
      return l10n.ruleNoAction;
    }
    return rule.actions.map((a) => l10n.actionTypeLabel(a.type)).join(' → ');
  }

  Widget _buildRuleList() {
    final l10n = AppLocalizations.of(context);
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
                  l10n.ruleListEmpty,
                  style: TextStyle(
                    fontSize: 17,
                    color: AppColors.primaryLabel(context),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _addRule,
                  child: Text(
                    l10n.ruleAddFirst,
                    style: const TextStyle(
                      fontSize: 16,
                      color: AppColors.blue,
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
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
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
                                _getConditionSummary(context, rule),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.systemBlue(context),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
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
                                _getActionSummary(context, rule),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.systemGreen(context),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
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
                                l10n.rulePriorityBadge(rule.priority + 1),
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
                                l10n.edit,
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
                                l10n.delete,
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
    final l10n = AppLocalizations.of(context);
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
            Text(l10n.ruleGuideTitle),
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
                l10n.ruleGuideAdd,
                l10n.ruleGuideAddDesc,
              ),
              const SizedBox(height: 16),
              _buildGuideItem(
                context,
                Icons.filter_alt,
                AppColors.systemOrange(context),
                l10n.ruleGuideCondition,
                l10n.ruleGuideConditionDesc,
              ),
              const SizedBox(height: 16),
              _buildGuideItem(
                context,
                Icons.play_arrow,
                AppColors.systemGreen(context),
                l10n.ruleGuideAction,
                l10n.ruleGuideActionDesc,
              ),
              const SizedBox(height: 16),
              _buildGuideItem(
                context,
                Icons.toggle_on,
                AppColors.systemPurple(context),
                l10n.ruleGuideEnable,
                l10n.ruleGuideEnableDesc,
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.systemBlue(context).withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  l10n.ruleGuideTip,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.ruleGuideGotIt),
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
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
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
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.ruleListTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: _showGuideDialog,
            tooltip: l10n.ruleHelp,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addRule,
            tooltip: l10n.ruleAddTooltip,
          ),
        ],
      ),
      body: _buildRuleList(),
      floatingActionButton: FloatingActionButton(
        onPressed: _addRule,
        backgroundColor: AppColors.blue,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
