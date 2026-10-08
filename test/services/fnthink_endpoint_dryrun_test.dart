import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notice_transmit/services/fnthink_endpoint_dryrun.dart';

/// `postFnthinkEndpointDryRun`（T106 片①b 格2）那一发本身。
///
/// 这一族最值得钉的两件事：**结论键只从契约读**（不写死 `ready`），
/// 以及**"没问到"绝不写成红**（非 200 是 429／404／反代拦下来的，跟"路断了"没关系）。
void main() {
  const secret = 'AB12CD34EF56GH78JK90MN23PQ45RS67';
  final probeUrl = Uri.parse(
    'https://push.example.com/api/fnthink/p/e_1/probe',
  );
  final contract = FnthinkContract.readFile();
  final readyField = contract.probeReadyField;

  /// 用桩发一发，顺便把送出去的那个请求交回来（断言头与 URL 用）。
  Future<(FnthinkProbeResult, http.Request)> run(
    http.Response Function() reply, {
    FnthinkContract? withContract,
    String body = 'x',
  }) async {
    late final http.Request sent;
    final result = await postFnthinkEndpointDryRun(
      contract: withContract ?? contract,
      probeUrl: probeUrl,
      secret: body,
      client: MockClient((req) async {
        sent = req;
        return reply();
      }),
    );
    return (result, sent);
  }

  group('绿与红（服务端答了才算结论）', () {
    test('ready:true ⇒ 结论是真布尔，而键名取自契约（不在这里写死 ready）', () async {
      final (result, sent) = await run(
        () =>
            http.Response(jsonEncode({readyField: true, 'serverTime': 1}), 200),
      );
      expect(result.ready, isTrue);
      expect(sent.url, probeUrl);
    });

    test('ready:false ⇒ 照实回 false（这一族的红灯承诺过是确凿的）', () async {
      final (result, _) = await run(
        () => http.Response(jsonEncode({readyField: false}), 200),
      );
      expect(result.ready, isFalse);
    });

    test('契约把结论键改名 ⇒ 实现跟着改（两处各写一个名字就是设备永远读到 null）', () async {
      final renamed = FnthinkContract.parse(
        jsonEncode({
          ...contract.raw,
          'clientEvents': {
            ...contract.raw['clientEvents']! as Map<String, Object?>,
            'probe': {
              ...(contract.raw['clientEvents']!
                      as Map<String, Object?>)['probe']!
                  as Map<String, Object?>,
              'readyField': 'readyV2',
            },
          },
        }),
      );
      final (newName, _) = await run(
        () => http.Response('{"readyV2":true}', 200),
        withContract: renamed,
      );
      expect(newName.ready, isTrue);
      // 反向自证：同一份正文喂给**旧**契约（键还叫 ready）⇒ 读不出来 = 没结论。
      final (oldName, _) = await run(
        () => http.Response('{"readyV2":true}', 200),
      );
      expect(oldName.ready, isNull);
    });

    test('结论键不在正文里 ⇒ ready:null（没结论 ≠ 红），并说清是哪一种', () async {
      final (result, _) = await run(
        () => http.Response('{"serverTime":1}', 200),
      );
      expect(result.ready, isNull);
      expect(result.reason, contains('no-verdict'));
    });

    test('正文不是 JSON ⇒ ready:null（反代送回来的 HTML 不是结论）', () async {
      final (result, _) = await run(
        () => http.Response('<html>gateway</html>', 200),
      );
      expect(result.ready, isNull);
      expect(result.reason, contains('not-json'));
    });
  });

  group('没问到就绝不当红', () {
    test('非 200 ⇒ ready:null（429／404／405 都不是"这条路断了"）', () async {
      for (final code in [400, 401, 403, 404, 405, 429, 500, 503]) {
        final (result, _) = await run(() => http.Response('{}', code));
        expect(
          result.ready,
          isNull,
          reason: '$code 被当成红 ⇒ 用户学到的是"忽略徽标"，而不是"这条真不通"',
        );
        expect(result.reason, contains('http:$code'));
      }
    });

    test('传输异常照旧往上抛（"重试到第几次算失败"只有一个作者）', () async {
      expect(
        () => postFnthinkEndpointDryRun(
          contract: contract,
          probeUrl: probeUrl,
          secret: secret,
          client: MockClient((req) async => throw http.ClientException('boom')),
        ),
        throwsA(isA<http.ClientException>()),
        reason: '这里自己吞掉再包一层，重试那一层就数不清是第几次了（同一件事两种记法）',
      );
    });
  });

  group('口令只进请求头（这一发唯一的新红线）', () {
    test('POST + Bearer 头；URL 与正文里都不出现那串口令', () async {
      final (_, sent) = await run(
        () => http.Response(jsonEncode({readyField: true}), 200),
        body: secret,
      );
      expect(sent.method, 'POST');
      expect(sent.url.toString(), isNot(contains(secret)));
      expect(sent.url.path, endsWith('/probe'));
      expect(sent.headers['authorization'], 'Bearer $secret');
      // 这一发不带载荷（服务端也不读任何字段）⇒ 没有正文可写，也就没有"把口令塞进 body"那条路。
      expect(sent.body, isEmpty);
    });
  });
}
