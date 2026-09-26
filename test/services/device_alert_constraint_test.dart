import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/battery_service.dart';
import 'package:notice_transmit/services/platform_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/engine_rule_store_fake.dart';

/// T23：设备态告警约束开关的 Dart 侧。
///
/// 这一枚开关的**默认值就是它的语义**：开着会改变已有设备的告警行为（本来一定推的
/// 电量告警，可能被关键词黑名单拦掉），所以它必须默认关，而且"升级不许改用户设置"
/// 这条不变量在这里意味着 —— 老用户升上来之后仍然看不到任何行为变化。
///
/// 通道复用 `setBatterySetting`（通用布尔写 + 顺带让服务重载），不新增方法：
/// 约束判定只有原生 `FilterEngine` 那一个点，这里递过去的只是一个布尔。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppChannels.notification, (call) async {
          calls.add(call);
          return true;
        });
  });

  BatteryService service() => BatteryService(store: MemoryRuleStore());

  test('默认关：新设备 loadSettings 之后不得是开着的', () async {
    final s = service();
    await s.loadSettings();
    expect(
      s.deviceAlertsRespectConstraints,
      isFalse,
      reason: '默认开 = 升级改了用户行为（本来必推的告警可能被拦）',
    );
  });

  test('已存的 true 要读得回来（开关重启后不许自己翻回去）', () async {
    SharedPreferences.setMockInitialValues({
      'device_alert_constraint_enabled': true,
    });
    final s = service();
    await s.loadSettings();
    expect(s.deviceAlertsRespectConstraints, isTrue);
  });

  test('保存：prefs、通道、监听者三处都到位', () async {
    final s = service();
    await s.loadSettings();
    var notified = 0;
    s.addListener(() => notified++);

    await s.saveDeviceAlertsRespectConstraints(true);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('device_alert_constraint_enabled'), isTrue);
    expect(s.deviceAlertsRespectConstraints, isTrue);
    expect(notified, greaterThan(0), reason: '点完不动 = 用户以为没生效又点一次');

    final call = calls.firstWhere((c) => c.method == 'setBatterySetting');
    expect(call.arguments['key'], 'device_alert_constraint_enabled');
    expect(call.arguments['value'], isTrue);
  });

  test('通道调用失败也不回滚内存与 prefs（点下去就是点下去了）', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppChannels.notification, (call) async {
          if (call.method == 'setBatterySetting') {
            throw PlatformException(code: 'boom');
          }
          return true;
        });
    final s = service();
    await s.loadSettings();
    await s.saveDeviceAlertsRespectConstraints(true); // 不许抛

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('device_alert_constraint_enabled'), isTrue);
    expect(s.deviceAlertsRespectConstraints, isTrue);
  });

  test('两族开关互不串键：动约束开关不翻电量/温度的推送总开关', () async {
    final s = service();
    await s.loadSettings();
    final prefs = await SharedPreferences.getInstance();
    // ⚠ 比对"键原来的值"而不是"服务里的值"：总开关从没写过时 prefs 里是 null，
    //   而服务默认 true —— 拿默认值去要求键必须存在，测的就不是串键了。
    final notifyBefore = prefs.getBool('battery_notify_enabled');

    await s.saveDeviceAlertsRespectConstraints(
      !s.deviceAlertsRespectConstraints,
    );

    expect(s.notifyEnabled, isTrue);
    expect(
      prefs.getBool('battery_notify_enabled'),
      notifyBefore,
      reason: '一把新键写进了别人的键 = 操作改了用户设置',
    );
    expect(prefs.getBool('device_alert_constraint_enabled'), isTrue);
  });
}
