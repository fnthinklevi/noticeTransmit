import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 输入框的统一形状（base.md §9.1）：圆角 10、浅底、边框取分割线色、聚焦取系统蓝。
const double kAppInputRadius = 10;

OutlineInputBorder appInputBorder(BuildContext context, {Color? color}) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(kAppInputRadius),
    borderSide: BorderSide(color: color ?? AppColors.separator(context)),
  );
}

/// CupertinoTextField 没有 InputDecorationTheme，按同一形状给一层 BoxDecoration。
BoxDecoration appCupertinoInputDecoration(BuildContext context) {
  return BoxDecoration(
    color: AppColors.inputBg(context),
    borderRadius: BorderRadius.circular(kAppInputRadius),
    border: Border.all(color: AppColors.separator(context)),
  );
}
