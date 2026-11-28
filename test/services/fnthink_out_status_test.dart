import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_out_status.dart';

/// P2-7：发出档的状态词映射。
///
/// 判据不在 UI 上：`ack_result` / `acked_at` 两列 → 既有送达词表。这里只钉映射，
/// 「词表怎么翻成人话」仍由 `delivery_display.dart` 那一份负责（不重复测）。
void main() {
  group('还没回执', () {
    test('空 result + 未 ack ⇒ queued（服务端已受理、等对面来取）', () {
      expect(fnthinkOutgoingStatusWord(ackResult: '', ackedAt: 0), 'queued');
    });

    test('空 result 但落了 ack 时刻 ⇒ delivered（旧服务端只带时刻）', () {
      expect(
        fnthinkOutgoingStatusWord(ackResult: '', ackedAt: 1700000000000),
        'delivered',
      );
    });
  });

  group('服务端回执原话', () {
    test('delivered / displayed 原样保留（P2-1 的两档不许压成一档）', () {
      expect(
        fnthinkOutgoingStatusWord(ackResult: 'delivered', ackedAt: 1),
        'delivered',
      );
      expect(
        fnthinkOutgoingStatusWord(ackResult: 'displayed', ackedAt: 1),
        'displayed',
      );
    });

    test('expired / dropped ⇒ failed（对发送者而言都是"没到"）', () {
      expect(
        fnthinkOutgoingStatusWord(ackResult: 'expired', ackedAt: 1),
        'failed',
      );
      expect(
        fnthinkOutgoingStatusWord(ackResult: 'dropped', ackedAt: 1),
        'failed',
      );
    });

    test('大小写与空白不影响判定', () {
      expect(
        fnthinkOutgoingStatusWord(ackResult: ' Displayed ', ackedAt: 1),
        'displayed',
      );
    });

    test('认不出的词不硬翻：原话交回词表（它会说「未知状态」）', () {
      expect(
        fnthinkOutgoingStatusWord(ackResult: 'waiting_online', ackedAt: 0),
        'waiting_online',
      );
    });
  });
}
