import 'package:notice_transmit/services/device_info_service.dart';
import 'package:flutter/cupertino.dart';
// 阈值框的**字段**仍是 Material 的（Slider / TextField），弹层外壳是 Cupertino 的（T90 片14）
// ⇒ 两边各引一处，用 show 限定避免同名件冲突。
import 'package:flutter/material.dart' show AlertDialog, Slider, TextField;
import 'package:flutter/services.dart';
import 'package:notice_transmit/widgets/engine_page_sections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/pages/device_state_page.dart';
import 'package:notice_transmit/services/device_state_service.dart';
import 'package:notice_transmit/widgets/app_root.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/engine_rule_store_fake.dart';
import '../test_setup.dart';

/// T24：设备状态告警页与服务。
///
/// 判据不在这里（引擎那一份），所以本文件只钉三件这层才会坏的事：
/// ① 规则真的落到 `engine_rules` 的 `device_state` 族；② 网络型不显示阈值（显示了就是
/// 在骗用户"断网也有一个数值可调"）；③ 删除走确认（T06）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DeviceStateService service;
  late MemoryRuleStore store;

  Widget buildApp() =>
      const AppRoot(locale: Locale('zh'), dark: false, home: DeviceStatePage());

  Map<String, dynamic> rule({
    String id = 'd1',
    String type = 'brightness_below',
    int value = 15,
    bool enabled = true,
    String title = '',
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
    SharedPreferences.setMockInitialValues({});
    stubNativeChannels();
    store = MemoryRuleStore();
    service = DeviceStateService(store: store);
    GetIt.instance.registerSingleton<DeviceStateService>(service);
    // 顶部实时读数要读 T17 的快照：注册真的 DeviceInfoService 就够 —— 通道 mock 回 null，
    // 页面必须显示「这台设备读不到」，而不是 0℃ / 0%（那一格本来就有的判据）。
    GetIt.instance.registerSingleton<DeviceInfoService>(DeviceInfoService());
    await service.loadSettings();
  });

  tearDown(() async {
    service.dispose();
    await GetIt.instance.reset();
    clearNativeChannelStubs();
  });

  test('默认关总开关之外一切照旧：新设备这族是空的', () async {
    expect(service.notifyEnabled, isTrue);
    expect(service.rules, isEmpty);
  });

  test('写一条规则：落到 device_state 族，且不动电量/温度两族', () async {
    await service.addRule(rule());
    expect(store.saveLog, isNotEmpty, reason: '没走仓储就是只改了内存（重启即丢）');
    final saved = store.rows['device_state']!;
    expect(saved, hasLength(1));
    expect(saved.single['type'], 'brightness_below');
    // 两族各从 0 编号：把设备态写进电量族 = 电量页凭空多一条
    expect(store.rows['battery'] ?? const [], isEmpty);
    expect(store.rows['temperature'] ?? const [], isEmpty);
  });

  test('总开关写 prefs 并下发原生；关掉不删规则', () async {
    await service.addRule(rule());
    await service.saveNotifyEnabled(false);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('device_state_notify_enabled'), isFalse);
    expect(service.rules, hasLength(1), reason: '关总开关不是清空规则');
    expect(
      service.notifyEnabled,
      isFalse,
      reason: '服务内存态没跟上 = 页面开关会弹回（T16 的病灶）',
    );
  });

  group('页面', () {
    testWidgets('亮度规则显示阈值，网络规则不显示阈值', (tester) async {
      await service.restoreSettings(
        rules: [
          rule(id: 'b1', type: 'brightness_above', value: 90),
          rule(id: 'n1', type: 'network_disconnected', value: 0),
        ],
      );
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('亮度高于'), findsOneWidget);
      expect(find.text('阈值 90%'), findsOneWidget);
      expect(find.text('断网时'), findsOneWidget);
      // 网络型没有第二个数字可写：跟着显示阈值就是凭空的读数（「断网时 · 0%」）
      expect(find.textContaining('断网时 '), findsNothing);
      expect(find.text('阈值 0%'), findsNothing);
    });

    testWidgets('删除必须过确认；取消不删', (tester) async {
      await service.restoreSettings(rules: [rule(id: 'b1')]);
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.longPress(find.text('亮度低于'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(
        find.text('确认删除'),
        findsOneWidget,
        reason: 'T06：删除不许点一下就没了（阈值是拖滑块调出来的）',
      );

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(service.rules, hasLength(1));
    });

    testWidgets('服务里加了规则，页面不重建也要出现（订阅而非快照）', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      expect(find.text('暂无设备状态规则，点右上角 + 添加'), findsOneWidget);

      await service.addRule(rule(id: 'b2', type: 'network_connected'));
      await tester.pumpAndSettle();
      expect(find.text('恢复联网时'), findsOneWidget);
    });
  });

  // 版式对齐电量页之后新增：顶部读数（亮度 + 网络）与总开关行。
  // T90 片14 把这枚阈值框换成了共享外壳 `IosFormDialog`，而**编辑分支**（isEdit → updateRule）
  // 此前没有任何页面级用例：温度页有一条「弹窗保存一条规则」看着新增分支，这两页只看着列表显示。
  // 这一组补的正是「改完了真的替换那一条 / 取消真的没动 / 网络型在编辑框里也没有滑杆」。
  group('阈值框的编辑分支（片14 换件后的页面级证据）', () {
    // ⚠ 按**标题**找那一行，不是按类型名：规则有标题时列表显示标题，只有标题为空才回落成
    //   类型名。第一版我按「亮度低于」找，两条带标题的用例当场红（`Found 0 widgets with text`）。
    Future<void> openEdit(
      WidgetTester tester, {
      required String rowLabel,
    }) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text(rowLabel));
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

    testWidgets('改完按「确定」⇒ 同 id 那一条被替换，不是多出一条', (tester) async {
      await service.restoreSettings(
        rules: [rule(id: 'b1', title: '旧标题')],
      );
      await openEdit(tester, rowLabel: '旧标题');

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
          matching: find.text('确定'),
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
      await service.restoreSettings(
        rules: [rule(id: 'b1', title: '旧标题')],
      );
      await openEdit(tester, rowLabel: '旧标题');

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

    testWidgets('编辑时切到网络型 ⇒ 没有滑杆，且那句「网络触发不需要阈值」在', (tester) async {
      await service.restoreSettings(
        rules: [rule(id: 'b1', type: 'brightness_below')],
      );
      // 无标题 ⇒ 那一行显示类型名（回落规则见 openEdit 注释）
      await openEdit(tester, rowLabel: '亮度低于');

      // 亮度型开着滑杆；切到网络型那一格之后它必须消失（凭空的数值会骗用户"断网也有阈值可调"）
      expect(find.byType(Slider), findsOneWidget);
      await tester.tap(find.text('断网时'));
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsNothing);
      expect(find.text('网络触发不需要阈值'), findsOneWidget);
    });
  });

  group('顶部读数与总开关（与电量页同构）', () {
    void stubSnapshot(Map<String, Object?>? snap) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.fnthink.notice/notification'),
            (call) async => call.method == 'getDeviceSnapshot' ? snap : null,
          );
    }

    testWidgets('读不到 ⇒ 明写读不到，不画 0%', (tester) async {
      stubSnapshot(null);
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('这台设备读不到'), findsOneWidget);
      expect(find.text('屏幕亮度'), findsOneWidget);
      expect(find.text('0%'), findsNothing, reason: '0% 会被读成"屏幕真的全黑"');
    });

    testWidgets('亮度和网络都显示出来（本页两类触发各有各的读数）', (tester) async {
      stubSnapshot({'brightnessPercent': 62, 'network': 'wifi'});
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('62%'), findsOneWidget);
      expect(find.text('网络：Wi-Fi'), findsOneWidget);
    });

    testWidgets('总开关那一行真的落到服务', (tester) async {
      stubSnapshot({'brightnessPercent': 10, 'network': 'none'});
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      expect(service.notifyEnabled, isTrue);

      await tester.tap(
        find.descendant(
          of: find.byType(EngineSwitchRow),
          matching: find.byType(CupertinoSwitch),
        ),
      );
      await tester.pumpAndSettle();

      expect(service.notifyEnabled, isFalse);
      expect(
        find.text('网络：未联网'),
        findsOneWidget,
        reason: 'none 那一档要说"未联网"，不是空着',
      );
    });
  });

  // 同上：设备状态页顶部是**两个**读数（亮度 + 网络），最容易被挤，锁竖屏 360 宽。
  group('手机竖屏（360×780 逻辑像素）', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.fnthink.notice/notification'),
            (call) async => call.method == 'getDeviceSnapshot'
                ? {'brightnessPercent': 62, 'network': 'wifi'}
                : null,
          );
    });

    testWidgets('亮度与网络两行都显示，且没有溢出', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('62%'), findsOneWidget);
      expect(
        find.text('网络：Wi-Fi'),
        findsOneWidget,
        reason: 'detail 那行被挤掉就等于本页只剩一半读数',
      );
      final row = tester.getRect(find.text('网络：Wi-Fi'));
      expect(row.right, lessThanOrEqualTo(360));
    });
  });
}
