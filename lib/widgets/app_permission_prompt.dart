import 'package:flutter/cupertino.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';

/// 应用筛选页与远程触发筛选页共用的「无应用列表读取权限」提示（T166 ③）。
///
/// 形状定稿：**中性文字档 + 下箭头**，不升成全宽主按钮 —— 它是空态页里的一句说明，
/// 大按钮会抢走这一屏的主视觉。仍是一枚真正的按钮：`CupertinoButton` 给按压反馈，
/// 箭头给"这里点得动"的静态线索；两页共用同一份，避免再分成两个作者。
class AppPermissionPrompt extends StatelessWidget {
  const AppPermissionPrompt({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = AppColors.secondaryLabel(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: CupertinoButton(
          onPressed: onTap,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: Size.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.appFilterNoPermPrompt,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, height: 1.6, color: color),
              ),
              const SizedBox(height: 2),
              Icon(CupertinoIcons.chevron_down, size: 12, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
