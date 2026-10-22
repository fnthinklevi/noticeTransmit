import 'package:flutter/cupertino.dart';

import '../theme/app_colors.dart';

/// 长说明的语义档：普通说明 / 信息 / 成功 / 警告。
enum AppInfoNoteTone { neutral, info, success, warning }

/// 页面内长说明的**唯一文本框形状**：细边框 + 圆角 + 浅底。
///
/// 为什么要有它：页面里成段的小字既读不出边界，也读不出"这段是说明还是警告"。
/// 帮助按钮负责把"想看才看"的长文收进弹层；还要留在页面上的说明走这一件，
/// 由边框给出边界、由 [tone] 给出语义色。
///
/// ⚠ 只用于**成段说明**：单行状态、卡片副标题、弹层正文都不套这一层。
class AppInfoNoteBox extends StatelessWidget {
  const AppInfoNoteBox({
    super.key,
    this.text,
    this.child,
    this.title,
    this.icon,
    this.tone = AppInfoNoteTone.neutral,
    this.padding = const EdgeInsets.fromLTRB(14, 12, 14, 12),
    this.radius = 10,
  }) : assert(text != null || child != null, 'text 与 child 至少要给一个');

  /// 纯文字说明；与 [child] 二选一。
  final String? text;

  /// 需要保留富文本或自定义排版时用；与 [text] 二选一。
  final Widget? child;

  /// 可选标题（一句话说明这一段在讲什么）。
  final String? title;

  /// 可选图标，只在有 [title] 时显示。
  final IconData? icon;

  final AppInfoNoteTone tone;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = _schemeFor(context);
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.background,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: scheme.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: scheme.foreground),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    title!,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.titleColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (text != null)
            Text(
              text!,
              style: TextStyle(
                fontSize: 13,
                height: 1.55,
                color: scheme.foreground,
              ),
            )
          else
            child!,
        ],
      ),
    );
  }

  _NoteScheme _schemeFor(BuildContext context) {
    switch (tone) {
      case AppInfoNoteTone.neutral:
        return _NoteScheme(
          background: AppColors.cardBg(context),
          border: AppColors.separator(context),
          foreground: AppColors.secondaryLabel(context),
          titleColor: AppColors.primaryLabel(context),
        );
      case AppInfoNoteTone.info:
        return _NoteScheme.semantic(AppColors.blue);
      case AppInfoNoteTone.success:
        return _NoteScheme.semantic(AppColors.green);
      case AppInfoNoteTone.warning:
        return _NoteScheme.semantic(AppColors.orange);
    }
  }
}

class _NoteScheme {
  const _NoteScheme({
    required this.background,
    required this.border,
    required this.foreground,
    required this.titleColor,
  });

  factory _NoteScheme.semantic(Color color) => _NoteScheme(
    background: color.withValues(alpha: 0.08),
    border: color.withValues(alpha: 0.30),
    foreground: color,
    titleColor: color,
  );

  final Color background;
  final Color border;
  final Color foreground;
  final Color titleColor;
}
