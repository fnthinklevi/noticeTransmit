import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T194 / T200 的回执链：顺序、方向与"一处作者"。
///
/// 这几条判据的后果都很具体：
///  - 清扫排在回执同步**之前** ⇒ 一条其实已送达的记录被标成 `no-receipt`（反馈⑭）；
///  - 重启清扫不按方向分档 ⇒ 发起端那行 pending 被写成 failed，
///    而对面其实已经执行完了（反馈 T200 原话）；
///  - 翻案判据长出第二份 ⇒ 真 failed 也会被迟到的 done 复活。
void main() {
  final root = projectRoot();
  String read(String rel) => File('$root/$rel').readAsStringSync();
  String code(String rel) => stripComments(read(rel));

  test('T194 回前台：先等回执同步，再清扫（顺序钉在同一个 helper 里）', () {
    final mainPage = code('lib/pages/main_page.dart');
    expect(mainPage, contains('_syncReceiptsThenSweep'));
    final body = blockAfter(mainPage, 'Future<void> _syncReceiptsThenSweep()');
    final syncAt = body.indexOf('runReceiptWatchdogNow()');
    final sweepAt = body.indexOf('sweepStaleDeliveries()');
    expect(syncAt, greaterThan(0), reason: 'helper 里必须先调回执看守');
    expect(
      sweepAt,
      greaterThan(syncAt),
      reason: '清扫读的是「还在路上」那一格；先扫会把已送达的那条标成 no-receipt',
    );
    // resumed 那一支不许再留一条**并行**清扫：两条并行 = 顺序判据形同虚设。
    final resumed = blockAfter(mainPage, 'void didChangeAppLifecycleState(');
    expect(
      RegExp(r'unawaited\(_notificationService\.sweepStaleDeliveries\(\)\)')
          .hasMatch(resumed),
      isFalse,
    );
  });

  test('T194 冷启动不再在 loadRecords 里先清扫（那一刻契约与同意门都还没到）', () {
    final svc = code('lib/services/notification_service.dart');
    final body = blockAfter(svc, 'Future<void> loadRecords()');
    expect(body, isNot(contains('sweepStaleDeliveries()')));
  });

  test('T194 只取回执走 /receipts，不借 poll 的 receiptsOnly 位', () {
    final contract = read('protocol/fnthink-v1.json');
    expect(contract, contains('"receipts": "/api/fnthink/receipts"'));
    expect(
      contract,
      contains('"receipts": {\n      "messageType": "receipts"'),
    );
    final svc = code('lib/services/fnthink_receiver_service.dart');
    expect(svc, contains("'receipts',"));
    final routes = code('server/lib/fnthink/routes.js');
    expect(routes, contains("'/receipts'"));
  });

  test('T194 回执落账只有一个作者（收货循环与看守共用）', () {
    final loop = code('lib/services/fnthink_receive_loop.dart');
    expect(loop, contains('applyFnthinkReceipts('));
    expect(
      loop,
      isNot(contains('for (final receipt in outcome.receipts)')),
      reason: '循环里不该再手抄一遍落账',
    );
    final coordinator = code('lib/services/fnthink_receive_coordinator.dart');
    expect(coordinator, contains('syncReceipts()'));
    expect(coordinator, contains('applyFnthinkReceipts('));
    final apply = code('lib/services/fnthink_receipt_apply.dart');
    expect(apply, contains('Future<int> applyFnthinkReceipts('));
  });

  test('T200 重启清扫按方向分档：out 写 no-receipt，不写 failed', () {
    final runner = code('lib/services/fnthink_remote_runner.dart');
    final body = blockAfter(runner, 'Future<int> sweepInterrupted(');
    expect(body, contains('row.outgoing'), reason: '清扫必须按主语分档');
    final outBranch = blockAfter(body, 'if (row.outgoing)');
    expect(outBranch, contains('reason: deliveryNoReceiptReason'));
    expect(
      outBranch,
      isNot(contains('RemoteExecutionStates.failed')),
      reason: '把「这一轮没拿到回执」写成 failed = 对面做完了、发起端说没做成',
    );
  });

  test('T200 迟到回执的翻案判据只在 remoteOutRowForReceipt 一处', () {
    final f = code('lib/services/fnthink_remote_out_record.dart');
    final start = f.indexOf(
      'FnthinkRemoteExecutionRecord? remoteOutRowForReceipt(',
    );
    final end = f.indexOf('String? _advanceOrBridge(');
    expect(start, greaterThan(0));
    expect(end, greaterThan(start));
    final body = f.substring(start, end);
    expect(body, contains('at.reason != deliveryNoReceiptReason'));
    expect(body, contains('if (!receipt.isFinished) return null;'));
  });

  test('T200 清扫调用点只取 in 方向；看守的判据来自送达模型一处作者', () {
    final mainPage = code('lib/pages/main_page.dart');
    final body = blockAfter(
      mainPage,
      'Future<void> _sweepInterruptedRemoteExecutions()',
    );
    expect(body, contains('direction: kFnthinkRemoteDirectionIn'));
    final store = code('lib/services/fnthink_delivery_link_store.dart');
    expect(store, contains('bool fnthinkDeliveryStillAwaitingReceipt('));
    expect(store, contains('unsettledStatuses.contains('));
    final locator = code('lib/di/service_locator.dart');
    expect(locator, contains('registerLazySingleton<FnthinkReceiptWatchdog>('));
    expect(locator, contains('fnthinkDeliveryStillAwaitingReceipt('));
  });
}
