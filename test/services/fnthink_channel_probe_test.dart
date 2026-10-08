import 'package:flutter_test/flutter_test.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:notice_transmit/services/fnthink_channel_probe.dart';

/// T106 片②：探针的节流与重试口径。
///
/// 这一层不判协议（那在内核），它只回答两件事：**什么时候可以收工**、
/// **问到什么时候算失败**。三条边界各对应维护者 2026-10-08 的一句原话
/// （「自动重试 3 次」「超时显示失败」）。
void main() {
  FnthinkProbeResult verdict(bool? ready) =>
      FnthinkProbeResult(status: FnthinkPollStatus.ok, ready: ready);

  test('有结论就收工：ready:false 也只发一发（重试针对"没问到"，不是"问到了坏消息"）', () async {
    var calls = 0;
    final r = await probeFnthinkWithRetries(({required peer}) async {
      calls++;
      return verdict(false);
    }, peer: 'PEER00000000000001');

    expect(r, isFalse);
    expect(calls, 1, reason: '服务端查过了的回答不会因为再问两次变成另一个答案');
  });

  test('连问三次都没问到 ⇒ false（超时显示失败），且真的试了三次', () async {
    final peers = <String>[];
    final r = await probeFnthinkWithRetries(
      ({required peer}) async {
        peers.add(peer);
        return Future<FnthinkProbeResult>.delayed(
          const Duration(milliseconds: 60),
          () => verdict(null),
        );
      },
      peer: 'PEER00000000000001',
      budget: const Duration(milliseconds: 10),
    );

    expect(r, isFalse, reason: '三次都没问到 ⇒ 记一次失败（维护者定的口径：超时显示失败）');
    expect(peers.length, kFnthinkProbeAttempts);
    expect(peers, everyElement('PEER00000000000001'));
  });

  test('中途拿到结论 ⇒ 返回它，且不再多发', () async {
    var calls = 0;
    final r = await probeFnthinkWithRetries(({required peer}) async {
      calls++;
      return calls == 1 ? verdict(null) : verdict(true);
    }, peer: 'PEER00000000000001');

    expect(r, isTrue);
    expect(calls, 2);
  });

  test('三发都"答了但没结论" ⇒ false（没问到就是没问到，不写绿）', () async {
    var calls = 0;
    final r = await probeFnthinkWithRetries(({required peer}) async {
      calls++;
      return verdict(null);
    }, peer: 'PEER00000000000001');

    expect(r, isFalse);
    expect(calls, kFnthinkProbeAttempts);
  });

  test('抛异常也算没问到（重试到上限，不写绿）', () async {
    var calls = 0;
    final r = await probeFnthinkWithRetries(({required peer}) async {
      calls++;
      throw StateError('boom');
    }, peer: 'PEER00000000000001');

    expect(r, isFalse);
    expect(calls, kFnthinkProbeAttempts);
  });
}
