import 'dart:convert';
import 'dart:io';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:test/test.dart';

/// 设备侧发送内核（§4 第 10 条：配对设备逐条签名投给另一台设备）的**判据**用例。
///
/// 这里一个真 HTTP 都没有：签名与传输都注入。为的是把三种失败分开测
/// （本机签不出来 / 网络不通 / 协议拒绝）—— 它们给用户的下一句完全不同。
///
/// ⚠ 期望值的出处：wire 那一串取自共享向量表（`titleEnvelope` 的 `te-plain` 行），
/// 不在测试里再算一遍 —— 拿实现读的那份真值去断实现，"写死前缀"与"读契约前缀"就分不出来。
void main() {
  final contract = FnthinkContract.readFile();
  final vectors =
      jsonDecode(File(fnthinkVectorsFile()).readAsStringSync())
          as Map<String, Object?>;
  final plainRow =
      (((vectors['titleEnvelope'] as Map<String, Object?>)['rows']
                  as List<Object?>)
              .cast<Map<String, Object?>>())
          .firstWhere((r) => r['id'] == 'te-plain');
  final plainWire =
      '${(plainRow['expect'] as Map<String, Object?>)['wireBody']}';

  const self = '8K3FJ6QPTM9WZ4VHNS';
  const peer = '7YD4RKQPBM8XZ3VHNT';
  final queued = contract.statusCodes['queued']!;

  Map<String, Object?> loaded() =>
      jsonDecode(File(fnthinkContractFile()).readAsStringSync())
          as Map<String, Object?>;

  Future<FnthinkSendResult> sendOne(
    _Harness h, {
    String title = '标题',
    String text = '正文',
    String type = 'notice',
    String target = peer,
  }) => h.kernel.send(target: target, type: type, title: title, text: text);

  group('拼出来的那一串', () {
    test('顶层只有 sender / signature / fields —— 没有 title（它一定被服务端丢掉）', () async {
      final h = _Harness(
        contract: contract,
        addressCode: self,
        replies: [
          FnthinkReply(status: queued, body: {'messageId': 'm_1'}),
        ],
      );
      await sendOne(h, title: '客厅温度', text: '30℃，请检查空调');
      expect(h.sentKeys, unorderedEquals(['sender', 'signature', 'fields']));
      expect(h.sentContainsTitle, isFalse);
    });

    test('标题进的是**已签的 body**：签字节的最后一段就是向量表里那一串 wireBody', () async {
      final h = _Harness(
        contract: contract,
        addressCode: self,
        replies: [
          FnthinkReply(status: queued, body: {'messageId': 'm_1'}),
        ],
      );
      await sendOne(h, title: '客厅温度', text: '30℃，请检查空调');
      final segments = utf8
          .decode(h.signedBytes!)
          .split(contract.signatureSeparator);
      expect(segments.last, plainWire);
      expect(h.sentField('body'), plainWire);
      expect(segments.length, contract.canonicalOrder.length);
    });

    test('没有标题就不套信封：body 原样，签字节的段数不变', () async {
      final h = _Harness(
        contract: contract,
        addressCode: self,
        replies: [
          FnthinkReply(status: queued, body: {'messageId': 'm_1'}),
        ],
      );
      await sendOne(h, title: '', text: '只有正文一行');
      expect(h.sentField('body'), '只有正文一行');
      expect(h.sentField('body'), isNot(contains(contract.deviceTitlePrefix)));
    });

    test('字段名单由契约说：canonicalOrder 多出第七个 ⇒ 当场抛，而不是照旧发六段', () async {
      // 这一条是"读契约"与"写死六个键"之间唯一的分界：写死的实现照旧拼六段并签出去，
      // 服务端只回一句同形的 403，而本机日志看起来像"对端坏了"。
      final doc = loaded();
      final signature = Map<String, Object?>.from(
        doc['signature']! as Map<String, Object?>,
      );
      signature['canonicalOrder'] = [
        ...(signature['canonicalOrder']! as List<Object?>),
        'item',
      ];
      doc['signature'] = signature;
      final h = _Harness(
        contract: FnthinkContract(doc),
        addressCode: self,
        replies: [FnthinkReply(status: queued)],
      );
      await expectLater(
        sendOne(h, title: '', text: 'x'),
        throwsA(isA<ArgumentError>()),
      );
      expect(h.sentCount, 0);
    });

    test('分隔符出现在标题 / 正文 / target 里 ⇒ 三种位置同形（都是当场拒，不发出去）', () async {
      final h = _Harness(
        contract: contract,
        addressCode: self,
        replies: [FnthinkReply(status: queued)],
      );
      final sep = contract.signatureSeparator;
      await expectLater(
        sendOne(h, title: 'a${sep}b', text: 'x'),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        sendOne(h, title: '', text: 'a${sep}b'),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        sendOne(h, title: '', text: 'x', target: 'x$sep'),
        throwsA(isA<ArgumentError>()),
      );
      expect(h.sentCount, 0);
    });

    test('type 不在契约的能力词表 ⇒ 当场说清（不发一次注定 403 的往返）', () async {
      final h = _Harness(
        contract: contract,
        addressCode: self,
        replies: [FnthinkReply(status: queued)],
      );
      await expectLater(
        sendOne(h, type: 'poll'),
        throwsA(isA<ArgumentError>()),
      );
      expect(h.sentCount, 0);
    });
  });

  group('回执的六种说法', () {
    test(
      '202 + messageId ⇒ accepted，并把 action 与 evicted 带回来（发送端看得见被挤掉的那几条）',
      () async {
        final h = _Harness(
          contract: contract,
          addressCode: self,
          replies: [
            FnthinkReply(
              status: queued,
              body: {
                'messageId': 'm_42',
                'receipt': 'queued',
                'action': 'refreshed',
                'evicted': ['m_1', 'm_2'],
              },
            ),
          ],
        );
        final r = await sendOne(h);
        expect(r.status, FnthinkSendStatus.accepted);
        expect(r.messageId, 'm_42');
        expect(r.action, 'refreshed');
        expect(r.evicted, ['m_1', 'm_2']);
      },
    );

    test('202 而没有 messageId ⇒ 不算收下（不猜一个 id 去追状态）', () async {
      final h = _Harness(
        contract: contract,
        addressCode: self,
        replies: [
          FnthinkReply(status: queued, body: {'receipt': 'queued'}),
        ],
      );
      expect((await sendOne(h)).status, FnthinkSendStatus.unparseable);
    });

    test('403 分两种：回执词是契约里"没认你这把钥匙"那一个才算签名问题', () async {
      Future<FnthinkSendStatus> of(String receipt) async {
        final h = _Harness(
          contract: contract,
          addressCode: self,
          replies: [
            FnthinkReply(
              status: contract.statusCodes['forbidden']!,
              body: {'receipt': receipt},
            ),
          ],
        );
        return (await sendOne(h)).status;
      }

      expect(
        await of(contract.unsignedReceipt),
        FnthinkSendStatus.rejectedUnsigned,
      );
      expect(
        await of('rejected_capability'),
        FnthinkSendStatus.rejectedCapability,
      );
      // 词表外的一个 receipt 不许被升级成"能力不足"：那等于把没见过的东西认成见过的。
      expect(await of('not-in-vocabulary'), FnthinkSendStatus.rejectedUnsigned);
    });

    test('409 / 410 / 429 各走各的下一步，429 把 Retry-After 带回来', () async {
      Future<FnthinkSendResult> of(int code, {int? retryAfter}) async {
        final h = _Harness(
          contract: contract,
          addressCode: self,
          replies: [FnthinkReply(status: code, retryAfterSeconds: retryAfter)],
        );
        return sendOne(h);
      }

      expect(
        (await of(contract.statusCodes['duplicate']!)).status,
        FnthinkSendStatus.replayed,
      );
      expect(
        (await of(contract.statusCodes['expired']!)).status,
        FnthinkSendStatus.needsCalibration,
      );
      final limited = await of(
        contract.statusCodes['rateLimited']!,
        retryAfter: 30,
      );
      expect(limited.status, FnthinkSendStatus.rateLimited);
      expect(limited.retryAfterSeconds, 30);
      // 状态码不在契约那张表上（500 是最常见的一种）⇒ unparseable：内核不许替服务端宣布结局。
      expect((await of(500)).status, FnthinkSendStatus.unparseable);
    });

    test('传输异常 ⇒ transportError，而且这一发确实出去了（什么都没发生就是什么都没发生）', () async {
      final h = _Harness(
        contract: contract,
        addressCode: self,
        transportThrows: true,
      );
      final r = await sendOne(h, title: '', text: 'x');
      expect(r.status, FnthinkSendStatus.transportError);
      expect(r.messageId, isNull);
      expect(h.attemptedCount, 1);
    });

    test('原生不肯签 ⇒ signingUnavailable，绝不报成"网络不通"（那是让用户一直等一个不会自己好的东西）', () async {
      final h = _Harness(
        contract: contract,
        addressCode: self,
        signerThrows: true,
      );
      final r = await sendOne(h, title: '', text: 'x');
      expect(r.status, FnthinkSendStatus.signingUnavailable);
      expect(h.attemptedCount, 0);
    });
  });

  group('时钟、nonce 与装配', () {
    test('ts 从外面给：内核自己不造偏移（偏移只有收货那一侧学得会）', () async {
      final h = _Harness(
        contract: contract,
        addressCode: self,
        replies: [
          FnthinkReply(status: queued, body: {'messageId': 'm'}),
        ],
        ts: '1700000000',
      );
      await sendOne(h, title: '', text: 'x');
      expect(h.sentField('ts'), '1700000000');
    });

    test('nonce 用注入的工厂，两次不许相同；没注入时也不许相同', () async {
      var n = 0;
      final h = _Harness(
        contract: contract,
        addressCode: self,
        replies: [
          FnthinkReply(status: queued, body: {'messageId': 'm'}),
          FnthinkReply(status: queued, body: {'messageId': 'm'}),
        ],
        nonceFactory: () => 'n-${++n}',
      );
      await sendOne(h, title: '', text: 'a');
      await sendOne(h, title: '', text: 'b');
      expect(h.nonces, ['n-1', 'n-2']);

      final fallback = _Harness(
        contract: contract,
        addressCode: self,
        replies: [
          FnthinkReply(status: queued, body: {'messageId': 'm'}),
          FnthinkReply(status: queued, body: {'messageId': 'm'}),
        ],
      );
      await sendOne(fallback, title: '', text: 'a');
      await sendOne(fallback, title: '', text: 'b');
      expect(fallback.nonces.first, isNot(fallback.nonces.last));
    });

    test('契约没声明 message 那条路径 ⇒ 构造期就抛（装配期炸与运行时炸是两回事）', () {
      final doc = loaded();
      final transport = Map<String, Object?>.from(
        doc['transport']! as Map<String, Object?>,
      );
      final paths = Map<String, Object?>.from(
        transport['apiPaths']! as Map<String, Object?>,
      );
      paths.remove('message');
      transport['apiPaths'] = paths;
      doc['transport'] = transport;
      expect(
        () => FnthinkSendKernel(
          contract: FnthinkContract(doc),
          addressCode: self,
          signer: (_) async => 'sig',
          transport: (_) async => FnthinkReply(status: 202),
          signedTimestamp: () => '1700000000',
        ),
        throwsStateError,
      );
    });
  });
}

class _Harness {
  _Harness({
    required FnthinkContract contract,
    required String addressCode,
    List<FnthinkReply> replies = const [],
    this.transportThrows = false,
    this.signerThrows = false,
    this.nonceFactory,
    String? ts,
  }) {
    kernel = FnthinkSendKernel(
      contract: contract,
      addressCode: addressCode,
      nonceFactory: nonceFactory,
      signedTimestamp: () => ts ?? '1700000000',
      signer: (bytes) async {
        if (signerThrows) throw StateError('keystore 不肯签');
        signedBytes = bytes;
        return 'sig';
      },
      transport: (envelope) async {
        attempted += 1;
        history.add(envelope);
        if (transportThrows) throw StateError('连不上');
        return replies.isEmpty
            ? FnthinkReply(status: 202, body: {'messageId': 'm'})
            : replies[history.length - 1];
      },
    );
  }

  late final FnthinkSendKernel kernel;
  final bool transportThrows;
  final bool signerThrows;
  final String Function()? nonceFactory;

  final List<Map<String, Object?>> history = [];
  int attempted = 0;
  List<int>? signedBytes;

  int get sentCount => history.length;
  int get attemptedCount => attempted;
  Map<String, Object?> get sent => history.last;
  List<String> get sentKeys => sent.keys.map((e) => '$e').toList();
  bool get sentContainsTitle => sent.containsKey('title');
  Object? sentField(String key) =>
      (sent['fields']! as Map<String, Object?>)[key];
  List<String> get nonces => [
    for (final e in history)
      '${(e['fields']! as Map<String, Object?>)['nonce']}',
  ];
}
