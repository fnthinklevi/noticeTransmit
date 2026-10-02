import 'package:flutter/cupertino.dart';
// 进度条是 Material 的 LinearProgressIndicator，而外壳是 Cupertino 的（与 IosFormDialog 同一件事：
// CupertinoAlertDialog 自己不含 Material 祖先，少了那层透明 Material 就 "No Material widget found"）。
// ⇒ 两边各引一处，用 show 限定避免同名件冲突。
import 'package:flutter/material.dart' show AlertDialog, LinearProgressIndicator;
import 'package:flutter_test/flutter_test.dart';

import 'package:notice_transmit/widgets/app_root.dart';
import 'package:notice_transmit/widgets/ios_progress_dialog.dart';

/// 进度型弹层的**外壳**（T90 片17）。
///
/// 这枚组件的判据只有一条，但它是从两个**用法不同**的调用点来的
/// （`history_page` 的批量补推：无标题、进度条上方一句「已推 N/M 条」、没有动作；
///   `main_page_update` 的更新下载：有标题、进度条下方一个百分比、强推时没有「取消」），
/// 所以每一条「给什么、画成什么样」的对应关系都要钉住 ——
/// 参数少一个、或者两个调用点的差异被抹平，两处都会安静地画错。
void main() {
  Widget wrap(Widget home) =>
      AppRoot(locale: const Locale('zh'), dark: false, home: home);

  /// 把弹层直接放进 AppRoot（它是个纯 widget，弹不弹由调用方决定）。
  Future<void> show(
    WidgetTester tester, {
    required double? progress,
    String? title,
    String? message,
    String? percentText,
    String? cancelText,
    VoidCallback? onCancel,
  }) async {
    await tester.pumpWidget(
      wrap(
        IosProgressDialog(
          progress: progress,
          title: title,
          message: message,
          percentText: percentText,
          cancelText: cancelText,
          onCancel: onCancel,
        ),
      ),
    );
    // ⚠ 这里必须用 `pump()` 而不是 `pumpAndSettle()`：不确定态（progress == null）的
    // LinearProgressIndicator 是**一直动的**，settle 永远不会收敛（第一版就是这么挂的）。
    // 真机那枚下载框在服务器还没给总大小的那一段同样永不静止 —— 想断言它就 pump 固定帧数。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
  }

  Finder bar() => find.byType(LinearProgressIndicator);
  double? barValue(WidgetTester tester) =>
      tester.widget<LinearProgressIndicator>(bar()).value;

  testWidgets('画的是 Cupertino 那一件，Material AlertDialog 一枚都不许有', (tester) async {
    await show(tester, progress: 0.4, title: '正在下载更新');
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(bar(), findsOneWidget, reason: '没有进度条 ⇒ 这枚框什么也没说');
  });

  testWidgets('标题给 null 就真的没有标题那一行（批量补推那一支）', (tester) async {
    // 断"少一行"而不是"没有那句字"：`title ?? ''` 会画出一行**空的**标题，
    // 页面上看不见任何字，但形状已经不对了（标题区多占一行高度）。
    // ⇒ 断的是弹层里 Text 的**数量**：给了标题比不给标题多一行。
    await show(tester, progress: 0.5, message: '已推 3/6 条');
    final withoutTitle = tester.widgetList<Text>(find.byType(Text)).length;
    expect(find.text('已推 3/6 条'), findsOneWidget);
    expect(withoutTitle, 1, reason: '没给标题却出现了不止一行文字 ⇒ 空标题也被画出来了');

    await show(tester, progress: 0.5, title: '正在下载更新', message: '已推 3/6 条');
    expect(find.text('正在下载更新'), findsOneWidget);
    expect(
      tester.widgetList<Text>(find.byType(Text)).length,
      withoutTitle + 1,
      reason: '给了标题却没多出那一行 ⇒ 标题那一支没被接上',
    );
  });

  testWidgets('progress 传 null = 不确定态；传数字 = 确定进度', (tester) async {
    await show(tester, progress: null);
    expect(
      barValue(tester),
      isNull,
      reason: '传了 null 还画成确定进度 ⇒ "服务器还没给总大小"那一段会假装自己知道进度',
    );

    await show(tester, progress: 0.42);
    expect(barValue(tester), 0.42);
  });

  testWidgets('cancelText 与 onCancel 都在才有那颗「取消」；只给一个 = 没有', (tester) async {
    // 只有文案没有回调：不允许出现"点得动但不做事"的动作
    await show(tester, progress: 0.2, cancelText: '取消');
    expect(find.text('取消'), findsNothing, reason: '只有文案没有回调却画出了动作 ⇒ 点它什么都不发生');

    // 只有回调没有文案：同上（文案必须由调用方给，组件不替他编）
    await show(tester, progress: 0.2, onCancel: () {});
    expect(find.byType(CupertinoDialogAction), findsNothing);

    // 两个都给 ⇒ 出现，且是破坏性那颗
    var cancelled = 0;
    await show(
      tester,
      progress: 0.2,
      cancelText: '取消',
      onCancel: () => cancelled++,
    );
    final action = find.widgetWithText(CupertinoDialogAction, '取消');
    expect(action, findsOneWidget);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(cancelled, 1, reason: '「取消」按下去没回调 ⇒ 用户以为撤了，下载还在跑');
  });

  testWidgets('批量补推那一支：没有标题、没有取消，但进度条上方那句一直更新', (tester) async {
    // 这一条照着 history_page 的实际用法写：无 title / 无 cancel / message 在进度条**上方**
    await show(tester, progress: 0.25, message: '已推 1/4 条');
    expect(find.text('已推 1/4 条'), findsOneWidget);
    expect(find.byType(CupertinoDialogAction), findsNothing);
    final messageTop = tester.getTopLeft(find.text('已推 1/4 条')).dy;
    final barTop = tester.getTopLeft(bar()).dy;
    expect(
      barTop,
      greaterThan(messageTop),
      reason: '进度句跑到进度条下面去了 ⇒ 与批量补推原来的形状对不上',
    );

    // 再来一次、内容变 ⇒ 组件只管画，变化由调用方的 ValueListenable 驱动
    await show(tester, progress: 0.75, message: '已推 3/4 条');
    expect(find.text('已推 3/4 条'), findsOneWidget);
    expect(find.text('已推 1/4 条'), findsNothing);
  });
}
