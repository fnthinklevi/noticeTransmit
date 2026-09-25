import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
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

  /// 破坏性动作的**统一确认框**（T06）。返回 true = 用户确认执行。
  ///
  /// 为什么要有它而不是让每个调用点自己搭 `AlertDialog`：上面的 `confirm` 只给
  /// actions，于是标题/圆角/按钮顺序在八处各抄一遍，"哪些删除有确认"就跟着漂移 ——
  /// webhook 与自建应用通道的删除一直是没有确认的（点一下就没了，还会连带丢凭据）。
  /// **删除类动作一律走这里**，且确认要写在"执行删除的那个函数"里（单一咽喉），
  /// 而不是写在每个调用点，否则新增入口时必然漏掉一条。
  static Future<bool> askConfirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmText,
    String? cancelText,
    bool destructive = true,
  }) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryLabel(ctx),
          ),
        ),
        content: Text(
          message,
          style: TextStyle(color: AppColors.primaryLabel(ctx)),
        ),
        actions: confirm(
          ctx,
          cancelText: cancelText ?? l10n.cancel,
          confirmText: confirmText,
          destructive: destructive,
          onConfirm: () => Navigator.pop(ctx, true),
        ),
      ),
    );
    return ok == true;
  }

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
