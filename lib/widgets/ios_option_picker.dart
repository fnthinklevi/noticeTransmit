import 'package:flutter/cupertino.dart';

import '../theme/app_colors.dart';

/// 「点开再选」那一类弹层的**全站唯一装配点**（T90 片6）。
///
/// 为什么收成一件组件而不是每页各搭一枚 `AlertDialog`：与 T05 长按菜单、T06 确认框、
/// `PullToRefreshList` 同一条理由 —— 各页自己搭，"哪一页用的是哪一件"就会重新散落。
///
/// 三个刻意的形状：
/// - **返回选中的值，不在弹层里回调**：旧写法是 `onTap: { Navigator.pop(ctx); onChanged(v); }`，
///   而"先 pop 再回调"这个顺序是砸过脚的（优先级那一档的 `onChanged` 会同步压入自定义输入框，
///   先回调时栈顶已经是那个新框，于是它同一帧被压入又弹出 ⇒ 用户看到"点自定义没反应"）。
///   把顺序做成组件的内部事实，调用点就没机会再写反。
/// - 画的是 `CupertinoAlertDialog` 而不是 `showCupertinoModalPopup` 那套动作面板：
///   闸门里"有没有模态盖在上面"的判据（`_modalUp()`）已经认这一类，换一件就要再补一类。
/// - 每一行带 `ValueKey('ios-picker-<value>')`：按文本点会在"选项文案与页面上别处同字"时点错，
///   而闸门与用例都需要点得准（第 19 轮那条 `GATE-MISSED-TAP` 就是这么来的）。
class IosPickerOption<T> {
  const IosPickerOption({
    required this.value,
    required this.label,
    this.description,
    this.icon,
    this.iconColor,
    this.labelColor,
  });

  /// 选中这一项时回填的值。
  final T value;

  /// 主文案。
  final String label;

  /// 副文案（可空）：iOS 的"选档"常常要靠它说明这一档到底做什么。
  final String? description;

  /// 行首图标（可空）。刻意收 `IconData` 而不是具体件，页面只喂 `CupertinoIcons.*`。
  final IconData? icon;

  final Color? iconColor;

  /// 主文案颜色（可空）。
  /// ⚠ 不是装饰：历史页那枚「清除记录」里，「全部」那一档是**不可撤销的批量删除**，
  ///   旧形状把它染成红色 —— 那个红是安全信号，收进本组件时必须一起搬过来，
  ///   否则用户就分不出"清今天"与"全清光"（两者的后果差着几个数量级）。
  final Color? labelColor;
}

/// 单选弹层。返回用户选中的值；被 barrier / 返回键关掉时返回 `null`（= 没改）。
Future<T?> showIosOptionPicker<T>(
  BuildContext context, {
  required String title,
  required List<IosPickerOption<T>> options,
  T? selectedValue,
}) {
  return showCupertinoDialog<T>(
    context: context,
    // ⚠ 这一句不是装饰：`showCupertinoDialog` 的 `barrierDismissible` **默认 false**
    // （ Cupertino 弹窗按 iOS 原生语义"必须答"），而旧的那枚 Material `showDialog` 默认可以点外面关。
    // 选档这一类没有「取消」按钮 —— 不显式打开它，用户就只剩"必须选一个"这一条出路，
    // 而"我点开看看又想收回去"恰恰是主题/语言那两格最常见的动作。
    barrierDismissible: true,
    builder: (ctx) => CupertinoAlertDialog(
      title: Text(title),
      content: Padding(
        padding: const EdgeInsets.only(top: 8),
        // 条件类型那一族有十几档 —— 这里**不自己套滚动**：`CupertinoAlertDialog` 已经把
        // content 放在有界且可滚的位置里（实测把 ConstrainedBox+SingleChildScrollView 整块删掉，
        // 六条用例一条都不红 ⇒ 那层包裹是不可观察的冗余，留着只会让人以为上限由它负责）。
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in options)
              CupertinoButton(
                key: ValueKey('ios-picker-${option.value}'),
                onPressed: () => Navigator.pop(ctx, option.value),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Row(
                  children: [
                    if (option.icon != null) ...[
                      Icon(
                        option.icon,
                        size: 20,
                        color:
                            option.iconColor ?? AppColors.secondaryLabel(ctx),
                      ),
                      const SizedBox(width: 10),
                    ] else
                      const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            option.label,
                            style: TextStyle(
                              fontSize: 16,
                              color:
                                  option.labelColor ??
                                  AppColors.primaryLabel(ctx),
                            ),
                          ),
                          if (option.description != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              option.description!,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.secondaryLabel(ctx),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // 当前那一档打勾（与换根组件之前那批 Material picker 同款线索）。
                    if (option.value == selectedValue) ...[
                      const SizedBox(width: 6),
                      Icon(
                        CupertinoIcons.check_mark,
                        size: 18,
                        color: AppColors.systemBlue(ctx),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
