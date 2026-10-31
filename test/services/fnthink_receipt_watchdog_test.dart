import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_receipt_watchdog.dart';

/// T194 A 档：发件回执看守。
///
/// 它只有三条判据，每一条都对应一个具体后果：
///  ① 没有在等的发件 ⇒ 一个字节都不发（不把它做成第二个轮询）；
///  ② 有 ⇒ 只跑一次同步；同一时刻进来的第二脚不叠成第二发；
///  ③ 等的是远程执行回执 ⇒ 补一轮收货（回执是一条消息），而不是去敲 /receipts。
void main() {
  test('没有在等的发件 ⇒ 不同步', () async {
    var syncs = 0;
    final w = FnthinkReceiptWatchdog(
      hasWaiting: () async => false,
      sync: () async {
        syncs++;
        return 0;
      },
    );
    await w.runNow();
    expect(syncs, 0);
    w.dispose();
  });

  test('有在等的 ⇒ 同步一次；并发的第二脚等同一发（不叠发）', () async {
    var syncs = 0;
    final gate = Completer<void>();
    final w = FnthinkReceiptWatchdog(
      hasWaiting: () async => true,
      sync: () async {
        syncs++;
        await gate.future;
        return 1;
      },
    );
    final first = w.runNow();
    final second = w.runNow();
    await Future<void>.delayed(Duration.zero);
    expect(syncs, 1);
    gate.complete();
    await Future.wait([first, second]);
    expect(syncs, 1);
    w.dispose();
  });

  test('等的是远程执行回执 ⇒ 补一轮收货，不去敲 /receipts', () async {
    var syncs = 0;
    var rounds = 0;
    final w = FnthinkReceiptWatchdog(
      hasWaiting: () async => false,
      sync: () async {
        syncs++;
        return 0;
      },
      remoteWaiting: () async => true,
      receiveRound: () async {
        rounds++;
      },
    );
    await w.runNow();
    await Future<void>.delayed(Duration.zero);
    expect(syncs, 0);
    expect(rounds, 1);
    w.dispose();
  });

  test('发送后连踢三脚 ⇒ 合并窗口后只同步一次', () async {
    var syncs = 0;
    final w = FnthinkReceiptWatchdog(
      hasWaiting: () async => true,
      sync: () async {
        syncs++;
        return 0;
      },
      debounce: const Duration(milliseconds: 20),
    );
    w.kick();
    w.kick();
    w.kick();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(syncs, 1);
    w.dispose();
  });

  test('dispose 之后踢不动也跑不动', () async {
    var syncs = 0;
    final w = FnthinkReceiptWatchdog(
      hasWaiting: () async => true,
      sync: () async {
        syncs++;
        return 0;
      },
      debounce: const Duration(milliseconds: 5),
    );
    w.dispose();
    w.kick();
    await w.runNow();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(syncs, 0);
  });
}
