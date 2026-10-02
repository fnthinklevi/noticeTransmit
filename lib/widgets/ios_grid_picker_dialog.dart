import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 图标网格型弹层的**外壳**（T90 片18）。
///
/// 台账里这一族是**第四种形状**（前三种：确认框 / 单选列表 / 表单 / 进度框）：
/// 一个标题 + 一片有高度上限的可滚网格，**没有动作区** —— 用户点中哪一格就选中并当场关掉
/// （`icon_picker_tile.dart` 的行为：`_select` 里既改当前值也 pop）。
///
/// ⚠ 参数纪律（T90 片8）：**每个参数都来自那一处真实数字**，不为"以后某天可能有第二个调用点"留口子。
/// ⚠ 而且要说清楚：**这一枚现在只有一处调用点**（`more_page` 的「应用图标」那一行）——
///   它值得存在不是因为"多处复用"，而是因为**那一层 Material 祖先**（见下）与网格的 Cupertino 形状
///   该有一个固定的家；下次真有第二个网格弹层时再扩参数，别今天就把想象出来的旋钮开好。
///
/// ⚠ 那层透明 `Material` 不是装饰：网格里每一格是 `InkWell` / `CircleAvatar` / `AppIconPreview`
///   （Material 件），而 `CupertinoAlertDialog` 自己**不含** Material 祖先 ——
///   少一层就整枚弹层抛 `No Material widget found`。
///   这是同一处坑的第三次：片12 在闸门上撞过一次（FM4），片17 那枚进度框抄了同一层（当时测不出来，
///   本地没有可观察的坏法，如实登记在案）。用 `transparency` 而非默认不透明：不透明会盖掉水波纹。
class IosGridPickerDialog extends StatelessWidget {
  const IosGridPickerDialog({
    super.key,
    required this.title,
    required this.itemCount,
    required this.itemBuilder,
    this.crossAxisCount = 4,
    this.childAspectRatio = 0.78,
    this.mainAxisSpacing = 14,
    this.crossAxisSpacing = 8,
    this.maxHeight = 380,
  });

  final String title;
  final int itemCount;

  /// 与 `GridView.builder.itemBuilder` 同型（**索引可空**）——直接把它接过去，
  /// 调用方不必为了签名再包一层 `(ctx, i) => ...`。
  final NullableIndexedWidgetBuilder itemBuilder;

  final int crossAxisCount;
  final double childAspectRatio;
  final double mainAxisSpacing;
  final double crossAxisSpacing;

  /// 网格那一块的高度上限。**必须有**：网格内容按 `itemCount` 线性长高，
  /// 没有上限时 `CupertinoAlertDialog` 那点内容高度装不下（界面上就是一片溢出黄条）。
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: Text(title),
      content: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: GridView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: mainAxisSpacing,
                crossAxisSpacing: crossAxisSpacing,
                childAspectRatio: childAspectRatio,
              ),
              itemCount: itemCount,
              itemBuilder: itemBuilder,
            ),
          ),
        ),
      ),
    );
  }
}
