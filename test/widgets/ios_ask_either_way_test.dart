import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show AlertDialog, ModalBarrier;
import 'package:flutter_test/flutter_test.dart';

import 'package:notice_transmit/widgets/app_root.dart';
import 'package:notice_transmit/widgets/ios_dialog_actions.dart';

/// 「二选一，两条路都要做事」那一枚（T90 片22）。
///
/// 它存在的**唯一理由**是：`askConfirm` 那一族里「取消」= 什么都不做，而语言切换那一枚的
/// 「暂不」**也要写盘**。所以这一组用例钉的不是"长得像"，而是那件最容易在换件时丢的事：
/// **按下第一颗与按下第二颗，返回值必须不同** —— 走成同一个值，界面就分不出
/// 「要顺手刷新语言」与「只落盘不刷新」，而用户在屏幕上看得见界面变了没有。
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

  group('二选一，两条路都做事', () {
    testWidgets('画的是 Cupertino 那一件，且两颗都在', (tester) async {
      await pumpHost(tester);
      unawaited(
        IosDialogActions.askEitherWay(
          hostContext,
          title: '切换语言',
          message: '检测到系统语言已变为中文，是否同步切换应用语言？',
          deferText: '暂不',
          confirmText: '切换',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(action('暂不'), findsOneWidget);
      expect(action('切换'), findsOneWidget);
    });

    testWidgets('第一颗回 false、第二颗回 true（两颗不许同值）', (tester) async {
      await pumpHost(tester);
      for (final pair in const [('暂不', false), ('切换', true)]) {
        bool? got;
        unawaited(
          IosDialogActions.askEitherWay(
            hostContext,
            title: '切换语言',
            message: '检测到系统语言已变为中文，是否同步切换应用语言？',
            deferText: '暂不',
            confirmText: '切换',
          ).then((v) => got = v),
        );
        await tester.pumpAndSettle();
        await tester.tap(action(pair.$1));
        await tester.pumpAndSettle();
        expect(
          got,
          pair.$2,
          reason:
              '「${pair.$1}」带回的值不是它自己 ⇒ 调用点分不出'
              '"落盘但不刷新界面"与"落盘且刷新界面"，用户在屏幕上看得见界面变没变',
        );
      }
    });

    testWidgets('（登记为不可观察）弹层铺满视口时点“外面”那一按落不到屏障上', (tester) async {
      await pumpHost(tester);
      unawaited(
        IosDialogActions.askEitherWay(
          hostContext,
          title: '切换语言',
          message: '检测到系统语言已变为中文，是否同步切换应用语言？',
          deferText: '暂不',
          confirmText: '切换',
        ),
      );
      await tester.pumpAndSettle();

      // ⚠ 这一条在测试里**不可观察**，如实登记在这里而不是冒充成一条用例。
      // 实测（几何探针）：`ModalBarrier` 与 `CupertinoAlertDialog` 的画面矩形都等于
      // 整个视口 —— 即便把视口调到 2000x2800，`CupertinoAlertDialog` 的**高度不封顶**，
      // 它仍然铺满整屏，直到屏幕上**没有「外面」**可以点。第一版连试四种坐标
      // （(20,20) / 顶边上方 4px / 屏障中心 / 两侧的缝）全部落在弹层里。
      //
      // 它为什么碰不到：`showCupertinoDialog` 的屏障是**不可点穿**的（真机上就是这个
      // 行为，与 Material 旧形状那层可点穿的隔层不同），而点它只会在路由本身可关断时提交。
      // 所以「点外面回 null」这个细节在 widget 测试里观察不到；
      // 它的保障是**参数面**（`barrierDismissible` 默认 true，且有注释写明
      // 为什么不能改成 false）。真机侧端口仍需逐屏验。
      final rect = tester.getRect(find.byType(ModalBarrier).first);
      expect(
        rect.size,
        tester.view.physicalSize / tester.view.devicePixelRatio,
        reason:
            '弹层铺满视口时屏障与弹层的几何完全重合 ⇒「点外面」无处可点'
            '（这条差跑登记在上面的注释里）',
      );
    });

    testWidgets('确认那颗是默认动作，两颗都不是破坏性', (tester) async {
      await pumpHost(tester);
      unawaited(
        IosDialogActions.askEitherWay(
          hostContext,
          title: '切换语言',
          message: '检测到系统语言已变为中文，是否同步切换应用语言？',
          deferText: '暂不',
          confirmText: '切换',
        ),
      );
      await tester.pumpAndSettle();

      final actions = tester.widgetList<CupertinoDialogAction>(
        find.byType(CupertinoDialogAction),
      );
      expect(actions, hasLength(2));
      expect(
        actions.where((a) => a.isDefaultAction).length,
        1,
        reason: '「切换」是这一枚要推荐的那条路 ⇒ 只能是它带默认动作',
      );
      expect(
        actions.where((a) => a.isDestructiveAction).length,
        0,
        reason: '这一枚两条路都不是破坏性（切语言不是删东西）⇒ 出了红字就是套错了族',
      );
    });
  });
}
