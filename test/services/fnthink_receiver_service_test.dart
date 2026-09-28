import 'dart:convert';
import 'dart:io';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notice_transmit/services/fnthink_receiver_service.dart';

/// #126 第二片：设备侧收货的**接线层**（传输事实），判据本身在 `receive_kernel.dart`。
///
/// 这一片要钉的四件事都属于"接上线才现形"的那类：
///  ① URL 只由契约 `transport.apiPaths` 说一次 —— 两边各拼一份时，改路径不会报错，
///     只会变成"服务端换了门、客户端还在敲旧门"，而这一层的失败一律同形；
///  ② 明文 base 在**装配时**就拒，不等发出去；
///  ③ 签名出不来 ≠ 网络不通：必须本地短路，一个未签名的包都不许离机；
///  ④ `Retry-After` 与非 JSON 响应体（反代给的 HTML 错误页）不许把分类冲掉。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FnthinkContract contract;
  const address = '8K3FJ6QPTM9WZ4VHNS';
  const base = 'https://push.example.com';

  setUp(() => contract = FnthinkContract.readFile());

  FnthinkReceiverService build(
    FnthinkContract c,
    _Recorder rec,
    _Signer signer, {
    String url = base,
  }) => FnthinkReceiverService(
    contract: c,
    baseUri: Uri.parse(url),
    signer: signer,
    addressCode: address,
    client: rec.client(),
  );

  group('URL 只由契约说一次', () {
    test('poll 与 ack 各发到自己那条声明过的路径', () async {
      final rec = _Recorder(
        scripts: [
          '{"messages":[{"messageId":"m_1","type":"notice","title":"t","body":"b"}],'
              '"receipts":[],"pending":0,"serverTime":1800000000000}',
          '{"receipt":"delivered","state":"delivered"}',
        ],
      );
      final service = build(contract, rec, _Signer());
      final polled = await service.pollOnce();
      expect(polled.ok, isTrue);
      expect(polled.messages.single.messageId, 'm_1');
      expect(rec.requests.first.url.path, contract.apiPath('poll'));

      final acked = await service.ack(messageId: 'm_1', result: 'displayed');
      expect(acked.status, FnthinkPollStatus.ok);
      expect(rec.requests.last.url.path, contract.apiPath('ack'));
      // host 与 scheme 来自传进来的 base，不是写死的某个官方实例
      expect(rec.requests.first.url.host, 'push.example.com');
    });

    test('实现里不出现第二条拼出来的路径（只允许经契约取）', () {
      final code = File('lib/services/fnthink_receiver_service.dart')
          .readAsStringSync()
          .split('\n')
          .where(
            (String line) =>
                !line.trim().startsWith('//') && !line.trim().startsWith('///'),
          )
          .join('\n');
      expect(code.contains('/api/fnthink/'), isFalse);
      expect(code.contains('apiPath'), isTrue);
    });

    test('契约缺那条路径 ⇒ 抛，而不是退回一个猜出来的 URL', () async {
      final mutated = FnthinkContract({
        ...contract.raw,
        'transport': {
          ...(contract.raw['transport']! as Map<String, Object?>),
          'apiPaths': {
            ...(contract.raw['transport']! as Map<String, Object?>)['apiPaths']!
                as Map<String, Object?>,
          }..remove('poll'),
        },
      });
      final rec = _Recorder();
      // 装配期就抛（ArgumentError）—— 不是第一次轮询时被内核的 catch 归成"传输异常"，
      // 那会把"契约与实现不匹配"伪装成一次网络抖动。
      expect(
        () => build(mutated, rec, _Signer()),
        throwsA(isA<ArgumentError>()),
      );
      expect(rec.requests, isEmpty); // 一个请求都没发：敲错门比不敲更难排查
    });
  });

  group('装配与失败的分类', () {
    test('契约说 httpsOnly 而 base 是 http ⇒ 装配时就抛（一个请求都不发）', () {
      final rec = _Recorder();
      expect(
        () => build(contract, rec, _Signer(), url: 'http://push.example.com'),
        throwsA(isA<ArgumentError>()),
      );
      expect(rec.requests, isEmpty);
    });

    test('签名不可用 ⇒ 本地短路成 signing-unavailable，零请求', () async {
      final rec = _Recorder();
      final service = build(contract, rec, _Signer(available: false));
      final result = await service.pollOnce();
      expect(result.ok, isFalse);
      expect(result.reason, 'signing-unavailable');
      expect(rec.requests, isEmpty);
      final acked = await service.ack(messageId: 'm_1', result: 'displayed');
      expect(acked.reason, 'signing-unavailable');
      expect(rec.requests, isEmpty); // 未签名的包不许离机
    });

    test('429 的 Retry-After 一路传到 nextDelay；没有这个头时不编数字', () async {
      final limited = contract.statusCodes['rateLimited']!;
      final rec = _Recorder(
        status: limited,
        headers: const {'retry-after': '17'},
        scripts: ['{}'],
      );
      final result = await build(contract, rec, _Signer()).pollOnce();
      expect(result.status, FnthinkPollStatus.rateLimited);
      expect(result.nextDelay, const Duration(seconds: 17));

      final noHeader = _Recorder(
        status: limited,
        headers: const {},
        scripts: ['{}'],
      );
      final fallback = await build(contract, noHeader, _Signer()).pollOnce();
      // 没给就不许当 0（那会变成"立刻重试"的洪水），缺省回落到常规节奏
      expect(fallback.nextDelay, greaterThan(Duration.zero));
    });

    test('反代回 HTML 的错误页 ⇒ 不崩，按状态分类且不带任何内容', () async {
      final rec = _Recorder(
        status: 502,
        scripts: ['<html>502 Bad Gateway</html>'],
      );
      final result = await build(contract, rec, _Signer()).pollOnce();
      expect(result.ok, isFalse);
      expect(result.status, FnthinkPollStatus.failed);
      expect(result.reason, contains('502'));
    });

    test('请求体恰好三键，而 summary 里不含签名', () async {
      final rec = _Recorder();
      final service = build(contract, rec, _Signer());
      final result = await service.pollOnce();
      final decoded =
          jsonDecode(rec.requests.first.body) as Map<String, Object?>;
      expect(decoded.keys.toSet(), {'sender', 'signature', 'fields'});
      expect(decoded['sender'], address);
      expect(
        (decoded['fields']! as Map).keys.toSet(),
        contract.canonicalOrder.toSet(),
      );
      expect(result.summary, isNot(contains('${decoded['signature']}')));
      // Content-Type 必须是 json：服务端的体积闸与解析器都按它走
      expect(
        rec.requests.first.headers['content-type'],
        contains('application/json'),
      );
    });

    test('nonce 50 发都不重（服务端去重窗口 900 秒，撞一次就是把自己判成重放）', () async {
      final rec = _Recorder();
      final service = build(contract, rec, _Signer());
      for (var i = 0; i < 50; i++) {
        await service.pollOnce();
      }
      final nonces = rec.requests
          .map(
            (r) => (jsonDecode(r.body)['fields']! as Map)['nonce']! as String,
          )
          .toList();
      expect(nonces.length, 50);
      // 断"不重"而不是断"看起来随机"：计数式 nonce 重启后会从同一个起点重来，
      // 而那正好落进服务端还记着的窗口里 —— 唯一性才是这条判据的内容。
      expect(nonces.toSet().length, 50);
      for (final nonce in nonces) {
        expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(nonce), isTrue);
        expect(nonce.length, 16);
      }
    });

    test('学到 serverTime 之后，下一发的 ts 用的是校正后的时间', () async {
      final local = DateTime.now().toUtc().millisecondsSinceEpoch;
      final rec = _Recorder(
        scripts: [
          jsonEncode({
            'messages': [],
            'receipts': [],
            'pending': 0,
            // 服务端比本机快一小时：第一发签完才知道，第二发就该带上偏移
            'serverTime': local + 3600 * 1000,
          }),
          '{"messages":[],"receipts":[],"pending":0}',
        ],
      );
      final service = build(contract, rec, _Signer());
      final first = await service.pollOnce();
      expect(first.signedWhileUncalibrated, isTrue);
      final second = await service.pollOnce();
      expect(second.signedWhileUncalibrated, isFalse);
      final ts = int.parse(
        (jsonDecode(rec.requests.last.body)['fields']! as Map)['ts']! as String,
      );
      final driftSeconds = (ts - local ~/ 1000).abs();
      // 秒级偏移≈一小时（留余量给执行耗时）。漂一小时还不校，就是每条都 410。
      expect(driftSeconds, greaterThan(3500));
      expect(driftSeconds, lessThan(3700));
    });
  });
}

/// 记下每一次请求，并按脚本回响应。
class _Recorder {
  _Recorder({
    List<String>? scripts,
    this.status = 200,
    this.headers = const {'content-type': 'application/json'},
  }) : scripts = scripts ?? ['{"messages":[],"receipts":[],"pending":0}'];

  final List<http.Request> requests = [];
  List<String> scripts;
  int status;
  Map<String, String> headers;

  MockClient client() => MockClient((http.Request request) async {
    requests.add(request);
    return http.Response(
      scripts[(requests.length - 1) % scripts.length],
      status,
      headers: headers,
    );
  });
}

/// 假的签名注入点：既能演"签得出来"，也能演"这台机器的 Keystore 用不了"。
class _Signer implements FnthinkIdentitySigner {
  _Signer({this.available = true});

  bool available;
  final List<String> signed = [];

  @override
  Future<String> call(List<int> bytes) async {
    if (!available) throw StateError('本机签不出来');
    signed.add(utf8.decode(bytes));
    return base64Encode(List<int>.filled(64, 7));
  }

  @override
  Future<bool> probe() async => available;
}
