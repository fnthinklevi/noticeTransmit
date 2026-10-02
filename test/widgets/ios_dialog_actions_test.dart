import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show AlertDialog;
import 'package:flutter_test/flutter_test.dart';

import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/widgets/app_root.dart';
import 'package:notice_transmit/widgets/ios_dialog_actions.dart';

/// 弹层的统一入口（T06 的 `askConfirm` + T90 片5 的 `showInfo`）。
///
/// ⚠ harness 用**真的 `AppRoot`**（样板见 `pull_to_refresh_list_test.dart`）：这两件 helper
/// 存在的理由就是"根组件是 CupertinoApp"，在 `MaterialApp` 壳里 pump 它们，
/// 测到的是另一套外观与另一套本地化装配 —— 恰好是这次要防的那件事。
///
/// 守卫那一侧（`ui_style_guards_test.dart`、`delete_confirmation_contract_test.dart`）
/// 只看源文本；这一份看的是行为：画出来的是哪一件、点哪颗回来的是什么。
void main() {
  Widget wrap(Widget home) =>
      AppRoot(locale: const Locale('zh'), dark: false, home: home);

  /// 一个把自身 context 交出来的宿主页面，helper 需要它才能读到本地化。
  Widget host({
    required Future<void> Function(BuildContext, AppLocalizations) action,
  }) {
    return Builder(
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return CupertinoPageScaffold(
          child: Center(
            child: CupertinoButton(
              onPressed: () => action(ctx, l10n),
              child: const Text('开'),
            ),
          ),
        );
      },
    );
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('开'));
    await tester.pumpAndSettle();
  }

  group('showInfo（单动作说明框）', () {
    testWidgets('画的是一件 Cupertino 的，Material 那一件一枚都不许有', (tester) async {
      late AppLocalizations l10n;
      await tester.pumpWidget(
        wrap(
          host(
            action: (ctx, locs) {
              l10n = locs;
              return IosDialogActions.showInfo(
                ctx,
                title: '选指定卡的局限',
                message: '部分短信识别不出所属卡',
              );
            },
          ),
        ),
      );

      await open(tester);
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason:
            '说明框又走回 Material 那件 ⇒ 纯 Cupertino 树里缺 MaterialLocalizations 时会红屏，'
            '而且这正是台账要划掉的那种形态',
      );
      expect(find.text('选指定卡的局限'), findsOneWidget);
      expect(find.text('部分短信识别不出所属卡'), findsOneWidget);
      // 缺省那颗按钮抄的是 l10n.ok，不是写死的「好」——词条换字时这里会跟着走。
      expect(find.text(l10n.ok), findsOneWidget);
    });

    testWidgets('只有一颗动作，点它就把模态关掉', (tester) async {
      await tester.pumpWidget(
        wrap(
          host(
            action: (ctx, locs) => IosDialogActions.showInfo(
              ctx,
              title: '标题',
              message: '正文',
              okText: '知道了',
            ),
          ),
        ),
      );

      await open(tester);
      expect(
        find.descendant(
          of: find.byType(CupertinoAlertDialog),
          matching: find.byType(CupertinoDialogAction),
        ),
        findsOneWidget,
        reason: '说明框不该有第二个出口 —— 多出来的那颗一定是"取消"，而这里没有可取消的选择',
      );

      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      expect(
        find.byType(CupertinoAlertDialog),
        findsNothing,
        reason: '点完还盖着 ⇒ 页面在模态底下，下一格控件就找不到了（闸门多节连红的根因）',
      );
    });

    testWidgets('不返回任何东西，且调用方不会因此拿不到后面的语句', (tester) async {
      var after = 0;
      await tester.pumpWidget(
        wrap(
          host(
            action: (ctx, locs) async {
              await IosDialogActions.showInfo(ctx, title: '标题', message: '正文');
              after++;
            },
          ),
        ),
      );

      await open(tester);
      expect(after, 0, reason: '关掉之前不该往下走 —— 说明框的意义就是"先看完这一屏"');
      await tester.tap(find.byType(CupertinoDialogAction));
      await tester.pumpAndSettle();
      expect(after, 1);
    });
  });

  group('askConfirm（双动作确认框）', () {
    testWidgets('确认那颗回 true，取消那颗回 false', (tester) async {
      final results = <bool>[];
      Future<void> ask(BuildContext ctx, AppLocalizations l10n) async {
        results.add(
          await IosDialogActions.askConfirm(
            ctx,
            title: '删除这条规则',
            message: '删掉之后不可恢复',
            confirmText: '删除',
            cancelText: '先不删',
            destructive: true,
          ),
        );
      }

      await tester.pumpWidget(wrap(host(action: ask)));

      await open(tester);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(results, [true]);

      await open(tester);
      await tester.tap(find.text('先不删'));
      await tester.pumpAndSettle();
      expect(results, [
        true,
        false,
      ], reason: '取消被读成确认 ⇒ "二次确认"变成一次点击就删，还会连带丢凭据');
    });

    testWidgets('框还开着的时候，底下那一层收不到点击', (tester) async {
      var underneath = 0;
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (ctx) {
              final l10n = AppLocalizations.of(ctx);
              return CupertinoPageScaffold(
                child: Center(
                  child: CupertinoButton(
                    key: const ValueKey('underneath'),
                    onPressed: () async {
                      await IosDialogActions.askConfirm(
                        ctx,
                        title: '删除这条规则',
                        message: '删掉之后不可恢复',
                        confirmText: '删除',
                        cancelText: l10n.cancel,
                      );
                      underneath++;
                    },
                    child: const Text('开'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      await open(tester);
      expect(find.text('删除这条规则'), findsOneWidget);
      expect(underneath, 0, reason: '确认还没被答，底下那件事就不能执行');

      // 隔着模态点下面那颗：屏障（barrier）必须把这一下吃掉。
      await tester.tapAt(
        tester.getCenter(find.byKey(const ValueKey('underneath'))),
      );
      await tester.pumpAndSettle();
      expect(underneath, 0, reason: '点得穿 ⇒ 用户可以绕过二次确认，连点两下就把东西删了');
      expect(find.text('删除这条规则'), findsOneWidget);
    });
  });
}
