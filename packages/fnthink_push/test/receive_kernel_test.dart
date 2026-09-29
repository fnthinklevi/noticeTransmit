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
    signer: (bytes) async => 'sig-${bytes.length}',
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
}
