import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:notice_transmit/models/fnthink_inbox_message.dart';
import 'package:notice_transmit/services/fnthink_receive_loop.dart';
import 'package:notice_transmit/services/fnthink_receiver_service.dart';

/// 收货循环（#126 第三片）。这里盯的是**顺序与后果**，不是节奏的数字（那些在契约与内核里，
/// 由 `packages/fnthink_push/test/receive_kernel_test.dart` 钉）。四件事每件一个"写反了会怎样"：
///  ① 落库失败还去 ack ⇒ 服务端按 ack 删正文，用户两头都没有；
///  ② 重发的那条因为"表里已经有了"就跳过 ack ⇒ 它在服务端队列里一直占着 pending 额度，
///     表现是"这条永远在投递中"；
///  ③ ack 撞 429 还继续发 ⇒ 拿积压去敲闸门，剩下的每条都白耗一发额度；
///  ④ 一轮没结束就起下一轮 ⇒ 同一条被 ack 两次、未读数上下跳。
/// 顺带钉一条隐私：一轮的账（`summary`）里不许出现标题与正文。
/// 假排期返回的定时器都记在这里，逐个取消 —— flutter_test 在用例结束时会对
/// "还挂着的 Timer" 报错，而这里故意不真的按间隔回调（间隔的取值由 `scheduled` 那份账判）。
final _timers = <Timer>[];

void main() {
  tearDown(() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  });

  group('顺序：取货 → 落库 → ack', () {
    test('三条取到就三条落库、三条各 ack 一次 delivered', () async {
      final h = _Harness();
      final report = await h
          .loop(
            pollScript: [
              _ok([_msg('m_1'), _msg('m_2'), _msg('m_3')]),
            ],
          )
          .runOnce();
      expect(report.taken, 3);
      expect(report.inserted, 3);
      expect(report.acked, 3);
      expect(h.persisted.map((m) => m.messageId), ['m_1', 'm_2', 'm_3']);
      expect(h.ackOrder, ['m_1', 'm_2', 'm_3']);
      expect(h.ackResults, ['delivered', 'delivered', 'delivered']);
    });

    test('落库的字段与 poll 那条逐一对得上（sender 不许在中途掉）', () async {
      final h = _Harness();
      await h
          .loop(
            pollScript: [
              _ok([_msg('m_1', sender: 'endpoint:ep_7')]),
            ],
            nowMs: () => 1780000000000,
          )
          .runOnce();
      final one = h.persisted.single;
      expect(one.messageId, 'm_1');
      expect(one.sender, 'endpoint:ep_7');
      expect(one.type, 'notice');
      expect(one.title, '机箱温度');
      expect(one.body, '温度 63 度（m_1）');
      expect(one.receivedAt, 1780000000000);
      expect(one.read, isFalse);
      expect(one.ackResult, '');
    });

    test('① 落库失败的那条绝不 ack（ack 会让服务端立刻删正文）', () async {
      final h = _Harness(failPersistFor: ['m_2']);
      final report = await h
          .loop(
            pollScript: [
              _ok([_msg('m_1'), _msg('m_2'), _msg('m_3')]),
            ],
          )
          .runOnce();
      expect(report.persistedFailed, 1);
      expect(h.persisted.map((m) => m.messageId), ['m_1', 'm_3']);
      expect(h.ackOrder, ['m_1', 'm_3'], reason: '没落到盘上的那条不许报成功');
      expect(report.acked, 2);
    });

    test('② 表里已有的那条（服务端在重发）仍然再 ack 一次', () async {
      final h = _Harness();
      final loop = h.loop(
        pollScript: [
          _ok([_msg('m_1')]),
        ],
      );
      await loop.runOnce();
      final report = await loop.runOnce();
      expect(report.duplicate, 1);
      expect(report.inserted, 0);
      expect(h.ackOrder, ['m_1', 'm_1'], reason: '跳过它就是让它永远挂在服务端队列里');
    });
  });

  group('失败与闸门', () {
    test('取货没成功 ⇒ 不落库不 ack，也不产生"这条没了"的判断', () async {
      final h = _Harness();
      final report = await h
          .loop(
            pollScript: [
              const FnthinkReceiveOutcome(
                status: FnthinkPollStatus.rateLimited,
                nextDelay: Duration(seconds: 11),
                reason: 'rate-limited:11',
              ),
            ],
          )
          .runOnce();
      expect(report.status, FnthinkPollStatus.rateLimited);
      expect(report.nextDelay, const Duration(seconds: 11));
      expect(h.persisted, isEmpty);
      expect(h.ackOrder, isEmpty);
    });

    test('③ ack 撞 429 ⇒ 本轮剩下的不发，等待时间用服务端给的那个', () async {
      final h = _Harness();
      h.ackByMessage['m_2'] = [
        const FnthinkAckResult(
          status: FnthinkPollStatus.rateLimited,
          nextDelay: Duration(seconds: 30),
          serverReceipt: 'queued',
        ),
      ];
      final report = await h
          .loop(
            pollScript: [
              _ok([_msg('m_1'), _msg('m_2'), _msg('m_3')]),
            ],
          )
          .runOnce();
      expect(h.ackOrder, ['m_1', 'm_2'], reason: '第三条不许再发');
      expect(report.acked, 1);
      expect(report.ackSkipped, 1);
      expect(report.ackFailed, 0, reason: '429 不是"这一条没送达"的意思');
      expect(report.nextDelay, const Duration(seconds: 30));
    });

    test('ack 的一般性失败计入 ackFailed，剩下的照发、下一轮照常排', () async {
      final h = _Harness();
      h.ackByMessage['m_1'] = [
        const FnthinkAckResult(
          status: FnthinkPollStatus.rejectedUnsigned,
          nextDelay: Duration(seconds: 20),
          reason: 'rejected-unsigned',
        ),
      ];
      final report = await h
          .loop(
            pollScript: [
              _ok([_msg('m_1'), _msg('m_2')]),
            ],
          )
          .runOnce();
      expect(report.ackFailed, 1);
      expect(report.acked, 1);
      expect(h.ackOrder, ['m_1', 'm_2']);
      expect(report.nextDelay, const Duration(seconds: 20));
    });
  });

  group('一轮只跑一轮', () {
    test('④ 上一轮还在途 ⇒ 整轮跳过，第二次连 poll 都不发', () async {
      final h = _Harness();
      final loop = h.loop(
        pollScript: [
          _ok([_msg('m_1')]),
        ],
      );
      final slow = loop.runOnce();
      // async 函数体在第一个 await 之前是同步跑的：这里 _inRound 已经立起来了。
      final second = await loop.runOnce();
      expect(second.skipped, isTrue);
      expect(second.reason, 'round-in-progress');
      // 跳过之后必须**等一会儿**再排：拿 zero 排等于把"跳过"变成一台空转的马达。
      expect(second.nextDelay, greaterThan(Duration.zero));
      await slow;
      expect(h.pollCalls, 1, reason: '被跳过的那一轮不该产生任何 IO');
    });

    test('start 立刻跑一轮并按 nextDelay 排下一轮；stop 之后不再排', () async {
      final h = _Harness();
      final loop = h.loop(
        pollScript: [
          _ok([_msg('m_1')]),
        ],
      );
      loop.start();
      await Future<void>.delayed(Duration.zero);
      expect(h.persisted.map((m) => m.messageId), ['m_1']);
      expect(h.scheduled, [const Duration(seconds: 20)]);

      loop.stop();
      expect(loop.isRunning, isFalse);
      expect(h.scheduled, hasLength(1), reason: '停了还排下一轮 = 关不掉的收货');
    });

    test('排下去的那一下真的会再起一轮（回调没接错地方）', () async {
      final h = _Harness();
      final loop = h.loop(
        pollScript: [
          _ok([_msg('m_1')]),
          _ok([_msg('m_2')]),
        ],
      );
      loop.start();
      await Future<void>.delayed(Duration.zero);
      expect(h.pollCalls, 1);
      expect(h.callbacks, hasLength(1));

      h.callbacks.single(); // 模拟定时器到点
      await Future<void>.delayed(Duration.zero);
      expect(h.pollCalls, 2);
      expect(h.persisted.map((m) => m.messageId), ['m_1', 'm_2']);
      loop.stop();
    });

    test('一轮里冒出来的异常不断链：按一个保守间隔排回去', () async {
      final h = _Harness();
      final loop = FnthinkReceiveLoop(
        poll: () async => throw StateError('不该冒出来的错'),
        ack: h.ack,
        persist: h.persist,
        schedule: h.schedule,
      );
      loop.start();
      await Future<void>.delayed(Duration.zero);
      expect(h.scheduled, [const Duration(seconds: 60)]);
    });
  });

  group('账目可见但不泄露内容', () {
    test('summary 里有各档计数，却没有标题与正文', () async {
      final h = _Harness();
      final report = await h
          .loop(
            pollScript: [
              _ok([_msg('m_1')], pending: 7),
            ],
          )
          .runOnce();
      final text = report.summary;
      expect(text, contains('待取 7'));
      expect(text, contains('ack 1/0_skip0'));
      expect(text, isNot(contains('机箱温度')));
      expect(text, isNot(contains('温度 63 度')));
    });
  });
}

FnthinkDelivered _msg(String id, {String sender = '8K3FJ6QPTM9WZ4VHNS'}) =>
    FnthinkDelivered(
      messageId: id,
      type: 'notice',
      item: '',
      title: '机箱温度',
      body: '温度 63 度（$id）',
      sender: sender,
    );

FnthinkReceiveOutcome _ok(List<FnthinkDelivered> messages, {int pending = 0}) =>
    FnthinkReceiveOutcome(
      status: FnthinkPollStatus.ok,
      messages: messages,
      pending: pending,
      nextDelay: const Duration(seconds: 20),
    );

/// 三个依赖的程序化替身 + 排期捕获。
class _Harness {
  _Harness({this.failPersistFor = const []});

  final List<String> failPersistFor;
  final List<FnthinkReceiveOutcome> _pollScript = [];
  final Set<String> _seen = {};

  int pollCalls = 0;
  final List<String> ackOrder = [];
  final List<String> ackResults = [];
  final List<FnthinkInboxMessage> persisted = [];
  final List<Duration> scheduled = [];
  final List<void Function()> callbacks = [];
  final Map<String, List<FnthinkAckResult>> ackByMessage = {};

  Future<FnthinkReceiveOutcome> poll() async {
    final i = pollCalls;
    pollCalls++;
    if (_pollScript.isEmpty) return _ok(const []);
    return _pollScript[i < _pollScript.length ? i : _pollScript.length - 1];
  }

  Future<FnthinkAckResult> ack(String messageId, String result) async {
    ackOrder.add(messageId);
    ackResults.add(result);
    final scripted = ackByMessage[messageId];
    if (scripted != null && scripted.isNotEmpty) return scripted.removeAt(0);
    return const FnthinkAckResult(
      status: FnthinkPollStatus.ok,
      nextDelay: Duration(seconds: 20),
    );
  }

  Future<bool> persist(FnthinkInboxMessage message) async {
    if (failPersistFor.contains(message.messageId)) {
      throw StateError('落库失败：${message.messageId}');
    }
    persisted.add(message);
    // 同一个 id 第二次见到 = 服务端在重发（表里那行已经在）⇒ 回 false（ignore 没插进去）
    return _seen.add(message.messageId);
  }

  Timer schedule(Duration delay, void Function() callback) {
    scheduled.add(delay);
    // 不自动按间隔回调（那会变成同步递归）：把回调存下来，由用例自己"点一下"，
    // 这样连"排下去的那一下真的会再起一轮"都能观察到。
    callbacks.add(callback);
    final timer = Timer(Duration.zero, () {});
    _timers.add(timer);
    return timer;
  }

  FnthinkReceiveLoop loop({
    List<FnthinkReceiveOutcome>? pollScript,
    int Function()? nowMs,
  }) {
    if (pollScript != null) {
      _pollScript
        ..clear()
        ..addAll(pollScript);
      pollCalls = 0;
    }
    return FnthinkReceiveLoop(
      poll: poll,
      ack: ack,
      persist: persist,
      nowMs: nowMs ?? () => 1700000000000,
      schedule: schedule,
    );
  }
}
