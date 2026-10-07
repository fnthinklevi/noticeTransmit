import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// 首页那颗圈的第三态（监听开着、推送被暂停）的两条形状判据。
///
/// 钉的都是"改了之后没人会发现"的那类：通道方法名两端对不上 = 运行时才炸；
/// 页面里自己再判一次态 = 颜色、那句话、点下去做的动作三样会各自漂。
void main() {
  final root = projectRoot();
  String read(String rel) =>
      File('$root/$rel').readAsStringSync().replaceAll('\r\n', '\n');

  const service = 'lib/services/notification_service.dart';
  const page = 'lib/pages/notification_page.dart';
  const kotlin =
      'android/app/src/main/kotlin/com/fnthink/notice/channels/DeviceChannelHandler.kt';

  group('首页那颗圈的三态（监听 / 暂停推送 / 停止）', () {
    test('isPushActive 与 resumePush：两端名字逐字对上，Dart 侧调用点只有一处', () {
      final dartSrc = stripComments(read(service));
      final ktSrc = stripComments(read(kotlin));
      final pages =
          Directory('$root/lib/pages')
              .listSync(followLinks: false)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))
              .map((f) => 'lib/pages/${f.uri.pathSegments.last}')
              .where((rel) => stripComments(read(rel)).contains('invokeMethod'))
              .toList()
            ..sort();

      for (final method in ['isPushActive', 'resumePush']) {
        expect(
          RegExp("invokeMethod\\('$method'").allMatches(dartSrc).length,
          1,
          reason:
              '$method 在 service 里的调用点不是恰好一处 ⇒ 原生那一份状态有了第二个读者，'
              '而"读不到就说没读到"那条纪律只会留在其中一份里',
        );
        expect(
          ktSrc,
          contains('"$method" ->'),
          reason:
              '原生那侧没有 `"$method"` 这个分支 ⇒ Dart 那一发在运行时才炸 MissingPluginException，'
              '而界面此时说的是"没读到"，看不出是名字写错了',
        );
        expect(
          pages.any(
            (rel) =>
                stripComments(read(rel)).contains("invokeMethod('$method')"),
          ),
          isFalse,
          reason: '页面直连原生读/改推送开关 ⇒ 分层断了（页面 → service → 通道），$pages',
        );
      }
    });

    test('颜色、那句话、点下去做什么，三样都从同一枚判定派生', () {
      final src = stripComments(read(page));
      expect(
        src,
        contains('homeServiceTone('),
        reason: '这一格不再自己判态：判态的函数只有一处（`lib/services/home_service_status.dart`）',
      );
      expect(
        RegExp(r'foregroundServiceRunning\s*\?').hasMatch(src),
        isFalse,
        reason:
            '页面里又出现了 `foregroundServiceRunning ?` 那种二元三元式 ⇒ 三态被拆成'
            '"颜色一处判、文案一处判、onTap 再判一次"，下一幕就是圈是橙的而点它停了监听',
      );
    });
    test('原生那一发恢复的是推送开关，并把常驻通知与桌面小部件一起刷', () {
      // 这一条钉的是"点下去之后到底发生了什么"，而 Dart 侧看不见：
      //  ① 写成 pause ⇒ 首页变绿了而发送其实被关掉（症状是"验证码再也不来了"）；
      //  ② 不刷常驻通知 ⇒ 栏里那颗按钮还写着「恢复推送」，两处屏幕说两句话；
      //  ③ 不刷小部件 ⇒ 桌面那颗仍是暂停色，用户以为没生效又点一次；
      //  ④ 改成 sendBroadcast ⇒ 广播没送达时 Dart 立刻重读会读回 false，
      //     症状是"点了没反应"，而推送其实已经恢复了（这条是最难发现的一种）。
      final kt = stripComments(read(kotlin));
      final body = blockAfter(kt, '"resumePush" ->');
      expect(body, contains('PushToggleManager.resume('));
      expect(body, isNot(contains('PushToggleManager.pause(')));
      expect(body, contains('notifyServiceToUpdate'));
      expect(body, contains('updateAllWidgets'));
      expect(body, isNot(contains('sendBroadcast')));
      // 暂停态是"监听继续、只不发"，所以恢复那一发**不该**碰监听的两条方法。
      for (final untouched in [
        'startNotificationListener',
        'stopNotificationListener',
      ]) {
        expect(
          body,
          isNot(contains(untouched)),
          reason: '恢复推送顺手动了监听（$untouched）⇒ 用户的一次点击做成了一件他没要的事',
        );
      }
    });
  });
}
