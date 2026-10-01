import 'package:flutter/cupertino.dart';

/// 列表/内容页的 **Cupertino 下拉刷新壳** —— 全站唯一构造
/// `CupertinoSliverRefreshControl(` 的地方（守卫③见
/// `test/architecture/ui_style_guards_test.dart`）。
///
/// 为什么收成组件而不是每页各写一遍 `CustomScrollView`：base.md ③ 要求下拉刷新用
/// `CustomScrollView` + `CupertinoSliverRefreshControl`，而 `RefreshIndicator` 依赖
/// `MaterialLocalizations`（纯 Cupertino 树里红屏）。各页自己搭 sliver 的话，
/// "哪一页用的是哪一件"就会重新散落 —— 与 T05 长按菜单、T06 确认框同一条理由。
class PullToRefreshList extends StatelessWidget {
  const PullToRefreshList({
    super.key,
    required this.onRefresh,
    required this.children,
    this.emptyChild,
    this.padding = EdgeInsets.zero,
  });

  /// 拉下来那一发。返回的 Future 结束之前转圈不退 ⇒ 这一发要把"重探"真的做完，
  /// 而不是起了个头就交回（否则徽标在圈退了之后才变，用户以为没刷新）。
  final Future<void> Function() onRefresh;

  /// 有内容时的每一格（顺序即屏幕顺序）。
  final List<Widget> children;

  /// 传了就画它、且**不滚动**（占满视口）—— 空态没有"上面还有内容"这回事，
  /// 但下拉仍然要能触发重探，所以它同样在这个壳里、而不是另开一条分支。
  final Widget? emptyChild;

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final empty = emptyChild;
    return CustomScrollView(
      slivers: [
        CupertinoSliverRefreshControl(onRefresh: onRefresh),
        if (empty != null)
          SliverFillRemaining(hasScrollBody: false, child: empty)
        else
          SliverPadding(
            padding: padding,
            sliver: SliverList(delegate: SliverChildListDelegate(children)),
          ),
      ],
    );
  }
}
