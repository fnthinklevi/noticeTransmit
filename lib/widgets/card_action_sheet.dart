import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 卡片上的一个长按动作（T05 共用组件的数据形状）。
///
/// [onTap] 为 null 表示**这条现在不能做**（置灰）：与"藏起来"不同，置灰能让用户
/// 知道功能存在、只是当前状态不允许（例如未启用的规则没有"停用"可言）。
class CardAction {
  const CardAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.description,
    this.iconColor,
    this.danger = false,
  });

  final IconData icon;
  final String label;

  /// 第二行说明：用于把"这条点了会发生什么"讲清楚（历史记录里就是"屏蔽哪个包"）。
  final String? description;
  final Color? iconColor;

  /// 破坏性动作（删除）⇒ 文字与图标转红。真正的确认弹窗仍由调用方在 [onTap] 里弹
  /// （T06：所有删除一律二次确认）。
  final bool danger;

  final VoidCallback? onTap;
}

/// 卡片长按动作表（iOS 底部弹层）。
///
/// 为什么要抽出来：三族通道卡片与两类推送规则卡片要挂同一套"修改/复制/删除"，
/// 而全仓此前仅有的两处长按是两份互不相干的写法（历史记录里整份底部弹层是就地写的，
/// 电量规则则是长按直接弹删除确认）。不抽出来就得抄五份。
/// 弹层里只放动作，不放业务判断 —— 副标题文案、可用性都由调用方算好后传进来。
///
/// 点击顺序固定为**先关弹层再执行**：动作里常有 `Navigator.push` 与 `setState`，
/// 拿着 `sheetContext` 去 push 会在已销毁的 element 上操作。
class CardActionSheet extends StatelessWidget {
  const CardActionSheet({super.key, required this.actions, this.title});

  final List<CardAction> actions;
  final String? title;

  /// 弹出动作表。`await` 到弹层关闭为止。
  static Future<void> show(
    BuildContext context, {
    required List<CardAction> actions,
    String? title,
  }) => showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.cardBg(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => CardActionSheet(actions: actions, title: title),
  );

  @override
  Widget build(BuildContext context) {
    return Material(
      // 不透明一层 Material 会让 ListTile 的水波纹画不出来（本仓库已撞到过一次：
      // Flutter 在 widget test 里直接断言 "ink splashes may be invisible"）
      type: MaterialType.transparency,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.separator(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 4),
                child: Text(
                  title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryLabel(context),
                  ),
                ),
              ),
            for (final action in actions)
              ListTile(
                enabled: action.onTap != null,
                leading: Icon(
                  action.icon,
                  color: action.danger
                      ? AppColors.red
                      : (action.iconColor ?? AppColors.blue),
                ),
                title: Text(
                  action.label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: action.danger
                        ? AppColors.red
                        : AppColors.primaryLabel(context),
                  ),
                ),
                subtitle: action.description == null
                    ? null
                    : Text(
                        action.description!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.secondaryLabel(context),
                        ),
                      ),
                onTap: action.onTap == null
                    ? null
                    : () {
                        Navigator.pop(context);
                        action.onTap!();
                      },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
