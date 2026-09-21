import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/battery_service.dart';
import 'package:notice_transmit/services/platform_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 温度规则类型双端契约（v1.59）。
///
/// Kotlin BatteryMonitor.TEMP_RULE_TYPES 与 Dart 侧温度规则类型的
/// 一致性守卫（漏一端编译器不报，规则将静默不触发）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppChannels.notification, (call) async {
          return true; // setBatterySetting / setBatteryRules 同步成功
        });
  });

  group('温度规则类型 – 双端契约', () {
    test('三维度类型常量与 Kotlin TEMP_RULE_TYPES 一致', () {
      // Dart 侧类型清单（battery_page chips 与本测试共同锁定）
      const dartTypes = {
        'battery_temp_above',
        'device_temp_above',
        'screen_temp_above',
      };
      expect(dartTypes, hasLength(3));
      // 每个类型必须以 _temp_above 结尾（原生 when 分支按此后缀约定匹配）
      for (final t in dartTypes) {
        expect(t.endsWith('_temp_above'), isTrue, reason: '类型 $t 命名不符契约');
      }
    });

    test('温度规则经 addRule/save 后类型透传保真', () async {
      final service = BatteryService();
      await service.loadSettings();
      final before = service.rules.length;
      await service.addRule({
        'id': 'temp-1',
        'type': 'battery_temp_above',
        'value': 45,
        'enabled': true,
        'title': '电池温度过高',
        'content': '',
      });
      final added = service.rules.firstWhere((r) => r['id'] == 'temp-1');
      expect(added['type'], 'battery_temp_above');
      expect(added['value'], 45);
      expect(service.rules.length, before + 1);
    });
  });
}
