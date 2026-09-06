import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/sms_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SmsService 配置存取单测：Dart prefs 持久化 + setSmsSetting 原生同步 payload 契约
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.fnthink.notice/notification');
  final List<Map<String, dynamic>> synced = [];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    synced.clear();
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'setSmsSetting') {
            final args = call.arguments as Map;
            synced.add({'key': args['key'], 'value': args['value']});
          }
          return true;
        });
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('SmsService – 默认值与存取', () {
    test('空配置时 loadSettings 读取默认值：监听开 / 全部卡 / 验证码开', () async {
      final service = SmsService();
      await service.loadSettings();

      expect(service.smsMonitorEnabled, isTrue);
      expect(service.simFilter, 'all');
      expect(service.codeMonitorEnabled, isTrue);
    });

    test('saveSmsMonitorEnabled(false)：内存生效 + prefs 持久化 + 原生同步', () async {
      final service = SmsService();
      await service.saveSmsMonitorEnabled(false);

      expect(service.smsMonitorEnabled, isFalse);
      expect(synced, [
        {'key': 'sms_monitor_enabled', 'value': false},
      ]);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('sms_monitor_enabled'), isFalse);
    });

    test('saveSimFilter("1")：仅卡1 持久化并同步', () async {
      final service = SmsService();
      await service.saveSimFilter('1');

      expect(service.simFilter, '1');
      expect(synced, [
        {'key': 'sms_sim_filter', 'value': '1'},
      ]);
    });

    test('saveCodeMonitorEnabled(false)：验证码开关持久化并同步', () async {
      final service = SmsService();
      await service.saveCodeMonitorEnabled(false);

      expect(service.codeMonitorEnabled, isFalse);
      expect(synced, [
        {'key': 'sms_code_monitor_enabled', 'value': false},
      ]);
    });

    test('重新实例化后 loadSettings 读回持久化配置', () async {
      final service = SmsService();
      await service.saveSmsMonitorEnabled(false);
      await service.saveSimFilter('2');
      await service.saveCodeMonitorEnabled(false);

      final reloaded = SmsService();
      await reloaded.loadSettings();

      expect(reloaded.smsMonitorEnabled, isFalse);
      expect(reloaded.simFilter, '2');
      expect(reloaded.codeMonitorEnabled, isFalse);
    });
  });
}
