import 'package:flutter/cupertino.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';
import '../update_manager.dart';

/// 「发现新版本」弹层的内容（T169）。
///
/// 首屏只放三行版本读数 + 更新日志的前几条；完整日志要点开才铺开。为什么不在首屏直接
/// 铺全文：服务端每一版都写一整篇（1.6.0 那版是十几段），弹层第一眼就变成"一堵字墙"，
/// 而用户真正要先决定的是要不要更新。
///
/// 日志那半份在 [UpdateChangelogBlock]（T203 抽出来的：摘要条数、展开键名、灰底容器与
/// 字号都在那一处）—— 首启那句「这次更新带来了什么」用的是同一半份，不在那里再抄排版。
class UpdateDialogBody extends StatelessWidget {
  const UpdateDialogBody({
    super.key,
    required this.result,
    required this.currentVersion,
    required this.changelog,
  });

  final VersionCheckResult result;
  final String currentVersion;

  /// 已按软件语言裁决过的那一份（`pickUpdateChangelog`）。
  final String changelog;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _infoRow(
          context,
          l10n.updateLatestVersionLabel,
          'v${result.latestVersion}',
        ),
        _infoRow(context, l10n.updateCurrentVersionLabel, 'v$currentVersion'),
        _infoRow(
          context,
          l10n.updateFileSizeLabel,
          result.fileSizeStr ?? l10n.updateSizeUnknown,
        ),
        const SizedBox(height: 14),
        UpdateChangelogBlock(
          changelog: changelog,
          heading: l10n.updateChangelogTitle,
        ),
      ],
    );
  }

  /// 「标签 + 值」一行（版本号 / 文件大小三处共用）。
  Widget _infoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.secondaryLabel(context),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.primaryLabel(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 更新日志那半份：首屏摘要 + 「查看完整更新内容」折叠（T169 立的那一份作者）。
///
/// ## 为什么单独成一枚（T203）
/// 首启那句「这次更新带来了什么」要的正是这半份排版。各写一份的后果：改了这里的折叠形状、
/// 摘要条数或字号，那边不会跟着变 —— 而界面上两处都叫"更新日志"，用户只会看到两种样子。
///
/// ⚠ 展开之后**不套内层滚动**：`CupertinoAlertDialog` 的 content 本身有界且可滚
/// （`main_page_update.dart` 里那条注释记着这件事）。再套一层就会让"滚哪一层"变成
/// 两个作者，而手机上先坏的是手指拖不动的那一层。
class UpdateChangelogBlock extends StatefulWidget {
  const UpdateChangelogBlock({
    super.key,
    required this.changelog,
    this.heading,
  });

  /// 那一份日志的原文（已按软件语言裁决过 —— 裁决仍在 `pickUpdateChangelog`）。
  final String changelog;

  /// 小标题那一行；给 null = **不画**：弹层自己的标题已经说了同一件事（T203 首启那一枚）。
  final String? heading;

  @override
  State<UpdateChangelogBlock> createState() => _UpdateChangelogBlockState();
}

class _UpdateChangelogBlockState extends State<UpdateChangelogBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final summary = updateChangelogSummary(widget.changelog);
    final hasMore = updateChangelogHasMore(widget.changelog);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: widget.heading == null
                  ? const SizedBox.shrink()
                  : Text(
                      widget.heading!,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryLabel(context),
                      ),
                    ),
            ),
            if (hasMore)
              CupertinoButton(
                key: const ValueKey('update-changelog-toggle'),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: Size.zero,
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(
                  _expanded
                      ? l10n.updateChangelogCollapse
                      : l10n.updateChangelogShowAll,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.inputBg(context),
            borderRadius: BorderRadius.circular(8),
          ),
          child: _expanded
              ? Text(
                  normalizeUpdateChangelog(widget.changelog),
                  key: const ValueKey('update-changelog-full'),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AppColors.primaryLabel(context),
                  ),
                )
              : Column(
                  key: const ValueKey('update-changelog-summary'),
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in summary)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          line,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: AppColors.primaryLabel(context),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
