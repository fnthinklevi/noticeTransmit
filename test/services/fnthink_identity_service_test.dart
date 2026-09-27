import 'dart:convert';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_identity_service.dart';

/// 幻念推送身份服务（T29 的签名入口）。
///
/// 两条容易写歪的地方，本文件各钉一遍：
///  ① 原生"成功"不等于拿到身份 —— 公钥为空必须当失败，否则对端会把一把谁都签不动的公钥
///     写进白名单，而本机日志里全是一片绿；
///  ② 规范化是**签名的输入契约**，缺字段要在跨通道之前就抛。真走到原生才发现问题，
///     等于让原生替 Dart 兜住"少传了什么"，那正是本项目反复出事的两端各兜一半。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.fnthink.notice/notification');
  final contract = FnthinkContract.readFile();

  late List<MethodCall> calls;

  void mock(Object? Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return handler(call);
        });
  }

  Map<String, Object?> fields() => {
    'version': '1',
    'type': 'notice',
    'target': '8K3FJ6QPTM9WZ4VHNS',
    'ts': '1760000000',
    'nonce': 'n-1',
    'body': '电量已低于 20%',
  };

  setUp(() => calls = <MethodCall>[]);
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('身份读取', () {
    test('三字段如实透传（含 keystoreBacked=false 那条）', () async {
      mock(
        (_) => {
          'publicKey': 'AAAAgICAgICAgICAgICAgICgoKCgoKCgoKCgoKCgoKA=',
          'plan': 'keystoreWrappedSoftwareKey',
          'keystoreBacked': false,
        },
      );
      final identity = await FnthinkIdentityService().identity();
      expect(identity, isNotNull);
      expect(identity!.plan, 'keystoreWrappedSoftwareKey');
      expect(
        identity.keystoreBacked,
        isFalse,
        reason: '包裹路径不许自称 keystoreBacked：不可导出的是包裹密钥，不是私钥本体',
      );
    });

    test('原生没给 keystoreBacked 时按 false（缺省只能往弱的那一侧缺省）', () async {
      mock(
        (_) => {
          'publicKey': 'AAAAgICAgICAgICAgICAgICgoKCgoKCgoKCgoKCgoKA=',
          'plan': 'keystoreWrappedSoftwareKey',
        },
      );
      final identity = await FnthinkIdentityService().identity();
      expect(identity, isNotNull);
      expect(
        identity!.keystoreBacked,
        isFalse,
        reason: '缺字段时默认 true 会把"不可导出的密钥包裹"报成"不可导出的密钥"',
      );
    });

    test('公钥为空算失败，不返回一个"看起来成功"的身份', () async {
      mock(
        (_) => {
          'publicKey': '',
          'plan': 'androidKeyStoreEd25519',
          'keystoreBacked': true,
        },
      );
      expect(await FnthinkIdentityService().identity(), isNull);
    });

    test('原生报错时返回 null 而不是抛给 UI', () async {
      mock(
        (_) => throw PlatformException(
          code: 'identity_unavailable',
          message: 'KeyStore 不可用',
        ),
      );
      expect(await FnthinkIdentityService().identity(), isNull);
      expect(calls.single.method, 'getFnthinkIdentity');
    });

    test('toString 不整串吐出公钥（日志里少一份可被拼接的副本）', () async {
      const identity = FnthinkDeviceIdentity(
        publicKey: 'AAAAgICAgICAgICAgICAgICgoKCgoKCgoKCgoKCgoKA=',
        plan: 'androidKeyStoreEd25519',
        keystoreBacked: true,
      );
      expect(identity.toString(), contains('androidKeyStoreEd25519'));
      expect(
        identity.toString(),
        isNot(contains('AAAAgICAgICAgICAgICAgICgoKCgoKCgoKCgoKCgoKA=')),
      );
    });
  });

  group('签名', () {
    test('送出去的是规范化字节的 base64，参数名与原生一致', () async {
      final expected = CanonicalMessage.bytes(contract, fields());
      mock((call) {
        expect(call.method, 'signFnthinkBytes');
        return base64Encode(List<int>.generate(64, (i) => i));
      });
      final signature = await FnthinkIdentityService().signCanonicalBytes(
        expected,
      );
      expect(signature, hasLength(64));
      final sent = calls.single.arguments! as Map<Object?, Object?>;
      expect(sent.keys.single, 'canonicalBase64');
      expect(sent['canonicalBase64'], base64Encode(expected));
    });

    test('签名字段缺一项 ⇒ 当场抛并点名，且一次都不碰通道', () async {
      final missing = fields()..remove('nonce');
      await expectLater(
        FnthinkIdentityService().signFields(contract, missing),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('nonce'),
          ),
        ),
      );
      expect(calls, isEmpty, reason: '规范化失败不该让原生去兜');
    });

    test('递给原生签的字节 = 契约拼出的那一串，两条入口拼出同一串', () async {
      // 钉的是"入口拼的字节 = 对端将来重算的字节"。服务端（Node）按契约顺序重算一遍再验签，
      // 所以顺序 / 分隔符 / 少拼一个字段任何一处歪了，双端就永远对不上签名，
      // 而两边各自跑测试都还是绿的（各测各的拼接）。真正的密码学互操作在别处钉：
      // Kotlin 仪器测试里用 eddsa 独立实现自验一次（T26-B），服务端用 Node 原生 Ed25519 验（T29-B）。
      final given = fields();
      final canonical = Uint8List.fromList(
        CanonicalMessage.bytes(contract, given),
      );
      expect(
        utf8.decode(canonical).split(String.fromCharCode(0)),
        contract.canonicalOrder.map((k) => '${given[k]}').toList(),
        reason: '按契约分隔符切开，必须正好是契约那一串字段值（顺序也是契约的顺序）',
      );
      mock((_) => null);
      final service = FnthinkIdentityService();
      expect(
        await service.signCanonicalBytes(canonical),
        isNull,
        reason: '原生返回空签名 ⇒ 如实算失败（下一条用例细说）',
      );
      expect(await service.signFields(contract, given), isNull);
      expect(calls, hasLength(2), reason: '两条入口各递给原生签一次');
      Uint8List handed(int i) => base64Decode(
        (calls[i].arguments as Map)['canonicalBase64'] as String,
      );
      expect(handed(0), canonical, reason: '拿着现成字节的那条入口不许自己再拼一套');
      expect(handed(1), canonical, reason: '按字段拼的那条入口必须拼出**同一串**，否则同一句话会有两个签名');
    });

    test('原生返回空签名算失败（否则会把 null 当签名发出去）', () async {
      for (final junk in <Object?>[null, '']) {
        calls.clear();
        mock((_) => junk);
        expect(
          await FnthinkIdentityService().signCanonicalBytes([1, 2, 3]),
          isNull,
        );
      }
    });
  });
}
