import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/models/delivery_status.dart';
import 'package:notice_transmit/services/fnthink_remote_execution.dart';
import 'package:notice_transmit/services/fnthink_remote_execution_state_words.dart';

/// T200：状态词那一格对「没拿到回执」要换一句话。
///
/// `pending` 普通那一档是「等执行」；可重启清扫把发起端那行留在 `pending` 并写上
/// `no-receipt` 之后，它**不会再执行**，也不该被读成「还在排队」。这一条钉的就是那个岔口。
void main() {
  final zh = lookupAppLocalizations(const Locale('zh'));
  final en = lookupAppLocalizations(const Locale('en'));

  test('pending + no-receipt ⇒ 未知，不是「等执行」', () {
    final text = fnthinkRemoteExecutionStateWord(
      zh,
      RemoteExecutionStates.pending,
      reason: deliveryNoReceiptReason,
    );
    expect(text, isNot(zh.remoteHistoryPending));
    expect(text, zh.remoteHistoryNoReceipt);
    expect(text, contains('没拿到回执'));
  });

  test('pending 没带那个理由 ⇒ 仍是「等执行」（不许把在排队的一律说成未知）', () {
    expect(
      fnthinkRemoteExecutionStateWord(zh, RemoteExecutionStates.pending),
      zh.remoteHistoryPending,
    );
    expect(
      fnthinkRemoteExecutionStateWord(
        zh,
        RemoteExecutionStates.pending,
        reason: 'network',
      ),
      zh.remoteHistoryPending,
    );
  });

  test('其它状态带 no-receipt 也不换词（判据只属于 pending 那一格）', () {
    expect(
      fnthinkRemoteExecutionStateWord(
        zh,
        RemoteExecutionStates.done,
        reason: deliveryNoReceiptReason,
      ),
      zh.remoteHistoryDone,
    );
  });

  test('英文同一条判据也换词', () {
    expect(
      fnthinkRemoteExecutionStateWord(
        en,
        RemoteExecutionStates.pending,
        reason: deliveryNoReceiptReason,
      ),
      en.remoteHistoryNoReceipt,
    );
  });
}
