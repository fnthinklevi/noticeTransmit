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

  group('响应体按 UTF-8 解码（T85a：没有 charset 也不能把中文解坏）', () {
    test('合法 UTF-8 字节 + 无 charset 头 ⇒ 中文正文原样读回（这一条在改之前必红）', () async {
      // ⚠ 实测过才这么写的（不是"听说 .body 按 latin-1"）：`package:http` 在没有 charset 时
      //  只有 **`text/*` 或干脆没有 content-type** 才按 latin-1 解；`application/json` 那一档
      //  它已经按 UTF-8 解。所以两条都要断：
      //   - `application/json`（线上此刻的样子）：断的是"换了实现也不许退回去";
      //   - `text/plain`（反代/CDN 把类型改写掉、或 WAF 直接回一页 text/plain 时）：
      //     这一条**在改之前必红** —— `.body` 会把 UTF-8 的中文按 latin-1 解成坏字符，
      //     然后被当成真内容落进收件表、上通知栏（"换设备后第一条推送是乱码"那种报法）。
      const payload =
          '{"messages":[{"messageId":"m_1","type":"notice","title":"",'
          '"body":"您的验证码是 8888，五分钟内的"}],'
          '"receipts":[],"pending":0}';
      for (final headers in const [
        {'content-type': 'application/json'},
        {'content-type': 'text/plain'},
      ]) {
        final rec = _Recorder(
          headers: headers,
          rawScripts: [utf8.encode(payload)],
        );
        final polled = await build(contract, rec, _Signer()).pollOnce();
        final message = polled.messages.single;
        expect(
          message.body,
          '您的验证码是 8888，五分钟内的',
          reason: '${headers['content-type']} 这一档解坏 ⇒ 又走回了按 charset 猜的 .body',
        );
        expect(
          message.body.contains('\uFFFD'),
          isFalse,
          reason: '出现替换字符就是 allowMalformed 被改成了 true（静默替换）',
        );
      }
    });

    test('正文里混进一个非法 UTF-8 字节 ⇒ 整发判成读不出，而不是带替换字符的那条被用出去', () async {
      // 这条钉的是 `allowMalformed: false` 本身。放开成 true 之后的形状不是"报错"，
      // 而是**一条看起来合法的消息**：那个坏字节变成 U+FFFD 混在正文里，照样落进收件表、
      // 照样上通知栏 —— 静默替换正是这次要修的乱码形状。
      final poisoned = <int>[
        ...utf8.encode(
          '{"messages":[{"messageId":"m_1","type":"notice","title":"","body":"A',
        ),
        0xFF, // 不是任何合法 UTF-8 序列里能出现的字节
        ...utf8.encode('"}],"receipts":[],"pending":0}'),
      ];
      final rec = _Recorder(
        headers: const {'content-type': 'application/json'},
        rawScripts: [poisoned],
      );
      final polled = await build(contract, rec, _Signer()).pollOnce();
      expect(
        polled.status,
        FnthinkPollStatus.ok,
        reason: '状态码不依赖正文：服务端确实答了这一发，别把它说成"没通上话"',
      );
      expect(
        polled.messages,
        isEmpty,
        reason:
            '冒出一条带 U+FFFD 的消息 = allowMalformed 被放开 ⇒ 坏字节被静默替换后'
            '当真内容落库、上通知栏',
      );
    });

    test('字节不是合法 UTF-8 ⇒ 内容判成读不出，但状态码照旧分类', () async {
      // 钉的是"不猜"：坏字节不许被当成合法文本用出去，也不许因为读不出就整发失败。
      // 403 那一档的结论只依赖状态码，所以这一发仍然要落到 rejectedUnsigned。
      final rec = _Recorder(
        status: contract.statusCodes['forbidden']!,
        headers: const {'content-type': 'application/json'},
        rawScripts: [
          const [0xC0, 0xC1, 0xFE, 0xFF, 0x41],
        ],
      );
      final result = await build(contract, rec, _Signer()).pollOnce();
      expect(
        result.status,
        FnthinkPollStatus.rejectedUnsigned,
        reason: '状态码不依赖正文：正文读不出也要把"服务端拒了这一发"说对',
      );
      expect(result.messages, isEmpty);
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

  group('pairArm 那一发（T42「添加设备」）', () {
    const pairingCode = '7A9QKM3PTVWXRBNSFGH4';

    test('发到自己声明的那条路径，载荷里就契约那一个键', () async {
      final rec = _Recorder(
        scripts: [
          '{"armed":true,"expiresAt":1800000300000,"ttlSeconds":300,'
              '"serverTime":1800000000000}',
        ],
      );
      final service = build(contract, rec, _Signer());
      final result = await service.pairArm(pairingCode: pairingCode);

      expect(
        rec.requests.single.url.path,
        contract.apiPath('pairArm'),
        reason: '路径只由契约说一次：写死一份的话，服务端换门时客户端还在敲旧门',
      );
      final fields = jsonDecode(rec.requests.single.body)['fields']! as Map;
      final body = jsonDecode(fields['body']! as String) as Map;
      expect(body.keys.toList(), contract.pairArmFields);
      expect(result.ok, isTrue);
      expect(result.expiresAtMs, 1800000300000);
    });

    test('200 但服务器没给过期时间 ⇒ 不算挂成功', () async {
      final rec = _Recorder(scripts: ['{"serverTime":1800000000000}']);
      final service = build(contract, rec, _Signer());
      final result = await service.pairArm(pairingCode: pairingCode);
      expect(
        result.ok,
        isFalse,
        reason:
            '这一发的全部意义是"服务器确实收下了"。把它说成成功，对端扫码只会拿到'
            '"口令不存在"，而这台界面上还写着已挂出',
      );
    });

    test('签名出不来时一个字节都不离机，且不谎报成网络故障', () async {
      final rec = _Recorder();
      final service = build(contract, rec, _Signer(available: false));
      final result = await service.pairArm(pairingCode: pairingCode);
      expect(rec.requests, isEmpty);
      expect(
        result.reason,
        'signing-unavailable',
        reason: '这是身份问题；说成"连接失败"会让用户去检查一直好好的网络',
      );
    });
  });

  group('答复配对请求 pairConfirm（T42 第四片）', () {
    // 另一台设备的地址码：这一发的 target 就是它（不是本机）。
    const peer = '8KMNPQRSTVWX999777';

    Map<String, Object?> confirmBody(String decision) => {
      'requestId': 'pr_9',
      'status': decision,
      'grantedLevel': 'L1',
      'serverTime': 1800000000000,
    };

    test('打到契约声明的那扇门，target 是对端而不是本机', () async {
      final approved = contract.pairConfirmApproveDecision;
      final rec = _Recorder(scripts: [jsonEncode(confirmBody(approved))]);
      final service = build(contract, rec, _Signer());
      final result = await service.pairConfirm(
        requestId: 'pr_9',
        decision: approved,
        level: 'L1',
        counterpart: peer,
      );
      expect(rec.requests.single.url.path, contract.apiPath('pairConfirm'));
      final fields = jsonDecode(rec.requests.single.body)['fields']! as Map;
      expect(
        fields['target'],
        peer,
        reason: '全协议唯一一发 target 不是自己：写成本机就换回一句与"不该由我管"同形的 403',
      );
      expect(fields['target'], isNot(address));
      expect(result.ok, isTrue);
      expect(result.grantedLevel, 'L1');
    });

    test('签不出来时不发出答复（授权这一发尤其不能"试试看"）', () async {
      final rec = _Recorder();
      final service = build(contract, rec, _Signer(available: false));
      final result = await service.pairConfirm(
        requestId: 'pr_9',
        decision: contract.pairConfirmApproveDecision,
        level: 'L1',
        counterpart: peer,
      );
      expect(rec.requests, isEmpty);
      expect(result.reason, 'signing-unavailable');
    });
  });

  group('发一条给名单里那台（§4-10 片2）', () {
    const peer = '8KMNPQRSTVWX999777';

    test('打到契约声明的那扇门，请求体只有三键而标题在**已签的 body** 里', () async {
      final rec = _Recorder(
        scripts: [
          '{"receipt":"queued","messageId":"m_7","action":"new","evicted":[]}',
        ],
        status: 202,
      );
      final signer = _Signer();
      final service = build(contract, rec, signer);
      final result = await service.sendNotice(
        peer: peer,
        title: '客厅温度',
        text: '30℃，请检查空调',
      );
      expect(result.status, FnthinkSendStatus.accepted);
      expect(result.messageId, 'm_7');
      expect(rec.requests.single.url.path, contract.apiPath('message'));
      final sent = jsonDecode(rec.requests.single.body) as Map<String, Object?>;
      expect(sent.keys.toSet(), {'sender', 'signature', 'fields'});
      final fields = sent['fields']! as Map<String, Object?>;
      expect(fields['target'], peer);
      expect(fields['type'], 'notice');
      expect(
        fields['body'],
        '${contract.deviceTitlePrefix}{"${contract.deviceTitleKey}":"客厅温度",'
        '"${contract.deviceBodyKey}":"30℃，请检查空调"}',
      );
      // 顶层没有 title：签名字节里没有它，服务端一定丢 —— 带着它只会让下一个人以为有用。
      expect(sent.containsKey('title'), isFalse);
    });

    test('九种结果各归各的下一步，而 429 的 Retry-After 传得到', () async {
      Future<FnthinkSendResult> once(
        int status,
        String body, {
        Map<String, String>? headers,
      }) async {
        final rec = _Recorder(
          scripts: [body],
          status: status,
          headers: headers ?? const {'content-type': 'application/json'},
        );
        return build(
          contract,
          rec,
          _Signer(),
        ).sendNotice(peer: peer, title: 't', text: 'b');
      }

      expect(
        (await once(403, '{"receipt":"${contract.unsignedReceipt}"}')).status,
        FnthinkSendStatus.rejectedUnsigned,
      );
      expect(
        (await once(403, '{"receipt":"rejected_capability"}')).status,
        FnthinkSendStatus.rejectedCapability,
      );
      expect(
        (await once(409, '{"receipt":"duplicate"}')).status,
        FnthinkSendStatus.replayed,
      );
      expect(
        (await once(410, '{"receipt":"expired"}')).status,
        FnthinkSendStatus.needsCalibration,
      );
      final limited = await once(
        429,
        '{"receipt":"rate_limited"}',
        headers: const {
          'content-type': 'application/json',
          'retry-after': '45',
        },
      );
      expect(limited.status, FnthinkSendStatus.rateLimited);
      expect(limited.retryAfterSeconds, 45);
      // 没有 messageId 的 202 不算收下：那条从此追不回来，不猜一个 id。
      expect(
        (await once(202, '{"receipt":"queued"}')).status,
        FnthinkSendStatus.unparseable,
      );
    });

    test('签不出来时一个字节都不离机（发送也是"未签的包不许出门"那一条）', () async {
      final rec = _Recorder();
      final result = await build(
        contract,
        rec,
        _Signer(available: false),
      ).sendNotice(peer: peer, title: 't', text: 'b');
      expect(rec.requests, isEmpty);
      expect(result.status, FnthinkSendStatus.signingUnavailable);
      expect(result.reason, 'signing-unavailable');
    });

    test('正文里有签名字段的分隔符 ⇒ 判成本机就没发出去，而不是把 ArgumentError 交给页面', () async {
      // 内核那条判据是对的（分隔符出现在被签字段的值里 = 能拼出与另一组字段相同的字节串），
      // 但它的**表达方式**必须是状态 + 原因：让每个调用方自己 try/catch，就会有一处漏 catch，
      // 而那处的表现是"点发送之后什么都不发生"。
      final rec = _Recorder();
      final result = await build(contract, rec, _Signer()).sendNotice(
        peer: peer,
        title: 't',
        text: 'a${contract.signatureSeparator}b',
      );
      expect(rec.requests, isEmpty);
      expect(result.status, FnthinkSendStatus.badInput);
      expect(result.reason, contains('input:'));
    });

    test('先学到服务端时间再发：那一发的 ts 用的是校正后的那个（不另起一本时钟账）', () async {
      final rec = _Recorder(
        scripts: [
          '{"messages":[],"receipts":[],"pending":0,"serverTime":1900000000000}',
          '{"receipt":"queued","messageId":"m_8"}',
        ],
        status: 200,
      );
      final signer = _Signer();
      final service = build(contract, rec, signer);
      await service.pollOnce();
      await service.sendNotice(peer: peer, title: '', text: 'b');
      // 校正后的毫秒 = 本机 now + (serverTime - 中点)，这里只验"用的是校正值"这一事实：
      // 它必须与 kernel.timestampMs 同一口径，而不是裸的本机时钟。
      final sent = signer.signed.last.split(contract.signatureSeparator);
      final ts = int.parse(sent[contract.canonicalOrder.indexOf('ts')]);
      expect(ts, (service.kernel.timestampMs / 1000).floor());
      expect(ts, isNot((DateTime.now().millisecondsSinceEpoch / 1000).floor()));
    });

    test('契约的能力词表里没有那个词 ⇒ 抛，不许在代码里补一个默认词', () async {
      final doc =
          jsonDecode(File(fnthinkContractFile()).readAsStringSync())
              as Map<String, Object?>;
      final caps = Map<String, Object?>.from(
        doc['capabilities']! as Map<String, Object?>,
      );
      final types = Map<String, Object?>.from(
        caps['messageTypes']! as Map<String, Object?>,
      );
      types.remove('notice');
      caps['messageTypes'] = types;
      doc['capabilities'] = caps;
      final rec = _Recorder();
      final service = build(FnthinkContract(doc), rec, _Signer());
      await expectLater(
        service.sendNotice(peer: peer, title: 't', text: 'b'),
        throwsA(isA<StateError>()),
      );
      expect(rec.requests, isEmpty);
    });
  });

  group('自登记 register（#177：其余每一发的共同前置）', () {
    test('URL 从契约反查，顶层带着公钥与名字', () async {
      final rec = _Recorder(
        scripts: [
          '{"addressCode":"$address","name":"MEIZU 21","peersGrantingMe":0,'
              '"serverTime":1800000000000}',
        ],
      );
      final signer = _Signer();
      final service = build(contract, rec, signer);

      final result = await service.register(name: 'MEIZU 21');

      expect(result.status, FnthinkPollStatus.ok);
      expect(result.addressCode, address);
      expect(rec.requests.single.url.path, contract.apiPath('register'));
      final body = jsonDecode(rec.requests.single.body) as Map<String, Object?>;
      expect(
        body['publicKey'],
        signer.key,
        reason: '交出去的公钥必须是与签名私钥成对的那一把（从签名口取，不另起一份来源）',
      );
      expect(body['name'], 'MEIZU 21');
      expect(
        (body['fields']! as Map)['type'],
        contract.str(['clientEvents', 'register', 'messageType']),
      );
    });

    test('签不出来 ⇒ 一个字节都不离机（与其余几发同一道闸）', () async {
      final rec = _Recorder();
      final service = build(contract, rec, _Signer(available: false));

      final result = await service.register(name: 'n');

      expect(result.status, FnthinkPollStatus.failed);
      expect(result.reason, 'signing-unavailable');
      expect(rec.requests, isEmpty);
    });

    test('这台还没有身份（取不到公钥）⇒ 不发：发出去只会换回同形的 403', () async {
      final rec = _Recorder();
      final result = await build(
        contract,
        rec,
        _Signer(key: null),
      ).register(name: 'n');

      expect(result.status, FnthinkPollStatus.failed);
      expect(result.reason, 'no-public-key');
      expect(rec.requests, isEmpty);
    });

    test('契约缺 register 那条路径 ⇒ 装配期就抛（不退回一个猜出来的 URL）', () {
      final mutated = FnthinkContract({
        ...contract.raw,
        'transport': {
          ...(contract.raw['transport']! as Map<String, Object?>),
          'apiPaths': {
            ...(contract.raw['transport']! as Map<String, Object?>)['apiPaths']!
                as Map<String, Object?>,
          }..remove('register'),
        },
      });
      expect(
        () => build(mutated, _Recorder(), _Signer()),
        throwsA(isA<ArgumentError>()),
        reason: '自登记是每一发的共同前置：它的门牌缺了，整条链都断在那一步',
      );
    });
  });
}

/// 记下每一次请求，并按脚本回响应。
class _Recorder {
  _Recorder({
    List<String>? scripts,
    this.status = 200,
    this.headers = const {'content-type': 'application/json'},
    this.rawScripts,
  }) : scripts = scripts ?? ['{"messages":[],"receipts":[],"pending":0}'];

  final List<http.Request> requests = [];
  List<String> scripts;
  int status;
  Map<String, String> headers;

  /// 直接给**字节**的回脚本（T85a）。给了它就走 `Response.bytes` —— 这一条是必须的：
  /// `http.Response(String body, …)` 会按 content-type 的 charset 编码，没有 charset 时
  /// 用 latin-1，于是"UTF-8 的中文响应"这种现场用字符串脚本根本演不出来。
  List<List<int>>? rawScripts;

  MockClient client() => MockClient((http.Request request) async {
    requests.add(request);
    final index = (requests.length - 1) % scripts.length;
    if (rawScripts != null) {
      return http.Response.bytes(
        rawScripts![index % rawScripts!.length],
        status,
        headers: headers,
      );
    }
    return http.Response(scripts[index], status, headers: headers);
  });
}

/// 假的签名注入点：既能演"签得出来"，也能演"这台机器的 Keystore 用不了"。
class _Signer implements FnthinkIdentitySigner {
  _Signer({this.available = true, this.key = 'cHVibGljLWtleQ=='});

  bool available;

  /// 本机公钥（自登记要交出去的那一把）。null = 这台没有身份 ⇒ 测"没有公钥就不发"。
  final String? key;
  final List<String> signed = [];

  @override
  Future<String> call(List<int> bytes) async {
    if (!available) throw StateError('本机签不出来');
    signed.add(utf8.decode(bytes));
    return base64Encode(List<int>.filled(64, 7));
  }

  @override
  Future<bool> probe() async => available;

  @override
  Future<String?> publicKey() async => key;
}
