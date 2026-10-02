import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notice_transmit/widgets/app_root.dart';
import 'package:notice_transmit/widgets/ios_grid_picker_dialog.dart';

/// 图标网格型弹层的**外壳**（T90 片18）。
///
/// 台账里这一族是**第四种形状**（确认框 / 单选列表 / 表单 / 进度框之外）：标题 + 有高度上限的
/// 可滚网格，**没有动作区**。这枚用例把四条判据钉住：外壳是 Cupertino 那一件、网格参数真的按
/// 传进来的数画（列数与格子比例写死的话，调用方那处真实数字就形同虚设）、`itemBuilder` 产出的
/// 格子能点、以及**网格里那些 Material 件（InkWell / CircleAvatar）真的找得到 Material 祖先**。
void main() {
  Widget wrap(Widget home) =>
      AppRoot(locale: const Locale('zh'), dark: false, home: home);

  Future<void> show(
    WidgetTester tester, {
    int itemCount = 12,
    int crossAxisCount = 4,
    double childAspectRatio = 0.78,
    double maxHeight = 380,
  }) async {
    await tester.pumpWidget(
      wrap(
        IosGridPickerDialog(
          title: '应用图标',
          itemCount: itemCount,
          crossAxisCount: crossAxisCount,
          childAspectRatio: childAspectRatio,
          maxHeight: maxHeight,
          itemBuilder: (context, i) =>
              InkWell(onTap: () {}, child: const SizedBox.expand()),
        ),
      ),
    );
    // ⚠ `pump` 而不是 `pumpAndSettle`：网格可滚，settle 在这里没有"静止"可言。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
  }

  SliverGridDelegateWithFixedCrossAxisCount gridOf(WidgetTester tester) =>
      tester.widget<GridView>(find.byType(GridView)).gridDelegate
          as SliverGridDelegateWithFixedCrossAxisCount;

  testWidgets('外壳是 Cupertino 那一件，Material AlertDialog 一枚都不许有', (tester) async {
    await show(tester);
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('应用图标'), findsOneWidget, reason: '标题没了');
  });

  testWidgets('列数与格子比例真的按参数画（写死的话这枚就没牙）', (tester) async {
    await show(tester, crossAxisCount: 4, childAspectRatio: 0.78);
    var g = gridOf(tester);
    expect(g.crossAxisCount, 4);
    expect(g.childAspectRatio, 0.78);

    // 换一组参数再来一次：同一枚组件必须跟着变
    await show(tester, crossAxisCount: 3, childAspectRatio: 1.2);
    g = gridOf(tester);
    expect(g.crossAxisCount, 3, reason: '参数换了网格还按 4 列画 ⇒ 那一处真实数字白传了');
    expect(g.childAspectRatio, 1.2);
  });

  testWidgets('网格按 itemCount 出格子，且高度上限真的生效（超出一屏就滚）', (tester) async {
    // ⚠ 格子数必须**多到装不下**：12 格 × 4 列 = 3 行，天然高度本来就不到 380
    //   ⇒ 那时"高度上限失效"这条判据读不出来（第一版就是这么假绿的，GD3 exit 0）。
    //   这里用 40 格（10 行）⇒ 去掉上限时网格高度远超上限。
    await show(tester, itemCount: 40, maxHeight: 380);
    final gridHeight = tester.getSize(find.byType(GridView)).height;
    expect(
      gridHeight,
      lessThanOrEqualTo(380),
      reason: '40 格还按 10 行铺开 ⇒ 图标多了就撑出一屏黄条，高度上限没接上',
    );
    expect(find.byType(InkWell), findsWidgets, reason: '网格一格都没画出来');
  });

  testWidgets('格子能点（InkWell 找得到 Material 祖先 —— CupertinoAlertDialog 自己不含）', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      wrap(
        IosGridPickerDialog(
          title: '应用图标',
          itemCount: 4,
          itemBuilder: (context, i) => InkWell(
            onTap: () => taps++,
            child: const CircleAvatar(radius: 10),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    // ⚠ 若外壳漏了那层 Material，这一句在构建时就抛 "No Material widget found"，
    //   到不了这里 —— 也就是说这条用例**能看见**那一层是否存在（与片17 那枚不同：
    //   那枚的字段只有进度条，不挑 Material 祖先，所以整层摘掉它也全绿）。
    final cell = find.byType(InkWell).first;
    await tester.tap(cell, warnIfMissed: false);
    await tester.pump();
    expect(taps, 1, reason: '格子点不动 ⇒ 图标那一格永远选不中');
    expect(
      find.byType(CircleAvatar),
      findsNWidgets(4),
      reason: 'CircleAvatar 也是 Material 件，它在就说明祖先那条路通着',
    );
  });
}
