import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';

/// 「有更新」那一屏用户选的那一档（T90 片21）。
enum UpdateChoice { ignore, later, update }

/// 确认弹窗的统一入口 —— 三条路，形状不同但**都只有一个作者**：
///
/// - [askConfirm]：**删除类**一律走它。T06 之后长成 `CupertinoAlertDialog`（base.md §UI 强约束），
///   返回 `true` 才算用户确认。
/// - [showInfo]：**只读说明框**（一句标题 + 一段正文 + 一个「好」）走它。T90 片5 补的这一条
///   不是为了少写四行，而是为了堵一个后门 —— 台账划掉一个文件有两种办法：真的走 helper，
///   或者自己手搭一枚 `CupertinoAlertDialog`。后者过了风格闸（Material 那件确实没了），
///   但标题字号、按钮色、`barrierDismissible` 会重新各页一份，与换根组件之前的散是同一样东西。
///   守卫见 `ui_style_guards_test.dart`「划掉台账的那几屏必须走 helper」。
/// - [showPermissionGuide]：**系统权限引导**（图标 + 说明 + 拒绝 / 允许），片11 建的。
/// - [showUpdatePrompt] / [showForceUpdatePrompt]：**有更新**那一枚（T90 片21）——
///   三颗等分档位（含「忽略」＝写进忽略名单）与强制更新那颗「只有一条出路」的，形状不同，
///   各是一颗入口；两者的内容（徽标 / 版本行 / 更新日志）由调用方往 [body] 塞。
/// - [confirm]：给仍在自己搭 `AlertDialog` 的历史页面当 actions 构建器（台账见
///   `test/architecture/ui_style_guards_test.dart`，只许缩短）。布局：0.5px 竖分割线 +
///   两等分按钮（取消 = 次要文字色；确认 = 蓝色，破坏性 = 红色）。
///
/// ⚠ 换根组件之后 `_modalUp()` 那类"有没有模态盖在上面"的判据不能再只认 Material 四类 ——
/// `CupertinoAlertDialog` 走 `DialogRoute`，不是 `Dialog` 的子类。
class IosDialogActions {
  IosDialogActions._();

  /// 单动作的说明框（T90 片5）。不返回什么 —— 它没有任何"用户的选择"要带走。
  static Future<void> showInfo(
    BuildContext context, {
    required String title,
    required String message,
    String? okText,
  }) {
    final l10n = AppLocalizations.of(context);
    return showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(message),
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: Text(okText ?? l10n.ok),
          ),
        ],
      ),
    );
  }

  /// 破坏性动作的**统一确认框**（T06）。返回 true = 用户确认执行。
  ///
  /// 为什么要有它而不是让每个调用点自己搭 `AlertDialog`：上面的 `confirm` 只给
  /// actions，于是标题/圆角/按钮顺序在八处各抄一遍，"哪些删除有确认"就跟着漂移 ——
  /// webhook 与自建应用通道的删除一直是没有确认的（点一下就没了，还会连带丢凭据）。
  /// **删除类动作一律走这里**，且确认要写在"执行删除的那个函数"里（单一咽喉），
  /// 而不是写在每个调用点，否则新增入口时必然漏掉一条。
  /// ⚠ [barrierDismissible] 默认 **false**（Cupertino 语义「必须答」），但**换件过来的调用点要按旧行为显式传**：
  ///   Material `showDialog` 默认点得穿，那些框「点外面」= 没答 = 不执行；在这里悄悄改成 false
  ///   会让「看一眼又想收回去」那条出路消失（片6 与片11 各撞过一次，方向相反）。
  static Future<bool> askConfirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmText,
    String? cancelText,
    bool destructive = true,
    bool barrierDismissible = false,
  }) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showCupertinoDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
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

  /// 系统权限引导框（T90 片11）：图标 + 标题 + 说明 + 「拒绝 / 允许」，返回 true = 允许。
  ///
  /// 为什么要有它：这一屏在 `app_filter_page` 与 `rule_edit_page` 里**逐字重复过两份**
  /// （连"允许"那颗去请求的原生方法名都一样）。重复的下一幕不是多两行代码，
  /// 而是两处的文案与行为各改各的 —— 用户在筛选页看到 A 说法、在规则页看到 B 说法，
  /// 而它们讲的是同一个系统权限。
  ///
  /// ⚠ `barrierDismissible: true` 是**照旧行为**保留的：旧的那两枚用的是 Material
  /// `showDialog`（默认点得穿外面），点外面 = 没选 = 不请求权限。这里不能顺手改成
  /// "必须答"——那会让"看一眼又想收回去"这条路消失（片6 撞过同一件事，方向相反）。
  static Future<bool> showPermissionGuide(
    BuildContext context, {
    required IconData icon,
    Color iconColor = AppColors.blue,
    String? title,
    required String message,
    required String rejectText,
    required String allowText,
  }) async {
    final picked = await showCupertinoDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => CupertinoAlertDialog(
        // 标题走 content 而不是 CupertinoAlertDialog 的 title：这一屏的形状是
        // 「图标在上、标题居中、说明在下」，塞进 title 会变成标题左对齐 + 图标悬空。
        // ⚠ [title] 可省：`main_page_dialogs` 那枚通知权限提醒本来就只有「图标 + 说明」两行，
        //   给它编一句标题要动 ARB ⇒ 措辞是维护者的决定，不在装配点里替他定。
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: iconColor),
            const SizedBox(height: 14),
            if (title != null) ...[
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryLabel(context),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppColors.primaryLabel(context),
              ),
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(rejectText),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(allowText),
          ),
        ],
      ),
    );
    return picked == true;
  }

  /// 有更新的那一枚弹层（T90 片21）。返回用户选的那一档（`UpdateChoice`）。
  ///
  /// 为什么不是 `askConfirm`：那一族是「一问一答」，而这一屏的形状是**三颗等分的档位**，
  /// 其中「忽略」按下还要顺手把这一版写进忽略名单（下次不再提示）—— 它带走的是一次**设置**，
  /// 不是一次确认，所以走 `Navigator.pop(choice)` 而不是 `pop(true)`。
  ///
  /// ⚠ [barrierDismissible] 默认 **true**，且**必须**由调用方按 `forceUpdate` 覆盖：
  ///   旧形状是 `showDialog(barrierDismissible: !forceUpdate)` —— 强推那一版**点外面不许关**
  ///   （唯一一条出路就是立刻更新），非强推点外面 = 先不更新。`showCupertinoDialog` 默认 false，
  ///   照抄默认会让"稍后再说"这条出路消失，漏传又会把强推那一版变成可以点穿（两条都撞过）。
  /// ⚠ [titleBadge] 是标题**上方**那枚红标（强推才出现）。它走 `content` 而不是 `title`：
  ///   `CupertinoAlertDialog` 的 title 是居中一行的文字，徽标要塞进去得改成行内流，不值当。
  static Future<UpdateChoice?> showUpdatePrompt(
    BuildContext context, {
    required String title,
    required String ignoreText,
    required String laterText,
    required String updateText,
    Widget? titleBadge,
    Widget? body,
    bool barrierDismissible = true,
  }) {
    return showCupertinoDialog<UpdateChoice>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => CupertinoAlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (titleBadge != null) ...[titleBadge, const SizedBox(height: 12)],
            Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryLabel(ctx),
              ),
            ),
            if (body != null) ...[const SizedBox(height: 12), body],
          ],
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, UpdateChoice.ignore),
            child: Text(ignoreText),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, UpdateChoice.later),
            child: Text(laterText),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, UpdateChoice.update),
            child: Text(updateText),
          ),
        ],
      ),
    );
  }

  /// 强制更新那一枚（片21 的第二颗入口）：**只有一条出路** —— 一颗默认色的「立即更新」。
  ///
  /// 为什么单独一颗而不是给上面那枚加个 `onlyUpdate` 开关：上面那枚的「忽略 / 稍后」在这一屏
  /// 不存在，这一屏的「点外面不许关」也不由本组件决定（它在 `showDialog` 上，本组件没有那个口）。
  /// 一个开关会把三颗等分 + 可点穿 + 两颗次要按钮这三件事全变成条件分支，而这一屏根本不走那三条。
  static Future<UpdateChoice?> showForceUpdatePrompt(
    BuildContext context, {
    required String title,
    required String updateText,
    Widget? titleBadge,
    Widget? body,
  }) {
    return showCupertinoDialog<UpdateChoice>(
      context: context,
      // ⚠ 照旧行为：强推那枚点外面**不许**关（`showDialog(barrierDismissible: false)`），
      // 而 `showCupertinoDialog` 的默认恰好也是 false —— 这一处默认是对的，但写成显式值，
      // 免得后人照着上面那颗「默认 true」的注释把这句删掉。
      barrierDismissible: false,
      builder: (ctx) => CupertinoAlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (titleBadge != null) ...[titleBadge, const SizedBox(height: 12)],
            Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryLabel(ctx),
              ),
            ),
            if (body != null) ...[const SizedBox(height: 12), body],
          ],
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, UpdateChoice.update),
            child: Text(updateText),
          ),
        ],
      ),
    );
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
