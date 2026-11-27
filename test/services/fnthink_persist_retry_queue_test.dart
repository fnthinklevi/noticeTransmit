import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notice_transmit/models/fnthink_inbox_message.dart';
import 'package:notice_transmit/services/fnthink_persist_retry_queue.dart';

/// P1-1：落库失败的本地待重试队列。
///
/// 它替的是"只靠服务端重投"那一条 3 分钟的路 —— 磁盘满、SQLCipher 密钥损坏这些故障
/// 不会在 3 分钟内自愈。所以这里钉的是四件事：
///  1. 失败的条能进队、能在下一轮补进去（这才叫"还在"）；
///  2. 补不进去的条留在队里并累加次数，不会静默消失；
///  3. 超龄/超次数/超容量时**记一笔放弃的账**，而不是无声丢弃（审计 P1-1 的验收）；
///  4. 队里的东西坏了一条，不影响其余条被补进去。
FnthinkInboxMessage _row(String id, {int receivedAt = 1700000000000}) =>
    FnthinkInboxMessage(
      messageId: id,
      sender: 'peer-a',
      type: 'notice',
      item: 'app.x',
      title: '标题$id',
      body: '正文$id',
      appName: 'X',
      receivedAt: receivedAt,
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('落库失败进队、下一轮补进去之后队列空', () async {
    final attempted = <String>[];
    var fail = true;
    final queue = FnthinkPersistRetryQueue(
      persist: (message) async {
        attempted.add(message.messageId);
        if (fail) throw StateError('表被占着');
        return true;
      },
      nowMs: () => 1700000000000,
    );

    await queue.enqueue(_row('m1'));
    await queue.enqueue(_row('m2'));
    expect(await queue.pendingCount(), 2);
    expect(await queue.abandonedCount(), 0);

    final stillFailing = await queue.drain();
    expect(stillFailing.persisted, 0);
    expect(stillFailing.abandoned, 0);
    expect(stillFailing.pending, 2);
    expect(attempted, ['m1', 'm2']);

    fail = false;
    final healed = await queue.drain();
    expect(healed.persisted, 2);
    expect(healed.abandoned, 0);
    expect(healed.pending, 0);
    expect(await queue.pendingCount(), 0);
  });

  test('同一条重复入队只留一份（按 messageId 去重）', () async {
    final queue = FnthinkPersistRetryQueue(
      persist: (_) async => true,
      nowMs: () => 1700000000000,
    );
    await queue.enqueue(_row('m1'));
    await queue.enqueue(_row('m1'));
    expect(await queue.pendingCount(), 1);
  });

  test('超龄的条按放弃处理并记一笔账（不再是只剩一行日志）', () async {
    var now = 1700000000000;
    final queue = FnthinkPersistRetryQueue(
      persist: (_) async => throw StateError('还是不行'),
      nowMs: () => now,
    );
    await queue.enqueue(_row('old'));
    // 25 小时之后（maxAgeMs 是 24 小时）
    now += FnthinkPersistRetryQueue.maxAgeMs + 60 * 60 * 1000;
    final report = await queue.drain();
    expect(report.abandoned, 1);
    expect(report.pending, 0);
    expect(await queue.abandonedCount(), 1);
    expect(await queue.pendingCount(), 0);
  });

  test('试满次数之后放弃，且累计计数只增不减（直到显式清）', () async {
    final queue = FnthinkPersistRetryQueue(
      persist: (_) async => throw StateError('永远失败'),
      nowMs: () => 1700000000000,
    );
    await queue.enqueue(_row('m1'));
    var total = 0;
    for (var i = 0; i < FnthinkPersistRetryQueue.maxAttempts; i++) {
      total += (await queue.drain()).abandoned;
    }
    expect(total, 1);
    expect(await queue.abandonedCount(), 1);
    expect(await queue.pendingCount(), 0);

    await queue.clearAbandoned();
    expect(await queue.abandonedCount(), 0);
  });

  test('超过容量时丢最旧的并记放弃，队列不会无限涨', () async {
    final queue = FnthinkPersistRetryQueue(
      persist: (_) async => throw StateError('表被占着'),
      nowMs: () => 1700000000000,
    );
    const over = FnthinkPersistRetryQueue.maxRows + 3;
    for (var i = 0; i < over; i++) {
      await queue.enqueue(_row('m$i'));
    }
    expect(await queue.pendingCount(), FnthinkPersistRetryQueue.maxRows);
    expect(await queue.abandonedCount(), 3);
  });

  test('队列里坏了一条只跳过那一条，其余照常补进去', () async {
    SharedPreferences.setMockInitialValues({
      FnthinkPersistRetryQueue.queueKey:
          '[{"r":{"message_id":"m1","sender":"p","type":"notice","item":"i",'
          '"title":"t","body":"b","app_name":"a","received_at":1,'
          '"sent_at":0,"read":0,"ack_result":"","acked_at":0,'
          '"direction":"in","via_backup":0},"a":1700000000000,"n":0},'
          '"不是一个对象",'
          '{"r":{"缺":"一堆列"},"a":1700000000000,"n":0}]',
    });
    final persisted = <String>[];
    final queue = FnthinkPersistRetryQueue(
      persist: (message) async {
        persisted.add(message.messageId);
        return true;
      },
      nowMs: () => 1700000000000,
    );
    final report = await queue.drain();
    expect(persisted, ['m1']);
    expect(report.persisted, 1);
    expect(report.pending, 0);
  });

  test('落库钩子抛的异常不会把 drain 带走（下一轮还会再试）', () async {
    final queue = FnthinkPersistRetryQueue(
      persist: (_) async => throw StateError('磁盘满'),
      nowMs: () => 1700000000000,
    );
    await queue.enqueue(_row('m1'));
    final report = await queue.drain();
    // 不抛出去、也不算放弃（才第 1 次）
    expect(report.persisted, 0);
    expect(report.abandoned, 0);
    expect(report.pending, 1);
    expect(await queue.pendingCount(), 1);
  });

  test('入队能扛住 prefs 不可用（只剩服务端重投，不许把循环打断）', () async {
    final queue = FnthinkPersistRetryQueue(
      persist: (_) async => true,
      prefs: () async => throw StateError('prefs 打不开'),
      nowMs: () => 1700000000000,
    );
    // 这三个都不许抛
    await queue.enqueue(_row('m1'));
    expect((await queue.drain()).persisted, 0);
    expect(await queue.pendingCount(), 0);
    expect(await queue.abandonedCount(), 0);
  });
}
