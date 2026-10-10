import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T133 片4：补推范围这个参数**跨语言那一段接缝**。
///
/// Dart 算出"这一条里可再发的那几族"，原生照它扇出。中间只有一串参数名（`onlySlugs`）
/// 与一个 intent extra 连着两侧，所以这一族守卫钉的是接缝本身：
/// 1. 参数名在两侧各只有**一处作者** —— 任何一侧改名或另起一名，另一侧就会安静地收到
///    `null`，而 `null` 的语义是"不限定"，表现是**多发**而不是报错（最难发现的那一类）；
/// 2. 两侧不许把「空集合」折成「缺省」—— 那是本片要修的那句话的另一半
///    （"这一条没有可再发的通道"必须变成"什么都不发"，不是"全都发"）。
///
/// ⚠ 本文件只钉形状；范围**算得对不对**由 `test/services/repush_scope_test.dart`（Dart）
///   与 `RepushScopeTest`（JVM）分别钉。
void main() {
  final root = projectRoot();

  String read(String rel) =>
      stripComments(File('$root/$rel').readAsStringSync());

  /// 原生 Kotlin 源码（相对 `android/app/src/main/kotlin/com/fnthink/notice/`）。
  String native(String rel) =>
      read('android/app/src/main/kotlin/com/fnthink/notice/$rel');

  final kotlinFiles =
      Directory('$root/android/app/src/main/kotlin/com/fnthink/notice')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.kt'))
          .toList();

  group('补推范围的跨语言接缝', () {
    test('参数名这个字面量两侧各只住一处（改名会安静地退化成"不限定"）', () {
      // 尺自己的非空自证：目录读空了，"零命中"看起来与"没人写过"一模一样
      expect(kotlinFiles, isNotEmpty, reason: '原生源码目录读空 ⇒ 下面全是假绿');

      // 扫的是**带引号的字面量**：两侧的参数名（`onlySlugs` 这个标识符） legitimately 在
      // 一条链上出现多次，而" MethodChannel 那个键的字符串"每侧只该有一个作者。
      final dartSide = Directory('$root/lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where(
            (f) => stripComments(f.readAsStringSync()).contains("'onlySlugs'"),
          )
          .map((f) => f.path.replaceAll('\\', '/').split('/lib/').last)
          .toList();
      final nativeSide = kotlinFiles
          .where(
            (f) => stripComments(f.readAsStringSync()).contains('"onlySlugs"'),
          )
          .map((f) => f.path.replaceAll('\\', '/').split('notice/').last)
          .toList();

      expect(
        dartSide,
        ['services/notification_service.dart'],
        reason:
            'Dart 侧递这个键的地方必须只有一处（service 的补推出口）。'
            '第二处 = 有人在页面/别的服务里自己拼范围，两侧判据就会漂开。',
      );
      expect(
        nativeSide,
        ['channels/StatsChannelHandler.kt'],
        reason:
            '原生侧读这个键的地方必须只有一处（MethodChannel 入口）。'
            '改名不会报错：另一侧安静地读到 null，而 null 的语义是"不限定"⇒ 多发一遍。',
      );
    });

    test('两侧都不许把空范围折叠成"不限定"', () {
      final dart = read('lib/services/notification_service.dart');
      final main = native('MainActivity.kt');
      // Dart：空集必须在递给原生之前就返回，而不是被 `ifEmpty`/`?? ` 之类折掉
      expect(
        RegExp(
          r'onlyDeliveryKeys != null && onlyDeliveryKeys\.isEmpty',
        ).hasMatch(dart),
        isTrue,
        reason: 'Dart 侧「空集 = 什么都不做」那一句不见了 ⇒ 空集会被当"不限定"，全部重发',
      );
      // 原生：extra 只在非 null 时写入，空列表要原样传下去
      expect(
        main,
        contains('onlySlugs?.let'),
        reason:
            '原生侧要"缺键=不限定 / 空列表=谁都不发"两种形状，'
            '写成 isNotEmpty 的判断就把空集折成了缺省',
      );
      for (final dead in ['takeIf { it.isNotEmpty }', 'ifEmpty { null }']) {
        expect(
          main.contains(dead),
          isFalse,
          reason: 'MainActivity 里出现「$dead」= 空范围被折成 null（不限定），会全部重发',
        );
      }
    });

    test('范围走到扇出口为止：中途不许有人替它判"要不要全发"', () {
      final service = native('NotificationMonitorService.kt');
      // ACTION → pushRecordNow → dispatchToChannels → routeChannels 一条链，
      // 每一环都必须把范围带下去（漏一环 = 那一环之后所有人都收到"不限定"）。
      expect(service, contains('getStringArrayListExtra(EXTRA_REPUSH_SLUGS)'));
      expect(
        blockAfter(service, 'private fun pushRecordNow('),
        contains('onlySlugs = onlySlugs'),
        reason: '手动补推没把范围递给扇出收口 ⇒ 范围在 intent 之后就断了',
      );
      expect(
        blockAfter(service, 'private fun dispatchToChannels('),
        contains('routeChannels(onlySlugs)'),
        reason: '收口函数没把范围转给路由 ⇒ 四族照旧全发',
      );
    });
  });
}
