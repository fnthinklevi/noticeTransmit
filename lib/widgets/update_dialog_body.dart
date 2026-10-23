import 'package:flutter/cupertino.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';
import '../update_manager.dart';

/// 「发现新版本」弹层的内容（T169）。
///
/// 首屏只放三行版本读数 + 更新日志的前 [updateChangelogSummary] 行；完整日志要点开
/// 才铺开。为什么不在首屏直接铺全文：服务端每一版都写一整篇（1.6.0 那版是十几段），
/// 弹层第一眼就变成"一堵字墙"，而用户真正要先决定的是要不要更新。
///
/// ⚠ 展开之后**不套内层滚动**：`CupertinoAlertDialog` 的 content 本身有界且可滚
/// （`main_page_update.dart` 里那条注释记着这件事）。再套一层就会让"滚哪一层"变成
/// 两个作者，而手机上先坏的是手指拖不动的那一层。
class UpdateDialogBody extends StatefulWidget {
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
  State<UpdateDialogBody> createState() => _UpdateDialogBodyState();
}

class _UpdateDialogBodyState extends State<UpdateDialogBody> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final result = widget.result;
    final summary = updateChangelogSummary(widget.changelog);
    final hasMore = updateChangelogHasMore(widget.changelog);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _infoRow(
          context,
          l10n.updateLatestVersionLabel,
          'v${result.latestVersion}',
        ),
        _infoRow(
          context,
          l10n.updateCurrentVersionLabel,
          'v${widget.currentVersion}',
        ),
        _infoRow(
          context,
          l10n.updateFileSizeLabel,
          result.fileSizeStr ?? l10n.updateSizeUnknown,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.updateChangelogTitle,
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
