import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T218：SSE 看门狗的三态接线。
///
/// 行为用例在 `test/services/fnthink_stream_service_test.dart`；这里只钉
/// **装配点**（漏接时行为用例仍可能各自绿，而真机上降级根本没生效）：
///  ① 判死不许直接 cleanup/重连，必须先走 `probeOnStale`；
///  ② degraded 的低频重探必须读 `degradedProbeIntervalForTest`，不许回到 5..120 退避；
///  ③ 协调者把三态接到 `shortPollMode` 与探针上；
///  ④ `pollOnce` 是短轮询的唯一落点（`hold && !shortPollMode`）。
void main() {
  final root = projectRoot();
  String read(String rel) =>
      stripComments(File('$root/$rel').readAsStringSync());
  String flat(String source) => source.replaceAll(RegExp(r'\s+'), ' ');

  const streamRel = 'lib/services/fnthink_stream_service.dart';
  const coordinatorRel = 'lib/services/fnthink_receive_coordinator.dart';
  const receiverRel = 'lib/services/fnthink_receiver_service.dart';

  test('判死分支先降级 + 探针，不许在 _onStale 里直接 cleanup/重连', () {
    final src = read(streamRel);
    final stale = blockAfter(src, 'void _onStale()');
    expect(stale, contains('probeOnStale'));
    expect(stale, contains('FnthinkStreamLinkState.degraded'));
    expect(
      stale,
      isNot(contains('_cleanupConnection()')),
      reason: '在 stale 里 cleanup 就是回到旧行为：每 50 秒断一次',
    );
    expect(stale, isNot(contains('_scheduleRetry()')));
  });

  test('degraded 低频重探读 degradedProbeIntervalForTest，不回到 5..120 退避', () {
    final src = read(streamRel);
    final schedule = blockAfter(src, 'void _scheduleDegradedProbe()');
    expect(schedule, contains('degradedProbeIntervalForTest'));
    expect(schedule, contains('probeDegradedForTest'));
  });

  test('任一字节恢复 healthy（wake/心跳都能把门铃救回来）', () {
    final src = read(streamRel);
    final consume = blockAfter(src, 'void _consume(String chunk)');
    expect(consume, contains('_setState(FnthinkStreamLinkState.healthy)'));
    expect(consume, contains('_startWatchdog(_generation)'));
  });

  test('协调者接到三态：degraded ⇒ shortPollMode=true；probeOnStale 接上', () {
    final src = flat(read(coordinatorRel));
    final build = flat(
      blockAfter(
        stripComments(File('$root/$coordinatorRel').readAsStringSync()),
        'FnthinkReceiveLoop buildFnthinkReceiveLoop(',
      ),
    );
    expect(build, contains('onLinkStateChanged:'));
    expect(build, contains('probeOnStale:'));
    expect(
      build,
      contains('shortPollMode = state == FnthinkStreamLinkState.degraded'),
      reason: '漏这一行 ⇒ degraded 仍发 hold，等于没降级',
    );
    expect(build, contains('fnthinkStreamProbeSucceeded(report)'));
    expect(src, contains('onLinkStateChanged:'));
  });

  test('pollOnce 的 hold 计算是短轮询的唯一落点', () {
    final src = stripComments(File('$root/$receiverRel').readAsStringSync());
    // ⚠ 不能 blockAfter 签名：pollOnce({bool hold = true}) 的**第一个 `{` 是命名参数表**，
    // 取到的只是 `{bool hold = true}`。按相邻成员切出真正的函数体。
    final start = src.indexOf('Future<FnthinkReceiveOutcome> pollOnce(');
    final end = src.indexOf('Future<FnthinkAckResult> ack(', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    expect(
      flat(src.substring(start, end)),
      contains('_holdPoll = hold && !shortPollMode'),
    );
  });
}
