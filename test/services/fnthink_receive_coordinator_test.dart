import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notice_transmit/models/fnthink_inbox_message.dart';
import 'package:notice_transmit/models/fnthink_peer.dart';
import 'package:notice_transmit/services/fnthink_contract_loader.dart';
import 'package:notice_transmit/services/fnthink_receive_coordinator.dart';
import 'package:notice_transmit/services/fnthink_receive_loop.dart';
import 'package:notice_transmit/services/fnthink_receiver_service.dart';
import 'package:notice_transmit/services/fnthink_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_setup.dart';

/// 收货链路的接线层（#126 第四片）：能不能开始、为什么不能、现在在跑吗。
///
/// 这一层的价值全在**顺序与零副作用**上：
///  ① 总开关关着 ⇒ 一个请求都不该发，**也不该去向 KeyStore 要一次签名能力**
///     （"功能没开"变成"系统在后台悄悄动钥匙"，是用户最没法接受的那种意外）；
///  ② 五种"起不来"必须分开报（disabled / contract-unavailable / settings-invalid /
///     credential-corrupted / signing-unavailable）—— 它们对应五种不同的用户动作；
///  ③ 已在跑就是幂等：叠第二个循环的表现为同一条 ack 两次、未读数上下跳；
///  ④ 装配出来的那发请求要打到**契约说的那扇门**上（这一条只在真机上验过一次是不够的）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final contractText = File(fnthinkContractFile()).readAsStringSync();
  final contract = FnthinkContract.parse(contractText);
  final endpoints =
      (contract.raw['transport'] as Map<String, Object?>)['endpoints']
          as Map<String, Object?>;
  final defaultHost = endpoints['default']! as String;

  /// 原生安全存储的内存替身（地址码要从这里读）。
  late Map<String, String?> disk;

  final timers = <Timer>[];
  tearDown(() {
    for (final t in timers) {
      t.cancel();
    }
    timers.clear();
    clearNativeChannelStubs();
  });

  void mockSecureStorage() {
    stubNativeChannels(
      onCall: (call) async {
        if (call.method == 'read') {
          return disk[call.arguments['key'] as String];
        }
        if (call.method == 'write') {
          disk[call.arguments['key'] as String] =
              call.arguments['value'] as String?;
          return null;
        }
        if (call.method == 'delete') {
          disk.remove(call.arguments['key'] as String);
          return null;
        }
        return null;
      },
    );
  }

  FnthinkContractLoader goodLoader() =>
      FnthinkContractLoader(readAsset: (_) async => contractText);

  FnthinkIdentitySigner signer(bool ok) => _FakeSigner(ok);

  Future<bool> persist(FnthinkInboxMessage message) async => true;

  FnthinkReceiveCoordinator coordinator({
    required _LoopRecorder recorder,
    FnthinkContractLoader? contracts,
    FnthinkIdentitySigner? signerOverride,
    FnthinkServiceFactory? serviceFactory,
    Future<FnthinkPeerWrite> Function(FnthinkPeer peer)? recordPeer,
    Future<bool> Function(String peerAddress)? removePeer,
    Future<void> Function({required bool keepAwake})? presenceNotice,
  }) => FnthinkReceiveCoordinator(
    contracts: contracts ?? goodLoader(),
    signer: signerOverride ?? signer(true),
    persist: persist,
    recordPeer: recordPeer,
    removePeer: removePeer,
    presenceNotice: presenceNotice,
    loopFactory: recorder.build,
    serviceFactory: serviceFactory,
  );

  /// 挂口令那一发的假服务器：只记请求、按脚本回话（真接线由服务层那片的两条用例保证）。
  FnthinkServiceFactory armFactory({
    int status = 200,
    String body =
        '{"armed":true,"expiresAt":1800000300000,"ttlSeconds":300,"serverTime":1800000000000}',
    required List<http.Request> sink,
    List<String>? steps,
  }) =>
      (spec) => FnthinkReceiverService(
        contract: spec.contract,
        baseUri: spec.baseUri,
        signer: spec.signer,
        addressCode: spec.addressCode,
        client: MockClient((req) async {
          sink.add(req);
          steps?.add('request');
          return http.Response(body, status);
        }),
      );

  setUp(() {
    disk = {};
    SharedPreferences.setMockInitialValues({});
    mockSecureStorage();
  });

  group('开关与顺序', () {
    test('① 关着 ⇒ disabled：不建循环，也不碰签名能力', () async {
      final probeCalls = <bool>[];
      final rec = _LoopRecorder();
      final result = await coordinator(
        recorder: rec,
        signerOverride: _FakeSigner(true, onProbe: () => probeCalls.add(true)),
      ).startIfEnabled();
      expect(result.started, isFalse);
      expect(result.reason, 'disabled');
      expect(rec.builds, 0);
      expect(probeCalls, isEmpty, reason: '功能没开就不该去动 KeyStore');
    });

    test('② 开着且一切就绪 ⇒ started，地址与地址码都按契约与本机来', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.${FnthinkSettings.keyReceiveEnabled}': true,
      });
      final rec = _LoopRecorder();
      final c = coordinator(recorder: rec);
      final result = await c.startIfEnabled();
      expect(result.started, isTrue);
      expect(result.reason, 'started');
      expect(rec.builds, 1);
      expect(rec.specs.single.baseUri.toString(), 'https://$defaultHost');
      expect(
        rec.specs.single.addressCode.length,
        contract.identityLength('addressCode'),
      );
      expect(c.isRunning, isTrue);
    });

    test('③ 已在跑就是幂等：不会叠出第二个循环', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.${FnthinkSettings.keyReceiveEnabled}': true,
      });
      final rec = _LoopRecorder();
      final c = coordinator(recorder: rec);
      await c.startIfEnabled();
      final again = await c.startIfEnabled();
      expect(again.reason, 'already-running');
      expect(again.started, isTrue);
      expect(rec.builds, 1);
    });

    test('stop 之后可以再起（这次是一个新循环）', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.${FnthinkSettings.keyReceiveEnabled}': true,
      });
      final rec = _LoopRecorder();
      final c = coordinator(recorder: rec);
      await c.startIfEnabled();
      c.stop();
      expect(c.isRunning, isFalse);
      await c.startIfEnabled();
      expect(rec.builds, 2);
    });
  });

  group('五种"起不来"分开报', () {
    test('契约不可用 ⇒ contract-unavailable，且原话带出来', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.${FnthinkSettings.keyReceiveEnabled}': true,
      });
      final rec = _LoopRecorder();
      final result = await coordinator(
        recorder: rec,
        contracts: FnthinkContractLoader(
          readAsset: (_) async => throw StateError('asset 不在'),
        ),
      ).startIfEnabled();
      expect(result.started, isFalse);
      expect(result.reason, startsWith('contract-unavailable'));
      expect(rec.builds, 0);
    });

    test('服务地址是坏值 ⇒ settings-invalid（备份恢复灌回来的那种）', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.${FnthinkSettings.keyReceiveEnabled}': true,
        'flutter.${FnthinkSettings.keyHost}': 'not a host/',
      });
      final rec = _LoopRecorder();
      final result = await coordinator(recorder: rec).startIfEnabled();
      expect(result.reason, startsWith('settings-invalid'));
      expect(rec.builds, 0);
    });

    test('本机地址码存量坏掉 ⇒ credential-corrupted（不自动换一枚）', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.${FnthinkSettings.keyReceiveEnabled}': true,
      });
      disk['fnthink.address_code'] = 'ILOU 不是合法字母表';
      final rec = _LoopRecorder();
      final result = await coordinator(recorder: rec).startIfEnabled();
      expect(result.reason, startsWith('credential-corrupted'));
      expect(
        disk['fnthink.address_code'],
        'ILOU 不是合法字母表',
        reason: '换一枚会让别人白名单里那一条指向一台不再存在的设备',
      );
      expect(rec.builds, 0);
    });

    test('签名取不到 ⇒ signing-unavailable（身份问题，不是网络问题）', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.${FnthinkSettings.keyReceiveEnabled}': true,
      });
      final rec = _LoopRecorder();
      final result = await coordinator(
        recorder: rec,
        signerOverride: signer(false),
      ).startIfEnabled();
      expect(result.reason, 'signing-unavailable');
      expect(rec.builds, 0);
    });
  });

  group('手动收取', () {
    test('关着 ⇒ 返回 null，且不因为"用户点了按钮"就绕过开关', () async {
      final rec = _LoopRecorder();
      expect(await coordinator(recorder: rec).receiveOnce(), isNull);
      expect(rec.builds, 0);
    });

    test('开着 ⇒ 交回这一轮的账目；上一轮还在途时交回的是"整轮跳过"', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.${FnthinkSettings.keyReceiveEnabled}': true,
      });
      final rec = _LoopRecorder();
      final c = coordinator(recorder: rec);
      await c.startIfEnabled();
      // start 已经把第一轮排出去，它此刻还在途（④ 那条判据在这里正好被看到）：
      // 手动那一下不该悄悄什么都不做，也不该叠出第二个循环 —— 它拿回的是 skipped 这份账，
      // 而界面上可以说"正在收，这一轮的结局马上见"。
      final whileBusy = await c.receiveOnce();
      expect(whileBusy, isNotNull);
      expect(whileBusy!.skipped, isTrue);
      expect(whileBusy.reason, 'round-in-progress');
      expect(rec.builds, 1, reason: '手动那一下不叠第二个循环');

      // 等第一轮真的跑完，再点一下：这一次是货真价实的一轮。
      await pumpEventQueue();
      final idle = await c.receiveOnce();
      expect(idle, isNotNull);
      expect(idle!.skipped, isFalse);
      expect(rec.polls, greaterThanOrEqualTo(2));
    });

    test('没起过就直接手动收取 ⇒ 顺手按开关装配一次（不静默什么都不做）', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.${FnthinkSettings.keyReceiveEnabled}': true,
      });
      final rec = _LoopRecorder();
      final report = await coordinator(recorder: rec).receiveOnce();
      expect(report, isNotNull);
      expect(rec.builds, 1);
    });
  });

  group('续排闹钟 presenceNotice（T33 第二片 / §4-9 片1b）', () {
    // 这一族只钉**调用形状**：什么时候说"还要醒"、什么时候说"停"、以及它失败时不许拖累主路。
    // 秒数的作者在 `test/services/fnthink_presence_scheduler_test.dart`（那边喂的是改过数值的
    // 契约副本），这里一个字都不重复 —— 重复一份断言等于给同一个数找两个作者。
    test('跑完一轮就续排（失败的那一轮同样要续：一次抖动不该弄丢这台叫醒自己的机会）', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.${FnthinkSettings.keyReceiveEnabled}': true,
      });
      final notices = <bool>[];
      final rec = _LoopRecorder();
      final c = coordinator(
        recorder: rec,
        presenceNotice: ({required bool keepAwake}) async =>
            notices.add(keepAwake),
      );

      await c.receiveOnce();
      await pumpEventQueue();
      expect(
        notices,
        isNotEmpty,
        reason: '一轮结束却没人续排 ⇒ 这一台从此只靠前台那颗循环；进程被杀就再没人取货',
      );
      expect(notices.every((k) => k), isTrue);

      notices.clear();
      rec.pollStatus = FnthinkPollStatus.transportError;
      await c.receiveOnce();
      await pumpEventQueue();
      expect(
        notices,
        isNotEmpty,
        reason: 'transportError / 429 说明路还活着只是这次没取到；在这里停下等于永久撤闹钟',
      );
      expect(notices.every((k) => k), isTrue);
    });

    test('起不来（开关关着）⇒ 撤掉闹钟，而不是留着一颗会空跑的', () async {
      final notices = <bool>[];
      final rec = _LoopRecorder();

      final result = await coordinator(
        recorder: rec,
        presenceNotice: ({required bool keepAwake}) async =>
            notices.add(keepAwake),
      ).startIfEnabled();

      expect(result.reason, 'disabled');
      expect(
        notices,
        [false],
        reason:
            '界面上写着"收货是关着的"而闹钟还在响 —— 被杀之后那一轮会起引擎、什么也不动，'
            '白耗一次唤醒与流量',
      );
    });

    test('stop() 同样撤（关掉接收与开关早退是同一个口径）', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.${FnthinkSettings.keyReceiveEnabled}': true,
      });
      final notices = <bool>[];
      final rec = _LoopRecorder();
      final c = coordinator(
        recorder: rec,
        presenceNotice: ({required bool keepAwake}) async =>
            notices.add(keepAwake),
      );
      await c.startIfEnabled();
      notices.clear();

      c.stop();
      await pumpEventQueue();

      expect(notices, [false]);
    });

    test('续排那一发失败 ⇒ 不拖累收货，也不静默：日志里必须看得见', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.${FnthinkSettings.keyReceiveEnabled}': true,
      });
      final logs = <String>[];
      final originalPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() => debugPrint = originalPrint);

      final rec = _LoopRecorder();
      final c = coordinator(
        recorder: rec,
        presenceNotice: ({required bool keepAwake}) async =>
            throw StateError('模拟：通道那头没人接'),
      );

      final report = await c.receiveOnce();
      await pumpEventQueue();

      expect(report, isNotNull);
      expect(
        rec.polls,
        greaterThan(0),
        reason:
            '旁路失败不许把主路带下去：这是"拿主路给旁路陪葬"那类缺陷的形状。'
            '这里看的是"那一轮真发出去了"，不看它的账目 —— 账目由循环那片自己钉，'
            '而且 start 之后手动那一下可能撞上在途的那一轮（skipped），那不是本条要答的题',
      );
      expect(
        logs.where((l) => l.contains('续排闹钟没送到')),
        isNotEmpty,
        reason: '不抛是对的，但也不许悄悄吞 —— 排查"闹钟为什么没响"时这一行是唯一的线索',
      );
    });

    test('这台没装配续排链路（hook 为 null）⇒ 收货照常，不崩', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.${FnthinkSettings.keyReceiveEnabled}': true,
      });
      final rec = _LoopRecorder();
      final report = await coordinator(recorder: rec).receiveOnce();
      expect(report, isNotNull);
      expect(rec.builds, 1);
    });
  });

  group('装配的端到端形状', () {
    test('④ 第一发打到契约说的那扇门上（https + host + apiPaths.poll）', () async {
      final asked = <String>[];
      final loop = buildFnthinkReceiveLoop(
        FnthinkLoopSpec(
          contract: contract,
          baseUri: Uri.https(defaultHost, ''),
          addressCode: 'AAAABBBBCCCCDDDDEEEE',
          signer: signer(true),
          persist: (_) async => true,
          client: _FakeClient(asked),
        ),
      );
      final report = await loop.runOnce();
      expect(report.status, FnthinkPollStatus.ok);
      expect(asked, [
        'https://$defaultHost${contract.apiPath('poll')}',
      ], reason: '路径的唯一出处是契约 transport.apiPaths，这里没有第二份可拼');
    });
  });

  group('挂口令那一发 publishPairingCode（T42 第二片）', () {
    const pairingCode = '7A9QKM3PTVWXRBNSFGH4';

    test('开关关着也挂得出去：配对是接收的前置，不是它的后果', () async {
      SharedPreferences.setMockInitialValues({}); // 没有 receive_enabled ⇒ 默认关
      final asked = <http.Request>[];
      final c = coordinator(
        recorder: _LoopRecorder(),
        serviceFactory: armFactory(sink: asked),
      );
      final result = await c.publishPairingCode(pairingCode);
      expect(result.ok, isTrue, reason: '用开关挡住挂口令，用户就没有第二条路把两台设备连起来了');
      expect(asked.single.url.path, contract.apiPath('pairArm'));
      // 挂口令不该顺手把收货循环也起来 —— 那是替用户点了"开始接收"。
      expect(c.isRunning, isFalse);
    });

    test('前置不满足时一句都没离机，且各有各的原话', () async {
      final asked = <http.Request>[];

      final noContract = coordinator(
        recorder: _LoopRecorder(),
        contracts: FnthinkContractLoader(readAsset: (_) async => '{ 坏 JSON'),
        serviceFactory: armFactory(sink: asked),
      );
      expect(
        (await noContract.publishPairingCode(pairingCode)).reason,
        startsWith('contract-unavailable'),
      );

      SharedPreferences.setMockInitialValues({
        FnthinkSettings.keyHost: 'a b/c',
      });
      final badHost = coordinator(
        recorder: _LoopRecorder(),
        serviceFactory: armFactory(sink: asked),
      );
      expect(
        (await badHost.publishPairingCode(pairingCode)).reason,
        startsWith('settings-invalid'),
      );

      // 把服务地址放回好值：判定顺序本身就是判据（设置先于签名探测），
      // 上一小步留下的坏值会把 signing-unavailable 遮成 settings-invalid。
      SharedPreferences.setMockInitialValues({});
      final cannotSign = coordinator(
        recorder: _LoopRecorder(),
        signerOverride: signer(false),
        serviceFactory: armFactory(sink: asked),
      );
      expect(
        (await cannotSign.publishPairingCode(pairingCode)).reason,
        'signing-unavailable',
        reason: '身份问题被说成"连接失败"，用户就会去检查一直好好的网络',
      );

      expect(asked, isEmpty, reason: '这几种都不该发出一个字节：前置判定没过时发出去只会换回一句同形的 403');
    });

    test('服务器没回过期时间 ⇒ 结果不 ok（界面据此不许说"已挂出"）', () async {
      SharedPreferences.setMockInitialValues({
        FnthinkSettings.keyReceiveEnabled: true,
      });
      final asked = <http.Request>[];
      final c = coordinator(
        recorder: _LoopRecorder(),
        serviceFactory: armFactory(
          sink: asked,
          body: '{"serverTime":1800000000000}',
        ),
      );
      expect(
        (await c.publishPairingCode(pairingCode)).ok,
        isFalse,
        reason:
            '"本机记下了"与"服务器收下了"是两件事；把前者说成后者，'
            '对端扫码只会拿到"口令不存在"，而这一台界面上写着已挂出',
      );
    });
  });

  group('答复一条配对请求 confirmPairing（T42 第四片）', () {
    const request = FnthinkPairRequest(
      requestId: 'pr_9',
      requester: '8KMNPQRSTVWX999777',
      requesterPublicKey: 'AAAA',
      level: 'L1',
    );

    String ackBody(String decision) =>
        '{"requestId":"pr_9","status":"$decision","grantedLevel":"L1",'
        '"serverTime":1800000000000}';

    test('同意那一发写给对端，且总开关关着也能答复', () async {
      SharedPreferences.setMockInitialValues({}); // 接收开关 = 默认关
      final asked = <http.Request>[];
      final c = coordinator(
        recorder: _LoopRecorder(),
        serviceFactory: armFactory(
          sink: asked,
          body: ackBody(contract.pairConfirmApproveDecision),
        ),
      );
      final result = await c.confirmPairing(request: request, approve: true);
      expect(result.ok, isTrue);
      final fields = jsonDecode(asked.single.body)['fields']! as Map;
      expect(
        fields['target'],
        request.requester,
        reason: '授权给谁就写给谁；写成本机等于替别人答复，服务端只会拦下来',
      );
      expect(asked.single.url.path, contract.apiPath('pairConfirm'));
      expect(
        c.isRunning,
        isFalse,
        reason: '答复一条请求不该顺手把收货循环起开 —— 那是替用户点了"开始接收"',
      );
    });

    test('前置不满足时一句都不发', () async {
      final asked = <http.Request>[];
      final cannotSign = coordinator(
        recorder: _LoopRecorder(),
        signerOverride: signer(false),
        serviceFactory: armFactory(sink: asked),
      );
      expect(
        (await cannotSign.confirmPairing(
          request: request,
          approve: false,
        )).reason,
        'signing-unavailable',
      );
      expect(asked, isEmpty);
    });

    test('契约给出第三个答复词 ⇒ 那一发不会带着猜出来的"拒绝"离机', () async {
      final threeWay = FnthinkContractLoader(
        readAsset: (_) async {
          final raw = jsonDecode(contractText) as Map<String, Object?>;
          (raw['clientEvents']! as Map)['pairConfirm'] = {
            ...((raw['clientEvents']! as Map)['pairConfirm']! as Map),
            'decisions': ['approved', 'denied', 'maybe'],
          };
          return jsonEncode(raw);
        },
      );
      final asked = <http.Request>[];
      final ambiguous = coordinator(
        recorder: _LoopRecorder(),
        contracts: threeWay,
        serviceFactory: armFactory(sink: asked),
      );
      // 这里有**两道**闸：契约 validate 先拒绝这份改过的契约（今日就是它挡住的，
      // reason 是 contract-unavailable）；真走到 confirmPairing 也会因"拒绝是哪一个词"
      // 有二义而抛。两道都不许变成"随便挑一个签出去" ⇒ 断言的是**没发出去 + 说得出原因**。
      final result = await ambiguous.confirmPairing(
        request: request,
        approve: false,
      );
      expect(asked, isEmpty);
      expect(result.ok, isFalse);
      expect(result.reason, isNotNull);
    });
  });

  group('待确认列表与本机名单（T42 第五片）', () {
    FnthinkPairRequest req(String level, {String id = 'pr_9'}) =>
        FnthinkPairRequest(
          requestId: id,
          requester: '8KMNPQRSTVWX999777',
          requesterPublicKey: 'AAAA',
          level: level,
        );

    String confirmBody({String? decision, String? grantedLevel}) =>
        '{"requestId":"pr_9",'
        '"status":"${decision ?? contract.pairConfirmApproveDecision}",'
        '"grantedLevel":${grantedLevel == null ? 'null' : '"$grantedLevel"'},'
        '"serverTime":1800000000000}';

    /// 从签出去的那一发里把**载荷**取回来（`fields.body` 是 json 字符串，套两层）。
    Map<String, Object?> sentPayload(http.Request request) =>
        jsonDecode(
              (jsonDecode(request.body)['fields']! as Map)['body']! as String,
            )
            as Map<String, Object?>;

    test('名单里那一行记的是服务端回的档位，不是本机刚发出去的那一档', () async {
      SharedPreferences.setMockInitialValues({});
      final asked = <http.Request>[];
      final rows = <FnthinkPeer>[];
      final c = coordinator(
        recorder: _LoopRecorder(),
        // 本机发的是 L2（对方就要 L2），服务端那侧还有一道自己的封顶，回的是 L1。
        serviceFactory: armFactory(
          sink: asked,
          body: confirmBody(grantedLevel: 'L1'),
        ),
        recordPeer: (peer) async {
          rows.add(peer);
          return FnthinkPeerWrite.created;
        },
      );
      final answer = await c.confirmPairing(request: req('L2'), approve: true);
      expect(answer.ok, isTrue);
      expect(answer.wrote, FnthinkPeerWrite.created);
      expect(
        rows.single.level,
        'L1',
        reason:
            '两端哪天对封顶的理解漂了，本机这份要跟着服务端走：'
            '名单写 L2 而对面实际被限在 L1，下一片那一格显示的就是本机的一厢情愿',
      );
      expect(rows.single.peerAddress, '8KMNPQRSTVWX999777');
      expect(rows.single.publicKey, 'AAAA');
      expect(rows.single.requestId, 'pr_9');
      expect(rows.single.grantedAt, greaterThan(0));
    });

    test('对方要 L3 ⇒ 发出去的是封顶那一档，不是 L3', () async {
      final asked = <http.Request>[];
      final c = coordinator(
        recorder: _LoopRecorder(),
        serviceFactory: armFactory(
          sink: asked,
          body: confirmBody(grantedLevel: contract.pairConfirmLevelCeiling),
        ),
      );
      final answer = await c.confirmPairing(request: req('L3'), approve: true);
      expect(
        sentPayload(asked.single)['level'],
        contract.pairConfirmLevelCeiling,
        reason:
            'L3 要在这台设备上本地确认（锁屏/生物认证），远程这一发给不出去；'
            '原样发过去只会换回一句与"口令错"同形的 403',
      );
      expect(answer.ok, isTrue);
    });

    test('对方报的档位不在词表里 ⇒ 同意一个字节都不发，原因带着那个词', () async {
      final asked = <http.Request>[];
      final rows = <FnthinkPeer>[];
      final c = coordinator(
        recorder: _LoopRecorder(),
        serviceFactory: armFactory(sink: asked),
        recordPeer: (peer) async {
          rows.add(peer);
          return FnthinkPeerWrite.created;
        },
      );
      final answer = await c.confirmPairing(request: req('L9'), approve: true);
      expect(asked, isEmpty, reason: '给一个没人请求过的档位，是替对方做决定');
      expect(rows, isEmpty);
      expect(answer.reason, 'unknown-level:L9');
    });

    test('同一条畸形请求仍然可以拒绝（划掉它不需要档位）', () async {
      final asked = <http.Request>[];
      final c = coordinator(
        recorder: _LoopRecorder(),
        serviceFactory: armFactory(
          sink: asked,
          body: confirmBody(
            decision: contract.pairConfirmDecisions.firstWhere(
              (d) => d != contract.pairConfirmApproveDecision,
            ),
          ),
        ),
      );
      final answer = await c.confirmPairing(request: req('L9'), approve: false);
      expect(asked, hasLength(1));
      expect(
        sentPayload(asked.single)['level'],
        contract.pairConfirmLevelCeiling,
        reason:
            '拒绝不写任何授权，服务端只要求这一键是个合法档位；'
            '因为档位读不懂就连划掉都做不到，那条请求会一直挂在待确认栏里',
      );
      expect(answer.ok, isTrue);
    });

    test('服务端没认下来 ⇒ 本机名单一行都不写', () async {
      final asked = <http.Request>[];
      final rows = <FnthinkPeer>[];
      final c = coordinator(
        recorder: _LoopRecorder(),
        serviceFactory: armFactory(
          sink: asked,
          status: 403,
          body: '{"receipt":"${contract.unsignedReceipt}"}',
        ),
        recordPeer: (peer) async {
          rows.add(peer);
          return FnthinkPeerWrite.created;
        },
      );
      final answer = await c.confirmPairing(request: req('L1'), approve: true);
      expect(answer.ok, isFalse);
      expect(rows, isEmpty, reason: '服务端那边没结成，本机先记一条"已授权"就是自己给自己造白名单');
    });

    test('同意且服务端认了、但没回档位 ⇒ 不写名单，并把这一态单独说清', () async {
      final asked = <http.Request>[];
      final rows = <FnthinkPeer>[];
      final c = coordinator(
        recorder: _LoopRecorder(),
        serviceFactory: armFactory(
          sink: asked,
          body: confirmBody(grantedLevel: null),
        ),
        recordPeer: (peer) async {
          rows.add(peer);
          return FnthinkPeerWrite.created;
        },
      );
      final answer = await c.confirmPairing(request: req('L1'), approve: true);
      expect(answer.ok, isTrue, reason: '配对**成了**，是本机不知道该记哪一档 —— 两件事不许混');
      expect(answer.skipped, FnthinkPeerSkip.grantedLevelUnusable);
      expect(rows, isEmpty);
    });

    test('这台设备没装配名单落库 ⇒ 结论是 storeUnavailable', () async {
      final asked = <http.Request>[];
      final c = coordinator(
        recorder: _LoopRecorder(),
        serviceFactory: armFactory(
          sink: asked,
          body: confirmBody(grantedLevel: 'L1'),
        ),
      );
      final answer = await c.confirmPairing(request: req('L1'), approve: true);
      expect(
        answer.skipped,
        FnthinkPeerSkip.storeUnavailable,
        reason: '装配点漏接时全场仍绿，只有这一格会说谎：界面必须能显示"服务器认了而本机名单是空的"',
      );
    });

    test('换钥那一次：`keySwapped` 原样交回，不改口成"已同意"', () async {
      final asked = <http.Request>[];
      final c = coordinator(
        recorder: _LoopRecorder(),
        serviceFactory: armFactory(
          sink: asked,
          body: confirmBody(grantedLevel: 'L1'),
        ),
        recordPeer: (_) async => FnthinkPeerWrite.keySwapped,
      );
      final answer = await c.confirmPairing(request: req('L1'), approve: true);
      expect(
        answer.wrote,
        FnthinkPeerWrite.keySwapped,
        reason: '同一个地址码带着另一把公钥来，本机一行都没改 —— 报成"已同意"就是替用户点了"同意换钥"',
      );
    });

    test('写名单时抛了 ⇒ 结论是 writeFailed，而不是让这一发答复炸在页面上', () async {
      final asked = <http.Request>[];
      final c = coordinator(
        recorder: _LoopRecorder(),
        serviceFactory: armFactory(
          sink: asked,
          body: confirmBody(grantedLevel: 'L1'),
        ),
        recordPeer: (_) async => throw StateError('表被锁'),
      );
      final answer = await c.confirmPairing(request: req('L1'), approve: true);
      expect(answer.ok, isTrue);
      expect(answer.skipped, FnthinkPeerSkip.writeFailed);
    });

    test('拒绝 ⇒ 不发之外也不写名单', () async {
      final asked = <http.Request>[];
      final rows = <FnthinkPeer>[];
      final c = coordinator(
        recorder: _LoopRecorder(),
        serviceFactory: armFactory(
          sink: asked,
          body: confirmBody(
            decision: contract.pairConfirmDecisions.firstWhere(
              (d) => d != contract.pairConfirmApproveDecision,
            ),
            grantedLevel: null,
          ),
        ),
        recordPeer: (peer) async {
          rows.add(peer);
          return FnthinkPeerWrite.created;
        },
      );
      final answer = await c.confirmPairing(request: req('L1'), approve: false);
      expect(answer.ok, isTrue);
      expect(rows, isEmpty, reason: '拒绝不产生任何授权');
      expect(
        sentPayload(asked.single)['decision'],
        isNot(contract.pairConfirmApproveDecision),
      );
    });

    test('循环已在跑时，手动那一轮带回来的请求也会上账（页面点的就是这条路）', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.${FnthinkSettings.keyReceiveEnabled}': true,
      });
      final rec = _LoopRecorder();
      final c = coordinator(recorder: rec);
      // 先把循环起起来：`receiveOnce` 在**没起过**时会顺手 start，那条路走 `_tick`，
      // `onRound` 自己就响了 —— 拿它来证"手动那一轮也记账"是证不出来的
      // （反证 P5 把 `receiveOnce` 里那句记账摘掉后全场仍绿，就是这么被抓出来的）。
      await c.startIfEnabled();
      await pumpEventQueue();
      expect(c.pendingPairRequests, isEmpty);

      rec.pollPairRequests = [req('L1')];
      await c.receiveOnce();
      expect(
        c.pendingPairRequests,
        hasLength(1),
        reason:
            '已在跑的循环里 `receiveOnce` 调的是 `runOnce`，不经过 `_tick` ⇒ `onRound` '
            '不会响。这条路不单独记账，用户按了"立即收取"，那一栏还是旧的',
      );
    });

    test('后台那一轮看到的请求会被接住（不点"立即收取"也看得见）', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.${FnthinkSettings.keyReceiveEnabled}': true,
      });
      final rec = _LoopRecorder()..pollPairRequests = [req('L1')];
      final c = coordinator(recorder: rec);
      await c.startIfEnabled();
      await pumpEventQueue();
      expect(
        c.pendingPairRequests,
        hasLength(1),
        reason:
            '开关开着时收货本来就是自动的：只有"立即收取"那一下才更新，'
            '界面就会在两次手动之间空着一条真在等的请求',
      );
    });

    test('失败的那一轮不清空待确认列表', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.${FnthinkSettings.keyReceiveEnabled}': true,
      });
      final rec = _LoopRecorder()..pollPairRequests = [req('L1')];
      final c = coordinator(recorder: rec);
      await c.startIfEnabled();
      await pumpEventQueue();
      rec.pollStatus = FnthinkPollStatus.transportError;
      rec.pollPairRequests = const [];
      await c.receiveOnce();
      expect(
        c.pendingPairRequests,
        hasLength(1),
        reason: '一次网络抖动之后把请求藏起来，用户分不出它是被撤了、过期了、还是这台根本没看见',
      );
    });

    test('答复成功 ⇒ 那一条立刻从待确认列表里摘掉', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.${FnthinkSettings.keyReceiveEnabled}': true,
      });
      final rec = _LoopRecorder()..pollPairRequests = [req('L1')];
      final asked = <http.Request>[];
      final c = coordinator(
        recorder: rec,
        serviceFactory: armFactory(
          sink: asked,
          body: confirmBody(grantedLevel: 'L1'),
        ),
        recordPeer: (_) async => FnthinkPeerWrite.created,
      );
      await c.receiveOnce();
      expect(c.pendingPairRequests, hasLength(1));
      await c.confirmPairing(request: req('L1'), approve: true);
      expect(
        c.pendingPairRequests,
        isEmpty,
        reason:
            '服务端 consumesRequest：一行只答一次。留着它等于请用户再点一下，'
            '而第二下只会换回一句同形的 403',
      );
    });

    test('在途那一轮的旧回信，不会把已答复的那条画回来（幽灵行）', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.${FnthinkSettings.keyReceiveEnabled}': true,
      });
      final rec = _LoopRecorder()..pollPairRequests = [req('L1')];
      final asked = <http.Request>[];
      final c = coordinator(
        recorder: rec,
        serviceFactory: armFactory(
          sink: asked,
          body: confirmBody(grantedLevel: 'L1'),
        ),
        recordPeer: (_) async => FnthinkPeerWrite.created,
      );
      await c.receiveOnce();
      await c.confirmPairing(request: req('L1'), approve: true);
      expect(c.pendingPairRequests, isEmpty);
      // 一次 poll 的往返可以晚于用户那一下点击：这一轮出发时那条还没被答过，
      // 落地时它已经结掉了 —— 旧回信不许把它画回来。
      await c.receiveOnce();
      expect(
        c.pendingPairRequests,
        isEmpty,
        reason: '那是一条点不开的幽灵行：再点一次换来的是一句与"口令错"同形的 403',
      );
    });

    test('答复没成 ⇒ 那一条还留着（可以再试，或等它过期）', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.${FnthinkSettings.keyReceiveEnabled}': true,
      });
      final rec = _LoopRecorder()..pollPairRequests = [req('L1')];
      final asked = <http.Request>[];
      final c = coordinator(
        recorder: rec,
        serviceFactory: armFactory(
          sink: asked,
          status: 403,
          body: '{"receipt":"${contract.unsignedReceipt}"}',
        ),
      );
      await c.receiveOnce();
      await c.confirmPairing(request: req('L1'), approve: true);
      expect(c.pendingPairRequests, hasLength(1));
    });
  });

  group('撤销那一发 revokePeer（T31 B 片第二片）', () {
    FnthinkPeer peerRow() => const FnthinkPeer(
      peerAddress: '8KMNPQRSTVWX999777',
      publicKey: 'AAAA',
      level: 'L1',
      grantedAt: 1700000000000,
    );

    String revokeBody({required bool revoked}) =>
        '{"revoked":$revoked,"serverTime":1800000000000}';

    /// 从签出去的那一发里把**载荷**取回来（`fields.body` 是 json 字符串，套两层）。
    Map<String, Object?> revokePayload(http.Request request) =>
        jsonDecode(
              (jsonDecode(request.body)['fields']! as Map)['body']! as String,
            )
            as Map<String, Object?>;

    test('撤的是契约声明的那条路径，而载荷里那个地址就是签名针对的那台', () async {
      final asked = <http.Request>[];
      final deleted = <String>[];
      final c = coordinator(
        recorder: _LoopRecorder(),
        serviceFactory: armFactory(
          sink: asked,
          body: revokeBody(revoked: true),
        ),
        removePeer: (addr) async {
          deleted.add(addr);
          return true;
        },
      );
      final result = await c.revokePeer(peerRow());
      expect(result.ok, isTrue);
      expect(asked.single.url.path, contract.apiPath('pairRevoke'));
      expect(
        revokePayload(asked.single).keys.toList(),
        contract.pairRevokeFields,
      );
      expect(revokePayload(asked.single).values.single, '8KMNPQRSTVWX999777');
      expect(deleted, ['8KMNPQRSTVWX999777']);
      expect(result.rowRemoved, isTrue);
    });

    test('那一行不许先于服务端消失：删行只发生在请求回来之后', () async {
      // 顺序是这一发的**判据**，不是实现细节：先删行的话，服务端那一发一旦失败，
      // 本机就再也不显示这一行而授权还留着 —— 对面照样推得进来，而屏幕上没有一行解释来源。
      final steps = <String>[];
      final c = coordinator(
        recorder: _LoopRecorder(),
        serviceFactory: armFactory(
          sink: <http.Request>[],
          body: revokeBody(revoked: true),
          steps: steps,
        ),
        removePeer: (_) async {
          steps.add('remove');
          return true;
        },
      );
      await c.revokePeer(peerRow());
      expect(steps, ['request', 'remove']);
    });

    test('服务端没撤成 ⇒ 本机那一行一个字都不动', () async {
      final asked = <http.Request>[];
      final deleted = <String>[];
      final c = coordinator(
        recorder: _LoopRecorder(),
        serviceFactory: armFactory(
          sink: asked,
          status: 403,
          body: '{"receipt":"${contract.unsignedReceipt}"}',
        ),
        removePeer: (addr) async {
          deleted.add(addr);
          return true;
        },
      );
      final result = await c.revokePeer(peerRow());
      expect(result.ok, isFalse);
      expect(deleted, isEmpty, reason: '撤失败却删了行＝"授权还在而来源消失"那一种静默');
      expect(result.rowRemoved, isNull);
      expect(result.skipped, isNull);
    });

    test('revoked:false 也算成 ⇒ 本机那一行照样删（幂等那半）', () async {
      final deleted = <String>[];
      final c = coordinator(
        recorder: _LoopRecorder(),
        serviceFactory: armFactory(
          sink: <http.Request>[],
          body: revokeBody(revoked: false),
        ),
        removePeer: (addr) async {
          deleted.add(addr);
          return true;
        },
      );
      final result = await c.revokePeer(peerRow());
      expect(
        result.ok,
        isTrue,
        reason:
            '目标状态是「它不在我的名单里」，那边本来没有就是已达成；'
            '把它当失败，用户看到的是一句"撤销没成"而对面其实推不进来',
      );
      expect(result.result.revoked, isFalse);
      expect(deleted, hasLength(1));
    });

    test('服务器撤了而本机删行抛 ⇒ 结论说得出"那一行还留着"', () async {
      final c = coordinator(
        recorder: _LoopRecorder(),
        serviceFactory: armFactory(
          sink: <http.Request>[],
          body: revokeBody(revoked: true),
        ),
        removePeer: (_) async => throw StateError('表被锁'),
      );
      final result = await c.revokePeer(peerRow());
      expect(result.ok, isTrue, reason: '撤销这件事本身成了，失败的是本机那一行');
      expect(result.skipped, FnthinkPeerRemoveSkip.removeFailed);
    });

    test('这台没装配删行 ⇒ storeUnavailable，而不是悄悄留着那一行', () async {
      final c = coordinator(
        recorder: _LoopRecorder(),
        serviceFactory: armFactory(
          sink: <http.Request>[],
          body: revokeBody(revoked: true),
        ),
      );
      final result = await c.revokePeer(peerRow());
      expect(result.ok, isTrue);
      expect(result.skipped, FnthinkPeerRemoveSkip.storeUnavailable);
      expect(result.rowRemoved, isNull);
    });

    test('总开关关着也能撤：撤销不是"收货"的一部分', () async {
      SharedPreferences.setMockInitialValues({}); // 默认关
      final asked = <http.Request>[];
      final c = coordinator(
        recorder: _LoopRecorder(),
        serviceFactory: armFactory(
          sink: asked,
          body: revokeBody(revoked: true),
        ),
        removePeer: (_) async => true,
      );
      final result = await c.revokePeer(peerRow());
      expect(
        asked,
        hasLength(1),
        reason:
            '「关掉收货」是这一台不去取，「别再推给我」是另一件事 —— '
            '后者被前者拦住，等于要用户先打开他刚说不想要的东西才能撤回许可',
      );
      expect(result.ok, isTrue);
    });

    test('签不出来 ⇒ 那一发不发、那一行不动（与答复那一路同一道闸）', () async {
      final asked = <http.Request>[];
      final deleted = <String>[];
      final c = coordinator(
        recorder: _LoopRecorder(),
        signerOverride: signer(false),
        serviceFactory: armFactory(
          sink: asked,
          body: revokeBody(revoked: true),
        ),
        removePeer: (addr) async {
          deleted.add(addr);
          return true;
        },
      );
      final result = await c.revokePeer(peerRow());
      expect(asked, isEmpty);
      expect(deleted, isEmpty);
      expect(result.reason, 'signing-unavailable');
    });
  });

  group('建一条接入端点 createEndpoint（T42 第七片）', () {
    String endpointBody({
      String? endpointId = 'ep_7',
      String? secret = 'ABCDEFGHIJKLMNOP2345678901',
      bool postOnly = true,
    }) =>
        '{"endpointId":${endpointId == null ? 'null' : '"$endpointId"'},'
        '"secret":${secret == null ? 'null' : '"$secret"'},'
        '"postOnly":$postOnly,"serverTime":1800000000000}';

    test('走的是契约声明的那条路径，而口令只在返回值里（prefs 一个键都没多）', () async {
      SharedPreferences.setMockInitialValues({});
      final asked = <http.Request>[];
      final c = coordinator(
        recorder: _LoopRecorder(),
        serviceFactory: armFactory(sink: asked, body: endpointBody()),
      );
      final result = await c.createEndpoint(name: '自家 NAS');
      expect(asked.single.url.path, contract.apiPath('endpointCreate'));
      expect(result.ok, isTrue);
      expect(result.secret, 'ABCDEFGHIJKLMNOP2345678901');
      // 长期凭证不进 prefs：这一条断的是"这件事根本没发生"，不是"值对"——
      // 写进 prefs 的那一份会跟着备份走，而服务端只存了摘要，谁都不知道丢了什么。
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys().where((k) => k.toLowerCase().contains('secret')),
        isEmpty,
        reason: '口令只出现一次是这件事的全部设计；本机留一份副本就等于把它变成一份明文备份',
      );
    });

    test('总开关关着也能建：入口这件事与"现在去不去取货"无关', () async {
      SharedPreferences.setMockInitialValues({}); // 默认关
      final asked = <http.Request>[];
      final c = coordinator(
        recorder: _LoopRecorder(),
        serviceFactory: armFactory(sink: asked, body: endpointBody()),
      );
      final result = await c.createEndpoint(name: 'x');
      expect(asked, hasLength(1));
      expect(result.ok, isTrue);
    });

    test('服务端认了而读不出口令 ⇒ 不算建成（界面无从显示"已创建"）', () async {
      final c = coordinator(
        recorder: _LoopRecorder(),
        serviceFactory: armFactory(
          sink: <http.Request>[],
          body: endpointBody(secret: null),
        ),
      );
      final result = await c.createEndpoint(name: 'x');
      expect(result.ok, isFalse);
      expect(result.reason, 'endpoint-create-unparsable-ack');
    });

    test('429（到上限）⇒ 失败原话带回来，且没冒成成功', () async {
      final c = coordinator(
        recorder: _LoopRecorder(),
        serviceFactory: armFactory(
          sink: <http.Request>[],
          status: 429,
          body: '{}',
        ),
      );
      final result = await c.createEndpoint(name: 'x');
      expect(result.ok, isFalse);
      expect(result.status, FnthinkPollStatus.rateLimited);
    });

    test('签不出来 ⇒ 那一发不发（与其余几发同一道闸）', () async {
      final asked = <http.Request>[];
      final c = coordinator(
        recorder: _LoopRecorder(),
        signerOverride: signer(false),
        serviceFactory: armFactory(sink: asked, body: endpointBody()),
      );
      final result = await c.createEndpoint(name: 'x');
      expect(asked, isEmpty);
      expect(result.ok, isFalse);
      expect(result.reason, 'signing-unavailable');
    });
  });

  group('读自己名下那几把入口 listEndpoints（#157 第二片）', () {
    const listBody =
        '{"endpoints":[{"id":"ep_7","name":"nas","status":"active",'
        '"createdAt":1700000000000}],"serverTime":1800000000000}';

    test('走的是契约声明的那条路径，而读回来的那份不在 prefs 里', () async {
      SharedPreferences.setMockInitialValues({});
      final asked = <http.Request>[];
      final c = coordinator(
        recorder: _LoopRecorder(),
        serviceFactory: armFactory(sink: asked, body: listBody),
      );
      final result = await c.listEndpoints();
      expect(asked.single.url.path, contract.apiPath('endpointList'));
      expect(result.ok, isTrue);
      expect(result.endpoints!.single.id, 'ep_7');
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys().where((k) => '${prefs.get(k)}'.contains('ep_7')),
        isEmpty,
        reason: '端点表的真值在服务端：本机存一份就是一本会漂的账 —— 那边吊销了，这本还写着"在用"',
      );
    });

    test('总开关关着也读得到：我有哪些入口与"这台现在去不去取货"是两件事', () async {
      SharedPreferences.setMockInitialValues({}); // 默认关
      final asked = <http.Request>[];
      final c = coordinator(
        recorder: _LoopRecorder(),
        serviceFactory: armFactory(sink: asked, body: listBody),
      );
      final result = await c.listEndpoints();
      expect(asked, hasLength(1));
      expect(
        result.ok,
        isTrue,
        reason:
            '把它绑到总开关上的下场：用户关接收省电，页面随之说"还没有端点"，'
            '而他挂在 NAS 上那把还在收信',
      );
    });

    test('签不出来 ⇒ 那一发不发，reason 是那句原话而不是空列表', () async {
      final asked = <http.Request>[];
      final c = coordinator(
        recorder: _LoopRecorder(),
        signerOverride: signer(false),
        serviceFactory: armFactory(sink: asked, body: listBody),
      );
      final result = await c.listEndpoints();
      expect(asked, isEmpty);
      expect(result.ok, isFalse);
      expect(
        result.endpoints,
        isNull,
        reason: '冒成空列表就是当着用户的面说"你没有端点"，而这次连一发都没出去',
      );
      expect(result.reason, 'signing-unavailable');
    });
  });

  group('关掉一条入口 revokeEndpoint（#157 第四片）', () {
    const revokeBody =
        '{"endpointId":"ep_7","revoked":true,"serverTime":1800000000000}';

    test('走的是契约声明的那条路径，而载荷里是那把 id', () async {
      SharedPreferences.setMockInitialValues({});
      final asked = <http.Request>[];
      final c = coordinator(
        recorder: _LoopRecorder(),
        serviceFactory: armFactory(sink: asked, body: revokeBody),
      );
      final result = await c.revokeEndpoint(endpointId: 'ep_7');
      expect(asked.single.url.path, contract.apiPath('endpointRevoke'));
      expect(result.ok, isTrue);
      expect(result.revoked, isTrue);
      expect(result.endpointId, 'ep_7');
    });

    test('总开关关着也关得掉：关一把入口与"这台现在去不去取货"无关', () async {
      SharedPreferences.setMockInitialValues({}); // 默认关
      final asked = <http.Request>[];
      final c = coordinator(
        recorder: _LoopRecorder(),
        serviceFactory: armFactory(sink: asked, body: revokeBody),
      );
      final result = await c.revokeEndpoint(endpointId: 'ep_7');
      expect(asked, hasLength(1));
      expect(
        result.ok,
        isTrue,
        reason: '关着接收的时候恰恰最可能需要关掉一把还在收信的入口 —— 绑到开关上就是那时候不给关',
      );
    });

    test('签不出来 ⇒ 那一发不发，reason 是那句原话（不说"已关闭"）', () async {
      final asked = <http.Request>[];
      final c = coordinator(
        recorder: _LoopRecorder(),
        signerOverride: signer(false),
        serviceFactory: armFactory(sink: asked, body: revokeBody),
      );
      final result = await c.revokeEndpoint(endpointId: 'ep_7');
      expect(asked, isEmpty);
      expect(result.ok, isFalse);
      expect(
        result.revoked,
        isNull,
        reason: '一句"已关闭"说错，用户就不再去管理面关，而 NAS 还在往那把入口推',
      );
      expect(result.reason, 'signing-unavailable');
    });
  });

  group('换一条端点的口令 rotateEndpoint（#157 第六片）', () {
    const rotateBody =
        '{"endpointId":"ep_7","rotated":true,"secret":"ZZZ7RABQKPZ3STVWX234",'
        '"rotatingUntil":1800003600000,"serverTime":1800000000000}';

    test('走的是契约声明的那条路径，而新口令与截止日期都在返回值里', () async {
      SharedPreferences.setMockInitialValues({});
      final asked = <http.Request>[];
      final c = coordinator(
        recorder: _LoopRecorder(),
        serviceFactory: armFactory(sink: asked, body: rotateBody),
      );
      final result = await c.rotateEndpoint(endpointId: 'ep_7');
      expect(asked.single.url.path, contract.apiPath('endpointRotate'));
      expect(result.exchanged, isTrue);
      expect(result.secret, 'ZZZ7RABQKPZ3STVWX234');
      expect(result.rotatingUntil, 1800003600000);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys().where(
          (k) => '${prefs.get(k)}'.contains('ZZZ7RABQKPZ3STVWX234'),
        ),
        isEmpty,
        reason:
            '新口令只在这一次出现：写进 prefs 的那一份会跟着备份走，'
            '而服务端只有摘要 —— 谁都不知道丢了什么',
      );
    });

    test('总开关关着也换得动：口令泄露了而接收正关着，恰恰是要换的那一回', () async {
      SharedPreferences.setMockInitialValues({}); // 默认关
      final asked = <http.Request>[];
      final c = coordinator(
        recorder: _LoopRecorder(),
        serviceFactory: armFactory(sink: asked, body: rotateBody),
      );
      final result = await c.rotateEndpoint(endpointId: 'ep_7');
      expect(asked, hasLength(1));
      expect(result.exchanged, isTrue);
    });

    test('签不出来 ⇒ 那一发不发，reason 是那句原话（不说"已换过"）', () async {
      final asked = <http.Request>[];
      final c = coordinator(
        recorder: _LoopRecorder(),
        signerOverride: signer(false),
        serviceFactory: armFactory(sink: asked, body: rotateBody),
      );
      final result = await c.rotateEndpoint(endpointId: 'ep_7');
      expect(asked, isEmpty);
      expect(result.ok, isFalse);
      expect(
        result.secret,
        isNull,
        reason: '一句"已换过"而手上没有新口令，是这一发最坏的假象：旧的那把已经在倒计时了',
      );
      expect(result.reason, 'signing-unavailable');
    });
  });

  group('发一条给名单里那台 sendNotice（§4-10 片2）', () {
    const sentBody =
        '{"receipt":"queued","messageId":"m_31","action":"new","evicted":[]}';

    test('开关关着也发得出去：发这一条与"这台现在去不去取货"是两件事', () async {
      SharedPreferences.setMockInitialValues({}); // 没有 receive_enabled ⇒ 默认关
      final asked = <http.Request>[];
      final rec = _LoopRecorder();
      final c = coordinator(
        recorder: rec,
        serviceFactory: armFactory(sink: asked, status: 202, body: sentBody),
      );
      final result = await c.sendNotice(
        peer: '7YD4RKQPBM8XZ3VHNT',
        title: '到家了',
        text: '门已开',
      );
      expect(
        result.status,
        FnthinkSendStatus.accepted,
        reason:
            '用接收总开关挡住发送 ⇒ 用户为了省电关掉收货，随之连"发一条"都发不出去，'
            '而屏幕上只有一句"发送失败"',
      );
      expect(asked.single.url.path, contract.apiPath('message'));
      expect(c.isRunning, isFalse, reason: '发一条不该顺手把收货循环也起来（那是替用户点了"开始接收"）');
      expect(rec.specs, isEmpty);
    });

    test('前置不满足时一句都没离机，而说的是"本机还没就绪"而不是"网络不好"', () async {
      final asked = <http.Request>[];

      final noContract = coordinator(
        recorder: _LoopRecorder(),
        contracts: FnthinkContractLoader(readAsset: (_) async => '{ 坏 JSON'),
        serviceFactory: armFactory(sink: asked, status: 202, body: sentBody),
      );
      final r1 = await noContract.sendNotice(
        peer: '7YD4RKQPBM8XZ3VHNT',
        title: 't',
        text: 'b',
      );
      expect(r1.status, FnthinkSendStatus.preconditionFailed);
      expect(r1.reason, startsWith('contract-unavailable'));

      SharedPreferences.setMockInitialValues({
        FnthinkSettings.keyHost: 'a b/c',
      });
      final badHost = coordinator(
        recorder: _LoopRecorder(),
        serviceFactory: armFactory(sink: asked, status: 202, body: sentBody),
      );
      final r2 = await badHost.sendNotice(
        peer: '7YD4RKQPBM8XZ3VHNT',
        title: 't',
        text: 'b',
      );
      expect(r2.status, FnthinkSendStatus.preconditionFailed);
      expect(r2.reason, startsWith('settings-invalid'));

      SharedPreferences.setMockInitialValues({});
      final cannotSign = coordinator(
        recorder: _LoopRecorder(),
        signerOverride: signer(false),
        serviceFactory: armFactory(sink: asked, status: 202, body: sentBody),
      );
      final r3 = await cannotSign.sendNotice(
        peer: '7YD4RKQPBM8XZ3VHNT',
        title: 't',
        text: 'b',
      );
      expect(r3.status, FnthinkSendStatus.preconditionFailed);
      expect(r3.reason, 'signing-unavailable');
      expect(asked, isEmpty);
    });
  });
}

class _FakeSigner implements FnthinkIdentitySigner {
  _FakeSigner(this.ok, {this.onProbe});

  final bool ok;
  final void Function()? onProbe;

  @override
  Future<String> call(List<int> canonicalBytes) async =>
      base64Encode(Uint8List(64));

  @override
  Future<bool> probe() async {
    if (onProbe != null) onProbe!();
    return ok;
  }
}

/// 只记 URL、回一个空队列的假 HTTP。
class _FakeClient extends http.BaseClient {
  _FakeClient(this.asked);

  final List<String> asked;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    asked.add(request.url.toString());
    final body = utf8.encode(
      jsonEncode({
        'messages': <Object?>[],
        'receipts': <Object?>[],
        'pending': 0,
        'serverTime': 1700000000000,
        'pairRequests': <Object?>[],
      }),
    );
    return http.StreamedResponse(
      Stream<List<int>>.value(body),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

/// 记次数与入参的循环工厂：返回一个真循环，但传输是假的（排期也不真等）。
class _LoopRecorder {
  final List<FnthinkLoopSpec> specs = [];
  int polls = 0;

  /// 假的那一轮"取回"什么。第五片用它把后台轮次里的配对请求喂进来 ——
  /// 这一片要钉的正是"那一轮看到的请求，有没有人接住"。
  FnthinkPollStatus pollStatus = FnthinkPollStatus.ok;
  List<FnthinkPairRequest> pollPairRequests = const [];

  FnthinkReceiveLoop build(FnthinkLoopSpec spec) {
    specs.add(spec);
    return FnthinkReceiveLoop(
      poll: () async {
        polls++;
        return FnthinkReceiveOutcome(
          status: pollStatus,
          pairRequests: pollPairRequests,
          nextDelay: const Duration(seconds: 20),
          reason: pollStatus == FnthinkPollStatus.ok ? null : 'simulated',
        );
      },
      ack: (id, result) async => const FnthinkAckResult(
        status: FnthinkPollStatus.ok,
        nextDelay: Duration.zero,
      ),
      persist: (_) async => true,
      // 协调者塞进 spec 的那一行必须接上：不接，"后台那几轮的账"这件事在测试里就永远不发生，
      // 那条用例只会红在别处（或者谁也不红）。
      onRound: spec.onRound,
      schedule: (delay, callback) {
        final t = Timer(delay, callback);
        _timers.add(t);
        return t;
      },
    );
  }

  int get builds => specs.length;
}

final _timers = <Timer>[];
