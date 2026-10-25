import 'package:flutter/widgets.dart';

import '../theme/app_colors.dart';

/// 分组卡/弹窗卡片的统一阴影（base §9.1：模糊 4、偏移 (0,2)）。
///
/// 颜色住主题（`AppColors.cardShadow`）：浅色 6% 黑、深色 24% 黑。
/// 只给"卡片"这一层用；行内 chip、分段控件、输入格不套。
List<BoxShadow> appCardShadows(BuildContext context) {
  return [
    BoxShadow(
      color: AppColors.cardShadow(context),
      blurRadius: 4,
      offset: const Offset(0, 2),
    ),
  ];
}
