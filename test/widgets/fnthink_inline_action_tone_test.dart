import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/theme/app_colors.dart';
import 'package:notice_transmit/widgets/app_root.dart';
import 'package:notice_transmit/widgets/fnthink_card.dart';

/// T108 片①：「行内动作」的语义色真的落到字上（不是只加了一个没人读的字段）。
///
/// 判据打在 **`colorOf` 这一枚唯一作者** 上，不抄 RGB 常量：抄一个色值进来，下一次改主题色
/// 就是假红；但也不能只断 `tone` 字段在 —— 那验不出"字段有人读"。所以两条一起断：
/// ① 页面上那颗 `Text` 的实际颜色 == 当场用同一棵树上的 context 算出来的 `colorOf(...)`；
/// ② 三档两两不同（有两档同色＝"按功能分色"这件事根本没发生）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 泵一棵最小的树，回来 `(那颗字的颜色, 期望颜色)` 一对 —— 两者都从**同一个 context** 取，
  /// 免得主题色按 context 解析时两头取到不同世界（那会永远相等或永远不等）。
  Future<(Color, Color)> pumpPair(
    WidgetTester tester,
    FnthinkActionTone tone,
    bool enabled,
  ) async {
    await tester.pumpWidget(
      AppRoot(
        locale: const Locale('zh'),
        dark: false,
        home: FnthinkInlineAction(
          label: '那一件',
          tone: tone,
          onPressed: enabled ? () {} : null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(FnthinkInlineAction));
    final actual = tester
        .widget<Text>(
          find
              .descendant(
                of: find.byType(FnthinkInlineAction),
                matching: find.byType(Text),
              )
              .first,
        )
        .style!
        .color!;
    return (actual, FnthinkInlineAction.colorOf(context, tone, enabled));
  }

  testWidgets('三档各有各的颜色，且页面上那颗字就是 colorOf 算出来的那一个', (tester) async {
    final expected = <Color>{};
    for (final tone in FnthinkActionTone.values) {
      final (actual, want) = await pumpPair(tester, tone, true);
      expect(actual, want, reason: '$tone 的字色不是 colorOf 给的 ⇒ 有人在页面里自己挑了一次颜色');
      expected.add(want);
    }
    expect(
      expected.length,
      FnthinkActionTone.values.length,
      reason: '三档里有两档同色 ⇒ "按功能分色"这件事没有发生',
    );
  });

  testWidgets('破坏性那一档确实是系统红（不是"另一种蓝"）', (tester) async {
    final (actual, want) = await pumpPair(
      tester,
      FnthinkActionTone.destructive,
      true,
    );
    expect(actual, want);
    expect(
      want,
      AppColors.systemRed(tester.element(find.byType(FnthinkInlineAction))),
      reason: '不可逆的动作画成蓝 ⇒ 它和"复制一下"看起来是同一类决定',
    );
  });

  testWidgets('不可用 ⇒ 置灰，那颗字还在（藏起来是 T100 反对的写法）', (tester) async {
    final (actual, want) = await pumpPair(
      tester,
      FnthinkActionTone.neutral,
      false,
    );
    final context = tester.element(find.byType(FnthinkInlineAction));
    expect(actual, want);
    expect(
      want,
      AppColors.tertiaryLabel(context),
      reason: '禁用态该是灰；"灰"与"消失"是两句话，用户看不出来这一页有这个功能',
    );
    expect(find.text('那一件'), findsOneWidget);
  });

  test('不传 tone 的旧调用点仍是主色蓝（默认档没被改走）', () {
    // 15 枚调用点里只给非默认的那些写了 tone；默认被改掉 ⇒ 一片蓝会安静变色，
    // 而没人会在 diff 里看见。这一条钉的就是那个默认值。
    const action = FnthinkInlineAction(label: 'x', onPressed: null);
    expect(action.tone, FnthinkActionTone.action);
  });
}
