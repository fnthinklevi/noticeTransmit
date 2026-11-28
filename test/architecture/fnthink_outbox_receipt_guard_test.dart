import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// P2-7：发出档"到没到"这件事有两条腿，少一条都会静默回到原样。
///
/// ① **看守得去取**：`hasWaiting` 只看 `notifications` 里幻念那一格 pending/queued，
///    而手动发送根本不写那一行 ⇒ 永远判"没有在等的" ⇒ 从不取 `/receipts`。
///    数据层再对也没用，因为那些行永远不会被翻。
/// ② **翻了也得看得见**：列表行的 `statusMessage` 对 outgoing 恒 null ⇒
///    即使 `acked_at` 已经写上，用户在列表里看到的仍是一片空白。
///
/// 这两件事都不是"某个函数算错了"，而是"装配点少接了一根线" ——
/// 所以尺量的是那根线在不在，而不是再算一遍结果。
void main() {
  final root = projectRoot();
  const locatorRel = 'lib/di/service_locator.dart';
  const rowsRel = 'lib/pages/history_page_rows.dart';

  String read(String rel) =>
      stripComments(File('$root/$rel').readAsStringSync());

  test('① 回执看守的 hasWaiting 会读 out 档未 ack（且下限取契约保留期）', () {
    final body = blockAfter(read(locatorRel), 'hasWaiting: () async {');
    expect(
      body,
      contains('hasFnthinkOutboxAwaitingAck('),
      reason:
          '看守不再读 `fnthink_messages` 的 out 档 ⇒ 手动发送没有那一行 pending，'
          '它永远判"没有在等的"，`/receipts` 一次都不取，发出档永远停在「排队中」。',
    );
    expect(
      body,
      contains('maxRetentionDays'),
      reason:
          '下限写死或干脆不设 ⇒ 要么把服务端已过期的死行当成"还在等"（看守空转），'
          '要么把还在保留期内的行漏掉（刚发出去就不取了）。',
    );
  });

  test('② 发出行把回执翻成人话，而不是留空', () {
    final rows = read(rowsRel);
    expect(
      rows,
      contains('fnthinkOutgoingStatusWord('),
      reason:
          '发出行不再算状态词 ⇒ statusMessage 对 outgoing 又回到 null，'
          '回执写进库了用户也看不见。',
    );
    expect(
      rows,
      contains('deliveryStatusText(l10n, outStatus!)'),
      reason: '状态词翻了却没上屏 ⇒ 后半根线还是断的',
    );
  });

  test('③ 反向自检：两处切点都切到了真代码（防空转假绿）', () {
    final locator = read(locatorRel);
    expect(locator, contains('FnthinkReceiptWatchdog('));
    expect(locator, contains('hasFnthinkOutboxAwaitingAck('));
    final rows = read(rowsRel);
    expect(rows, contains('FnthinkInboxMessage m, {'));
  });
}
