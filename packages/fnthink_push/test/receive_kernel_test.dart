import 'dart:convert';
import 'dart:io';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:test/test.dart';

/// #126 设备侧收货内核。这个文件盯的四件事，每件都有一个具体的"写反了会怎样"：
///  ① `ts` 是**秒**且来自服务端时间 —— 写成毫秒不会报错，只会让每条都超出容差，
///     看起来像"服务端不认我的签名"；
///  ② 提频只在有货时开 —— 一直提着是拿用户的电换不到任何东西；
///  ③ 设备不许自报 `expired` / `dropped` —— 那是服务端自己的决定，让设备报就等于让它
///     替全世界宣布"这条结束了"，而正文会按契约被立刻删掉；
///  ④ 一次传输异常**不改变任何状态** —— 把抖动当成结论，表现是"网络抖一下就掉线半天"。
/// 一台可以推着走的时钟 + 一个把信封记下来的假传输层。
///
/// 它不是"测试替身的摆设"：内核里每一条判据（ts 用谁的时间、什么时候提频、
/// 什么结果不许发出去）都要能被观察到，而观察点就是"这几次往返各发了什么、
/// 拿回什么时钟"。`dart format` 之前先声明在 main() 里是错的 —— Dart 不允许在函数体里声明类。
class _Harness {
  _Harness(this.contract, this._now);

  final FnthinkContract contract;
  int _now;

  /// 往返耗时（毫秒）：偏移是按"发出与收到的中点"学的，所以延迟必须在传输里走，
  /// 不能在调用之前手动推时钟 —— 那样测出来的是"我预期的算术"，不是内核的取中点。
  int latencyMs = 0;
  final List<Map<String, Object?>> sent = [];

  /// 每次签名收到的规范化字节（解成文本）。用来证"哪些东西**不进**签名载荷"
  /// —— 那类形状错了不会抛，只会换回一句同形的 403。
  final List<String> signedBytes = [];
  FnthinkReply reply = const FnthinkReply(status: 200, body: {});
  Object? throws;

  int nowMs() => _now;
  void advance(int ms) => _now += ms;

  Future<FnthinkReply> transport(Map<String, Object?> envelope) async {
    sent.add(envelope);
    _now += latencyMs;
    if (throws != null) throw throws!;
    return reply;
  }

  FnthinkReceiveKernel kernel() => FnthinkReceiveKernel(
    contract: contract,
    addressCode: _self,
    signer: (bytes) async {
      signedBytes.add(utf8.decode(bytes));
      return 'sig-${bytes.length}';
    },
    transport: transport,
    nowMs: nowMs,
    nonceFactory: () => 'n${sent.length + 1}',
  );
}

const _self = '8K3FJ6QPTM9WZ4VHNS';
const _peer = '8KMNPQRSTVWX999777';

void main() {
  late FnthinkContract contract;

  setUp(() => contract = FnthinkContract.readFile());

  /// 状态码一律从契约读（本文件里不许出现 4xx 字面量，与 routes.js 同一条纪律）。
  int code(String name) => contract.statusCodes[name]!;

  Map<String, Object?> okPoll({
    int messages = 0,
    int pending = 0,
    int? serverTime,
    List<Object?> receipts = const [],
    List<Object?> pairRequests = const [],
  }) {
    final batch = contract.maxBatchPerPoll;
    final taken = messages > batch ? batch : messages;
    return {
      'messages': [
        for (var i = 0; i < taken; i++)
          {
            'messageId': 'm_$i',
            'type': 'notice',
            'item': '',
            'title': '机箱',
            'body': '温度 63 度 $i',
            'sender': _peer,
          },
      ],
      'receipts': receipts,
      'pending': pending,
      contract.pairRequestPollKey: pairRequests,
      'serverTime': serverTime ?? DateTime.now().toUtc().millisecondsSinceEpoch,
    };
  }

  group('校准与 ts', () {
    test('没校准前 signedTimestamp 是本机秒；一发之后按 serverTime 折半学偏移', () async {
      final local = 1_800_000_000_000; // 毫秒
      // 服务端比本机快 10 分钟
      final harness = _Harness(contract, local);
      final poll = harness.kernel();
      expect(poll.calibrated, isFalse);
      // ⚠ 秒，不是毫秒：这一条一旦被写成毫秒，后面每一条都会被判 410，而那看起来像签名坏了
      expect(poll.signedTimestamp, '${local ~/ 1000}');

      harness.reply = FnthinkReply(
        status: 200,
        body: okPoll(serverTime: local + 600_000),
      );
      // 往返 2 秒 ⇒ 中点 = local + 1000
      harness.latencyMs = 2000;
      final result = await poll.poll();
      expect(result.status, FnthinkPollStatus.ok);
      expect(poll.calibrated, isTrue);
      expect(poll.offsetMs, (local + 600_000) - (local + 1000));
      expect(
        poll.signedTimestamp,
        '${(local + 2000 + poll.offsetMs!) ~/ 1000}',
      );
    });

    test('没校准就签这一发要如实说出去（不静默当成准的）', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = FnthinkReply(status: 200, body: okPoll());
      final poll = harness.kernel();
      final result = await poll.poll();
      expect(result.signedWhileUncalibrated, isTrue);
      // 下一轮已经校准过了：校准是**这个实例**上的状态
      final second = await poll.poll();
      expect(second.signedWhileUncalibrated, isFalse);
    });

    test('失败的那一发只要带 serverTime，也要拿去校准', () async {
      final local = 1_800_000_000_000;
      final harness = _Harness(contract, local);
      final poll = harness.kernel();
      harness.reply = FnthinkReply(
        status: code('expired'),
        body: okPoll(serverTime: local + 900_000),
      );
      final first = await poll.poll();
      expect(first.status, FnthinkPollStatus.needsCalibration);
      // 拿着 410 却不肯学时间，就会一路 410 到底 —— 而现场只会看到"连不上"
      expect(poll.calibrated, isTrue);
      expect(poll.offsetMs, greaterThan(0));
    });

    test('签名字段恰好是契约那六个，顶层只有三个键', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = FnthinkReply(status: 200, body: okPoll());
      await harness.kernel().poll();
      final envelope = harness.sent.single;
      expect(envelope.keys.toList()..sort(), ['fields', 'sender', 'signature']);
      final fields = envelope['fields'] as Map<String, Object?>;
      expect(
        (fields.keys.toList()..sort()),
        (contract.canonicalOrder.toList()..sort()),
      );
      expect(fields['target'], _self);
      expect(fields['type'], 'poll');
      expect(fields['body'], '');
      // target 只能是构造时那台自己：内核没有给调用方覆盖它的口子
      expect(envelope['sender'], _self);
    });
  });

  group('节奏（提频只在有货时）', () {
    test('pending=0 ⇒ 常态间隔，且这个数从契约来', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = FnthinkReply(status: 200, body: okPoll());
      final result = await harness.kernel().poll();
      expect(result.nextDelay, Duration(seconds: contract.pollIntervalSeconds));

      // 换一份只改数字的契约副本，间隔跟着变（断来源，不是断值等于 20）
      final mutated = FnthinkContract({
        ...contract.raw,
        'presence': {
          ...contract.raw['presence'] as Map<String, Object?>,
          'pollIntervalSeconds': {'default': 27, 'min': 15, 'max': 30},
        },
      });
      final other = FnthinkReceiveKernel(
        contract: mutated,
        addressCode: _self,
        signer: (bytes) async => 'sig',
        transport: (_) async => const FnthinkReply(
          status: 200,
          body: {'messages': [], 'pending': 0},
        ),
      );
      expect((await other.poll()).nextDelay, Duration(seconds: 27));
    });

    test('本机那一档（T88）：常态跟着用户选的走，提频仍是契约那档', () async {
      // 内核是节奏的**用**处，不是作者：这里注入的数只能来自契约范围内的一个值，
      // 而提频档（有货时）仍然是协议给的 —— 用户选得再慢，也不该让已经等在那里的通知
      // 按慢档去等。
      final chosen = contract.pollIntervalRange.max;
      final kernel = FnthinkReceiveKernel(
        contract: contract,
        addressCode: _self,
        signer: (_) async => 'sig',
        transport: (_) async => const FnthinkReply(
          status: 200,
          body: {'messages': [], 'pending': 0},
        ),
        pollIntervalSeconds: chosen,
      );
      expect(kernel.steadyPollSeconds, chosen);
      expect(
        chosen,
        isNot(contract.pollIntervalSeconds),
        reason: '锚点：注入的值必须与契约 default 不同，否则这条断不出"谁在起作用"',
      );
      expect((await kernel.poll()).nextDelay, Duration(seconds: chosen));

      final burst = contract.burstWhenPending;
      final withPending = FnthinkReceiveKernel(
        contract: contract,
        addressCode: _self,
        signer: (_) async => 'sig',
        transport: (_) async => const FnthinkReply(
          status: 200,
          body: {'messages': [], 'pending': 2},
        ),
        pollIntervalSeconds: chosen,
      );
      expect(
        (await withPending.poll()).nextDelay,
        Duration(seconds: burst.intervalSeconds),
        reason: '有货时该回到协议那档提频 —— 用户把常态调慢不等于让待取的东西也等那么久',
      );
    });

    test('注入一档协议不允许的间隔 ⇒ 构造就抛，不夹（悄悄夹掉是"屏幕 60 而实际 30"）', () {
      final tooBig = contract.pollIntervalRange.max + 1;
      expect(
        () => FnthinkReceiveKernel(
          contract: contract,
          addressCode: _self,
          signer: (_) async => 'sig',
          transport: (_) async => const FnthinkReply(status: 200, body: {}),
          pollIntervalSeconds: tooBig,
        ),
        throwsStateError,
        reason:
            '越过上限 ⇒ 常态比服务端额度推导还慢/还快都不会报错，只是这台被持续 429；'
            '宁可在装配期就抛出来',
      );
      expect(
        () => FnthinkReceiveKernel(
          contract: contract,
          addressCode: _self,
          signer: (_) async => 'sig',
          transport: (_) async => const FnthinkReply(status: 200, body: {}),
          pollIntervalSeconds: contract.pollIntervalRange.min - 1,
        ),
        throwsStateError,
      );
    });

    test('429 没带 Retry-After ⇒ 等的是本机那一档，而不是契约 default', () async {
      final chosen = contract.pollIntervalRange.min;
      final kernel = FnthinkReceiveKernel(
        contract: contract,
        addressCode: _self,
        signer: (_) async => 'sig',
        transport: (_) async => FnthinkReply(
          status: contract.statusCodes['rateLimited']!,
          body: const {},
        ),
        pollIntervalSeconds: chosen,
      );
      final result = await kernel.poll();
      expect(
        result.status,
        FnthinkPollStatus.rateLimited,
        reason: '锚点：先确认真的走到了 429 那一支',
      );
      expect(result.nextDelay, Duration(seconds: chosen));
    });

    test('pending>0 ⇒ 提频；用完 durationSeconds 自动回落常态', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      final burst = contract.burstWhenPending;
      harness.reply = FnthinkReply(status: 200, body: okPoll(pending: 1));
      final poll = harness.kernel();
      final first = await poll.poll();
      expect(first.nextDelay, Duration(seconds: burst.intervalSeconds));

      harness.advance(burst.durationSeconds * 1000 - 1000);
      expect(poll.currentDelay, Duration(seconds: burst.intervalSeconds));
      harness.advance(2000);
      expect(
        poll.currentDelay,
        Duration(seconds: contract.pollIntervalSeconds),
      );
    });

    test('货取满一整批（服务端截断过）⇒ 即使 pending 报 0 也继续提频', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = FnthinkReply(
        status: 200,
        body: okPoll(messages: contract.maxBatchPerPoll, pending: 0),
      );
      final result = await harness.kernel().poll();
      expect(result.messages.length, contract.maxBatchPerPoll);
      expect(
        result.nextDelay,
        Duration(seconds: contract.burstWhenPending.intervalSeconds),
      );
    });

    test('429 就等 Retry-After，并且不因此丢掉"还有货"这件事', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      final poll = harness.kernel();
      await poll.poll(); // 先让 pending>0 把提频窗口打开
      harness.reply = FnthinkReply(status: 200, body: okPoll(pending: 3));
      await poll.poll();
      harness.reply = FnthinkReply(
        status: code('rateLimited'),
        retryAfterSeconds: 11,
      );
      final limited = await poll.poll();
      expect(limited.status, FnthinkPollStatus.rateLimited);
      expect(limited.nextDelay, Duration(seconds: 11));
      expect(limited.reason, contains('rate-limited'));
      // 窗口没被 429 抹掉：货还在服务端排着
      expect(
        poll.currentDelay,
        Duration(seconds: contract.burstWhenPending.intervalSeconds),
      );
    });
  });

  group('ack：设备只说自己那一半', () {
    Future<FnthinkReceiveKernel> withOneMessage(_Harness harness) async {
      harness.reply = FnthinkReply(
        status: 200,
        body: okPoll(messages: 1, pending: 0),
      );
      final poll = harness.kernel();
      await poll.poll();
      return poll;
    }

    test(
      'result 只认契约 resultToEvent 的键；expired / dropped 在本地就拒，一发都不发',
      () async {
        final harness = _Harness(contract, 1_800_000_000_000);
        final poll = await withOneMessage(harness);
        final before = harness.sent.length;
        for (final forbidden in [
          'expired',
          'dropped',
          'delivered-but-late',
          '',
        ]) {
          final result = await poll.ack(messageId: 'm_0', result: forbidden);
          expect(result.status, FnthinkPollStatus.failed, reason: forbidden);
          expect(result.reason, contains('unknown-result'));
        }
        expect(harness.sent.length, before); // 真的没发出去
        // 而合法那几个词都能发
        for (final allowed in contract.ackResultToEvent.keys) {
          final harness2 = _Harness(contract, 1_800_000_000_000);
          final poll2 = await withOneMessage(harness2);
          harness2.reply = const FnthinkReply(
            status: 200,
            body: {'receipt': 'delivered'},
          );
          final ok = await poll2.ack(messageId: 'm_0', result: allowed);
          expect(ok.status, FnthinkPollStatus.ok, reason: allowed);
        }
      },
    );

    test('ack 的载荷里只有 messageId 与 result 两个键（服务端逐字节比名单）', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      final poll = await withOneMessage(harness);
      harness.reply = const FnthinkReply(
        status: 200,
        body: {'receipt': 'displayed'},
      );
      await poll.ack(messageId: 'm_0', result: 'displayed');
      final envelope = harness.sent.last;
      final body =
          jsonDecode((envelope['fields'] as Map)['body'] as String)
              as Map<String, Object?>;
      expect(body.keys.toList()..sort(), contract.ackFields.toList()..sort());
      expect(body['messageId'], 'm_0');
      expect(body['result'], 'displayed');
    });

    test('两种事件各签各的词：poll 与 ack 的 type 都从契约来', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      final poll = harness.kernel();
      harness.reply = FnthinkReply(status: 200, body: okPoll(messages: 1));
      await poll.poll();
      harness.reply = const FnthinkReply(
        status: 200,
        body: {'receipt': 'displayed'},
      );
      await poll.ack(messageId: 'm_0', result: 'displayed');
      final types = harness.sent
          .map((e) => (e['fields'] as Map)['type'])
          .toList();
      expect(types, [
        contract.str(const ['clientEvents', 'poll', 'messageType']),
        contract.str(const ['clientEvents', 'ack', 'messageType']),
      ]);
      // 这两枚词必须不同 —— 相同的话服务端会按同一 kind 裁决（poll 不查 messageId，
      // ack 也不查归属），那是一条"看起来在跑其实没判"的通道。
      expect(types[0], isNot(types[1]));
    });

    test('不属于本轮的那条 id 在本地就拒（不发出去换一句同形的 403）', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      final poll = await withOneMessage(harness);
      final before = harness.sent.length;
      final result = await poll.ack(messageId: 'm_other', result: 'displayed');
      expect(result.reason, contains('not-in-current-round'));
      expect(harness.sent.length, before);
    });

    test('渲染回调来两次 ⇒ 第二次不发（duplicateSuppressed）', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      final poll = await withOneMessage(harness);
      harness.reply = const FnthinkReply(
        status: 200,
        body: {'receipt': 'displayed'},
      );
      final first = await poll.ack(messageId: 'm_0', result: 'displayed');
      expect(first.duplicateSuppressed, isFalse);
      final second = await poll.ack(messageId: 'm_0', result: 'displayed');
      expect(second.duplicateSuppressed, isTrue);
      expect(
        harness.sent.where((e) => (e['fields'] as Map)['type'] == 'ack').length,
        1,
      );
    });

    test('下一轮 poll 之后，上一轮的 id 不再可 ack（本地内存有界，不靠"记住所有历史"）', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      final poll = await withOneMessage(harness);
      harness.reply = FnthinkReply(
        status: 200,
        body: okPoll(messages: 1, pending: 0),
      );
      await poll.poll(); // 新一轮把 _round 换成新的（同样是 m_0，但这里是新的一张表）
      final fresh = FnthinkReply(
        status: 200,
        body: okPoll(messages: 0, pending: 0),
      );
      harness.reply = fresh;
      await poll.poll();
      final late = await poll.ack(messageId: 'm_0', result: 'displayed');
      expect(late.reason, contains('not-in-current-round'));
    });

    test('ack 被 429 ⇒ 分类成 rateLimited 并把 Retry-After 传下去', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      final poll = await withOneMessage(harness);
      harness.reply = FnthinkReply(
        status: code('rateLimited'),
        retryAfterSeconds: 5,
      );
      final result = await poll.ack(messageId: 'm_0', result: 'displayed');
      expect(result.status, FnthinkPollStatus.rateLimited);
    });
  });

  group('失败分类与"抖动不改变状态"', () {
    test('401 与 403 都只报 rejectedUnsigned，不猜是哪一种（同形是设计而不是缺陷）', () async {
      for (final name in ['unauthorized', 'forbidden']) {
        final harness = _Harness(contract, 1_800_000_000_000);
        harness.reply = FnthinkReply(status: code(name));
        final result = await harness.kernel().poll();
        expect(result.status, FnthinkPollStatus.rejectedUnsigned, reason: name);
        expect(result.reason, 'rejected-unsigned');
      }
    });

    test('409 报 replayed（换 nonce，不是换密钥）', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = FnthinkReply(status: code('duplicate'));
      final result = await harness.kernel().poll();
      expect(result.status, FnthinkPollStatus.replayed);
    });

    test('传输异常 ⇒ 校准、提频窗口一个都不动', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      final poll = harness.kernel();
      harness.reply = FnthinkReply(status: 200, body: okPoll(pending: 2));
      await poll.poll();
      final offset = poll.offsetMs;
      final burstBefore = poll.currentDelay;
      harness.throws = StateError('网络断了');
      final failed = await poll.poll();
      expect(failed.status, FnthinkPollStatus.transportError);
      expect(poll.offsetMs, offset);
      expect(poll.currentDelay, burstBefore);
      expect(poll.calibrated, isTrue);
      // 下一轮照常：异常没有把任何东西变成"结论"
      harness.throws = null;
      harness.reply = FnthinkReply(status: 200, body: okPoll());
      expect((await poll.poll()).status, FnthinkPollStatus.ok);
    });

    test('形状不对的记录一律丢掉，不猜 id（猜一个去 ack 就是替另一条宣布结局）', () {
      expect(FnthinkDelivered.tryFrom(contract, {'type': 'notice'}), isNull);
      expect(
        FnthinkDelivered.tryFrom(contract, {'messageId': '', 'type': 'notice'}),
        isNull,
      );
      expect(FnthinkDelivered.tryFrom(contract, 'not a map'), isNull);
      // 完整的一条能读出来，缺 item/title 时按空串（那是服务端本来给的空值，不是猜的）
      final one = FnthinkDelivered.tryFrom(contract, {
        'messageId': 'm_1',
        'type': 'notice',
      });
      expect(one!.messageId, 'm_1');
      expect(one.item, '');
    });

    test('取到的那条带发件人；旧服务端不给这一列时留空而不是把消息丢掉', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = FnthinkReply(status: 200, body: okPoll(messages: 2));
      final result = await harness.kernel().poll();
      expect(result.messages.map((m) => m.sender).toSet(), {_peer});
      // 这一列的名字与"必须有"都由契约说：把它从名单里摘掉，Dart 侧 validate 先红
      expect(contract.pollMessageFields, contains('sender'));

      // 对端是旧版（名单里还没有 sender）：消息照旧收下、sender 留空，界面显示"未知来源"。
      // 反过来（因为缺归属就丢）才是违规 —— 正文已经到手，丢掉就是「不静默丢」的反面。
      final legacy = _Harness(contract, 1_800_000_000_000);
      legacy.reply = FnthinkReply(
        status: 200,
        body: {
          'messages': [
            {
              'messageId': 'm_old',
              'type': 'notice',
              'title': '旧版',
              'body': '没有 sender',
            },
          ],
          'pending': 0,
          'serverTime': 1_800_000_000_000,
        },
      );
      final old = await legacy.kernel().poll();
      expect(old.messages, hasLength(1));
      expect(old.messages.single.sender, '');
    });

    test('回执词表外的结论被丢（两端对"结论"的理解漂了就要能看出来）', () {
      expect(
        FnthinkReceipt.tryFrom(contract, {
          'messageId': 'm_1',
          'receipt': 'totally_fine',
        }),
        isNull,
      );
      final ok = FnthinkReceipt.tryFrom(contract, {
        'messageId': 'm_1',
        'receipt': contract.receipts.first,
      });
      expect(ok!.receipt, contract.receipts.first);
    });

    test('不注入 nonceFactory 时用的是进程内计数器（够防自己重发，不够防跨重启 ⇒ 标注为调用方的洞）', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = FnthinkReply(status: 200, body: okPoll());
      final poll = FnthinkReceiveKernel(
        contract: contract,
        addressCode: _self,
        signer: (bytes) async => 'sig',
        transport: harness.transport,
        nowMs: harness.nowMs,
      );
      await poll.poll();
      await poll.poll();
      final nonces = harness.sent
          .map((e) => (e['fields'] as Map)['nonce'])
          .toSet();
      expect(nonces.length, 2); // 两次不同
      expect(nonces.first.toString(), contains('-'));
    });
  });

  group('数字只从契约读', () {
    test(
      '缺 pollIntervalSeconds / burstWhenPending / maxSkewSeconds / maxBatchPerPoll ⇒ 抛',
      () {
        Map<String, Object?> without(List<String> path) {
          final copy = {
            ...contract.raw,
            path[0]: {
              ...(contract.raw[path[0]] as Map<String, Object?>),
              ...{path[1]: null},
            },
          };
          return copy;
        }

        final noPoll = FnthinkContract(
          without(['presence', 'pollIntervalSeconds']),
        );
        expect(() => noPoll.pollIntervalSeconds, throwsStateError);
        expect(
          () => FnthinkContract(
            without(['signature', 'maxSkewSeconds']),
          ).maxSkewSeconds,
          throwsStateError,
        );
        expect(
          () => FnthinkContract(
            without(['clientEvents', 'poll']),
          ).maxBatchPerPoll,
          throwsStateError,
        );
        expect(
          () => FnthinkContract(
            without(['presence', 'burstWhenPending']),
          ).burstWhenPending,
          throwsStateError,
        );
      },
    );

    test('源码守卫：内核里没有第二个数字真值，也没有 4xx 字面量', () {
      // 状态码一律经 contract.statusCodes 比（与 routes.js 同一条纪律）；
      // 间隔与额度一律经契约 getter。写死一个 20 或 429，表现是契约改了而设备按老的跑，
      // 那不会报错，只会让在线判定与配额两头对不上。
      final raw = File('lib/src/receive_kernel.dart').readAsStringSync();
      final stripped = raw
          .split('\n')
          .where(
            (String line) =>
                !line.trim().startsWith('///') && !line.trim().startsWith('//'),
          )
          .join('\n');
      expect(RegExp(r'Duration\(seconds: [0-9]').hasMatch(stripped), isFalse);
      for (final literal in ['429', '410', '409', '403', '401']) {
        expect(stripped.contains(literal), isFalse, reason: literal);
      }
      // 200 是 HTTP 层的"这一发有 body"，不是协议结论，所以它允许出现（且只允许那一处）
      expect(RegExp(r'!= 200').hasMatch(stripped), isTrue);
      expect(stripped.split('200').length - 1, lessThanOrEqualTo(2));
      // pairArm 的载荷键名同样只许来自契约：内核里出现 'pairingCode' 字面量 = 名单被抄了第二份，
      // 契约把那一栏改名的那天，这一发会照旧签出老键 —— 换回来的还是一句同形的 403。
      expect(stripped.contains("'pairingCode'"), isFalse);
    });

    test('签名的 version 取自协议名，且与 contractVersion 不一致时立刻抛（不猜一个）', () {
      expect(
        contract.protocolVersionForSignature,
        '${contract.contractVersion}',
      );
      final broken = FnthinkContract({
        ...contract.raw,
        'protocol': 'fnthink-v9',
      });
      expect(() => broken.protocolVersionForSignature, throwsStateError);
    });
  });

  group('挂口令 pairArm（T42「添加设备」的第一跳）', () {
    // 20 位 Crockford Base32（契约 identity.pairingCode.length）。这里不做校验——
    // 校验住口令形状是 credential_store 那一层的事，内核只管"按契约名单发出去"。
    const pairingCode = '7A9QKM3PTVWXRBNSFGH4';

    Map<String, Object?> armOk({int? serverTime}) {
      final server =
          serverTime ?? DateTime.now().toUtc().millisecondsSinceEpoch;
      return {
        'armed': true,
        'expiresAt': server + 300_000,
        'ttlSeconds': 300,
        'serverTime': server,
      };
    }

    test('载荷键名单来自契约：多带一个 level 当场抛，且不先把信封发出去', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      final poll = harness.kernel();
      expect(
        () => poll.pairArmFields(
          payload: {contract.pairArmPayloadField: pairingCode, 'level': 'L1'},
          nonce: 'n1',
        ),
        throwsA(isA<ArgumentError>()),
        reason:
            '服务端按契约名单逐字节比，多一个键就整条拒 —— 而拒信只有一句同形的 403，'
            '把"我多塞了东西"伪装成"身份有问题"是最难查的那类失败',
      );
      expect(harness.sent, isEmpty, reason: '抛在发出去之前，不该已经留下一封必然被拒的信');
    });

    /// 一发 pairArm，返回它签出去的那个 `fields`。
    /// 形状检查拆成"每件事一条用例"：反证要的是**一条植入红一条用例**，
    /// 四个断言同住一条用例时，红了哪一句只能靠读日志猜。
    Future<Map<String, Object?>> armOnce(_Harness harness) async {
      harness.reply = FnthinkReply(status: 200, body: armOk());
      await harness.kernel().pairArm(pairingCode: pairingCode);
      return harness.sent.single['fields'] as Map<String, Object?>;
    }

    test('type 用 pairArm 自己的那个词，不是借来的 poll', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      final fields = await armOnce(harness);
      expect(
        fields['type'],
        contract.str(const ['clientEvents', 'pairArm', 'messageType']),
        reason: '一个内核跑多种事件时，type 借错词只会换回一句同形的 403',
      );
    });

    test('target 必须是本机地址码（selfOnly：挂口令的人是自己）', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      final fields = await armOnce(harness);
      expect(
        fields['target'],
        _self,
        reason: 'target 填别人 = 替别人挂出口令，那枚口令之后会认到别人身上',
      );
    });

    test('body 里就契约那一个键，键序也按契约', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      final fields = await armOnce(harness);
      final body = jsonDecode(fields['body'] as String) as Map<String, Object?>;
      expect(body.keys.toList(), contract.pairArmFields);
      expect(body[contract.pairArmPayloadField], pairingCode);
    });

    test('ts 是秒（写成毫秒不报错，只会每一发都超出容差）', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      final fields = await armOnce(harness);
      expect(fields['ts'], '${1_800_000_000_000 ~/ 1000}');
    });

    test('200 带回 expiresAt ⇒ 挂成功，并从这一发学到服务端时间', () async {
      final local = 1_800_000_000_000;
      final harness = _Harness(contract, local);
      final server = local + 600_000;
      harness.reply = FnthinkReply(
        status: 200,
        body: armOk(serverTime: server),
      );
      final poll = harness.kernel();
      final result = await poll.pairArm(pairingCode: pairingCode);
      expect(result.ok, isTrue);
      expect(result.expiresAtMs, server + 300_000);
      expect(result.ttlSeconds, 300);
      expect(
        poll.calibrated,
        isTrue,
        reason: '任何带 serverTime 的响应都是校准机会；这一发是用户主动点的，比后台轮询更早发生',
      );
    });

    test('200 但没给过期时间 ⇒ 不算挂成功（界面不许说"已挂出"）', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = FnthinkReply(
        status: 200,
        body: {'serverTime': 1_800_000_000_000},
      );
      final result = await harness.kernel().pairArm(pairingCode: pairingCode);
      expect(
        result.ok,
        isFalse,
        reason:
            '"本机记下了"与"服务器收下了"差一次网络往返，而用户看不出差别：'
            '把前者说成后者，对端扫码只会得到"口令不存在"',
      );
      expect(result.expiresAtMs, isNull);
    });

    test('限流那一发按 Retry-After 说成"要等"，不是"挂失败"', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = FnthinkReply(
        status: code('rateLimited'),
        retryAfterSeconds: 30,
        body: {},
      );
      final result = await harness.kernel().pairArm(pairingCode: pairingCode);
      expect(
        result.status,
        FnthinkPollStatus.rateLimited,
        reason: '429 不是这一发的结论；让它落成 failed 会诱导用户连点，而连点只会更限流',
      );
    });

    test('传输异常不发任何结论，也不改校准状态', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.throws = const SocketException('dns down');
      final poll = harness.kernel();
      final result = await poll.pairArm(pairingCode: pairingCode);
      expect(result.status, FnthinkPollStatus.transportError);
      expect(poll.calibrated, isFalse);
      expect(
        poll.lastReason,
        startsWith('transport:'),
        reason: '一次连不上不说明任何关于服务端的 anything，改了状态就把抖动放大成错误判断',
      );
    });
  });

  // ── #176 / T28-B 的 B 侧：把那枚口令交出去，换回一条**等 A 确认**的请求 ──
  // 这一组盯的是三件"错了不会报错"的事：
  //  ① target 填成本机 —— 服务端拒，而拒信与"口令错"同形，用户与开发者都读不出是这一步；
  //  ② 载荷键名从契约派生（口令那项 = `pairArm.arms`，另一项即档位）—— 内核里写死字面量
  //     就等于把名单抄成第二份，契约改名那天照旧签出老键；
  //  ③ 200 不等于"配上了"：没有 requestId、或状态词不认识，都必须落到失败 —— 界面据此
  //     说"已提交，等对方确认"，而不是"配对成功"（`pairing.autoApprove=false`）。
  group('交口令 pair（#176 / T28-B 的 B 侧）', () {
    const code = 'PAIRCODE123456';
    const wantedLevel = 'L1';

    Map<String, Object?> paired({
      String? id = 'pr_1',
      Object? status = 'pending',
    }) => {
      'requestId': id,
      'status': status,
      'expiresAt': 1800000300000,
      'serverTime': 1800000000000,
    };

    Future<Map<String, Object?>> pairOnce(
      _Harness harness, {
      String target = _peer,
      String level = wantedLevel,
      Map<String, Object?>? body,
    }) async {
      harness.reply = FnthinkReply(status: 200, body: body ?? paired());
      await harness.kernel().pair(
        targetAddressCode: target,
        pairingCode: code,
        level: level,
      );
      return harness.sent.single['fields'] as Map<String, Object?>;
    }

    test('type 用 pair 自己的那个词，target 是对端地址码', () async {
      final harness = _Harness(contract, 1800000000000);
      final fields = await pairOnce(harness);
      expect(
        fields['type'],
        contract.str(const ['clientEvents', 'pair', 'messageType']),
        reason: '借别人的词 = 服务端按另一种事件验签，永远回一句同形的 403',
      );
      expect(fields['target'], _peer, reason: 'B 签的是"关于 A"那一封信');
      expect(
        fields['target'],
        isNot(_self),
        reason: '填成自己就是自配 —— 服务端 selfOnlyRules 的第三条会拒',
      );
    });

    test('载荷两项都按契约名单与顺序编进 body（内核不写字面量）', () async {
      final harness = _Harness(contract, 1800000000000);
      final fields = await pairOnce(harness);
      final body = jsonDecode(fields['body'] as String) as Map<String, Object?>;
      expect(
        body.keys.toList(),
        contract.pairFields,
        reason: '规范化字节逐字节比：键序不同就签成另一封信，而服务端只回一句"验签不过"',
      );
      expect(body[contract.pairArmPayloadField], code);
      expect(
        body[contract.pairFields.firstWhere(
          (k) => k != contract.pairArmPayloadField,
        )],
        wantedLevel,
      );
    });

    test('target 填成本机 ⇒ 抛在发出之前，一封都不留', () async {
      final harness = _Harness(contract, 1800000000000);
      expect(
        () => harness.kernel().pairFields(
          pairingCode: code,
          level: wantedLevel,
          targetAddressCode: _self,
          nonce: 'n1',
        ),
        throwsA(isA<ArgumentError>()),
        reason: '这一发必被拒，而拒信与"口令错"同形 —— 让它在离机前就炸',
      );
      expect(harness.sent, isEmpty);
    });

    test('档位不在词表里 ⇒ 不离机，并给一句能显示的原因', () async {
      final harness = _Harness(contract, 1800000000000);
      final result = await harness.kernel().pair(
        targetAddressCode: _peer,
        pairingCode: code,
        level: 'L9',
      );
      expect(harness.sent, isEmpty, reason: '发出去只会换回一句同形的 403');
      expect(result.ok, isFalse);
      expect(result.reason, 'pair-level-unknown:L9');
    });

    test('200 但没给 requestId ⇒ 按失败：那句"已提交"没有证据', () async {
      final harness = _Harness(contract, 1800000000000);
      harness.reply = FnthinkReply(status: 200, body: paired(id: null));
      final result = await harness.kernel().pair(
        targetAddressCode: _peer,
        pairingCode: code,
        level: wantedLevel,
      );
      expect(result.ok, isFalse, reason: '服务器没真记下这条请求，界面不能说"已提交，等对方确认"');
      expect(result.reason, 'pair-acked-without-request');
    });

    test('状态词不在契约表里 ⇒ 同样按失败（两端对"结了没有"的理解漂了）', () async {
      final harness = _Harness(contract, 1800000000000);
      harness.reply = FnthinkReply(
        status: 200,
        body: paired(status: 'waiting'),
      );
      final result = await harness.kernel().pair(
        targetAddressCode: _peer,
        pairingCode: code,
        level: wantedLevel,
      );
      expect(result.ok, isFalse);
      expect(contract.pairRequestStatuses, isNotEmpty);
    });

    test('认下来的那一发：ok 带 requestId 与状态词，口令不进签名载荷', () async {
      final harness = _Harness(contract, 1800000000000);
      harness.reply = FnthinkReply(status: 200, body: paired());
      final result = await harness.kernel().pair(
        targetAddressCode: _peer,
        pairingCode: code,
        level: wantedLevel,
      );
      expect(result.ok, isTrue);
      expect(result.requestId, 'pr_1');
      expect(result.expiresAtMs, 1800000300000);
      expect(
        harness.signedBytes.single,
        isNot(contains('privateKey')),
        reason: '契约 mayNotCarry：私钥与端点口令都不许进这一发',
      );
    });
  });

  group('poll 带回的配对请求：解析成类型（T42 第四片）', () {
    Map<String, Object?> okPollWith(List<Object?> reqs) => {
      'messages': const [],
      'receipts': const [],
      'pending': 0,
      contract.pairRequestPollKey: reqs,
      'serverTime': 1800000000000,
    };

    FnthinkPairRequest? parse(Object? raw) => FnthinkPairRequest.tryFrom(raw);

    test('一条完整的请求被解析出来，答复要用的 id 与对端地址都在', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = FnthinkReply(
        status: 200,
        body: okPollWith([
          {
            'id': 'pr_1',
            'requester': _peer,
            'requesterPublicKey': 'AAAA',
            'level': 'L1',
            'createdAt': 1780000000000,
            'expiresAt': 1780000060000,
          },
        ]),
      );
      final result = await harness.kernel().poll();
      final req = result.pairRequests.single;
      expect(req.requestId, 'pr_1');
      expect(
        req.requester,
        _peer,
        reason: '这一发 pairConfirm 的 target 就是它 —— 认错了人等于把白名单开给别台设备',
      );
      expect(req.level, 'L1');
      expect(req.expiresAt, 1780000060000);
    });

    test('键缺或为空的请求被丢掉，不被画成"某台设备请求配对你"', () {
      expect(
        parse({
          'id': '',
          'requester': _peer,
          'requesterPublicKey': 'A',
          'level': 'L1',
        }),
        isNull,
      );
      expect(
        parse({
          'id': 'x',
          'requester': '',
          'requesterPublicKey': 'A',
          'level': 'L1',
        }),
        isNull,
      );
      expect(parse({'id': 'x', 'requester': _peer, 'level': 'L1'}), isNull);
      expect(parse('not a map'), isNull);
    });

    test('target 与 status 缺席不影响（服务端今日不回它们）', () {
      final one = parse({
        'id': 'x',
        'requester': _peer,
        'requesterPublicKey': 'A',
        'level': 'L2',
      });
      expect(one, isNotNull);
      expect(one!.createdAt, isNull, reason: '没有就显示未知，不拿 0 当成"1970 年请求的"');
    });
  });

  group('答复一条请求 pairConfirm（T42 第四片）', () {
    // 两个答复词也从契约读，不在测试里抄一份：抄了的那份，契约改词时会红成"测试坏了"，
    // 而不是"实现跟着词走了"—— 分不清是哪一种。
    String approvedWord() => contract.pairConfirmApproveDecision;
    String deniedWord() =>
        contract.pairConfirmDecisions.firstWhere((d) => d != approvedWord());

    Future<FnthinkPairConfirmResult> confirm(
      _Harness harness,
      String decision, {
      String level = 'L1',
    }) => harness.kernel().pairConfirm(
      requestId: 'pr_9',
      decision: decision,
      level: level,
      counterpart: _peer,
    );

    test('target 写的是对端，不是本机（全协议唯一一发）', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = FnthinkReply(
        status: 200,
        body: {
          'requestId': 'pr_9',
          'status': approvedWord(),
          'grantedLevel': 'L1',
          'serverTime': 1800000000000,
        },
      );
      await confirm(harness, approvedWord());
      final fields = harness.sent.single['fields']! as Map<String, Object?>;
      expect(fields['target'], _peer);
      expect(fields['target'], isNot(_self));
      final body = jsonDecode(fields['body']! as String) as Map;
      expect(body.keys.toList(), contract.pairConfirmFields);
    });

    test('答应的词与档位都必须在契约的封闭集合里，否则当场抛、不签出去', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      expect(
        () => harness.kernel().pairConfirm(
          requestId: 'pr_9',
          decision: 'granted',
          level: 'L1',
          counterpart: _peer,
        ),
        throwsArgumentError,
        reason: '把界面上任意字符串签出去，换回来的只是一句与"这个词不存在"同形的 403',
      );
      expect(
        () => harness.kernel().pairConfirm(
          requestId: 'pr_9',
          decision: approvedWord(),
          level: 'L9',
          counterpart: _peer,
        ),
        throwsArgumentError,
      );
      expect(harness.sent, isEmpty);
    });

    test('200 但状态词看不懂 ⇒ 不算已答复（两端的理解已经漂了）', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = FnthinkReply(
        status: 200,
        body: {'requestId': 'pr_9', 'status': 'granted', 'serverTime': 1},
      );
      final result = await confirm(harness, approvedWord());
      expect(result.ok, isFalse);
      expect(
        result.reason,
        'pair-confirm-unparsable-ack',
        reason: '"granted" 不在 pairRequest.statuses 里；把它当成功，本机就会记下一条其实没成立的授权',
      );
    });

    test('服务端给的档位可能低于答应的：回什么就记什么', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = FnthinkReply(
        status: 200,
        body: {
          'requestId': 'pr_9',
          'status': approvedWord(),
          'grantedLevel': 'L1',
          'serverTime': 1800000000000,
        },
      );
      final result = await confirm(harness, approvedWord(), level: 'L2');
      expect(result.ok, isTrue);
      expect(
        result.grantedLevel,
        'L1',
        reason:
            '契约 pairing.maxRequestableLevelFromPairing 那道封顶由服务端落，界面要显示的是这一格',
      );
    });

    test('拒绝那一路同样要发出去（不是一句本地状态）', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = FnthinkReply(
        status: 200,
        body: {
          'requestId': 'pr_9',
          'status': deniedWord(),
          'serverTime': 1800000000000,
        },
      );
      final result = await confirm(harness, deniedWord());
      expect(result.ok, isTrue);
      expect(harness.sent, hasLength(1));
    });
  });

  group('划掉一个发送方 pairRevoke（T31 B 片）', () {
    Map<String, Object?> sentFields(_Harness harness) =>
        harness.sent.single['fields']! as Map<String, Object?>;

    Future<FnthinkPairRevokeResult> revoke(_Harness harness) =>
        harness.kernel().pairRevoke(peer: _peer);

    test('target 是被划掉那台，载荷里也是同一个地址（一个入参喂给两处）', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = const FnthinkReply(
        status: 200,
        body: {'revoked': true, 'serverTime': 1800000000000},
      );
      final result = await revoke(harness);
      expect(result.ok, isTrue);
      final fields = sentFields(harness);
      expect(fields['target'], _peer);
      expect(
        fields['target'],
        isNot(_self),
        reason: '写成自己的地址码就是替别人撤销他自己的授权，而拒信与"口令错"同形',
      );
      final body = jsonDecode(fields['body']! as String) as Map;
      expect(body.keys.toList(), contract.pairRevokeFields);
      expect(
        body.values.single,
        _peer,
        reason:
            '服务端判「载荷里那个地址逐字等于签名里的 target」。这里从一开始就只有一个入参，'
            '于是"两处能不能不一致"不是调用方要负责的事',
      );
    });

    test('type 用 pairRevoke 自己的那个词（不借 pairConfirm 的）', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = const FnthinkReply(status: 200, body: {'revoked': true});
      await revoke(harness);
      expect(
        sentFields(harness)['type'],
        contract.str(['clientEvents', 'pairRevoke', 'messageType']),
      );
      expect(
        sentFields(harness)['type'],
        isNot(contract.str(['clientEvents', 'pairConfirm', 'messageType'])),
        reason: '一个内核跑多种事件时，借词的那一发会落到别人的入口上，而服务端只回一句同形 403',
      );
    });

    test('revoked:false 是一次**成功**（撤销是幂等的，不是失败）', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = const FnthinkReply(
        status: 200,
        body: {'revoked': false, 'serverTime': 1800000000000},
      );
      final result = await revoke(harness);
      expect(
        result.ok,
        isTrue,
        reason:
            '目标状态是「它不在我的名单里」，已经不在就是已达成。'
            '把它读成失败，本机就留着那一行不再删 —— 两边从此各说一段',
      );
      expect(result.revoked, isFalse);
    });

    test('200 而 revoked 不是布尔 ⇒ 不算撤成（宁可那一行留着）', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = const FnthinkReply(status: 200, body: {'revoked': 'yes'});
      final result = await revoke(harness);
      expect(result.ok, isFalse);
      expect(
        result.reason,
        'pair-revoke-unparsable-ack',
        reason: '看不懂的 200 当成"撤好了"，本机删了一行而对面其实还在名单里',
      );
    });

    test('403 ⇒ 没成、revoked 是空的（本机一行都不许动）', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = FnthinkReply(
        status: code('forbidden'),
        body: const {'receipt': 'rejected_capability'},
      );
      final result = await revoke(harness);
      expect(result.status, FnthinkPollStatus.rejectedUnsigned);
      expect(result.ok, isFalse);
      expect(result.revoked, isNull);
    });

    test('契约名单里多出第二个键 ⇒ 当场抛、不签出去', () async {
      final events = contract.raw['clientEvents'] as Map<String, Object?>;
      final revoked = events['pairRevoke'] as Map<String, Object?>;
      final widened = FnthinkContract({
        ...contract.raw,
        'clientEvents': {
          ...events,
          'pairRevoke': {
            ...revoked,
            'fields': ['peerAddress', 'level'],
          },
        },
      });
      final harness = _Harness(widened, 1_800_000_000_000);
      expect(
        () => harness.kernel().pairRevokeFields(peer: _peer, nonce: 'n1'),
        throwsStateError,
      );
      expect(
        harness.sent,
        isEmpty,
        reason:
            '"两个来源合一"靠的就是名单里就一个键。多一个键时哪个算数必须由契约明说，'
            '而不是让实现继续只收一个参数去猜',
      );
    });
  });

  group('建一条接入端点 endpointCreate（T42 第七片）', () {
    Future<FnthinkEndpointCreateResult> create(_Harness harness) =>
        harness.kernel().endpointCreate(name: '自家 NAS');

    test('target 是**本机**地址码，载荷只有 name（名单里没有 secret 也不该有）', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = const FnthinkReply(
        status: 200,
        body: {
          'endpointId': 'ep_1',
          'secret': 'ABCDEFGHIJKLMNOP2345678901',
          'postOnly': true,
        },
      );
      await create(harness);
      final fields = harness.sent.single['fields']! as Map<String, Object?>;
      expect(fields['target'], _self);
      expect(
        fields['type'],
        contract.str(['clientEvents', 'endpointCreate', 'messageType']),
      );
      final body = jsonDecode(fields['body']! as String) as Map;
      expect(body.keys.toList(), contract.endpointCreateFields);
      expect(
        contract.endpointCreateFields,
        isNot(contains('secret')),
        reason: '口令由服务端生成：设备自带等于把"选一把多强的口令"交给最不方便负责它的一端',
      );
      expect(body['name'], '自家 NAS');
    });

    test('建成 ⇒ id 与口令都在；postOnly 没回就是 null，不默认成某一种', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = const FnthinkReply(
        status: 200,
        body: {'endpointId': 'ep_1', 'secret': 'ABCDEFGHIJKLMNOP2345678901'},
      );
      final result = await create(harness);
      expect(result.ok, isTrue);
      expect(result.endpointId, 'ep_1');
      expect(result.secret, 'ABCDEFGHIJKLMNOP2345678901');
      expect(
        result.postOnly,
        isNull,
        reason: '界面那句"只收 POST"要么跟着服务端说，要么不说；猜一个方向就是替用户配错 NAS',
      );
    });

    test('200 而读不出口令 ⇒ 不算建成（不许有"建好了但抄不到"那种状态）', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = const FnthinkReply(
        status: 200,
        body: {'endpointId': 'ep_1'},
      );
      final result = await create(harness);
      expect(result.ok, isFalse, reason: '表里已经多了一行而用户手上什么都没有 —— 那行东西此后谁也打不开它');
      expect(result.reason, 'endpoint-create-unparsable-ack');
      expect(result.secret, isNull);
    });

    test('口令是空串也算读不到（形状对、内容空 ⇒ 一样不认）', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = const FnthinkReply(
        status: 200,
        body: {'endpointId': 'ep_1', 'secret': ''},
      );
      final result = await create(harness);
      expect(result.ok, isFalse);
      expect(result.reason, 'endpoint-create-unparsable-ack');
    });

    test('429（到上限）⇒ 报失败而不是冒成"建好了"', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = FnthinkReply(status: code('rateLimited'), body: const {});
      final result = await create(harness);
      expect(result.status, FnthinkPollStatus.rateLimited);
      expect(result.ok, isFalse);
      expect(result.secret, isNull);
    });

    test('契约名单一旦出现 secret ⇒ 当场抛、不发出去', () async {
      final events = contract.raw['clientEvents'] as Map<String, Object?>;
      final created = events['endpointCreate'] as Map<String, Object?>;
      final widened = FnthinkContract({
        ...contract.raw,
        'clientEvents': {
          ...events,
          'endpointCreate': {
            ...created,
            'fields': ['name', 'secret'],
          },
        },
      });
      final harness = _Harness(widened, 1_800_000_000_000);
      expect(
        () => harness.kernel().endpointCreateFields(name: 'x', nonce: 'n1'),
        throwsArgumentError,
        reason: '名单里一旦出现 secret，"设备不许自带口令"这条判据在实现里就没有分支了 —— 宁可炸在这里',
      );
      expect(harness.sent, isEmpty);
    });
  });

  group('读自己名下那几把入口 endpointList（#157 第二片）', () {
    Future<FnthinkEndpointListResult> read(_Harness harness) =>
        harness.kernel().endpointList();

    test('target 是**本机**地址码，载荷是空的（一个键都不带）', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = const FnthinkReply(status: 200, body: {'endpoints': []});
      await read(harness);
      final fields = harness.sent.single['fields']! as Map<String, Object?>;
      expect(
        fields['target'],
        _self,
        reason: '这一发按 owner 过滤，主键就是签名者自己。target 换成别人 ⇒ 列的是别人的入口',
      );
      expect(
        fields['type'],
        contract.str(['clientEvents', 'endpointList', 'messageType']),
      );
      expect(
        jsonDecode(fields['body']! as String),
        isEmpty,
        reason: '契约给这一发的名单是空的。带键不叫方便，叫长出第二个读口',
      );
    });

    test('契约名单一旦不空 ⇒ 当场抛、不发出去', () async {
      final events = contract.raw['clientEvents'] as Map<String, Object?>;
      final listed = events['endpointList'] as Map<String, Object?>;
      final widened = FnthinkContract({
        ...contract.raw,
        'clientEvents': {
          ...events,
          'endpointList': {
            ...listed,
            'fields': ['includeCalls'],
          },
        },
      });
      final harness = _Harness(widened, 1_800_000_000_000);
      expect(
        () => harness.kernel().endpointListFields(nonce: 'n1'),
        throwsArgumentError,
        reason: '有人给这一发加了输入 ⇒ 必须先想清楚"谁能填"，而不是照旧发一份空载荷换一句同形 403',
      );
      expect(harness.sent, isEmpty);
    });

    test('两行都进来：已吊销的那行也在，而 usable 跟着契约说', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = const FnthinkReply(
        status: 200,
        body: {
          'endpoints': [
            {
              'id': 'ep_new',
              'name': '自家 NAS',
              'owner': _self,
              'status': 'active',
              'postOnly': true,
              'createdAt': 1_700_000_000_000,
              'lastUsedAt': 1_700_000_900_000,
            },
            {
              'id': 'ep_old',
              'name': '',
              'owner': _self,
              'status': 'revoked',
              'createdAt': 1_600_000_000_000,
            },
          ],
        },
      );
      final result = await read(harness);
      expect(result.ok, isTrue);
      expect(result.endpoints!.map((e) => e.id), ['ep_new', 'ep_old']);
      expect(result.endpoints!.first.name, '自家 NAS');
      expect(result.endpoints!.first.postOnly, isTrue);
      expect(result.endpoints!.first.createdAt, 1_700_000_000_000);
      expect(result.endpoints!.first.usable, isTrue);
      expect(
        result.endpoints!.last.usable,
        isFalse,
        reason:
            '已吊销的那行要能说出来：用户问的是"我建过哪些、哪把还不收信"，'
            '只列可用的会把"我明明建过"变成"界面说没有"',
      );
      expect(result.endpoints!.last.status, 'revoked');
      expect(
        result.endpoints!.last.postOnly,
        isNull,
        reason: '服务端没回的项不许本机替它选一个方向',
      );
    });

    test('usable 判的是契约那一个词，不是"不是 revoked"', () async {
      // 喂一份改过数的契约：可用的那一档换名字。黑名单式（`!= 'revoked'`）在这里会说谎，
      // 而它今日的表现正是 `_usableStatusWhy` 记过的那一类错 —— 没人认得的那一档照旧收信。
      final ep = contract.raw['endpoint'] as Map<String, Object?>;
      final renamed = FnthinkContract({
        ...contract.raw,
        'endpoint': {
          ...ep,
          'statuses': ['active', 'revoked', 'live_v2'],
          'usableStatus': 'live_v2',
        },
      });
      final harness = _Harness(renamed, 1_800_000_000_000);
      harness.reply = const FnthinkReply(
        status: 200,
        body: {
          'endpoints': [
            {'id': 'ep_a', 'status': 'live_v2'},
            {'id': 'ep_b', 'status': 'active'},
          ],
        },
      );
      final result = await read(harness);
      expect(result.ok, isTrue);
      expect(result.endpoints!.first.usable, isTrue);
      expect(
        result.endpoints!.last.usable,
        isFalse,
        reason: '换了名之后，旧词 active 不再是"还收信"—— 跟着契约走，不跟着字面量走',
      );
    });

    test('空列表是一次**成功**，与"没读到"分得开', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = const FnthinkReply(status: 200, body: {'endpoints': []});
      final result = await read(harness);
      expect(result.ok, isTrue);
      expect(result.endpoints, isEmpty);
      expect(result.reason, isNull);
    });

    test('服务端没回 endpoints ⇒ 失败，绝不冒成"你没有"', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = const FnthinkReply(status: 200, body: {'serverTime': 1});
      final result = await read(harness);
      expect(result.ok, isFalse, reason: '少了这个键与"列表是空的"是两件事：前者是读失败，后者是"确实没有"');
      expect(result.endpoints, isNull);
      expect(result.reason, 'endpoint-list-unparsable');
    });

    test('某一行缺 id ⇒ 整读失败，不许悄悄少画一行', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = const FnthinkReply(
        status: 200,
        body: {
          'endpoints': [
            {'id': 'ep_ok', 'status': 'active'},
            {'status': 'active'},
          ],
        },
      );
      final result = await read(harness);
      expect(result.ok, isFalse);
      expect(result.endpoints, isNull);
      expect(
        result.reason,
        'endpoint-list-unparsable:row=1',
        reason: '"我有 2 把"与"我其实有 3 把，其中一行没解析出来"在用户眼里是同一句话',
      );
    });

    test('状态不在契约词表上 ⇒ 整读失败，不认识的那一档不当成可用的', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = const FnthinkReply(
        status: 200,
        body: {
          'endpoints': [
            {'id': 'ep_x', 'status': 'frozen'},
          ],
        },
      );
      final result = await read(harness);
      expect(result.ok, isFalse);
      expect(result.reason, 'endpoint-list-unknown-status:row=0');
    });

    test('别人名下一行漏出来 ⇒ 整读失败（服务端已过滤，这里是第二道咽喉）', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = const FnthinkReply(
        status: 200,
        body: {
          'endpoints': [
            {'id': 'ep_mine', 'status': 'active', 'owner': _self},
            {'id': 'ep_theirs', 'status': 'active', 'owner': _peer},
          ],
        },
      );
      final result = await read(harness);
      expect(result.ok, isFalse);
      expect(
        result.endpoints,
        isNull,
        reason: '这一发按定义是 self-only。万一过滤那半挂了，本机也不把别人的入口画进"我的端点"',
      );
      expect(result.reason, 'endpoint-list-not-mine:row=1');
    });

    test('403 / 429 ⇒ 报那一句，不冒充一份空列表', () async {
      for (final status in [code('forbidden'), code('rateLimited')]) {
        final harness = _Harness(contract, 1_800_000_000_000);
        harness.reply = FnthinkReply(status: status, body: const {});
        final result = await read(harness);
        expect(result.ok, isFalse);
        expect(result.endpoints, isNull);
      }
    });
  });

  group('关掉一条接入端点 endpointRevoke（#157 第四片）', () {
    Future<FnthinkEndpointRevokeResult> close(
      _Harness harness, {
      String id = 'ep_7',
    }) => harness.kernel().endpointRevoke(endpointId: id);

    test('target 是**本机**地址码，载荷里是那一把 id（名单只有那一个键）', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = const FnthinkReply(
        status: 200,
        body: {'endpointId': 'ep_7', 'revoked': true},
      );
      await close(harness);
      final fields = harness.sent.single['fields']! as Map<String, Object?>;
      expect(fields['target'], _self, reason: '关闸那一发替的是自己：target 填别人 = 替别人关闸');
      expect(
        fields['type'],
        contract.str(['clientEvents', 'endpointRevoke', 'messageType']),
      );
      final body = jsonDecode(fields['body']! as String) as Map;
      expect(body.keys.toList(), contract.endpointRevokeFields);
      expect(
        contract.endpointRevokeFields,
        isNot(contains('secret')),
        reason: '吊销要证明的是"你签过名 + 你说得清关哪一把"，不是"你手里有那把口令"',
      );
      expect(body['endpointId'], 'ep_7');
    });

    test('载荷里那个键名跟着契约走（不写死 endpointId）', () async {
      // 与上一条是一对：上一条断"形状对的时候键值是那把 id"，这一条断"键名本身是从契约读的"。
      // 只喂同一份契约去比，写死与读契约当场分不出来（本仓在这类断言上砸过两次：X5、Z4）。
      final events = contract.raw['clientEvents'] as Map<String, Object?>;
      final revoked = events['endpointRevoke'] as Map<String, Object?>;
      final renamed = FnthinkContract({
        ...contract.raw,
        'clientEvents': {
          ...events,
          'endpointRevoke': {
            ...revoked,
            'fields': ['whichEndpoint'],
          },
        },
      });
      final harness = _Harness(renamed, 1_800_000_000_000);
      final fields = harness.kernel().endpointRevokeFields(
        endpointId: 'ep_7',
        nonce: 'n1',
      );
      final body = jsonDecode(fields['body']! as String) as Map;
      expect(body.keys.toList(), [
        'whichEndpoint',
      ], reason: '服务端逐字节比那份名单：键名写死在这里，契约改名那天这一发就只剩一句同形 403');
      expect(body['whichEndpoint'], 'ep_7');
    });

    test('revoked:false 是一次**成功**（那把本来就不收了，幂等）', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = const FnthinkReply(
        status: 200,
        body: {'endpointId': 'ep_7', 'revoked': false},
      );
      final result = await close(harness);
      expect(result.ok, isTrue);
      expect(result.revoked, isFalse);
    });

    test('200 而 revoked 不是布尔 ⇒ 不算关掉（宁可界面上还说"没关掉"）', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = const FnthinkReply(
        status: 200,
        body: {'endpointId': 'ep_7', 'revoked': 'yes'},
      );
      final result = await close(harness);
      expect(
        result.ok,
        isFalse,
        reason: '"已关闭"说错一次的代价是 NAS 还在往一把仍然收信的入口推，而用户以为停了',
      );
      expect(result.reason, 'endpoint-revoke-unparsable-ack');
    });

    test('结论里带的是**调用方给的那一把**，不是服务端回的那一个', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = const FnthinkReply(
        status: 200,
        body: {'endpointId': 'ep_other', 'revoked': true},
      );
      final result = await close(harness, id: 'ep_7');
      expect(
        result.endpointId,
        'ep_7',
        reason:
            '界面那句"你关掉了 ep_7"必须跟着用户点的那一行；跟着响应走，'
            '一句回错 id 就能把另一把说成已关',
      );
    });

    test('403 ⇒ 没关掉、revoked 是空的（本机一份列表都不改）', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = FnthinkReply(status: code('forbidden'), body: const {});
      final result = await close(harness);
      expect(result.ok, isFalse);
      expect(result.revoked, isNull);
    });

    test('契约名单一旦多出第二个键 ⇒ 当场抛、不签出去', () async {
      final events = contract.raw['clientEvents'] as Map<String, Object?>;
      final revoked = events['endpointRevoke'] as Map<String, Object?>;
      final widened = FnthinkContract({
        ...contract.raw,
        'clientEvents': {
          ...events,
          'endpointRevoke': {
            ...revoked,
            'fields': ['endpointId', 'note'],
          },
        },
      });
      final harness = _Harness(widened, 1_800_000_000_000);
      expect(
        () => harness.kernel().endpointRevokeFields(
          endpointId: 'ep_7',
          nonce: 'n1',
        ),
        throwsStateError,
        reason: '名单多一键时，"关哪一把"与"替谁关"就成两件事 —— 必须由契约明说哪个算数',
      );
      expect(harness.sent, isEmpty);
    });
  });

  group('换一条端点的口令 endpointRotate（#157 第六片）', () {
    Future<FnthinkEndpointRotateResult> swap(
      _Harness harness, {
      String id = 'ep_7',
    }) => harness.kernel().endpointRotate(endpointId: id);

    test('target 是**本机**地址码，载荷只有那一把 id（宽限期不在此参数化）', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = const FnthinkReply(
        status: 200,
        body: {
          'endpointId': 'ep_7',
          'rotated': true,
          'secret': 'ZZZ7RABQKPZ3STVWX234',
          'rotatingUntil': 1800003600000,
        },
      );
      await swap(harness);
      final fields = harness.sent.single['fields']! as Map<String, Object?>;
      expect(
        fields['target'],
        _self,
        reason: '替别人换口令 = 拿到别人那条入口的新明文，拿着它就能冒充那台设备',
      );
      expect(
        fields['type'],
        contract.str(['clientEvents', 'endpointRotate', 'messageType']),
      );
      final body = jsonDecode(fields['body']! as String) as Map;
      expect(
        body.keys.toList(),
        contract.endpointRotateFields,
        reason: '键名从契约读：写死那天就是"契约改名而设备照旧发一份旧键"的开始',
      );
      expect(body.length, 1, reason: '载荷里一旦能传 graceSeconds，宽限期就从安全属性变成客户端偏好');
      expect(body['endpointId'], 'ep_7');
    });

    test('载荷里那个键名跟着契约走（不写死 endpointId）', () async {
      // 与 revoke 那一组同一条：断言不能拿同一份契约比实现（写死与读契约当场分不出来）。
      // RC1 第一次就是在这里 NO FAILURE 的 —— 轮换这组当初照抄了 revoke 的弱断言。
      final events = contract.raw['clientEvents'] as Map<String, Object?>;
      final rotated = events['endpointRotate'] as Map<String, Object?>;
      final renamed = FnthinkContract({
        ...contract.raw,
        'clientEvents': {
          ...events,
          'endpointRotate': {
            ...rotated,
            'fields': ['whichEndpoint'],
          },
        },
      });
      final harness = _Harness(renamed, 1_800_000_000_000);
      final fields = harness.kernel().endpointRotateFields(
        endpointId: 'ep_7',
        nonce: 'n1',
      );
      final body = jsonDecode(fields['body']! as String) as Map;
      expect(body.keys.toList(), [
        'whichEndpoint',
      ], reason: '服务端逐字节比那份名单：键名写死在这里，契约改名那天这一发只剩一句同形 403');
      expect(body['whichEndpoint'], 'ep_7');
    });

    test('换成 ⇒ 新口令与旧口令的死刑日期都在', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = const FnthinkReply(
        status: 200,
        body: {
          'endpointId': 'ep_7',
          'rotated': true,
          'secret': 'ZZZ7RABQKPZ3STVWX234',
          'rotatingUntil': 1800003600000,
        },
      );
      final result = await swap(harness);
      expect(result.ok, isTrue);
      expect(result.exchanged, isTrue);
      expect(result.secret, 'ZZZ7RABQKPZ3STVWX234');
      expect(result.rotatingUntil, 1800003600000);
      expect(result.endpointId, 'ep_7');
    });

    test('rotated:true 而读不出口令 ⇒ 不算换成，且 reason 单独一个', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = const FnthinkReply(
        status: 200,
        body: {'endpointId': 'ep_7', 'rotated': true},
      );
      final result = await swap(harness);
      expect(
        result.exchanged,
        isFalse,
        reason:
            '这一档表里已经换掉了而用户手上什么都没有：NAS 从此 401，'
            '而没人能说出新口令 —— 比"没换成"更糟，所以要单独一个 reason 说清',
      );
      expect(result.ok, isFalse);
      expect(result.reason, 'endpoint-rotate-missing-new-secret');
      expect(result.rotated, isTrue, reason: '但"服务端说换了"这件事要原样带回去，不许抹平');
    });

    test('rotated:false 是一次**看得懂的答复**（那把已停，换口令不会复活它）', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = const FnthinkReply(
        status: 200,
        body: {'endpointId': 'ep_7', 'rotated': false},
      );
      final result = await swap(harness);
      expect(result.ok, isTrue);
      expect(result.exchanged, isFalse);
      expect(result.secret, isNull);
      expect(result.reason, isNull);
    });

    test('200 而 rotated 不是布尔 ⇒ 什么都没说（宁可报看不懂）', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = const FnthinkReply(
        status: 200,
        body: {'endpointId': 'ep_7', 'rotated': 'ok'},
      );
      final result = await swap(harness);
      expect(result.ok, isFalse);
      expect(result.reason, 'endpoint-rotate-unparsable-ack');
    });

    test('403 ⇒ 没换成（本机一份列表都不改）', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = FnthinkReply(status: code('forbidden'), body: const {});
      final result = await swap(harness);
      expect(result.ok, isFalse);
      expect(result.rotated, isNull);
      expect(result.secret, isNull);
    });

    test('契约名单一旦多出第二个键 ⇒ 当场抛、不签出去', () async {
      final events = contract.raw['clientEvents'] as Map<String, Object?>;
      final rotated = events['endpointRotate'] as Map<String, Object?>;
      final widened = FnthinkContract({
        ...contract.raw,
        'clientEvents': {
          ...events,
          'endpointRotate': {
            ...rotated,
            'fields': ['endpointId', 'graceSeconds'],
          },
        },
      });
      final harness = _Harness(widened, 1_800_000_000_000);
      expect(
        () => harness.kernel().endpointRotateFields(
          endpointId: 'ep_7',
          nonce: 'n1',
        ),
        throwsStateError,
        reason: '名单多一键那天，"换哪一把"与"换成什么规矩"就成两件事 —— 必须由契约先明说哪个算数',
      );
      expect(harness.sent, isEmpty);
    });
  });

  group('register：设备自登记（#177 —— 其余每一发的共同前置）', () {
    const publicKey = 'cHVibGljLWtleS1vZi10aGlzLWRldmljZQ==';

    Map<String, Object?> okRegister({
      String address = _self,
      String name = 'MEIZU 21',
      int peers = 0,
    }) => {
      'addressCode': address,
      'name': name,
      'peersGrantingMe': peers,
      'serverTime': 1800000000000,
    };

    test('形状：顶层带 publicKey 与 name，被签的仍是契约那六个键（公钥不进签名）', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = FnthinkReply(status: 200, body: okRegister());

      final result = await harness.kernel().register(
        publicKey: publicKey,
        name: 'MEIZU 21',
      );

      expect(result.status, FnthinkPollStatus.ok);
      expect(result.addressCode, _self);
      expect(result.name, 'MEIZU 21');
      expect(result.peersGrantingMe, 0, reason: '登记不给授权：0 是正常值（"还没人配对我"），不是失败');

      final envelope = harness.sent.single;
      expect(
        envelope['publicKey'],
        publicKey,
        reason: '自带公钥是这一类的形状（verifyAgainst=presented-public-key）：服务端拿它验这一发',
      );
      expect(envelope['name'], 'MEIZU 21');
      final fields = envelope['fields']! as Map<String, Object?>;
      expect(
        fields['type'],
        contract.str(['clientEvents', 'register', 'messageType']),
      );
      expect(
        fields['type'],
        isNot(contract.str(['clientEvents', 'poll', 'messageType'])),
        reason: '借 poll 那个词 ⇒ 服务端按 poll 的路子判这一发，换回一句同形的 403',
      );
      expect(fields['target'], _self, reason: 'self-only：target 必须是本机自己的地址码');
      expect(fields['body'], '');
      // 公钥与名字**不进**被签的字节：服务端拿顶层那把验签、再按契约顺序重算 fields ——
      // 并进载荷会让服务端算出的字节多出两段，于是每一发都判"签名不对"。
      expect(
        harness.signedBytes.single.contains(publicKey),
        isFalse,
        reason: '公钥进了签名载荷 ⇒ 服务端重算的字节里没有它 ⇒ 永远换回同形的 403',
      );
      expect(
        harness.signedBytes.single.split('\u0000').length,
        contract.canonicalOrder.length,
        reason: '被签的就是契约那六个键，一个不多一个不少',
      );
    });

    test('200 但没回地址码 ⇒ 不算登记成功（与 pairArm"没有过期时间就不算"同形）', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = const FnthinkReply(status: 200, body: {'name': 'x'});

      final result = await harness.kernel().register(
        publicKey: publicKey,
        name: 'n',
      );

      expect(result.status, FnthinkPollStatus.failed);
      expect(result.reason, 'register-acked-without-address');
      expect(
        result.addressCode,
        isNull,
        reason: '服务端没认下这一台就没有地址码可回；当成"成功"会让后面每一发的 403 变得莫名其妙',
      );
    });

    test('403 ⇒ rejectedUnsigned：这一档才是"服务端不认本机"的原话', () async {
      final harness = _Harness(contract, 1_800_000_000_000);
      harness.reply = FnthinkReply(
        status: code('forbidden'),
        body: const {'receipt': 'rejected_unsigned'},
      );

      final result = await harness.kernel().register(
        publicKey: publicKey,
        name: 'n',
      );

      expect(result.status, FnthinkPollStatus.rejectedUnsigned);
      expect(result.reason, 'rejected-unsigned');
    });

    test('传输异常 ⇒ transportError，且什么都不改（与 poll 同一条纪律）', () async {
      final harness = _Harness(contract, 1_800_000_000_000)
        ..throws = const SocketException('no route');
      final kernel = harness.kernel();

      final result = await kernel.register(publicKey: publicKey, name: 'n');

      expect(result.status, FnthinkPollStatus.transportError);
      expect(
        kernel.calibrated,
        isFalse,
        reason: '一次连不上不说明任何关于服务端的事，不该顺手把它当成"校准过"',
      );
    });

    test('登记常常是这台机器的第一发 ⇒ 它顺手学一次服务端时间', () async {
      final harness = _Harness(contract, 1_800_000_000_000)..latencyMs = 200;
      harness.reply = FnthinkReply(status: 200, body: okRegister());
      final kernel = harness.kernel();
      expect(kernel.calibrated, isFalse);

      await kernel.register(publicKey: publicKey, name: 'n');

      expect(kernel.calibrated, isTrue);
      expect(
        kernel.offsetMs,
        -100,
        reason: '偏移按"发出与收到的中点"学（往返 200ms ⇒ 中点比服务端慢 100ms）',
      );
    });
  });
}
