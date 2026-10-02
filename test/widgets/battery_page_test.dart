import 'dart:io';

import 'package:flutter/cupertino.dart';
// 阈值框的**字段**仍是 Material 的（Slider / TextField），弹层外壳是 Cupertino 的（T90 片14）
// ⇒ 两边各引一处，用 show 限定避免同名件冲突。
import 'package:flutter/material.dart' show AlertDialog, TextField;
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/pages/battery_page.dart';
import 'package:notice_transmit/services/battery_service.dart';
import 'package:notice_transmit/widgets/app_root.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/engine_rule_store_fake.dart';
import '../support/source_guards.dart';
import '../test_setup.dart';

/// 电量页顶部读数的色调档位（1.5.76 实拍三页时发现的不一致，维护者点头后修）。
///
/// 病灶：`currentLevel` 读不到时是 `-1`，而旧判据只有三档（`>=50` 绿 / `>=20` 橙 / 否则红）
/// ⇒ `-1` 掉进红色档，顶部大字写着「未知」、图标与数字却是"电量已低于阈值"的红。
/// 那是把"没有数"报成"出事了"，比不显示更坏。
void main() {
  group('batteryToneOf 档位', () {
    test('读不到（-1）走 unknown，不许落进任何一档颜色', () {
      expect(batteryToneOf(-1), BatteryTone.unknown);
      // 比 -1 更小的异常值同样不许被当成"极低电量"
      expect(batteryToneOf(-100), BatteryTone.unknown);
    });

    test('边界前后一格分明（20 / 50 是含端点的）', () {
      expect(batteryToneOf(0), BatteryTone.critical);
      expect(batteryToneOf(19), BatteryTone.critical);
      expect(batteryToneOf(20), BatteryTone.warn);
      expect(batteryToneOf(49), BatteryTone.warn);
      expect(batteryToneOf(50), BatteryTone.good);
      expect(batteryToneOf(100), BatteryTone.good);
    });
  });

  group('页面确实按档位上色（不是只改了函数没接线）', () {
    final src = stripComments(
      File('${projectRoot()}/lib/pages/battery_page.dart').readAsStringSync(),
    );

    test('色调只从 batteryToneOf 来，页里不再留第二份三档判据', () {
      expect(src, contains('batteryToneOf(_service.currentLevel)'));
      expect(
        src,
        isNot(contains('_service.currentLevel >= 50')),
        reason: '阈值判据留在 build 里 = 改档位时只改到一处，另一处继续骗人',
      );
    });

    test('unknown 档给中性色，不给红/绿/橙', () {
      final line = src
          .split('\n')
          .firstWhere((l) => l.contains('BatteryTone.unknown =>'));
      expect(line, contains('AppColors.tertiaryLabel(context)'));
      expect(
        line,
        isNot(anyOf(contains('AppColors.red'), contains('AppColors.green'))),
      );
    });

    // 片13：那一发系统请求原来写在弹层按钮的回调里（pop 完立刻 invokeMethod），
    // 现在必须等 `askConfirm` 返回答案之后由调用点发 —— 与 #103、片11 同一条道理：
    // 「点没点中那颗钮」与「用户到底选了哪颗」是两件事，后者才是发请求的条件。
    test('去设置那一发在 await 之后，不在弹层回调里', () {
      expect(
        src,
        contains('IosDialogActions.askConfirm('),
        reason: '外壳没走装配点 ⇒ 形状又要各页一份',
      );
      expect(
        src.indexOf('askConfirm(') <
            src.indexOf("invokeMethod('requestBatteryOptimization')"),
        isTrue,
        reason: '那一发跑到 askConfirm 之前 ⇒ 框一弹出来就把用户送去设置了',
      );
      // 「拿到答案之后按答案早退」这一条由 `delete_confirmation_contract_test` 的咽喉清单钉
      // （那里断的是同一个标识符被否定过），这里不重复写第二份判据。
      expect(
        src,
        isNot(contains('onConfirm:')),
        reason: '又把动作塞回弹层回调 ⇒ 点「暂不」与点「去设置」在这条链上又分不开了',
      );
    });
  });

  // T90 片14 把这枚阈值框换成了共享外壳 `IosFormDialog`，而**编辑分支**（isEdit → updateRule）
  // 从来没有页面级用例 —— 这一组是那一屏唯一的整页证据（此前本文件只有纯函数 + 源文本守卫）。
  group('阈值框的编辑分支（片14 换件后的页面级证据）', () {
    late BatteryService service;
    late MemoryRuleStore store;

    Map<String, dynamic> rule({
      String id = 'b1',
      String type = 'level_below',
      int value = 20,
      bool enabled = true,
      String title = '旧标题',
    }) => {
      'id': id,
      'type': type,
      'value': value,
      'enabled': enabled,
      'title': title,
      'content': '',
    };

    setUp(() async {
      await GetIt.instance.reset();
      // ⚠ 不 mock 就会出现 `BatteryService: 规则保存失败: MissingPluginException(getAll …)` ——
      //   第一版漏了这一行，「保存」那条靠服务里的兜底吞掉了异常才勉强绿，而「取消」那条
      //   直接挂在 10 分钟超时上（读数只认日志正文，不认"看起来对"）。
      SharedPreferences.setMockInitialValues({});
      store = MemoryRuleStore();
      service = BatteryService(store: store);
      GetIt.instance.registerSingleton<BatteryService>(service);
      stubNativeChannels();
      await service.restoreSettings(rules: [rule()]);
    });

    tearDown(() async {
      clearNativeChannelStubs();
      service.dispose();
      await GetIt.instance.reset();
    });

    Widget buildApp() =>
        const AppRoot(locale: Locale('zh'), dark: false, home: BatteryPage());

    Future<void> openEdit(WidgetTester tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      // ⚠ 按**标题**点那一行（列表显示标题；标题为空才回落成类型名 —— 与设备状态页同一条坑）
      await tester.tap(find.text('旧标题'));
      await tester.pumpAndSettle();
      expect(
        find.byType(CupertinoAlertDialog),
        findsOneWidget,
        reason: '点规则行没打开编辑框 ⇒ 入口那一下就断了',
      );
      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason: 'Material 那一件还在 ⇒ 外壳没真的换掉（片14 的判据在这里被复现一次）',
      );
    }

    testWidgets('改完按「保存」⇒ 同 id 那一条被替换，不是多出一条', (tester) async {
      await openEdit(tester);

      await tester.enterText(
        find.descendant(
          of: find.byType(CupertinoAlertDialog),
          matching: find.byType(TextField),
        ),
        '改过的标题',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(CupertinoAlertDialog),
          matching: find.text('保存'),
        ),
      );
      await tester.pumpAndSettle();

      expect(service.rules, hasLength(1), reason: '编辑不是新增：编辑后规则数不该变');
      expect(service.rules.single['title'], '改过的标题');
      expect(
        service.rules.single['id'],
        'b1',
        reason: '换标题不该把 id 也换了 ⇒ 后面编辑开关都指不到',
      );
    });

    testWidgets('按「取消」⇒ 服务里那一条一个字都没变', (tester) async {
      await openEdit(tester);

      await tester.enterText(
        find.descendant(
          of: find.byType(CupertinoAlertDialog),
          matching: find.byType(TextField),
        ),
        '不该被写进去',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(CupertinoAlertDialog),
          matching: find.text('取消'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoAlertDialog), findsNothing);
      expect(service.rules.single['title'], '旧标题', reason: '取消那条路也把值写进去了');
    });
  });
}
