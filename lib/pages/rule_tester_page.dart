import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../l10n/app_localizations.dart';
import '../services/filter_service.dart';
import '../services/installed_apps_service.dart';
import '../services/rule_trace.dart';
import '../theme/app_colors.dart';
import '../widgets/app_text_selection_menu.dart';
import '../widgets/ios_dialog_actions.dart';

/// F1 规则测试器：输入模拟通知，实时展示完整命中链路
///（① 过滤 → ② 规则匹配 → ③ 最终动作）。
///
/// 评估由 [RuleTracer] 完成（纯函数，与原生 FilterEngine/RuleEngine 逐条对齐）；
/// 本页只负责输入采集与结果渲染。
class RuleTesterPage extends StatefulWidget {
  const RuleTesterPage({super.key});

  @override
  State<RuleTesterPage> createState() => _RuleTesterPageState();
}

class _RuleTesterPageState extends State<RuleTesterPage> {
  final _pkgController = TextEditingController(text: 'com.tencent.mm');
  final _appNameController = TextEditingController(text: '微信');
  final _titleController = TextEditingController(text: '张三');
  final _contentController = TextEditingController(text: '在吗？');

  /// 0=低 1=中 2=高（与原生 NotificationInfo.priority 同口径）
  int _priority = 1;
  RuleTraceResult? _result;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    for (final c in [_pkgController, _titleController, _contentController]) {
      c.addListener(_recompute);
    }
    _init();
  }

  @override
  void dispose() {
    _pkgController.dispose();
    _appNameController.dispose();
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final filter = GetIt.instance<FilterService>();
    await filter.loadSettings();
    _recompute();
    if (mounted) setState(() => _loading = false);
  }

  /// 实时重算（纯函数，规则数量级下开销可忽略）
  void _recompute() {
    if (!mounted) return;
    final filter = GetIt.instance<FilterService>();
    final result = RuleTracer.trace(
      filter,
      packageName: _pkgController.text.trim(),
      title: _titleController.text,
      content: _contentController.text,
      notifyPriority: _priority,
    );
    setState(() => _result = result);
  }

  Future<void> _pickApp() async {
    // 列表由对话框自行加载（缓存优先 + 全量兜底，无权限时展示空列表）
    // T90 片27：外壳收进 `IosDialogActions.showExplainer`（正文高度 420 经 [bodyHeight] 传进去），
    // 这里只剩选择器本身。⚠ 旧形状的 `apps` 入参**唯一调用点一直传空列表**
    // （`_AppPickDialog(apps: [])`，注释也写着「由对话框自行加载」）⇒ 那个口从来没接过东西，一并去掉。
    final selected = await IosDialogActions.showExplainer<Map<String, dynamic>>(
      context,
      title: AppLocalizations.of(context).testerPickApp,
      gotItText: AppLocalizations.of(context).cancel,
      bodyHeight: 420,
      body: const _AppPickBody(),
    );
    if (selected == null) return;
    if (!mounted) return;
    setState(() {
      _pkgController.text = selected['packageName']?.toString() ?? '';
      _appNameController.text = selected['appName']?.toString() ?? '';
    });
    _recompute();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(title: Text(l10n.ruleTesterTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Text(
                  l10n.testerHint,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
                const SizedBox(height: 12),
                _buildInputCard(context, l10n),
                const SizedBox(height: 12),
                _buildResult(context, l10n),
              ],
            ),
    );
  }

  // ── 输入区 ──

  Widget _buildInputCard(BuildContext context, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(context, l10n.testerInputSection),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _textField(
                  context,
                  _pkgController,
                  l10n.testerAppPackage,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _pickApp,
                icon: const Icon(Icons.apps, color: AppColors.blue),
                tooltip: l10n.testerPickApp,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _textField(context, _titleController, l10n.testerTitleField),
          const SizedBox(height: 10),
          TextField(
            contextMenuBuilder: AppTextSelectionMenu.editableText,
            controller: _contentController,
            maxLines: 3,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.primaryLabel(context),
            ),
            decoration: _inputDecoration(context, l10n.testerContentField),
          ),
          const SizedBox(height: 14),
          Text(
            l10n.testerPriorityLabel,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.secondaryLabel(context),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              _priorityChip(context, 2, l10n.testerPriorityHigh, AppColors.red),
              _priorityChip(
                context,
                1,
                l10n.testerPriorityMid,
                const Color(0xFFFF9500),
              ),
              _priorityChip(context, 0, l10n.testerPriorityLow, Colors.grey),
            ],
          ),
        ],
      ),
    );
  }

  Widget _priorityChip(
    BuildContext context,
    int value,
    String label,
    Color color,
  ) {
    final selected = _priority == value;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(fontSize: 13, color: selected ? Colors.white : color),
      ),
      selected: selected,
      selectedColor: color,
      backgroundColor: color.withValues(alpha: 0.1),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      onSelected: (_) {
        setState(() => _priority = value);
        _recompute();
      },
    );
  }

  // ── 结果区 ──

  Widget _buildResult(BuildContext context, AppLocalizations l10n) {
    final result = _result;
    if (result == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFilterCard(context, l10n, result),
        const SizedBox(height: 12),
        _buildRuleCard(context, l10n, result),
        const SizedBox(height: 12),
        _buildActionCard(context, l10n, result),
      ],
    );
  }

  Widget _buildFilterCard(
    BuildContext context,
    AppLocalizations l10n,
    RuleTraceResult r,
  ) {
    final ok = r.allowed;
    final color = ok ? AppColors.green : AppColors.red;
    return _stageCard(
      context,
      title: l10n.testerStageFilter,
      statusText: ok ? l10n.testerAllowed : l10n.testerBlocked,
      statusColor: color,
      children: [
        Text(
          switch (r.filterSource) {
            TraceFilterSource.blacklist => l10n.testerSrcBlacklist(
              r.filterKeyword,
            ),
            TraceFilterSource.whitelist => l10n.testerSrcWhitelist(
              r.filterKeyword,
            ),
            TraceFilterSource.appFilter => l10n.testerSrcAppFilter,
            TraceFilterSource.defaultPass => l10n.testerSrcDefault,
          },
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            color: AppColors.primaryLabel(context),
          ),
        ),
        if (!ok) ...[
          const SizedBox(height: 6),
          Text(
            l10n.testerFilteredNote,
            style: const TextStyle(fontSize: 12, color: AppColors.red),
          ),
        ],
      ],
    );
  }

  Widget _buildRuleCard(
    BuildContext context,
    AppLocalizations l10n,
    RuleTraceResult r,
  ) {
    final hit = r.hitRule;
    return _stageCard(
      context,
      title: l10n.testerStageRules,
      statusText: hit != null ? l10n.testerRuleHit : l10n.testerNoRules,
      statusColor: hit != null
          ? AppColors.blue
          : AppColors.secondaryLabel(context),
      children: [
        if (r.ruleEntries.isEmpty && r.allowed)
          Text(
            l10n.testerNoRules,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.secondaryLabel(context),
            ),
          ),
        for (final e in r.ruleEntries)
          _buildRuleRow(context, l10n, e, hit?.id == e.rule.id),
      ],
    );
  }

  Widget _buildRuleRow(
    BuildContext context,
    AppLocalizations l10n,
    TraceRuleEntry e,
    bool isHit,
  ) {
    final (markText, markColor) = switch (e.mark) {
      TraceRuleMark.hit => (l10n.testerRuleHit, AppColors.blue),
      TraceRuleMark.missed => (
        l10n.testerRuleMissed,
        AppColors.secondaryLabel(context),
      ),
      TraceRuleMark.disabled => (l10n.testerRuleDisabled, Colors.grey),
      TraceRuleMark.excluded => (
        l10n.testerRuleExcluded,
        const Color(0xFFFF9500),
      ),
    };
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isHit
            ? AppColors.blue.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isHit
              ? AppColors.blue.withValues(alpha: 0.5)
              : AppColors.separator(context),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${e.rule.name}（P${e.rule.priority}）',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.primaryLabel(context),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            markText,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: markColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context,
    AppLocalizations l10n,
    RuleTraceResult r,
  ) {
    final (text, color) = switch (r.action) {
      TraceActionKind.silent => (
        l10n.testerActionSilent,
        const Color(0xFFFF9500),
      ),
      TraceActionKind.delay => (
        l10n.testerActionDelay(_formatFireAt(r.delayFireAtMs)),
        AppColors.blue,
      ),
      TraceActionKind.merge => (
        [
          l10n.testerActionMerge(r.mergeWindowSeconds ?? 60),
          if (r.mergeMaxItems > 0)
            l10n.ruleMergeMaxItemsSummary(r.mergeMaxItems),
          if (r.mergeGroupByTitle) l10n.ruleMergeGroupByTitleSummary,
        ].join(' · '),
        AppColors.blue,
      ),
      TraceActionKind.record => (l10n.testerActionRecord, AppColors.green),
      TraceActionKind.push => (l10n.testerActionPush, AppColors.green),
    };
    return _stageCard(
      context,
      title: l10n.testerStageAction,
      statusText: text,
      statusColor: color,
      children: const [],
    );
  }

  String _formatFireAt(int? ms) {
    if (ms == null) return '-';
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final ss = t.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  // ── 通用小部件 ──

  Widget _stageCard(
    BuildContext context, {
    required String title,
    required String statusText,
    required Color statusColor,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _sectionTitle(context, title)),
              Text(
                statusText,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
            ],
          ),
          if (children.isNotEmpty) ...[const SizedBox(height: 8), ...children],
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Text(
    text,
    style: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: AppColors.secondaryLabel(context),
    ),
  );

  Widget _textField(
    BuildContext context,
    TextEditingController c,
    String label,
  ) => TextField(
    contextMenuBuilder: AppTextSelectionMenu.editableText,
    controller: c,
    style: TextStyle(fontSize: 14, color: AppColors.primaryLabel(context)),
    decoration: _inputDecoration(context, label),
  );

  InputDecoration _inputDecoration(BuildContext context, String label) =>
      InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          fontSize: 13,
          color: AppColors.secondaryLabel(context),
        ),
        fillColor: AppColors.inputBg(context),
        filled: true,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.separator(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.blue),
        ),
      );
}

/// 应用选择那块正文（复用已安装应用缓存，搜索过滤）。
///
/// T90 片27：外壳（`AlertDialog`）收进 `IosDialogActions.showExplainer`，这里只剩选择器本身 ——
/// 搜索框、「显示系统应用」开关、应用列表。选中一行仍是 `Navigator.pop(context, a)`
/// 把那个 Map 带出去（与 `showIosOptionPicker` 同一个思路：带值的是正文里的行，不是外壳）。
class _AppPickBody extends StatefulWidget {
  const _AppPickBody();

  @override
  State<_AppPickBody> createState() => _AppPickBodyState();
}

class _AppPickBodyState extends State<_AppPickBody> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _apps = [];
  bool _showSystem = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_apps.isNotEmpty) {
      setState(() => _loading = false);
      return;
    }
    try {
      final svc = GetIt.instance<InstalledAppsService>();
      var list = await svc.loadCached();
      if (list.isEmpty) list = await svc.load();
      _apps = list;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final q = _search.text.trim().toLowerCase();
    final filtered = _apps.where((a) {
      if (!_showSystem && (a['isSystemApp'] as bool? ?? false)) return false;
      if (q.isEmpty) return true;
      final name = (a['appName'] as String? ?? '').toLowerCase();
      final pkg = (a['packageName'] as String? ?? '').toLowerCase();
      return name.contains(q) || pkg.contains(q);
    }).toList();

    // ⚠ T90 片27：这里返回的是**正文**，不再是弹层。标题、那颗「取消」、正文高度 420、
    //   以及「点外面关得掉」全都归 `showExplainer` 那一边管了。
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              TextField(
                contextMenuBuilder: AppTextSelectionMenu.editableText,
                controller: _search,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.primaryLabel(context),
                ),
                decoration: InputDecoration(
                  hintText: l10n.searchAppHint,
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: AppColors.secondaryLabel(context),
                  ),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true,
                  fillColor: AppColors.inputBg(context),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.separator(context)),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.showSystemApps,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.secondaryLabel(context),
                      ),
                    ),
                  ),
                  CupertinoSwitch(
                    value: _showSystem,
                    activeTrackColor: AppColors.blue,
                    onChanged: (v) => setState(() => _showSystem = v),
                  ),
                ],
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final a = filtered[i];
                    return ListTile(
                      dense: true,
                      title: Text(
                        a['appName'] as String? ?? '',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.primaryLabel(context),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        a['packageName'] as String? ?? '',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.secondaryLabel(context),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.pop(context, a),
                    );
                  },
                ),
              ),
            ],
          );
  }
}
