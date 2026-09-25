import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/widgets/card_action_sheet.dart';
import 'package:notice_transmit/pages/temperature_page.dart';
import 'package:notice_transmit/services/temperature_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// T16：温度规则页「保存后不刷新 / 开关点完弹回」。
///
/// 根因不是漏 `setState`：本页是 `_pushPage` 推进去的路由，父页 `setState` 重建不到它；
/// 而它过去只读构造时传进来的 `List` 快照，`TemperatureService` 的每个写操作又是
/// `_rules = [..._rules, rule]` **整体换新** —— 快照与被换掉的列表就此分家，
/// 界面上永远停在进页那一刻的内容。回调里的 `setState(() {})` 刷的是父页，等于没刷。
///
/// 现在页面订阅服务。因此这些用例的共同判据是：
/// **只改服务、不重新 pumpWidget（不重建父树），界面必须自己跟上。**
/// 一旦有人把订阅改回"传快照"，这四条会立刻全红。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TemperatureService service;

  Widget buildApp() {
    return const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale('zh'),
      home: TemperaturePage(),
    );
  }

  Map<String, dynamic> rule({String id = 'r1', bool enabled = true}) => {
    'id': id,
    'type': 'battery_temp_above',
    'value': 45,
    'enabled': enabled,
    'title': '电池过热',
    'content': '',
  };

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({});
    // 服务每次写都会 invokeMethod('setTemperatureRules')。**在 testWidgets 里不给通道
    // 装 mock handler，这个 await 就永远不返回**（实测：四条用例全部 did not complete；
    // 同一个调用放在普通 test() 里则会立刻 MissingPluginException 返回）。
    // 与 app_channel_settings_page_test 同一做法：先把通道接住。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.fnthink.notice/notification'),
          (call) async => null,
        );
    service = TemperatureService();
    GetIt.instance.registerSingleton<TemperatureService>(service);
    await service.loadSettings();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.fnthink.notice/notification'),
          null,
        );
    await GetIt.instance.reset();
  });

  testWidgets('服务侧新增规则 → 界面立刻出现（不重建父树）', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    expect(find.textContaining('暂无温度规则'), findsOneWidget);

    await service.addRule(rule());
    await tester.pumpAndSettle();

    expect(find.text('电池过热'), findsOneWidget);
    expect(find.textContaining('暂无温度规则'), findsNothing);
  });

  testWidgets('弹窗保存一条规则 → 列表出现该条（用户看到的"保存不刷新"）', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '添加'));
    await tester.pumpAndSettle();

    expect(find.byType(ListTile), findsOneWidget);
    expect(service.rules, hasLength(1), reason: '服务侧确实写了，问题只可能出在刷新链路');
  });

  testWidgets('点规则开关 → 开关停在新位置（此前"点完弹回"）', (tester) async {
    await service.restoreSettings(rules: [rule(enabled: false)]);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    final sw = find.byType(CupertinoSwitch);
    expect(tester.widget<CupertinoSwitch>(sw).value, isFalse);

    await tester.tap(sw);
    await tester.pumpAndSettle();

    expect(
      tester.widget<CupertinoSwitch>(sw).value,
      isTrue,
      reason: '开关回弹 = 界面读的还是进页那一刻的旧列表',
    );
    expect(service.rules.single['enabled'], isTrue);
  });

  testWidgets('删除规则 → 条目消失；备份恢复同理（两条都是换新列表的操作）', (tester) async {
    await service.restoreSettings(
      rules: [
        rule(),
        rule(id: 'r2'),
      ],
    );
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNWidgets(2));

    await service.deleteRule('r1');
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsOneWidget);

    await service.restoreSettings(rules: [rule(id: 'r9')]);
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsOneWidget);
    expect(service.rules.single['id'], 'r9');
  });

  // T05：规则卡的滑出动作（删除/暂停）原本要先横向拖一下才看得见，
  // 长按菜单把同一批动作 + 修改/复制收进一个不需要发现的入口。
  testWidgets('长按规则行 ⇒ 修改/复制/暂停/删除；复制换新 id', (tester) async {
    await service.addRule(rule());
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.longPress(find.text('电池过热'));
    await tester.pumpAndSettle();
    Finder inSheet(String label) => find.descendant(
      of: find.byType(CardActionSheet),
      matching: find.text(label),
    );
    expect(inSheet('编辑'), findsOneWidget);
    expect(inSheet('复制'), findsOneWidget);
    expect(inSheet('停用'), findsOneWidget, reason: '规则当前是启用态 ⇒ 给"停用"');
    expect(inSheet('删除'), findsOneWidget);

    await tester.tap(inSheet('复制'));
    await tester.pumpAndSettle();

    final rules = service.rules;
    expect(rules, hasLength(2));
    expect(
      rules.map((r) => r['id']).toSet(),
      hasLength(2),
      reason: 'updateRule/deleteRule 都按 id 找，两条同 id 会一次改中两条',
    );
    expect(rules[1]['value'], rules[0]['value'], reason: '复制要带走阈值，否则用户得再拖一次滑块');
  });
}
