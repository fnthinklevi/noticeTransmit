import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show AlertDialog, ModalBarrier;
import 'package:flutter_test/flutter_test.dart';

import 'package:notice_transmit/widgets/app_root.dart';
import 'package:notice_transmit/widgets/ios_dialog_actions.dart';

/// 「三选一决策」那一枚（T90 片25，备份恢复冲突策略）。
///
/// 它存在的**唯一理由**是：那两颗已��的装配件的「取消」都是「什么都不做」，
/// 而这一枚的中间那档（仅导入空缺项）**也是一个真决策** —— 它照样写盘。
/// 所以它不能被拆成「二选一 + 取消」，也不能退回 `bool`：
/// 三个结果在语义上都是「做了某件事」，只有覆盖那一档是破坏性的。
///
/// 这一组用例钉的是那三件事：
/// ① 三颗动作都在，且**覆盖是唯一带破坏性标色**的那颗（红 = 覆盖掉已有配置）；
/// ② 三颗带回三个互不相同的值（走成同一个值 = 两条写盘路径串台）；
/// ③ 「取消」与点外面回 `null`（不是某个值）—— 调用点靠 `null` 判断「这一发恢复整个没做」。
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

  group('三选一决策', () {
    testWidgets('画的是 Cupertino 那一件，三颗动作都在', (tester) async {
      await pumpHost(tester);
      unawaited(
        IosDialogActions.askThreeWay(
          hostContext,
          title: '检测到现有配置',
          message: '当前已有部分配置。覆盖将替换对应类别的全部内容；仅导入空缺项则保留现有配置不动。',
          cancelText: '取消',
          fillGapsText: '仅导入空缺项',
          overwriteText: '覆盖全部',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(action('取消'), findsOneWidget);
      expect(action('仅导入空缺项'), findsOneWidget);
      expect(action('覆盖全部'), findsOneWidget);
    });

    testWidgets('只有「覆盖全部」是破坏性那一颗', (tester) async {
      await pumpHost(tester);
      unawaited(
        IosDialogActions.askThreeWay(
          hostContext,
          title: '检测到现有配置',
          message: '当前已有部分配置。覆盖将替换对应类别的全部内容；仅导入空缺项则保留现有配置不动。',
          cancelText: '取消',
          fillGapsText: '仅导入空缺项',
          overwriteText: '覆盖全部',
        ),
      );
      await tester.pumpAndSettle();

      final destructive = tester
          .widgetList<CupertinoDialogAction>(find.byType(CupertinoDialogAction))
          .where((a) => a.isDestructiveAction)
          .toList();
      expect(
        destructive,
        hasLength(1),
        reason:
            '破坏性那颗的数量不对 ⇒ 要么覆盖没标红（用户看不出它会盖掉已有配置），'
            '要么「仅导入空缺项」被误标成破坏性（它其实保留现有配置）',
      );
      // ⚠ 按**那一行自己的文案**去认破坏性标色，不要拿 widget 实例去比
      //   （`find.byWidget(destructive.first)` 与 finder 里的那一个不是同一实例，
      //   恒零命中 —— 我连着踩了 `descendant` 方向错与实例比对两次）。
      // 这里只需要「三颗里恰好一颗是破坏性的，且它在文案上就是覆盖那一颗」。
      String? destructiveLabel;
      for (final label in const ['取消', '仅导入空缺项', '覆盖全部']) {
        final act = tester.widget<CupertinoDialogAction>(action(label));
        if (act.isDestructiveAction) destructiveLabel = label;
      }
      expect(
        destructiveLabel,
        '覆盖全部',
        reason:
            '带破坏性标色的不是「覆盖全部」⇒ 用户看到的红色指向了别的动作，'
            '而「仅导入空缺项」其实保留现有配置、「取消」什么都不做',
      );
    });

    testWidgets('两档各回各的值（走成同一个 = 两条写盘路径串台）', (tester) async {
      await pumpHost(tester);
      for (final pair in const [
        ('仅导入空缺项', ConflictChoice.fillGaps),
        ('覆盖全部', ConflictChoice.overwrite),
      ]) {
        ConflictChoice? got;
        unawaited(
          IosDialogActions.askThreeWay(
            hostContext,
            title: '检测到现有配置',
            message: '当前已有部分配置。覆盖将替换对应类别的全部内容；仅导入空缺项则保留现有配置不动。',
            cancelText: '取消',
            fillGapsText: '仅导入空缺项',
            overwriteText: '覆盖全部',
          ).then((v) => got = v),
        );
        await tester.pumpAndSettle();
        await tester.tap(action(pair.$1));
        await tester.pumpAndSettle();
        expect(
          got,
          pair.$2,
          reason:
              '「${pair.$1}」带回的值不是它自己 ⇒ 调用点会走错那条写盘路径，'
              '而这两条的后果差着「保留现有配置」与「替换已有配置」',
        );
      }
    });

    testWidgets('「取消」回 null（不是某个值）', (tester) async {
      await pumpHost(tester);
      ConflictChoice? got = ConflictChoice.fillGaps;
      unawaited(
        IosDialogActions.askThreeWay(
          hostContext,
          title: '检测到现有配置',
          message: '当前已有部分配置。覆盖将替换对应类别的全部内容；仅导入空缺项则保留现有配置不动。',
          cancelText: '取消',
          fillGapsText: '仅导入空缺项',
          overwriteText: '覆盖全部',
        ).then((v) => got = v),
      );
      await tester.pumpAndSettle();

      await tester.tap(action('取消'));
      await tester.pumpAndSettle();
      expect(got, isNull, reason: '取消回了一个值 ⇒ 调用点当它选了某一档，恢复照跑');
      expect(find.byType(CupertinoAlertDialog), findsNothing);
    });

    testWidgets('点外面关得掉（照旧那枚 Material 框的行为）', (tester) async {
      await pumpHost(tester);
      unawaited(
        IosDialogActions.askThreeWay(
          hostContext,
          title: '检测到现有配置',
          message: '当前已有部分配置。覆盖将替换对应类别的全部内容；仅导入空缺项则保留现有配置不动。',
          cancelText: '取消',
          fillGapsText: '仅导入空缺项',
          overwriteText: '覆盖全部',
        ),
      );
      await tester.pumpAndSettle();

      // ⚠ **只断屏障可点穿这一位**（照旧那枚 Material `showDialog` 的默认）：
      // 「点外面回 null」在 widget 测试里**不可观察** —— `CupertinoAlertDialog` 高度不封顶，
      // 屏障与弹层的画面矩形完全重合，屏幕上没有「外面」可点（片22/23/24 各撞过一次，已登记）。
      expect(
        tester
            .widgetList<ModalBarrier>(find.byType(ModalBarrier))
            .where((b) => b.dismissible)
            .toList(),
        isNotEmpty,
        reason: '这一枚点外面关不掉 ⇒「看一眼又想收回去」这条路没了',
      );
    });
  });
}
