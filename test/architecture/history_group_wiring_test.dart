import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T147②：组行这条跨语言链的三段各只有一个作者。
///
/// 原生算组 id → 随历史广播交给 Dart → Dart 记映射 → 历史页折叠成一行。
/// 任何一段少写一个字，整条链静默消失，而各端自己的单元测试都绿。
void main() {
  final root = projectRoot();

  String native(String rel) => stripComments(
    File(
      '$root/android/app/src/main/kotlin/com/fnthink/notice/$rel',
    ).readAsStringSync(),
  );

  String dart(String rel) => stripComments(librarySource(root, 'lib/$rel'));

  test('原生：merge/delay 两个生产者都把组 id 交给广播', () {
    final service = native('NotificationMonitorService.kt');
    expect(
      service,
      contains('appendResult.memberGroupId'),
      reason: 'merge 成员没有组 id ⇒ 历史页永远折不出组行',
    );
    expect(service, contains('decision.fireAt'));
    expect(service, contains('delay:'));
    expect(
      native('WebhookSender.kt'),
      allOf(
        contains('put("historyGroupId", historyGroupId)'),
        contains('put("historyGroupKind", historyGroupKind)'),
      ),
      reason: '广播 JSON 少一个字段，Dart 侧就收不到组映射',
    );
  });

  test('原生：组 id 的拼法只有 MergePushLogic 一个作者', () {
    final merge = native('MergePushManager.kt');
    expect(merge, contains('fun memberGroupId(key: String, windowEnd: Long)'));
    expect(
      merge,
      contains(
        'fun mergedId(): String = MergePushLogic.memberGroupId(key, windowEnd)',
      ),
    );
    expect(merge, contains('val memberGroupId: String'));
  });

  test('Dart：收件时记映射，历史页按成员回表算 X/Y', () {
    final service = dart('services/notification_service.dart');
    expect(service, contains('HistoryGroupStore().noteMember'));
    expect(service, contains("record['historyGroupId']"));

    final page = dart('pages/history_page.dart');
    expect(page, contains('historyGroupsLoader'));
    expect(page, contains('_forwardedRows'));
    expect(page, contains('_buildGroupRow'));
    expect(
      page,
      contains('deliveryBucketOf'),
      reason: '组行的「失败 Y」必须复用送达桶的唯一作者，不能另数一套',
    );
  });
}
