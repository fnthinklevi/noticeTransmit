import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/models/delivery_status.dart';

/// T175 ②：超时清扫的纯函数。
///
/// 三条边界：
///  ① 不到时限的 pending/queued **不动**（在途不是失败）；
///  ② 到了时限的只动 pending/queued，`success`/`delivered`/`failed`/`paused`/`intercepted`
///     一格都不碰（终态不许被清扫改写）；
///  ③ 一条记录里没有任何要改的格子 ⇒ 返回 null（调用方据此跳过写库）。
void main() {
  const olderThan = Duration(minutes: 30);
  const now = 10 * 60 * 60 * 1000;
  const oldEnough = now - 30 * 60 * 1000 - 1;

  test('不到时限：原样返回 null', () {
    final delivery = <String, dynamic>{
      'chan:webhook': {'status': 'pending', 'message': ''},
      'chan:fnthink': {'status': 'queued', 'message': ''},
    };
    expect(
      sweepStaleDelivery(
        delivery,
        postTimeMs: now - 1000,
        nowMs: now,
        olderThan: olderThan,
      ),
      isNull,
    );
  });

  test('到时限：pending 与 queued 改成 failed(no-receipt)', () {
    final next = sweepStaleDelivery(
      <String, dynamic>{
        'chan:webhook': {'status': 'pending', 'message': '旧'},
        'chan:fnthink': {'status': 'queued', 'message': 'fanout: 1/1'},
      },
      postTimeMs: oldEnough,
      nowMs: now,
      olderThan: olderThan,
    );
    expect(next, isNotNull);
    expect(next!['chan:webhook']['status'], 'failed');
    expect(next['chan:webhook']['message'], deliveryNoReceiptReason);
    expect(next['chan:fnthink']['status'], 'failed');
    expect(next['chan:fnthink']['message'], deliveryNoReceiptReason);
  });

  test('终态一格都不碰；只有一格里是 pending 也只改那一格', () {
    final next = sweepStaleDelivery(
      <String, dynamic>{
        'chan:webhook': {'status': 'success', 'message': 'ok'},
        'chan:email': {'status': 'failed', 'message': '超时'},
        'chan:fnthink': {'status': 'queued', 'message': 'fanout: 1/1'},
        'chan:app': {'status': 'paused', 'message': ''},
      },
      postTimeMs: oldEnough,
      nowMs: now,
      olderThan: olderThan,
    );
    expect(next, isNotNull);
    expect(next!['chan:webhook'], {'status': 'success', 'message': 'ok'});
    expect(next['chan:email'], {'status': 'failed', 'message': '超时'});
    expect(next['chan:app'], {'status': 'paused', 'message': ''});
    expect(next['chan:fnthink']['status'], 'failed');
  });

  test('没有未终态格子 ⇒ null（不白写一次库）', () {
    expect(
      sweepStaleDelivery(
        <String, dynamic>{
          'chan:webhook': {'status': 'success', 'message': 'ok'},
          'chan:email': {'status': 'intercepted', 'message': ''},
        },
        postTimeMs: oldEnough,
        nowMs: now,
        olderThan: olderThan,
      ),
      isNull,
    );
  });

  test('postTime 未知（0）不猜：不去动它', () {
    expect(
      sweepStaleDelivery(
        <String, dynamic>{
          'chan:webhook': {'status': 'pending', 'message': ''},
        },
        postTimeMs: 0,
        nowMs: now,
        olderThan: olderThan,
      ),
      isNull,
    );
  });
}
