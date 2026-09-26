import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/pages/device_state_page.dart';
import 'package:notice_transmit/services/device_state_service.dart';
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

  Widget buildApp() => const MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: Locale('zh'),
    home: DeviceStatePage(),
  );

  Map<String, dynamic> rule({
    String id = 'd1',
    String type = 'brightness_below',
    int value = 15,
    bool enabled = true,
  }) => {
    'id': id,
    'type': type,
    'value': value,
    'enabled': enabled,
    'title': '',
    'content': '',
  };

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({});
    stubNativeChannels();
    store = MemoryRuleStore();
    service = DeviceStateService(store: store);
    GetIt.instance.registerSingleton<DeviceStateService>(service);
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
}
