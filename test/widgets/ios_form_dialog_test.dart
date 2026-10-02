import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show AlertDialog, InputDecoration, InkWell, showDialog, TextField;
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/widgets/app_root.dart';
import 'package:notice_transmit/widgets/ios_form_dialog.dart';

/// `IosFormDialog` 的契约（T90 片12）。
///
/// harness 用**真的 `AppRoot`**（样板 `pull_to_refresh_list_test.dart`）：这枚外壳存在的理由
/// 就是"根组件是 CupertinoApp"，在 `MaterialApp` 壳里 pump 它验不到那个环境。
///
/// ⚠ 这四处调用点（新增/编辑条件、新增/编辑动作）在迁移前**没有任何页面级用例**
/// （grep `ruleAddCondition` / `ConditionAdd` 全仓零命中）⇒ 本文件钉的是外壳自己的形状，
/// "条件填进去之后规则真的多了一条"仍欠一条页面级证据（登记在 roadmap 的边界里）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> log;

  Future<void> open(
    WidgetTester tester, {
    int fieldCount = 2,
    Size? surface,
  }) async {
    log = <String>[];
    if (surface != null) {
      await tester.binding.setSurfaceSize(surface);
      addTearDown(() => tester.binding.setSurfaceSize(null));
    }
    await tester.pumpWidget(
      AppRoot(
        locale: const Locale('zh'),
        dark: false,
        home: Builder(
          builder: (pageContext) => CupertinoButton(
            onPressed: () => showDialog<void>(
              context: pageContext,
              builder: (ctx) => IosFormDialog(
                title: '新增条件',
                cancelText: '取消',
                submitText: '添加',
                onSubmit: () {
                  log.add('submit');
                  Navigator.pop(ctx);
                },
                fields: [
                  for (var i = 0; i < fieldCount; i++)
                    Text('第${i + 1}格', key: ValueKey('f$i')),
                ],
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder action(String label) => find.descendant(
    of: find.byType(CupertinoDialogAction),
    matching: find.text(label),
  );

  group('取值与形状（含 fields 是 Material 控件那一种）', () {
    testWidgets('画的是 Cupertino 那一件，标题在字段之上，字段按给的顺序排', (tester) async {
      await open(tester);

      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason: '外壳换回 Material 那件 ⇒ 纯 Cupertino 树里风格又散开一次',
      );
      expect(
        tester.getTopLeft(find.text('新增条件')).dy,
        lessThan(tester.getTopLeft(find.text('第1格')).dy),
        reason: '标题必须压在最上面，字段跟在下面',
      );
      expect(
        tester.getTopLeft(find.text('第1格')).dy,
        lessThan(tester.getTopLeft(find.text('第2格')).dy),
        reason: 'fields 的顺序就是屏幕上的顺序 —— 外壳不许自己排序',
      );
    });

    testWidgets('只有两颗动作：左取消、右保存；保存那颗不许顺手长出第三颗', (tester) async {
      await open(tester);

      final actions = tester
          .widgetList<CupertinoDialogAction>(
            find.descendant(
              of: find.byType(CupertinoAlertDialog),
              matching: find.byType(CupertinoDialogAction),
            ),
          )
          .toList();
      expect(actions, hasLength(2));

      expect(
        tester.getTopLeft(action('取消')).dx,
        lessThan(tester.getTopLeft(action('添加')).dx),
        reason: 'iOS 那条：取消在左、动作在右（反过来会误点）',
      );
    });

    testWidgets('fields 给的是 Material 控件时，外壳必须供得出 Material 祖先（闸门 5.7 喊过的那次）', (
      tester,
    ) async {
      // ⚠ 这条是从**真机红**里学来的：调用点塞进 fields 的是 Material 的 `TextField` 与
      // `InkWell`（`_IosSelectField`），而 `CupertinoAlertDialog` 自己不含 Material ⇒
      // 少一层透明 Material 就整枚表单抛 "No Material widget found"。
      // 上面那四条用例的 fields 全是纯 `Text`，**一条都检不到** —— 外壳用例必须带上
      // "调用方实际会塞什么"的那一种，否则它测的是一个不存在的调用点。
      log = <String>[];
      await tester.pumpWidget(
        AppRoot(
          locale: const Locale('zh'),
          dark: false,
          home: Builder(
            builder: (pageContext) => CupertinoButton(
              onPressed: () => showDialog<void>(
                context: pageContext,
                builder: (_) => IosFormDialog(
                  title: '新增条件',
                  cancelText: '取消',
                  submitText: '添加',
                  onSubmit: () => log.add('submit'),
                  fields: [
                    const TextField(
                      decoration: InputDecoration(hintText: '匹配值'),
                    ),
                    InkWell(onTap: () {}, child: const Text('条件类型')),
                  ],
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: '检不到这条的外壳用例等于在测一个不存在的调用点');
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('提交与取消', () {
    testWidgets('点保存执行 onSubmit 一次；点取消什么都不执行', (tester) async {
      await open(tester);
      await tester.tap(action('添加'));
      await tester.pumpAndSettle();

      expect(log, ['submit'], reason: '保存那颗必须把动作交给调用方（判据在它手里）');
      expect(find.byType(CupertinoAlertDialog), findsNothing);

      await open(tester);
      await tester.tap(action('取消'));
      await tester.pumpAndSettle();

      expect(log, isEmpty, reason: '取消被读成"提交了"就是替用户加了条件');
      expect(find.byType(CupertinoAlertDialog), findsNothing);
    });

    testWidgets('格子多到一屏放不下 ⇒ 最后一格仍滚得到（滚动由框架提供，我方不许再套一层）', (tester) async {
      // ⚠ 这条今天**没有坏法可植**：反证 FM1 把我原先多套的那层 SingleChildScrollView 摘掉之后
      // 一条都不红 ⇒ 滚动一直是 `CupertinoAlertDialog` 那层在有界容器里给的（与片6 PK5 同一课）。
      // 所以它是**回归护栏**（防未来有人给 content 加固定高度或关掉滚动），不是"已验证的闸"。
      await open(tester, fieldCount: 12, surface: const Size(360, 300));

      const surfaceHeight = 300.0;
      final last = find.byKey(const ValueKey('f11'));
      expect(
        tester.getRect(last).bottom,
        greaterThan(surfaceHeight),
        reason: '最后一格本来就该在视口外，否则这条什么都没验（全都看得见时摘掉滚动也不会红）',
      );

      await tester.ensureVisible(last);
      await tester.pumpAndSettle();

      expect(
        tester.getRect(last).bottom,
        lessThanOrEqualTo(surfaceHeight),
        reason: '滚完之后最后一格要整条进入视口 —— 否则矮屏上根本填不完这张表',
      );
      // 标题留在滚动区外：滚到一半也要知道自己在填哪张表。
      expect(
        tester.getRect(find.text('新增条件')).bottom,
        lessThanOrEqualTo(surfaceHeight),
      );
    });
  });
}
