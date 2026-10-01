import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';

/// 确认弹窗的统一入口 —— 两条路，形状不同但**都只有一个作者**：
///
/// - [askConfirm]：**删除类**一律走它。T06 之后长成 `CupertinoAlertDialog`（base.md §UI 强约束），
///   返回 `true` 才算用户确认。
/// - [confirm]：给仍在自己搭 `AlertDialog` 的历史页面当 actions 构建器（台账见
///   `test/architecture/ui_style_guards_test.dart`，只许缩短）。布局：0.5px 竖分割线 +
///   两等分按钮（取消 = 次要文字色；确认 = 蓝色，破坏性 = 红色）。
///
/// ⚠ 换根组件之后 `_modalUp()` 那类"有没有模态盖在上面"的判据不能再只认 Material 四类 ——
/// `CupertinoAlertDialog` 走 `DialogRoute`，不是 `Dialog` 的子类。
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
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(message),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: Text(cancelText ?? l10n.cancel),
          ),
          CupertinoDialogAction(
            isDestructiveAction: destructive,
            isDefaultAction: !destructive,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmText),
          ),
        ],
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
