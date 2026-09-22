import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/installed_apps_service.dart';
import 'package:notice_transmit/services/platform_channel.dart';

/// InstalledAppsService 契约测试（mock 通道，不出网、不起原生）。
///
/// 锁三件事：
/// 1. **原生方法名与参数形状**（`getInstalledApps` / `getCachedInstalledApps` /
///    `{'force': true}`）——方法名是字符串契约，改错一端只有运行时才会炸；
/// 2. **返回类型归一化**：通道解码后是 `List<dynamic>`，直接当
///    `List<Map<String, dynamic>>` 用会隐式 downcast 抛异常（表现为列表恒为空）；
/// 3. **错误语义分工**：读缓存失败必须吞掉（首帧不该报错），
///    `load` 失败必须上抛（调用方要弹「刷新失败」）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InstalledAppsService service;
  late List<MethodCall> calls;
  late Object? Function(MethodCall call) respond;

  final rows = [
    {'appName': '微信', 'packageName': 'com.tencent.mm', 'isSystemApp': false},
    {'appName': '系统桌面', 'packageName': 'and', 'isSystemApp': true},
  ];

  setUp(() {
    service = InstalledAppsService();
    calls = [];
    respond = (_) => rows;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppChannels.notification, (call) async {
          calls.add(call);
          return respond(call);
        });
  });

  group('方法名与参数契约', () {
    test('loadCached 调 getCachedInstalledApps 且不带参数', () async {
      await service.loadCached();
      expect(calls.single.method, 'getCachedInstalledApps');
      expect(calls.single.arguments, isNull);
    });

    test('load 调 getInstalledApps；force 才带 {"force": true}', () async {
      await service.load();
      expect(calls.single.method, 'getInstalledApps');
      expect(calls.single.arguments, isNull);

      calls.clear();
      await service.load(force: true);
      expect(calls.single.method, 'getInstalledApps');
      expect(calls.single.arguments, {'force': true});
    });
  });

  group('返回类型归一化', () {
    test('解码得到的 List<dynamic> 必须归一化为强类型列表', () async {
      final List<Map<String, dynamic>> apps = await service.load();
      expect(apps, hasLength(2));
      expect(apps.first['appName'], '微信');
      expect(apps.last['isSystemApp'], isTrue);
    });
  });

  group('错误语义分工', () {
    test('读缓存失败被吞掉并返回空列表（页面据此再走全量）', () async {
      respond = (_) => throw PlatformException(code: 'unavailable');
      expect(await service.loadCached(), isEmpty);
    });

    test('全量读取失败向上抛出（调用方需要它弹「刷新失败」）', () async {
      respond = (_) => throw PlatformException(code: 'unavailable');
      expect(service.load(), throwsA(isA<PlatformException>()));
    });
  });
}
