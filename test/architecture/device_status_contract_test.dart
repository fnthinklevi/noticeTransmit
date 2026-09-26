import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T18 的跨端与分层契约（静态源码守卫，注释已剥离）。
///
/// 这一页是 T17 那份快照的第一个消费方，两个方向都会静默出错：
/// - **字段名**：Dart 按名字查 `unavailable`，原生按名字塞键。两端各写一份字符串，
///   改一侧没有任何编译期报错 —— 表现是"这一项明明读不到，界面却显示空白/0"。
/// - **分层**：推送路由只有原生那一份（T12）。页面一旦自己挑通道，就会出现
///   "历史页按主备推、设备状态页按别的推"。
void main() {
  final root = projectRoot();
  String read(String path) =>
      stripComments(File('$root/$path').readAsStringSync());

  final page = read('lib/pages/device_snapshot_page.dart');
  final native = read(
    'android/app/src/main/kotlin/com/fnthink/notice/DeviceSnapshot.kt',
  );
  final more = read('lib/pages/more_page.dart');
  final notify = read('lib/services/notification_service.dart');

  group('快照字段名是跨端契约', () {
    /// 原生那侧的键清单（`private const val KEY_X = "x"`）
    final nativeKeys = RegExp(
      r'const val KEY_\w+ = "([a-zA-Z]+)"',
    ).allMatches(native).map((m) => m.group(1)!).toSet();

    /// 页面里用来查 `unavailable` 的字段名（元组第一项）
    final pageFields = RegExp(
      r"\(\s*'([a-zA-Z]+)',\s*l10n\.",
    ).allMatches(page).map((m) => m.group(1)!).toSet();

    test('原生键清单取到了（提取失效不得让本组空转）', () {
      expect(
        nativeKeys.length,
        greaterThanOrEqualTo(16),
        reason: '没从 DeviceSnapshot.kt 取出 KEY_* 字面量 = 提取式失效',
      );
    });

    test('页面查的字段名原生都认识', () {
      expect(pageFields, isNotEmpty, reason: '页面里一个字段名都没取到 = 空守卫');
      final unknown = pageFields.difference(nativeKeys);
      expect(
        unknown,
        isEmpty,
        reason: '页面按 $unknown 查"读不到"名单，而原生从不写这些名字 ⇒ 这些项永远显示成有值',
      );
    });

    // 原生回的几个键**并进同一行**显示（不是每一键一行）。这张表就是那份说明：
    // 原生加一个新字段而这里既没建行、也没写清并进哪一行 ⇒ 本条变红，逼一次决定。
    const mergedInto = {
      'sdkInt': '并入「系统版本」行',
      'batteryCharging': '并入「电量」行的括号',
      'storageFreeMb': '并入「存储」行（已用 = 总 − 可用）',
      'memoryTotalMb': '并入「内存」行的总量',
      'brightnessMode': '并入「屏幕亮度」行的括号',
      'capturedAtMs': '行下方那行「读取于 …」',
      'unavailable': '就是"读不到"名单本身，不单独成行',
    };

    test('原生回的每一个键，页面要么有自己的行，要么写明并进哪一行', () {
      final unmapped = nativeKeys
          .difference(pageFields)
          .difference(mergedInto.keys.toSet());
      expect(
        unmapped,
        isEmpty,
        reason: '原生已经会回 $unmapped，而页面既没有这一行也没登记并进哪里 ⇒ 用户看不见，等于没读',
      );
      // 登记表自己也会过期：删掉原生某个键后，这里必须跟着删
      final stale = mergedInto.keys.toSet().difference(nativeKeys);
      expect(stale, isEmpty, reason: '登记表里 $stale 已经不是原生会回的键了');
    });
  });

  group('页面不自己实现推送与读数', () {
    for (final forbidden in const [
      'invokeMethod',
      'ChannelRouting',
      'role',
      'engaged',
      'backup',
    ]) {
      test('设备状态页里不出现 $forbidden', () {
        expect(
          page.contains(forbidden),
          isFalse,
          reason:
              '读数/路由另有单一入口（DeviceInfoService、原生 dispatchToChannels）；'
              '页面里出现 $forbidden 就是抄了第二份',
        );
      });
    }

    test('推送走 NotificationService 那一个入口', () {
      expect(
        page.contains('pushSynthesizedRecord('),
        isTrue,
        reason: '页面绕过服务自己拼记录 = 送达快照与历史形状会漂',
      );
      expect(
        RegExp(
          r'Future<NotificationRecord>\s+pushSynthesizedRecord',
        ).hasMatch(notify),
        isTrue,
        reason: '服务侧那个入口不见了 ⇒ 页面调用会断，或各处自己拼一份记录',
      );
    });
  });

  group('更多页入口', () {
    test('「设备状态」行点进 DeviceSnapshotPage，而不是就地画快照', () {
      expect(
        RegExp(r'DeviceSnapshotPage\(\)').hasMatch(more),
        isTrue,
        reason: '更多页不再跳设备状态页 ⇒ 这一族读数退化成没有消费方的死数据',
      );
      expect(
        more.contains('getDeviceSnapshot'),
        isFalse,
        reason: '更多页自己读快照 = 每次主题切换都白读一遍设备（详情页里已经有）',
      );
    });
  });
}
