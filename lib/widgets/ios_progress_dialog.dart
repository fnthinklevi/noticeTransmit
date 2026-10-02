import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 进度型弹层的**外壳**（T90 片17）。
///
/// 为什么要有它：台账里最后两枚「进度框」是**同一件事的两种样子** ——
/// `history_page` 的批量补推（一条一句「已推 N/M 条」，一条进度条，没有动作）与
/// `main_page_update` 的更新下载（标题 + 进度条 + 百分比，非强推时多一颗「取消」）。
/// 各自写一遍 `AlertDialog` 的下一幕是同一段代码两份：圆角、内容列、进度条、
/// 进度值怎么算，两处以后各改各的。
///
/// ⚠ 刻意**只**收真差异，不收"为将来留的口子"：
/// - 进度值 [progress] 传 `null` 就是不确定态（下载刚起步时服务器还没给总大小）；
/// - [title] 传 null 就是没有标题那一行（批量补推没有）；
/// - [cancelText] / [onCancel] **同时**给才有那颗「取消」，都不给就没有动作区
///   （批量补推不能中途取消，补推到一半停下的下一幕是"用户以为推完了"）；
/// - 文案一律由调用方给：本组件不读 l10n，也不替用户算百分比。
///
/// ⚠ 生命周期归调用方：组件只管画，**谁弹、谁能关、什么时候关**都在调用方手里
/// （批量补推跑完自己 pop；下载结束自己 pop；非强推那颗「取消」由调用方接）。
/// 与 `IosFormDialog` 同一条规矩：形状归这里，判据与流程留在各页。
class IosProgressDialog extends StatelessWidget {
  const IosProgressDialog({
    super.key,
    required this.progress,
    this.title,
    this.message,
    this.percentText,
    this.cancelText,
    this.onCancel,
  });

  /// 0..1；**null = 不确定态**（进度条来回走，而不是停在 0）。
  final double? progress;

  final String? title;

  /// 进度条**上方**那一行（批量补推的「已推 N/M 条」）。
  final String? message;

  /// 进度条**下方**那一行（下载的「42%」）。
  final String? percentText;

  /// 两颗动作里那颗红色的「取消」；[onCancel] 也给才会出现。
  final String? cancelText;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: title == null ? null : Text(title!),
      // ⚠ 字段是 Material 的进度条/文字，而 `CupertinoAlertDialog` **不含** Material 祖先
      //   （片12 那次闸门红的就是这件事：`No Material widget found`）⇒ 这层透明 Material 是必需的。
      // ⚠⚠ 但**如实登记**：这枚外壳目前**测不出**这层的作用 —— 反证 PD4 把整层摘掉，五条用例
      //   仍然全绿（`LinearProgressIndicator` 自己不需要 Material 祖先，而这枚外壳没有
      //   `TextField` / `InkWell` 那类必须要祖先的字段）。它是照着 `IosFormDialog` 抄的防御层：
      //   哪天有人往 `content` 里塞一个 Material 输入格，少了它就当场抛 `No Material widget found`。
      //   ⇒ 别把"现在测不出来"读成"这层没用"。
      content: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message != null) ...[
                Text(
                  message!,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.primaryLabel(context),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: AppColors.inputBg(context),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.blue,
                  ),
                ),
              ),
              if (percentText != null) ...[
                const SizedBox(height: 12),
                Text(
                  percentText!,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primaryLabel(context),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (cancelText != null && onCancel != null)
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: onCancel,
            child: Text(cancelText!),
          ),
      ],
    );
  }
}
