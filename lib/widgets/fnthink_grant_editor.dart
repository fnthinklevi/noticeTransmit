import 'package:flutter/cupertino.dart';
import 'package:fnthink_push/fnthink_push.dart';

import '../l10n/app_localizations.dart';
import '../services/channel_display.dart';
import '../services/fnthink_grant_items.dart';
import '../services/fnthink_l2_actions.dart';
import '../services/fnthink_remote_action_categories.dart';
import '../services/fnthink_remote_action_labels.dart';
import '../theme/app_colors.dart';
import 'fnthink_card.dart';

/// 逐项授权编辑器（T174）：设备详情 → 权限那一页用的那一张表。
///
/// 与同意屏当初那张表是**同一份行集**（`pairItemRows` 从契约两张表现取），
/// 区别只在交互：这里改成「允许 / 不允许」两档，并把「高级项」那几组默认收起。
/// 行集、参数形状、拼串与判据都不在这里另写一份 —— 抄一份名单的下场是
/// "契约加了一项而某一页没加"，而那一格的缺席长得和"用户没兴趣"一模一样。
class FnthinkGrantEditor extends StatefulWidget {
  const FnthinkGrantEditor({
    super.key,
    required this.contract,
    required this.initialItems,
    required this.busy,
    required this.onChanged,
  });

  final FnthinkContract contract;

  /// 这一行现在已经勾上的整串（`<名>/<参数>`）。空 = 只到档位、一项都没给。
  final List<String> initialItems;

  /// 保存正在飞：这一期间所有开关与输入都锁住 —— 否则屏幕上会留下一张与刚签出去
  /// 那一份不一致的表。
  final bool busy;

  final ValueChanged<Set<String>> onChanged;

  @override
  State<FnthinkGrantEditor> createState() => _FnthinkGrantEditorState();
}

class _FnthinkGrantEditorState extends State<FnthinkGrantEditor> {
  late List<FnthinkGrantItemRow> _rows;
  late Set<String> _checked;
  final Map<String, _GrantArgumentDraft> _drafts = {};

  /// 展开的组。高级项那几组默认收起（见 `kFnthinkGrantCollapsedGroups`）：
  /// 高级项一屏铺开正是维护者反馈⑥说的"太抽象"。
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _rows = pairItemRows(widget.contract);
    _checked = Set<String>.of(widget.initialItems);
    _expandDefaults();
    _prefillDrafts();
  }

  void _expandDefaults() {
    for (final group in fnthinkRemoteItemGroups(_rows, (r) => r.base)) {
      if (!kFnthinkGrantCollapsedGroups.contains(group.slug)) {
        _expanded.add(group.slug);
      }
    }
  }

  void _prefillDrafts() {
    for (final item in widget.initialItems) {
      final base = widget.contract.grantItemBase(item);
      FnthinkGrantItemRow? row;
      for (final candidate in _rows) {
        if (candidate.base == base) row = candidate;
      }
      if (row == null || !row.needsArgument) continue;
      final draft = _draftFor(base);
      final argument = widget.contract.grantItemArgument(item);
      switch (row.kind) {
        case FnthinkGrantArgumentKind.count:
        case FnthinkGrantArgumentKind.keyword:
          draft.text.text = argument;
        case FnthinkGrantArgumentKind.toggle:
          final words = widget.contract.l3ItemTargetWords;
          if (argument == words.first) {
            draft.want = true;
          } else if (argument == words[1]) {
            draft.want = false;
          }
        case FnthinkGrantArgumentKind.channelTarget:
          final parsed = parseChannelTarget(widget.contract, argument);
          if (parsed != null) {
            draft.family = parsed.family;
            draft.text.text = parsed.id;
            draft.want = parsed.enabled;
          }
        case FnthinkGrantArgumentKind.none:
          break;
      }
    }
  }

  @override
  void dispose() {
    for (final draft in _drafts.values) {
      draft.dispose();
    }
    _drafts.clear();
    super.dispose();
  }

  _GrantArgumentDraft _draftFor(String base) =>
      _drafts.putIfAbsent(base, _GrantArgumentDraft.new);

  String _itemFor(FnthinkGrantItemRow row) => widget.contract.grantItemWire(
    base: row.base,
    argument: _draftFor(row.base).argumentFor(widget.contract, row.kind),
  );

  void _emit() => widget.onChanged(Set<String>.of(_checked));

  void _setAllowed(FnthinkGrantItemRow row, String item, bool allowed) {
    setState(() {
      if (allowed) {
        _checked.add(item);
      } else {
        _checked.removeWhere(
          (i) => widget.contract.grantItemBase(i) == row.base,
        );
      }
    });
    _emit();
  }

  void _editArgument(FnthinkGrantItemRow row, void Function() change) {
    setState(() {
      change();
      // 参数一变，先前那个勾说的就不是屏幕上现在这个东西了：擦掉这一名字下的所有勾选，
      // 让用户重新按新的整串点一次。
      _checked.removeWhere((i) => widget.contract.grantItemBase(i) == row.base);
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final group in fnthinkRemoteItemGroups(_rows, (r) => r.base))
          ..._group(l10n, group),
      ],
    );
  }

  List<Widget> _group(
    AppLocalizations l10n,
    FnthinkRemoteItemGroup<FnthinkGrantItemRow> group,
  ) {
    final advanced = kFnthinkGrantCollapsedGroups.contains(group.slug);
    final expanded = _expanded.contains(group.slug);
    final allowed = group.items
        .where((row) => _checked.contains(_itemFor(row)))
        .length;
    return [
      CupertinoButton(
        key: ValueKey(
          'fnthink-grant-group-${group.slug.isEmpty ? 'uncategorized' : group.slug}',
        ),
        padding: const EdgeInsets.symmetric(vertical: 6),
        minimumSize: Size.zero,
        onPressed: widget.busy
            ? null
            : () => setState(() {
                if (!_expanded.remove(group.slug)) _expanded.add(group.slug);
              }),
        child: Row(
          children: [
            Icon(
              expanded
                  ? CupertinoIcons.chevron_down
                  : CupertinoIcons.chevron_right,
              size: 14,
              color: AppColors.secondaryLabel(context),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: FnthinkRowLabel(
                keyName:
                    'fnthink-grant-group-title-${group.slug.isEmpty ? 'uncategorized' : group.slug}',
                label: advanced
                    ? '${fnthinkRemoteCategoryTitle(l10n, group.slug)} · ${l10n.fnthinkPeerGrantAdvanced}'
                    : fnthinkRemoteCategoryTitle(l10n, group.slug),
              ),
            ),
            Text(
              '$allowed/${group.items.length}',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.secondaryLabel(context),
              ),
            ),
          ],
        ),
      ),
      if (expanded)
        for (final row in group.items) ..._row(l10n, row),
    ];
  }

  List<Widget> _row(AppLocalizations l10n, FnthinkGrantItemRow row) {
    final item = _itemFor(row);
    final problem = grantItemProblem(widget.contract, item);
    final allowed = _checked.contains(item);
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              fnthinkRemoteActionLabel(l10n, row.base),
              style: TextStyle(
                fontSize: 13,
                color: AppColors.secondaryLabel(context),
              ),
            ),
          ),
          CupertinoSwitch(
            key: ValueKey('fnthink-grant-item-${row.base}'),
            value: allowed,
            onChanged: widget.busy || problem != null
                ? null
                : (v) => _setAllowed(row, item, v),
          ),
        ],
      ),
      // 维护者要的「一句影响说明」：短、每行都同一句，不替每一项编一句听上去不同的翻译。
      Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(
          l10n.fnthinkPeerGrantImpact,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.secondaryLabel(context),
          ),
        ),
      ),
      if (row.needsArgument) ..._argumentControls(l10n, row, item, problem),
    ];
  }

  List<Widget> _argumentControls(
    AppLocalizations l10n,
    FnthinkGrantItemRow row,
    String item,
    String? problem,
  ) {
    final draft = _draftFor(row.base);
    void edit(void Function() change) => _editArgument(row, change);
    return [
      if (problem != null)
        Text(
          problem,
          key: ValueKey('fnthink-grant-problem-${row.base}'),
          style: const TextStyle(fontSize: 11, color: AppColors.orange),
        ),
      if (row.kind == FnthinkGrantArgumentKind.count ||
          row.kind == FnthinkGrantArgumentKind.keyword)
        SizedBox(
          height: 34,
          child: CupertinoTextField(
            key: ValueKey('fnthink-grant-arg-${row.base}'),
            controller: draft.text,
            keyboardType: row.kind == FnthinkGrantArgumentKind.count
                ? TextInputType.number
                : TextInputType.text,
            placeholder: _argumentHint(row),
            autocorrect: false,
            onChanged: (_) => edit(() {}),
          ),
        ),
      if (row.kind == FnthinkGrantArgumentKind.toggle)
        _wantChips(
          l10n,
          'fnthink-grant-arg-${row.base}',
          widget.contract.l3ItemTargetWords,
          draft,
          edit,
        ),
      if (row.kind == FnthinkGrantArgumentKind.channelTarget) ...[
        FnthinkNote(
          keyName: 'fnthink-grant-arg-${row.base}-family-label',
          text: l10n.remoteSendFamilyLabel,
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final family in widget.contract.l2ChannelTargetFamilies)
              FnthinkChoiceChip(
                keyName: 'fnthink-grant-arg-${row.base}-family-$family',
                label: channelFamilyName(family),
                selected: draft.family == family,
                onTap: widget.busy
                    ? null
                    : () => edit(() => draft.family = family),
              ),
          ],
        ),
        SizedBox(
          height: 34,
          child: CupertinoTextField(
            key: ValueKey('fnthink-grant-arg-${row.base}-id'),
            controller: draft.text,
            placeholder: l10n.fnthinkPairChannelIdLabel,
            autocorrect: false,
            onChanged: (_) => edit(() {}),
          ),
        ),
        _wantChips(
          l10n,
          'fnthink-grant-arg-${row.base}',
          widget.contract.l2ChannelTargetWords,
          draft,
          edit,
        ),
      ],
    ];
  }

  Widget _wantChips(
    AppLocalizations l10n,
    String keyNamePrefix,
    List<String> words,
    _GrantArgumentDraft draft,
    void Function(void Function()) edit,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < words.length; i++)
          FnthinkChoiceChip(
            keyName: '$keyNamePrefix-${words[i]}',
            label: i == 0 ? l10n.remoteSendWantOn : l10n.remoteSendWantOff,
            selected: draft.want == (i == 0),
            onTap: widget.busy ? null : () => edit(() => draft.want = i == 0),
          ),
      ],
    );
  }

  String _argumentHint(FnthinkGrantItemRow row) {
    if (row.kind == FnthinkGrantArgumentKind.count) {
      return '${widget.contract.l2ReportMinItems(row.base) ?? 1}–'
          '${widget.contract.l2ReportMaxItems(row.base) ?? 1}';
    }
    return '${widget.contract.l2ReportMinChars(row.base) ?? 1}–'
        '${widget.contract.l2ReportMaxChars(row.base) ?? 1}';
  }
}

/// 一个「要参数」的项填到哪儿了（编辑器私有草稿，不是协议类型）。
///
/// 不拼带分隔符的整串：拼串的作者只有 `grantItemWire`（以及两种形状自己的
/// `buildChannelArgument` / L3 目标词）。界面只交出"选了哪一族、填了什么、要哪一档"。
class _GrantArgumentDraft {
  final TextEditingController text = TextEditingController();
  String? family;
  bool? want;

  String argumentFor(FnthinkContract contract, FnthinkGrantArgumentKind kind) =>
      switch (kind) {
        FnthinkGrantArgumentKind.none => '',
        FnthinkGrantArgumentKind.count ||
        FnthinkGrantArgumentKind.keyword => text.text.trim(),
        FnthinkGrantArgumentKind.toggle =>
          want == null ? '' : _targetWord(contract, want!),
        FnthinkGrantArgumentKind.channelTarget =>
          want == null
              ? ''
              : buildChannelArgument(
                  contract,
                  family: family ?? contract.l2ChannelTargetFamilies.first,
                  id: text.text.trim(),
                  enabled: want!,
                ),
      };

  static String _targetWord(FnthinkContract contract, bool wanted) {
    final words = contract.l3ItemTargetWords;
    return wanted ? words.first : words[1];
  }

  void dispose() => text.dispose();
}
