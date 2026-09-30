import 'package:flutter/cupertino.dart';
import '../theme/app_colors.dart';

/// 二级页导航栏返回件 —— 全站唯一允许的返回件（守卫见
/// `test/architecture/ui_style_guards_test.dart`）。
///
/// 为什么不用 `CupertinoNavigationBarBackButton`：它会带一段**本地化的**「返回」文字
/// （取 `CupertinoLocalizations.backButtonLabel`），中文环境下这段文字加图标会把
/// `CupertinoNavigationBar` 的 leading 挤爆；而 `CupertinoLocalizations` 一旦取不到
/// （`DefaultCupertinoLocalizations` 只认 `en`）它就是直接抛异常，导航栏整块红。
///
/// 「安全」还体现在第二点：没有可弹的路由时它**不渲染**，而不是渲染一个点了没反应的按钮。
class SafeBackButton extends StatelessWidget {
  const SafeBackButton({super.key, this.onPressed, this.color});

  /// 默认 `Navigator.pop`。给了 `onPressed` 就交给调用方（例如先收键盘再弹）。
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final navigator = Navigator.maybeOf(context);
    final canPop = navigator?.canPop() ?? false;
    if (onPressed == null && !canPop) return const SizedBox.shrink();
    return CupertinoButton(
      onPressed: () {
        if (onPressed != null) {
          onPressed!();
        } else {
          navigator?.pop();
        }
      },
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(44, 44),
      child: Icon(
        CupertinoIcons.back,
        color: color ?? AppColors.systemBlue(context),
        size: 28,
      ),
    );
  }
}
