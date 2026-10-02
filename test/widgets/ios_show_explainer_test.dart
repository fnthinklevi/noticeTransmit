import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show AlertDialog, ModalBarrier;
import 'package:flutter_test/flutter_test.dart';

import 'package:notice_transmit/widgets/app_root.dart';
import 'package:notice_transmit/widgets/ios_dialog_actions.dart';

/// 「长文说明型」那一枚（T90 片26，规则引导）。
///
/// 它与 `showInfo` 的差别就是**正文能不能不是一句话**：规则引导要装四组
/// 「小标题 + 描述」条目加一个提示框。压进 `showInfo(message: String)` 只有两条路 ——
/// 把整段拼成一个字符串（丢掉每条自己的图标与颜色），或者给 `message` 开一个 `Widget?` 口
/// （那口一开始能装任何东西，`showInfo` 就不再是「只读说明框」了）。
/// 所以另立 `showExplainer`：[body] 是 Widget，`message` 那一族仍然是 String。
///
/// 这一组钉三件事：① 正文真的按调用方给的 widget 画（不是被压成一句话）；
/// ② 只有**一颗**动作（说明型没有「确认 / 取消」之分）；③ 「知道了」那次回什么值 ——
/// 它不带走任何选择，返回 `void`，调用点不该去判它。
void main() {
  late BuildContext hostContext;

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      AppRoot(
        locale: const Locale('zh'),
        dark: false,
        home: Builder(
          builder: (ctx) {
            hostContext = ctx;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();
  }

  Finder action(String text) =>
      find.widgetWithText(CupertinoDialogAction, text);

  /// 打开那一枚；[dismissible] 照实传（规则引导那一枚显式传 false）。
  Future<void> open(WidgetTester tester, {bool dismissible = true}) {
    unawaited(
      IosDialogActions.showExplainer(
        hostContext,
        title: '规则约束介绍',
        gotItText: '知道了',
        barrierDismissible: dismissible,
        body: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('新增规则'),
            Text('条件'),
            Text('动作'),
            Text('启用'),
            Text('提示：规则按优先级顺序执行'),
          ],
        ),
      ),
    );
    return tester.pumpAndSettle();
  }

  group('长文说明型', () {
    testWidgets('画的是 Cupertino 那一件，正文就是调用方给的那几行', (tester) async {
      await pumpHost(tester);
      await open(tester);

      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('规则约束介绍'), findsOneWidget);
      // 五行都在 ⇒ body 真的被当 widget 画了，没有被压成一句话
      for (final line in const ['新增规则', '条件', '动作', '启用', '提示：规则按优先级顺序执行']) {
        expect(find.text(line), findsOneWidget, reason: '「$line」那一行没画出来');
      }
    });

    testWidgets('只有一颗动作，且就是那一句「知道了」', (tester) async {
      await pumpHost(tester);
      await open(tester);

      final actions = tester.widgetList<CupertinoDialogAction>(
        find.byType(CupertinoDialogAction),
      );
      expect(actions, hasLength(1), reason: '说明型弹层不该有「确认 / 取消」两颗');
      expect(action('知道了'), findsOneWidget);
      expect(actions.single.isDefaultAction, isTrue);
    });

    testWidgets('按「知道了」关掉，且不带走任何选择', (tester) async {
      await pumpHost(tester);
      await open(tester);

      await tester.tap(action('知道了'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoAlertDialog), findsNothing);
    });

    testWidgets('gotItText 不给就退回 l10n.ok', (tester) async {
      await pumpHost(tester);
      unawaited(
        IosDialogActions.showExplainer(
          hostContext,
          title: '规则约束介绍',
          body: const Text('说明'),
        ),
      );
      await tester.pumpAndSettle();

      // app_zh.arb 里 `ok` = 「好的」
      expect(find.text('好的'), findsOneWidget);
    });

    // ⚠ **两条分开写**，不要在同一条里连开两枚：第二枚弹层是叠在第一枚
    //   之上的，**第一枚那条可点穿的屏障还在树上** ⇒ `where(dismissible)` 仍然非空，
    //   断言会报成「显式传 false 没生效」——那是测试自己的问题。
    testWidgets('barrierDismissible 默认开着（照旧 Material 框的行为）', (tester) async {
      await pumpHost(tester);
      await open(tester);
      expect(
        tester
            .widgetList<ModalBarrier>(find.byType(ModalBarrier))
            .where((b) => b.dismissible)
            .toList(),
        isNotEmpty,
        reason: '默认可点穿 ⇒「看一眼又想收回去」这条路还在',
      );
    });

    testWidgets('显式传 false 那枚就不可点穿（规则引导那种「读完才行」）', (tester) async {
      await pumpHost(tester);
      await open(tester, dismissible: false);
      expect(
        tester
            .widgetList<ModalBarrier>(find.byType(ModalBarrier))
            .where((b) => b.dismissible)
            .toList(),
        isEmpty,
        reason: '显式传 false 却没有生效 ⇒ 规则引导那种「读完才行」会退化成可跳过',
      );
    });
  });
}
