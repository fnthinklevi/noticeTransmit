import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/theme/app_colors.dart';
import 'package:notice_transmit/widgets/card_action_sheet.dart';

/// T05 共用组件的契约。
///
/// 这个组件被六个页面共用（三族通道卡 + 两类规则卡 + 历史记录），所以它自己的
/// 每条行为都必须钉住 —— 一处漂移会同时影响所有入口。
/// 纯 UI 组件：不碰 MethodChannel，因此无需 `stubNativeChannels()`。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const zh = Locale('zh');

  Future<void> open(
    WidgetTester tester, {
    required List<CardAction> actions,
    String? title,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: zh,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => CardActionSheet.show(
                  context,
                  actions: actions,
                  title: title,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('CardActionSheet', () {
    testWidgets('列出标题与全部动作；点某项 = 先关弹层再执行那一项', (tester) async {
      final order = <String>[];
      await open(
        tester,
        title: '值班邮箱',
        actions: [
          CardAction(
            icon: Icons.copy,
            label: '复制它',
            onTap: () => order.add('copy'),
          ),
          CardAction(
            icon: Icons.delete_outline,
            label: '删了它',
            danger: true,
            onTap: () => order.add('delete'),
          ),
        ],
      );

      expect(find.text('值班邮箱'), findsOneWidget);
      expect(find.text('复制它'), findsOneWidget);
      expect(find.text('删了它'), findsOneWidget);

      await tester.tap(find.text('复制它'));
      await tester.pumpAndSettle();

      // 关闭必须在回调之前：回调里常是 Navigator.push / setState，
      // 拿弹层的 context 去 push 会作用在已销毁的 element 上。
      expect(order, ['copy']);
      expect(find.text('open'), findsOneWidget);
      expect(find.text('删了它'), findsNothing);
    });

    testWidgets('onTap 为 null ⇒ 置灰且点不动（不藏起来，用户要看得见功能存在）', (tester) async {
      var ran = false;
      await open(
        tester,
        actions: [
          CardAction(icon: Icons.copy, label: '可以点', onTap: () => ran = true),
          const CardAction(
            icon: Icons.delete_outline,
            label: '不能删',
            onTap: null,
          ),
        ],
      );
      // 找"不能删"那一项：ListTile 顺序与 actions 顺序一致
      final disabledTile = tester.widget<ListTile>(
        find.ancestor(of: find.text('不能删'), matching: find.byType(ListTile)),
      );
      expect(
        disabledTile.onTap,
        isNull,
        reason: '没有回调时必须整项禁用（置灰靠的是 ListTile.enabled）',
      );
      expect(
        disabledTile.enabled,
        isFalse,
        reason: '藏起来会让用户以为功能不存在；置灰才说明"存在但当前不许"',
      );

      await tester.tap(find.text('不能删'));
      await tester.pumpAndSettle();
      expect(ran, isFalse);
      expect(
        find.text('不能删'),
        findsOneWidget,
        reason: '点禁用项不该把弹层关掉（否则看起来像"点了没反应却丢了上下文"）',
      );
    });

    testWidgets('破坏性动作转红；普通动作不抢色', (tester) async {
      await open(
        tester,
        actions: [
          CardAction(icon: Icons.copy, label: '复制', onTap: () {}),
          CardAction(
            icon: Icons.delete_outline,
            label: '删除',
            danger: true,
            onTap: () {},
          ),
        ],
      );
      Text textOf(String s) => tester.widget<Text>(find.text(s));
      expect(
        textOf('删除').style?.color,
        AppColors.red,
        reason: '危险动作不显红 = 与"复制"看起来一样，误删的机会',
      );
      expect(textOf('复制').style?.color, isNot(AppColors.red));
    });

    testWidgets('弹层不吞水波纹（Material 透明层是必须的）', (tester) async {
      // Flutter 会在 widget test 里直接断言 "ListTile background color or ink
      // splashes may be invisible" —— 本仓库已经撞到过一次，所以这条不是洁癖。
      await open(
        tester,
        actions: [CardAction(icon: Icons.copy, label: '复制', onTap: () {})],
      );
      await tester.longPress(find.text('复制'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('空动作列表不崩（调用方条件构造时可能一条都不给）', (tester) async {
      await open(tester, actions: const []);
      expect(tester.takeException(), isNull);
      expect(find.byType(CardActionSheet), findsOneWidget);
    });
  });
}
