import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/app_quick_select.dart';
import 'fnthink_card.dart';

/// 组名那一枚词（三处页面共用；词表在 ARB，分组在 [AppQuickGroup]）。
String appQuickGroupLabel(AppLocalizations l10n, AppQuickGroup group) =>
    switch (group) {
      AppQuickGroup.sms => l10n.ruleAppQuickSms,
      AppQuickGroup.phone => l10n.ruleAppQuickPhone,
      AppQuickGroup.comm => l10n.ruleAppQuickComm,
      AppQuickGroup.mail => l10n.ruleAppQuickMail,
    };

/// 应用筛选页 / 远程触发页共用的一排「一键选整组」（T209）。
///
/// 为什么是一排按钮而不是把规则编辑页那张大卡搬过来：那几张页的列表模型不一样
/// （允许/阻止两模式 vs 排除集），照搬会把"点一下整组加进哪一边"这件判据搬进公共件，
/// 而各页的"选中"含义并不相同。这里只给**分组与包名**，按压后把 `(组, 这一组装着的包)`
/// 交回宿主，由各页按自己的模型落。
///
/// 选中态 = 这一组**已经全部**进了宿主的集合（部分进 = 未选中）：它是"再点一下会怎样"的
/// 提示，不是另一份选中集合。
class AppQuickSelectBar extends StatelessWidget {
  const AppQuickSelectBar({
    super.key,
    required this.groups,
    required this.isApplied,
    required this.onToggle,
    this.keyPrefix = 'app-quick',
  });

  /// 只传"这一页确实装着、且有命中的应用"的组；空 ⇒ 整条不画。
  final Map<AppQuickGroup, List<String>> groups;

  /// 这一组是否已全部落在宿主的集合里。
  final bool Function(AppQuickGroup group) isApplied;

  /// 按压回传：这一组 + 这一组装着的包。选/取消由宿主按自己的模型决定。
  final void Function(AppQuickGroup group, List<String> packages) onToggle;

  /// 两页各自给一枚前缀，用例按 `ValueKey('$keyPrefix-sms')` 点得到自己那一页的。
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final group in appQuickGroups)
          if (groups[group] != null)
            FnthinkChoiceChip(
              keyName: '$keyPrefix-${group.name}',
              label: appQuickGroupLabel(l10n, group),
              selected: isApplied(group),
              onTap: () => onToggle(group, groups[group]!),
            ),
      ],
    );
  }
}
