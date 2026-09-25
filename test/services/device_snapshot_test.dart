import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/models/device_snapshot.dart';
import 'package:notice_transmit/services/device_info_service.dart';

import '../support/source_guards.dart';
import '../test_setup.dart';

/// T17：设备快照（原生一次读全 → Dart 侧解析）的契约。
///
/// 锁三件事：
/// 1. 解析层**不把"读不到"变成 0**（跨端表达方式是"缺字段 + unavailable 记账"）；
/// 2. `num → int/double` 的宽容转换（MethodChannel 不保证原生给的 30 到了 Dart 还是
///    int、1.0 还是 double，写死 `as double` 会在真机上炸）；
/// 3. **跨端字段名单**：Dart 读的每个键都必须存在于原生 `DeviceSnapshot` 的常量里。
///    方法名/字段名是字符串契约，改一端不会有任何编译期报错（本仓库已有同族守卫）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabase();

  /// 原生 `normalize()` 完整输出的一份样本（单位已经换算过：MB 是 double、温度是℃）
  Map<String, Object?> fullMap() => {
    'model': 'MEIZU 21',
    'brand': 'MEIZU',
    'manufacturer': 'Meizu',
    'osVersion': '14',
    'sdkInt': 34,
    'network': 'wifi',
    'batteryLevel': 82,
    'batteryCharging': false,
    'batteryTemperatureC': 31.5,
    'storageTotalMb': 122070.3,
    'storageFreeMb': 28610.2,
    'memoryTotalMb': 11444.1,
    'memoryAvailableMb': 4291.5,
    'brightnessPercent': 50,
    'brightnessMode': 'manual',
    'uptimeSeconds': 7200,
    'capturedAtMs': 1770000000000,
    'unavailable': <String>[],
  };

  group('DeviceSnapshot.fromMap', () {
    test('完整快照逐字段解析', () {
      final s = DeviceSnapshot.fromMap(fullMap());
      expect(s.model, 'MEIZU 21');
      expect(s.osVersion, '14');
      expect(s.sdkInt, 34);
      expect(s.network, 'wifi');
      expect(s.batteryLevel, 82);
      expect(s.batteryCharging, isFalse);
      expect(s.batteryTemperatureC, 31.5);
      expect(s.memoryAvailableMb, 4291.5);
      expect(s.brightnessPercent, 50);
      expect(s.brightnessMode, 'manual');
      expect(s.uptimeSeconds, 7200);
      expect(s.capturedAtMs, 1770000000000);
      expect(s.unavailable, isEmpty);
      expect(s.storageUsedMb, closeTo(93460.1, 0.1));
    });

    test('整数写成的 MB（122070 而不是 122070.3）也能解析', () {
      // 平台通道把 1.0 传成 int 是真实会发生的（Kotlin 侧 Long/Int 字段混在同一个 map 里）
      final m = fullMap()
        ..['storageTotalMb'] = 122070
        ..['batteryTemperatureC'] = 31;
      final s = DeviceSnapshot.fromMap(m);
      expect(s.storageTotalMb, 122070.0);
      expect(s.batteryTemperatureC, 31.0);
    });

    test('缺字段一律 null，不兜成 0', () {
      final s = DeviceSnapshot.fromMap({
        'unavailable': ['model', 'batteryLevel', 'storageFreeMb'],
      });
      expect(s.model, isNull);
      expect(s.batteryLevel, isNull, reason: '0% 是合法读数，兜 0 等于伪造');
      expect(s.storageFreeMb, isNull);
      expect(s.isMissing('batteryLevel'), isTrue);
      // 缺一侧就不算"已用"：否则"可用读不到"会显示成"几乎用满"
      expect(s.storageUsedMb, isNull);
    });

    test('空白字符串按未读到处理（原生同样处理，两端必须同口径）', () {
      final s = DeviceSnapshot.fromMap({...fullMap(), 'model': '   '});
      expect(s.model, isNull);
    });
  });

  group('DeviceInfoService.getDeviceSnapshot', () {
    tearDown(clearNativeChannelStubs);

    test('通道返回 map → 解析成对象', () async {
      stubNativeChannels(
        onCall: (call) async =>
            call.method == 'getDeviceSnapshot' ? fullMap() : null,
      );
      final s = await DeviceInfoService().getDeviceSnapshot();
      expect(s, isNotNull);
      expect(s!.batteryLevel, 82);
      expect(s.storageUsedMb, isNotNull);
    });

    test('通道抛异常 → null（读不到要能被看出是读不到）', () async {
      stubNativeChannels(
        onCall: (call) async {
          if (call.method == 'getDeviceSnapshot') {
            throw PlatformException(code: 'boom');
          }
          return null;
        },
      );
      expect(await DeviceInfoService().getDeviceSnapshot(), isNull);
    });
  });

  group('跨端字段名单', () {
    final root = projectRoot();
    final kotlinSrc = stripComments(
      File(
        '$root/android/app/src/main/kotlin/com/fnthink/notice/DeviceSnapshot.kt',
      ).readAsStringSync(),
    );
    final dartSrc = stripComments(
      File('$root/lib/models/device_snapshot.dart').readAsStringSync(),
    );

    final kotlinKeys = RegExp(
      r'KEY_[A-Z_]+ = "([A-Za-z]+)"',
    ).allMatches(kotlinSrc).map((m) => m.group(1)!).toSet();

    /// Dart 从快照里读的键：helper 形式（`str('x')`）与直接下标（`map['x']`）两种都要收
    final dartKeys = <String>{
      ...RegExp(
        r"\b(?:str|intOf|doubleOf)\('([A-Za-z]+)'\)",
      ).allMatches(dartSrc).map((m) => m.group(1)!),
      ...RegExp(
        r"\bmap\['([A-Za-z]+)'\]",
      ).allMatches(dartSrc).map((m) => m.group(1)!),
    };

    test('两侧都解析到了键名（否则下面两条形同虚设）', () {
      expect(kotlinKeys, hasLength(greaterThanOrEqualTo(10)));
      expect(dartKeys, isNotEmpty);
    });

    test('Dart 读的每个键都在原生常量表里', () {
      // 注释必须剥掉：文档里写的示例键名会伪装成真实读取点
      final unknown = dartKeys.difference(kotlinKeys).toList()..sort();
      expect(
        unknown,
        isEmpty,
        reason: 'Dart 读了原生从不输出的键（改名一端不会报错，只会永远显示"读不到"）：$unknown',
      );
    });

    test('原生输出的每个键 Dart 都认得（不认得就是快照里躺着没人读的数据）', () {
      final unread = kotlinKeys.difference(dartKeys).toList()..sort();
      expect(
        unread,
        isEmpty,
        reason: '原生输出但 Dart 不读：$unread（要么接上，要么删掉，别留第二份真相）',
      );
    });
  });
}
