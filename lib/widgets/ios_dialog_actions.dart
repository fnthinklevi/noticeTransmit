import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// iOS 风格弹窗按钮行 —— 全项目确认弹窗统一的 actions 构建器。
///
/// 布局：0.5px 竖分割线 + 两等分按钮（取消 = 次要文字色；
/// 确认 = 蓝色，破坏性操作 = 红色）。替换 Material 默认的右对齐按钮布局。
///
/// 用法：
/// ```dart
/// AlertDialog(
///   backgroundColor: AppColors.cardBg(ctx),
///   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
///   actions: IosDialogActions.confirm(
///     context,
///     cancelText: l10n.cancel,
///     confirmText: l10n.delete,
///     onConfirm: () { Navigator.pop(ctx, true); },
///     destructive: true,
///   ),
/// )
/// ```
class IosDialogActions {
  IosDialogActions._();

  static List<Widget> confirm(
    BuildContext context, {
    required String cancelText,
    required String confirmText,
    VoidCallback? onCancel,
    required VoidCallback onConfirm,
    bool destructive = false,
  }) {
    final confirmColor = destructive ? AppColors.red : AppColors.blue;
    return [
      Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: onCancel ?? () => Navigator.pop(context),
              child: Text(
                cancelText,
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
            ),
          ),
          Container(
            width: 0.5,
            height: 20,
            color: AppColors.separator(context),
          ),
          Expanded(
            child: TextButton(
              onPressed: onConfirm,
              child: Text(
                confirmText,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: confirmColor,
                ),
              ),
            ),
          ),
        ],
      ),
    ];
  }
}
