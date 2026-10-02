import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show AlertDialog, ModalBarrier;
import 'package:flutter_test/flutter_test.dart';

import 'package:notice_transmit/widgets/app_root.dart';
import 'package:notice_transmit/widgets/ios_dialog_actions.dart';

/// 「有更新」那一枚弹层的两个装配点（T90 片21）。
///
/// 这枚原来没有页面级用例（实测 `updateFoundNew` / `updateIgnore` / `updateButton` 在 `test/`
/// 与 `integration_test/` 里**零命中**），换件时只能靠肉眼搬。搬完之后必须有这样一组用例 ——
/// 这一屏上真正会出事的三件事都不是"长得好不好看"：
/// ① 「忽略」那一档带走的是**一次写盘**（写进忽略名单），不是一次确认 ⇒ 走成"关框"就等于没按；
/// ② 强推那版**点外面不许关**（唯一出路是立刻更新），非强推点外面 = 先不更新；
/// ③ 「更新」那一档按下时弹层**已经**被 pop 掉了，于是 `_startDownloadUpdate` 里那个
///    `Navigator.pop` 必须同时摘掉 —— 留着就把刚弹出来的进度框关掉了（那一处在页面里，
///    这里断的是它的前提：三颗都在、值不走串）。
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

  /// 弹 [prompt]，返回用户选的那一档（点外面关掉 = null）。
  Future<UpdateChoice?> openAndPick(
    WidgetTester tester,
    Future<UpdateChoice?> Function(BuildContext) prompt,
  ) async {
    UpdateChoice? picked;
    unawaited(prompt(hostContext).then((v) => picked = v));
    await tester.pumpAndSettle();
    return picked;
  }

  Future<UpdateChoice?> normalPrompt(BuildContext ctx) =>
      IosDialogActions.showUpdatePrompt(
        ctx,
        title: '发现新版本',
        ignoreText: '忽略',
        laterText: '稍后',
        updateText: '更新',
      );

  Future<UpdateChoice?> forcePrompt(BuildContext ctx) =>
      IosDialogActions.showForceUpdatePrompt(
        ctx,
        title: '需要更新',
        updateText: '立即更新',
      );

  group('「有更新」三颗档位那枚', () {
    testWidgets('画的是 Cupertino 那一件，且三颗都在', (tester) async {
      await pumpHost(tester);
      await openAndPick(tester, normalPrompt);

      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(action('忽略'), findsOneWidget);
      expect(action('稍后'), findsOneWidget);
      expect(action('更新'), findsOneWidget);
    });

    testWidgets('每一档各自回自己的值（三颗不许串台）', (tester) async {
      await pumpHost(tester);
      for (final pair in const [
        ('忽略', UpdateChoice.ignore),
        ('稍后', UpdateChoice.later),
        ('更新', UpdateChoice.update),
      ]) {
        UpdateChoice? got;
        unawaited(normalPrompt(hostContext).then((v) => got = v));
        await tester.pumpAndSettle();
        await tester.tap(action(pair.$1));
        await tester.pumpAndSettle();
        expect(
          got,
          pair.$2,
          reason:
              '「${pair.$1}」带回的值不是它自己 ⇒ 调用点会走错分支'
              '（「忽略」要写盘，「更新」要启下载，两者都不是关框）',
        );
      }
    });

    testWidgets('点外面关掉回 null，不是默认那档', (tester) async {
      await pumpHost(tester);
      UpdateChoice? got = UpdateChoice.update;
      unawaited(normalPrompt(hostContext).then((v) => got = v));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(got, isNull, reason: '点外面 ≠ 答了 ⇒ 不能回一个值让调用方误判');
      expect(find.byType(CupertinoAlertDialog), findsNothing);
    });

    testWidgets('titleBadge 给 null 就是没有徽标那一格', (tester) async {
      await pumpHost(tester);
      unawaited(normalPrompt(hostContext));
      await tester.pumpAndSettle();
      expect(find.text('发现新版本'), findsOneWidget);
      expect(find.text('强制更新'), findsNothing);

      // ⚠ 必须先 `pumpHost` 重新挂树：上一枚退场时宿主那个 `Builder` 也被拆掉了，
      // 拿旧 `hostContext` 去弹第二枚会撞 "Looking up a deactivated widget's ancestor"（第一版）。
      await pumpHost(tester);
      unawaited(
        IosDialogActions.showUpdatePrompt(
          hostContext,
          title: '发现新版本',
          ignoreText: '忽略',
          laterText: '稍后',
          updateText: '更新',
          titleBadge: const Text('强制更新'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('强制更新'), findsOneWidget);
    });

    testWidgets('barrierDismissible 默认开着（照旧那枚 Material 框的行为）', (tester) async {
      await pumpHost(tester);
      unawaited(normalPrompt(hostContext));
      await tester.pumpAndSettle();
      final barriers = tester.widgetList<ModalBarrier>(
        find.byType(ModalBarrier),
      );
      expect(
        barriers.any((b) => b.dismissible),
        isTrue,
        reason: '点外面关不掉 ⇒ 非强推时「点开看看又想收回去」这条路消失了',
      );
    });
  });

  group('强制更新那一枚（只有一条出路）', () {
    testWidgets('只有一颗动作，且那一颗是默认动作', (tester) async {
      await pumpHost(tester);
      await openAndPick(tester, forcePrompt);

      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      final actions = tester.widgetList<CupertinoDialogAction>(
        find.byType(CupertinoDialogAction),
      );
      expect(actions, hasLength(1), reason: '强推那版不该有「忽略 / 稍后」两条出路');
      expect(
        actions.single.isDefaultAction,
        isTrue,
        reason: '唯一那颗不是默认动作 ⇒ 它看起来像颗「可以跳过」的动作',
      );
      expect(action('立即更新'), findsOneWidget);
    });

    testWidgets('强推那版点外面不许关（唯一出路就是立刻更新）', (tester) async {
      await pumpHost(tester);
      UpdateChoice? got = UpdateChoice.later;
      unawaited(forcePrompt(hostContext).then((v) => got = v));
      await tester.pumpAndSettle();

      // ⚠ 断的是**屏障那一层本身**：有没有一条可点穿的 `ModalBarrier`。
      // 坐标式的那一按（`tapAt(20,20)`）不能用 —— 这一枚只有一颗动作、弹层更矮，
      // 左上角本来就落在弹层内，按下去等于按了弹层里的东西（第一版就写成那样，
      //  `got` 变成 UpdateChoice.later —— 那是测试自己的问题，不是产品的）。
      // 屏障的 `dismissible` 才是"点外面会发生什么"的唯一事实。
      final dismissible = tester
          .widgetList<ModalBarrier>(find.byType(ModalBarrier))
          .where((b) => b.dismissible)
          .toList();
      expect(
        dismissible,
        isEmpty,
        reason:
            '强推那版存在一条可点穿的屏障 ⇒ 点外面能把它关掉，'
            '而旧形状是 showDialog(barrierDismissible: false)，唯一出路只能是立刻更新',
      );
      expect(got, UpdateChoice.later, reason: '（未确认的初值，证明下面那次按压什么也没走成）');
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    });

    testWidgets('按下那颗回 update（null 的话下载永远起不来）', (tester) async {
      await pumpHost(tester);
      UpdateChoice? got;
      unawaited(forcePrompt(hostContext).then((v) => got = v));
      await tester.pumpAndSettle();
      await tester.tap(action('立即更新'));
      await tester.pumpAndSettle();
      expect(got, UpdateChoice.update);
    });

    testWidgets('强推那枚任何一条结果都只有 update 一个取值', (tester) async {
      await pumpHost(tester);
      final seen = <UpdateChoice?>{};
      unawaited(forcePrompt(hostContext).then(seen.add));
      await tester.pumpAndSettle();
      await tester.tap(action('立即更新'));
      await tester.pumpAndSettle();
      expect(seen, {UpdateChoice.update});
    });

    testWidgets('三颗那枚的「更新」也回 update（两枚不许互相顶替）', (tester) async {
      await pumpHost(tester);
      UpdateChoice? got;
      unawaited(normalPrompt(hostContext).then((v) => got = v));
      await tester.pumpAndSettle();
      await tester.tap(action('更新'));
      await tester.pumpAndSettle();
      expect(got, UpdateChoice.update);
    });
  });
}
