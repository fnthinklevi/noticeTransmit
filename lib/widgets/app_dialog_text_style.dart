import 'package:flutter/widgets.dart';

import '../theme/app_colors.dart';

/// 弹窗「取消」那一档的文字形态（base §9.1：按钮 16px 粗体、取消 #8E8E93）。
///
/// 只给真正的取消/退出动作；确认、破坏性、暂不各有自己的语义色，
/// 不在这里一刀切。
TextStyle appDialogCancelStyle(BuildContext context) {
  return TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.secondaryLabel(context),
  );
}
