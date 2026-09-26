import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/pages/device_snapshot_page.dart';
import 'package:notice_transmit/services/app_channel_service.dart';
import 'package:notice_transmit/services/battery_service.dart';
import 'package:notice_transmit/services/channel_health_store.dart';
import 'package:notice_transmit/services/device_info_service.dart';
import 'package:notice_transmit/services/email_service.dart';
import 'package:notice_transmit/services/notification_service.dart';
import 'package:notice_transmit/services/webhook_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_setup.dart';

/// T18：设备状态页（T17 那份 `getDeviceSnapshot` 的第一个消费方）。
///
/// 锁四件事：
/// 1. **读不到 ≠ 0** —— 原生把未知表达成"缺字段 + `unavailable` 名单"，界面必须照着
///    显示「这台设备读不到」；兜成 0 会把"存储读不到"画成"已用满"；
/// 2. 通道整次没回话（返回 null）要单独说清楚，且这时**不给**推送按钮 —— 没有快照就
///    推一条空正文是凭空发通知；
/// 3. 「推送设备信息」= 先落一条历史记录、再交给原生补推，顺序反了送达结果就没有落点；
/// 4. 重复点不并发出两条。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];

  Map<String, Object?>? Function() snapshotProvider = () => _fullSnapshot;

  Future<Object?> onChannelCall(MethodCall call) async {
    calls.add(call);
    switch (call.method) {
      case 'getDeviceSnapshot':
        return snapshotProvider();
      default:
        return null;
    }
  }

  setUp(() async {
    calls.clear();
    snapshotProvider = () => _fullSnapshot;
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({});
    stubNativeChannels(onCall: onChannelCall);
    GetIt.instance
      ..registerSingleton<DeviceInfoService>(DeviceInfoService())
      ..registerSingleton<BatteryService>(BatteryService())
      ..registerSingleton<NotificationService>(NotificationService())
      ..registerSingleton<WebhookService>(WebhookService())
      ..registerSingleton<AppChannelService>(AppChannelService())
      ..registerSingleton<EmailService>(EmailService())
      ..registerSingleton<ChannelHealthStore>(ChannelHealthStore());
  });

  tearDown(() async {
    clearNativeChannelStubs();
    await GetIt.instance.reset();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    // ListView 懒建：默认 800x600 视口下「推送设备信息」那颗按钮根本还没被构建，
    // find.byKey 会得到 0 个（不是"找不到可点的"，是"不在树上"）。
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('zh'),
        home: DeviceSnapshotPage(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('快照逐项显示：型号 / 系统 / 网络 / 电量 / 温度 / 存储 / 亮度 / 运行时长', (tester) async {
    await pumpPage(tester);

    expect(find.text('MEIZU 21'), findsOneWidget);
    expect(find.text('Android 16（API 36）'), findsOneWidget);
    expect(find.text('Wi-Fi'), findsOneWidget);
    expect(find.text('76%（充电中）'), findsOneWidget);
    expect(find.text('33.7℃'), findsOneWidget);
    expect(find.textContaining('117.2 GB'), findsOneWidget);
    expect(find.textContaining('8.0 GB'), findsOneWidget);
    expect(find.text('45%（自动）'), findsOneWidget);
    expect(find.text('1 天 1 小时 0 分'), findsOneWidget);
  });

  testWidgets('原生报告读不到的项显示「这台设备读不到」，不兜成 0', (tester) async {
    snapshotProvider = () => _fullSnapshot.copyWith(
      unavailable: const ['batteryTemperatureC', 'memoryAvailableMb'],
      drop: const ['batteryTemperatureC', 'memoryAvailableMb'],
    );
    await pumpPage(tester);

    expect(find.text('这台设备读不到'), findsNWidgets(2));
    expect(find.text('0.0℃'), findsNothing, reason: '把未知画成 0.0℃ 就是编造读数');
    expect(find.textContaining('0.0 GB / 共'), findsNothing);
  });

  testWidgets('整次没读到：说清楚没测成，并且不给推送按钮', (tester) async {
    snapshotProvider = () => null;
    await pumpPage(tester);

    expect(find.text('没读到设备快照（原生通道没有回话）'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('device-status-push')),
      findsNothing,
      reason: '没有快照就推一条，推出去的是空正文 —— 那是凭空发通知',
    );
  });

  testWidgets('有快照时给出推送按钮，且文案说的是"结果见推送历史"', (tester) async {
    await pumpPage(tester);
    expect(find.byKey(const ValueKey('device-status-push')), findsOneWidget);
    expect(find.text('推送设备信息'), findsOneWidget);
    // 点下去的那条链（先落历史再补推、连点只推一条）在服务层用例里钉：
    // test/services/push_synthesized_record_test.dart
  });

  testWidgets('右上角重新读取会再问一次原生', (tester) async {
    await pumpPage(tester);
    final before = calls.where((c) => c.method == 'getDeviceSnapshot').length;
    await tester.tap(find.byKey(const ValueKey('device-status-refresh')));
    await tester.pumpAndSettle();

    expect(
      calls.where((c) => c.method == 'getDeviceSnapshot').length,
      greaterThan(before),
      reason: '快照是某一刻的读数，"重新读取"必须是真读一次，不是把旧值再画一遍',
    );
  });
}

/// 原生 `DeviceSnapshot.normalize()` 的输出形状（键名是跨语言契约）。
Map<String, Object?> get _fullSnapshot => {
  'model': 'MEIZU 21',
  'brand': 'MEIZU',
  'manufacturer': 'Meizu',
  'osVersion': '16',
  'sdkInt': 36,
  'network': 'wifi',
  'batteryLevel': 76,
  'batteryCharging': true,
  'batteryTemperatureC': 33.7,
  'storageTotalMb': 120000.0,
  'storageFreeMb': 40000.0,
  'memoryTotalMb': 8192.0,
  'memoryAvailableMb': 3072.0,
  'brightnessPercent': 45,
  'brightnessMode': 'auto',
  'uptimeSeconds': 90000,
  'capturedAtMs': 1700000000000,
  'unavailable': <String>[],
};

extension on Map<String, Object?> {
  /// 造"这一项原生没读到"的形状：**缺键 + 记进 unavailable**（原生就是这么表达的）。
  Map<String, Object?> copyWith({
    List<String> unavailable = const [],
    List<String> drop = const [],
  }) {
    final out = Map<String, Object?>.of(this);
    for (final key in drop) {
      out.remove(key);
    }
    out['unavailable'] = <String>[
      ...(out['unavailable'] as List? ?? const []).cast<String>(),
      ...unavailable,
    ];
    return out;
  }
}
