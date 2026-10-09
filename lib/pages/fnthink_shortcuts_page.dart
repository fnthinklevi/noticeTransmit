import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/fnthink_shortcut_registry.dart';
import '../theme/app_colors.dart';
import '../widgets/fnthink_card.dart';
import '../widgets/ios_dialog_actions.dart';
import '../widgets/ios_form_dialog.dart';

/// 「可被远程打开的入口」这一页（T124 片B 的 `app:launch` 的本机那一半）。
///
/// ## 这一页存在的原因
/// 对面只能打开**你在这里登记过**的东西：Android 上没有第二条合法路 ——
/// 要么那枚 App 自己公开的 deeplink，要么你亲手写下"用这个组件名打开它"。
/// 所以这一页不是"高级设置"，它就是这条能力**本身**：不登记，对面那个动作对不上名字、
/// 什么都不会做（fail-closed，不猜一条最像的）。
///
/// ## 名字是给对面点的名
/// 本机的清单**不出门**：只有"请你打开 <名字>"这一句过线，名字到目标的映射留在本机。
/// 名字由你起（同一台设备上的两份"名字→目标"不许重名 —— 重名等于有一条永远点不到）。
class FnthinkShortcutsPage extends StatefulWidget {
  const FnthinkShortcutsPage({super.key, this.load, this.save});

  /// 读写口（测试注入；默认走注册表那一份）。⚠ 与其余几页同一条纪律：
  /// 不注入时就是生产那份，页面不自己 new 一份实现。
  final Future<List<FnthinkShortcut>> Function()? load;
  final Future<void> Function(List<FnthinkShortcut> rows)? save;

  @override
  State<FnthinkShortcutsPage> createState() => _FnthinkShortcutsPageState();
}

class _FnthinkShortcutsPageState extends State<FnthinkShortcutsPage> {
  List<FnthinkShortcut>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final rows = await (widget.load ?? loadFnthinkShortcuts)();
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _persist(List<FnthinkShortcut> rows) async {
    await (widget.save ?? saveFnthinkShortcuts)(rows);
    if (mounted) setState(() => _rows = rows);
  }

  Future<void> _add() async {
    final l10n = AppLocalizations.of(context);
    final name = TextEditingController();
    final target = TextEditingController();
    String? problem;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            String? check() {
              final nameProblem = validateFnthinkShortcutName(name.text);
              if (nameProblem != null) return l10n.fnthinkShortcutsNameInvalid;
              final targetProblem = validateFnthinkShortcutTarget(target.text);
              if (targetProblem != null) {
                return l10n.fnthinkShortcutsTargetInvalid;
              }
              final rows = _rows ?? const <FnthinkShortcut>[];
              if (findFnthinkShortcut(rows, name.text) != null) {
                return l10n.fnthinkShortcutsDuplicate;
              }
              return null;
            }

            return IosFormDialog(
              title: l10n.fnthinkShortcutsAdd,
              cancelText: l10n.cancel,
              submitText: l10n.add,
              submitKey: const ValueKey('fnthink-shortcut-submit'),
              submitEnabled: check() == null,
              onSubmit: () {
                final bad = check();
                if (bad != null) {
                  setDialogState(() => problem = bad);
                  return;
                }
                final rows = [
                  ...(_rows ?? const <FnthinkShortcut>[]),
                  FnthinkShortcut(
                    name: name.text.trim(),
                    target: target.text.trim(),
                  ),
                ];
                _persist(rows);
                Navigator.pop(dialogContext);
              },
              fields: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    l10n.fnthinkShortcutsNameLabel,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.secondaryLabel(dialogContext),
                    ),
                  ),
                ),
                CupertinoTextField(
                  key: const ValueKey('fnthink-shortcut-name'),
                  controller: name,
                  autocorrect: false,
                  onChanged: (_) => setDialogState(() => problem = check()),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    l10n.fnthinkShortcutsTargetLabel,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.secondaryLabel(dialogContext),
                    ),
                  ),
                ),
                CupertinoTextField(
                  key: const ValueKey('fnthink-shortcut-target'),
                  controller: target,
                  autocorrect: false,
                  onChanged: (_) => setDialogState(() => problem = check()),
                ),
                if (problem != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    problem!,
                    style: const TextStyle(fontSize: 12, color: AppColors.red),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
    name.dispose();
    target.dispose();
  }

  Future<void> _delete(FnthinkShortcut row) async {
    final l10n = AppLocalizations.of(context);
    final ok = await IosDialogActions.askConfirm(
      context,
      title: l10n.delete,
      message: l10n.fnthinkShortcutsDeleteAsk(row.name),
      confirmText: l10n.delete,
    );
    if (!ok) return;
    final rows = [
      for (final r in _rows ?? const <FnthinkShortcut>[])
        if (r != row) r,
    ];
    await _persist(rows);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(
        title: Text(
          l10n.fnthinkShortcutsTitle,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          FnthinkCard(
            title: l10n.fnthinkShortcutsTitle,
            children: [
              FnthinkNote(
                keyName: 'fnthink-shortcuts-why',
                text: l10n.fnthinkShortcutsWhy,
              ),
              if (_error != null)
                FnthinkNote(
                  keyName: 'fnthink-shortcuts-error',
                  text: l10n.remotePeersReadFailed,
                )
              else if ((_rows ?? const <FnthinkShortcut>[]).isEmpty)
                FnthinkNote(
                  keyName: 'fnthink-shortcuts-empty',
                  text: l10n.fnthinkShortcutsEmpty,
                )
              else
                for (final row in _rows!)
                  ListTile(
                    key: ValueKey('fnthink-shortcut-${row.name}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(row.name),
                    subtitle: Text(
                      row.target,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // 「行内次要动作」走公共件（T90/T108 的形状规矩）：删一条会让对面
                    // 从此打不开它 ⇒ tone 是 destructive（颜色由 colorOf 那一处定）。
                    trailing: FnthinkInlineAction(
                      key: ValueKey('fnthink-shortcut-delete-${row.name}'),
                      label: l10n.delete,
                      tone: FnthinkActionTone.destructive,
                      onPressed: () => _delete(row),
                    ),
                  ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: FnthinkInlineAction(
                  key: const ValueKey('fnthink-shortcuts-add'),
                  label: l10n.fnthinkShortcutsAdd,
                  onPressed: _add,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
