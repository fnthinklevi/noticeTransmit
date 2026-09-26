import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/widgets/card_action_sheet.dart';
import 'package:notice_transmit/pages/temperature_page.dart';
import 'package:notice_transmit/services/engine_rule_codec.dart';
import 'package:notice_transmit/services/temperature_service.dart';

import '../support/engine_rule_store_fake.dart';
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
  late MemoryRuleStore store;

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
    // 服务每次写都会落库 + 刷镜像 + invokeMethod('refreshEngineRules')。**在 testWidgets
    // 里不给通道装 mock handler，那个 await 就永远不返回**（实测：四条用例全部 did not
    // complete；同一个调用放在普通 test() 里则会立刻 MissingPluginException 返回）。
    // 存储注伪：T20 起规则落 engine_rules 表，真库要走 sqflite ffi，页测试不该依赖它。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.fnthink.notice/notification'),
          (call) async => null,
        );
    store = MemoryRuleStore();
    service = TemperatureService(store: store);
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

  // T06：这一族以前"点一下就没了"，而且滑出与长按两条路都没有确认。
  testWidgets('长按删除先弹确认；取消不留痕，确认才真删', (tester) async {
    await service.addRule(rule());
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    Finder inSheet(String label) => find.descendant(
      of: find.byType(CardActionSheet),
      matching: find.text(label),
    );
    await tester.longPress(find.text('电池过热'));
    await tester.pumpAndSettle();
    await tester.tap(inSheet('删除'));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(TextButton, '删除'),
      findsWidgets,
      reason: '菜单里点删除就直接删 ⇒ 确认被绕开',
    );
    await tester.tap(find.widgetWithText(TextButton, '取消').last);
    await tester.pumpAndSettle();
    expect(service.rules, hasLength(1), reason: '取消不许改数据');

    await tester.longPress(find.text('电池过热'));
    await tester.pumpAndSettle();
    await tester.tap(inSheet('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '删除').last);
    await tester.pumpAndSettle();
    expect(service.rules, isEmpty, reason: '确认之后必须真的删掉（并落盘）');
    expect(
      store.rows[EngineRuleCodec.familyTemperature],
      isEmpty,
      reason: '内存空了而存储还有行 = 重启后规则复活',
    );
  });

  testWidgets('换一个服务实例重读（= 重启进程）：规则原样回来', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await service.addRule(rule());
    await tester.pumpAndSettle();

    final reopened = TemperatureService(store: store);
    await reopened.loadSettings();
    expect(reopened.rules.map((r) => r['id']).toList(), [
      'r1',
    ], reason: '写操作只改内存列表的话，这条必红');
  });

  group('T25：温度试跑入口', () {
    const channel = MethodChannel('com.fnthink.notice/notification');

    /// 装一个只回这份载荷的通道桩（原生那侧的求值结果，这里不重跑判据）。
    Future<void> stubPreview(
      WidgetTester tester,
      Map<Object?, Object?>? payload,
    ) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'previewTemperatureRule') return payload;
            return null;
          });
    }

    testWidgets('命中：弹层给出原生渲染的标题，并列出三步走查', (tester) async {
      await stubPreview(tester, {
        'ok': true,
        'fired': true,
        'temps': {'battery_temp_above': 52.0},
        'steps': [
          {'phase': 'baseline', 'outcome': 'BASELINE'},
          {'phase': 'below', 'outcome': 'NOT_TRIGGERED'},
          {'phase': 'current', 'outcome': 'FIRE'},
        ],
        'ruleCount': 1,
        'ruleId': 'r1',
        'type': 'battery_temp_above',
        'threshold': 45,
        'temperatureC': 52.0,
        'title': '电池过热',
        'content': '电池温度 52.0℃',
      });
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.science_outlined));
      await tester.pumpAndSettle();

      expect(find.text('温度告警试跑'), findsOneWidget);
      // 标题/正文来自原生那条渲染抄本，Dart 不参与拼判据。
      expect(find.textContaining('会触发：电池过热'), findsOneWidget);
      expect(find.textContaining('首轮只记录基准，不触发'), findsOneWidget);
      expect(find.textContaining('52.0℃'), findsOneWidget);
    });

    testWidgets('读不到温区 ≠ 没到阈值：两种说法必须分开', (tester) async {
      await stubPreview(tester, {
        'ok': true,
        'fired': false,
        'temps': <String, double>{},
        'steps': [
          {'phase': 'current', 'outcome': 'NO_READING'},
        ],
        'ruleCount': 1,
        'silence': 'NO_READING',
      });
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.science_outlined));
      await tester.pumpAndSettle();

      expect(find.textContaining('该维度本机读不到'), findsOneWidget);
      expect(
        find.textContaining('未达到阈值'),
        findsNothing,
        reason: '把"读不到"说成"没到阈值"会把用户支使去调阈值，而问题在传感器',
      );
    });

    testWidgets('通道没通 = 没测成，不许显示成"不会触发"', (tester) async {
      await stubPreview(tester, null);
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.science_outlined));
      await tester.pumpAndSettle();

      expect(find.textContaining('试跑失败'), findsOneWidget);
      expect(find.textContaining('不会触发：'), findsNothing);
    });

    testWidgets('长按菜单里也有单条试跑', (tester) async {
      await service.addRule(rule());
      await stubPreview(tester, {
        'ok': true,
        'fired': false,
        'silence': 'NO_RULES',
      });
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.longPress(find.text('电池过热'));
      await tester.pumpAndSettle();
      expect(find.text('试一次'), findsOneWidget);
    });
  });
}
