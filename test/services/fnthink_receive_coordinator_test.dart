import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:http/http.dart' as http;
import 'package:notice_transmit/models/fnthink_inbox_message.dart';
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
  }) => FnthinkReceiveCoordinator(
    contracts: contracts ?? goodLoader(),
    signer: signerOverride ?? signer(true),
    persist: persist,
    loopFactory: recorder.build,
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

  FnthinkReceiveLoop build(FnthinkLoopSpec spec) {
    specs.add(spec);
    return FnthinkReceiveLoop(
      poll: () async {
        polls++;
        return const FnthinkReceiveOutcome(
          status: FnthinkPollStatus.ok,
          nextDelay: Duration(seconds: 20),
        );
      },
      ack: (id, result) async => const FnthinkAckResult(
        status: FnthinkPollStatus.ok,
        nextDelay: Duration.zero,
      ),
      persist: (_) async => true,
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
