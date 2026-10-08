import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;

import '../theme/app_colors.dart';

/// 「一页最多一枚」的主操作：**全宽圆角填充**按钮（T100 判据④ 的公共件）。
///
/// 形状是从「推送开关」页那两枚（一键添加 2×2 / 添加 4×2）抬上来的 —— 它们与幻念这边的
/// 「创建端点」「立即收取」是同一件事：**这一页最主要的那个动作**。§1 把这一族的合法形状
/// 收成三种，这就是其中第三种；各页各搭会漂的不只是配色 ——
/// 「禁用态怎么表现」「副标题那一行怎么排」「圆角多少」都会各自长一套。
///
/// ⚠ 与 `FnthinkEntryRow`（形状①「行」）不是一件东西：行是"进一页／改一个值"，
///   这一枚是"把这件事做掉"。同一张页上两者同框时，行在上、主操作在下。
class PrimaryActionButton extends StatelessWidget {
  const PrimaryActionButton({
    required this.label,
    required this.onPressed,
    this.subtitle,
    super.key,
  });

  final String label;

  /// 这一页最主要的那个动作。传 null 表示**此刻不可用**（如正在忙、前置没开）——
  /// 这是真语义，不要用 `if` 把整枚按钮藏掉：藏掉之后用户看到的是"这页没有这个功能"。
  final VoidCallback? onPressed;

  /// 可选的一行小字（例如「会新建一把口令，请立刻复制」）。留空是版式，不是"忘了写"。
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton.filled(
      onPressed: onPressed,
      // 内边距归零：行高与左右留白在本层定，交给 CupertinoButton 默认值会让
      // "全宽"和"两行文字"这两件事在别的页面上重新商量一遍。
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 与主操作**同高同宽**的次级一枚：描边、不着填充（T108 片②：原通道设置页的 `_OutlineActionButton`）。
///
/// 存在的理由是页脚那一对：「仅探测」与「探测并保存」是**同一个决定的两个档**，
/// 一实一虚、一高一矮会让人以为它们是两个不相干的动作。所以形状与
/// [PrimaryActionButton] 对齐（圆角 12、左右 16、上下 12、字号 15／w600），只换底色为描边。
///
/// ⚠ 不要复用 `FnthinkInlineAction`（那枚是"对行里那个值做点什么"：复制、重置）——
///   它与"这一页要办的事"不是同一件事，贴在主操作旁边会一高一矮。
class SecondaryActionButton extends StatelessWidget {
  const SecondaryActionButton({
    required this.keyName,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String keyName;
  final String label;

  /// null = 此刻不可用（正在忙）：**置灰，不是藏起来**。
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final dim = onPressed == null;
    return CupertinoButton(
      key: ValueKey(keyName),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: dim
                ? AppColors.separator(context)
                : AppColors.blue.withValues(alpha: 0.45),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: dim ? AppColors.tertiaryLabel(context) : AppColors.blue,
          ),
        ),
      ),
    );
  }
}
