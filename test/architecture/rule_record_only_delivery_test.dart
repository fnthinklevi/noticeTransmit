import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// 「只记录不推送」那一档必须留下一个**可判的送达值**（T150 片2，维护者 2026-10-12 第 6 条）。
///
/// 症状：推送已暂停／规则判仅记录时，历史逐条那一格一直显示「发送中」。
/// 首页那枚圆点不是根因（它读的是服务态）；根因是**这条记录写进历史时，
/// 每一条通道的初值都是 `pending`，而这一档没有任何发送器会碰它 ⇒ 没人把它推离初值**。
///
/// 这里钉的是接缝的两端：
/// 1. 原生那一档要发一发拦截伪通道（`FILTER`），理由走 I18n，不许写成功的词；
/// 2. Dart 那侧的 `applyDelivery` 仍要把伪通道的结果**扇到每一格** —— 只改一头就变成
///    「原生发了没人接」或「Dart 准备接而原生没发」，两种都不报错，只是那一格永远说谎。
void main() {
  final root = projectRoot();

  String read(String rel) =>
      stripComments(File('$root/$rel').readAsStringSync());

  /// 取 `RuleEngine.Decision.Record ->` 那一臂（到下一臂 `Delay` 为止）。
  /// 按臂取而不是全文件搜：全文件搜 `DeliveryNotifier.notify(` 会被设备告警那一条喂成恒绿。
  String recordArm(String src) {
    final start = src.indexOf('RuleEngine.Decision.Record ->');
    expect(start, greaterThanOrEqualTo(0), reason: '规则引擎那一臂搬走了：请把这条一起搬过去，别删');
    final stop = src.indexOf('RuleEngine.Decision.Delay', start);
    expect(stop, greaterThan(start), reason: '下一臂的先后顺序变了 ⇒ 这段提取尺量错了对象');
    return src.substring(start, stop);
  }

  group('仅记录那一档留下可判的送达值（T150）', () {
    test('原生那一臂补一发拦截伪通道，而不是静默写完历史就返回', () {
      final arm = recordArm(
        read(
          'android/app/src/main/kotlin/com/fnthink/notice/NotificationMonitorService.kt',
        ),
      );
      expect(
        arm,
        contains('DeliveryNotifier.notify('),
        reason:
            '只 `sendBroadcast` 不补送达 = 那条记录里每一格停在 `pending`，'
            '界面替本机说「发送中」，而那台设备根本没把这条交给任何发送器',
      );
      expect(
        arm,
        contains('"FILTER"'),
        reason:
            '伪通道只能是 Dart 那侧会**扇到每一格**的那两个之一（FILTER／MERGE）；'
            '换成真实通道名就只改一格，其余照样永远「发送中」',
      );
      expect(
        arm,
        contains('I18n.ruleRecordOnlyReason()'),
        reason:
            '理由必须是那句「按规则仅记录，未推送」。写『应用过滤』是给了一条假理由 —— '
            '那条通知其实是被"只记录"这一档挡下的，不是被名单挡下的',
      );
      expect(
        arm,
        isNot(contains('DeliveryStatus.SUCCESS')),
        reason: '这一档没投递出去。把初值写成成功比写成「发送中」更坏（界面说了句彻底的假话）',
      );
    });

    test('Dart 那侧仍把拦截伪通道扇到每一格（接缝的另一头）', () {
      final svc = read('lib/services/notification_service.dart');
      expect(
        svc,
        contains('if (slug == kBlockedChannelKey) {'),
        reason:
            '`applyDelivery` 不再为拦截伪通道扇出 ⇒ 原生那一发改成只写一格，'
            '其余通道列仍停在 `pending`，症状一模一样回来',
      );
      final block = blockAfter(svc, 'if (slug == kBlockedChannelKey) {');
      expect(
        block,
        contains("'intercepted'"),
        reason: '扇出去的值必须是确定的那一档，不许沿用 `pending`',
      );
    });

    test('理由那句话住在 I18n（原生两侧都要能中英各一句）', () {
      final i18n = read(
        'android/app/src/main/kotlin/com/fnthink/notice/I18n.kt',
      );
      final fn = blockAfter(i18n, 'fun ruleRecordOnlyReason(): String');
      expect(
        fn,
        allOf(contains('isEn'), contains('Recorded only'), contains('仅记录')),
        reason:
            '这一族的原生措辞一律走 I18n（与 `filterAppBlockReason` 同式）；'
            '在服务里硬写中文字面量，英文系统上就给出一条没人看得懂的理由',
      );
    });
  });
}
