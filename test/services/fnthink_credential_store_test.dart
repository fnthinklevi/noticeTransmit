import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:notice_transmit/services/fnthink_credential_store.dart';

import '../support/source_guards.dart';
import '../test_setup.dart';

/// T26 的设备侧凭证落盘：地址码与一次性配对口令怎么生成、怎么存、什么时候绝不自己换。
///
/// 三条判据各有"写反了会怎样"：
///  ① 存量校验不过 ⇒ **抛**，不许"那就换一枚"。换一枚的表现不是报错，而是别人白名单里那一条
///     指向一台不再存在的设备，而用户抄给别人的那串字符还在生效地失败着；
///  ② 口令过期**不在本机判**。一台时钟漂了两天的设备若自己判过期而不再显示口令，
///     界面上就是"永远挂不出口令"，最难查的那种；本机只有"看起来挂了多久"这一层显示;
///  ③ 口令不进日志（连 toString 都不带本体），且不落 prefs（明文 XML）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final contract = FnthinkContract.readFile();
  late Map<String, String?> disk;

  setUp(() {
    disk = {};
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
        if (call.method == 'deleteAll') {
          disk.clear();
          return null;
        }
        return null;
      },
    );
  });

  tearDown(clearNativeChannelStubs);

  final store = FnthinkCredentialStore(contract: contract);

  group('地址码', () {
    test('首启自动生成一枚，形状按契约来（位数与字母表都不是这里写的）', () async {
      final code = await store.ensureAddressCode();
      final length = contract.identityLength('addressCode');
      expect(code.value.length, length);
      expect(code.value, isNot(anyOf(contains('I'), contains('L'))));
      expect(code.value, isNot(anyOf(contains('O'), contains('U'))));
      expect(disk[FnthinkCredentialStore.addressCodeKey], code.value);
    });

    test('第二次读回同一枚，绝不重新生成', () async {
      final first = await store.ensureAddressCode();
      final second = await store.ensureAddressCode();
      expect(second.value, first.value);
    });

    test('① 存量坏掉 ⇒ 抛，且原来那一串还在盘上（不自作主张换）', () async {
      await store.ensureAddressCode();
      disk[FnthinkCredentialStore.addressCodeKey] = 'ILOU-短';
      await expectLater(
        store.ensureAddressCode(),
        throwsA(isA<FnthinkCredentialCorrupted>()),
      );
      expect(
        disk[FnthinkCredentialStore.addressCodeKey],
        'ILOU-短',
        reason: '抛之前不许顺手改写盘上的值：改写等于抹掉排查现场',
      );
    });

    test('resetAddressCode 才换一枚（页面那条路必须走二次确认）', () async {
      final before = await store.ensureAddressCode();
      final after = await store.resetAddressCode();
      expect(after.value, isNot(before.value));
      expect(disk[FnthinkCredentialStore.addressCodeKey], after.value);
      expect(await store.ensureAddressCode(), after);
    });
  });

  group('配对口令', () {
    test('arm 一枚：长度按契约、时间戳落盘、重复 arm 必换新的', () async {
      final length = contract.identityLength('pairingCode');
      final first = await store.armPairingCode(nowMs: 1000);
      expect(first.code.value.length, length);
      expect(first.armedAtMs, 1000);
      expect(first.ttlSeconds, contract.identityTtlSeconds('pairingCode'));
      expect(disk[FnthinkCredentialStore.pairingArmedAtKey], '1000');

      final second = await store.armPairingCode(nowMs: 2000);
      expect(second.code.value, isNot(first.code.value));
      expect(await store.currentPairingCode(), isNotNull);
    });

    test('没挂过 ⇒ null（不是空串、也不是"生成长度为 0 的口令"）', () async {
      expect(await store.currentPairingCode(), isNull);
    });

    test('② 过期不在本机判：时间戳漂到未来也照样带回，只给一个"看起来"的显示值', () async {
      await store.armPairingCode(nowMs: 0);
      final ttl = contract.identityTtlSeconds('pairingCode')!;
      final late = await store.currentPairingCode();
      expect(late, isNotNull, reason: '判活不判活是服务端的事（它按 serverTime 算）');
      expect(late!.looksExpired(ttl * 1000 + 1), isTrue);
      expect(late.looksExpired(1), isFalse);
      expect(late.ageMs(ttl * 1000 + 1), ttl * 1000 + 1);
    });

    test('时间戳缺失时 age/过期都是 null（显示"未知"，不许显示 0 秒）', () async {
      await store.armPairingCode(nowMs: 5000);
      disk.remove(FnthinkCredentialStore.pairingArmedAtKey);
      final state = await store.currentPairingCode();
      expect(state!.armedAtMs, isNull);
      expect(state.ageMs(99999), isNull);
      expect(state.looksExpired(99999), isNull);
    });

    test('clearPairingCode 只撤口令，不动地址码', () async {
      final code = await store.ensureAddressCode();
      await store.armPairingCode(nowMs: 1);
      await store.clearPairingCode();
      expect(await store.currentPairingCode(), isNull);
      expect(disk[FnthinkCredentialStore.pairingArmedAtKey], isNull);
      expect(await store.ensureAddressCode(), code);
    });

    test('clearAll 两件都清（换机/恢复出厂那条路）', () async {
      await store.ensureAddressCode();
      await store.armPairingCode(nowMs: 1);
      await store.clearAll();
      expect(disk.keys.where((k) => disk[k] != null), isEmpty);
    });

    test('③ 口令坏掉的存量 ⇒ 抛（重新生成就能修，但不许读出一个空口令）', () async {
      disk[FnthinkCredentialStore.pairingCodeKey] = '!!!不是字母表里的!!!';
      await expectLater(
        store.currentPairingCode(),
        throwsA(isA<FnthinkCredentialCorrupted>()),
      );
    });
  });

  group('不泄露', () {
    test('toString 里没有口令本体（日志会离开这台机）', () async {
      final armed = await store.armPairingCode(nowMs: 10);
      expect(armed.toString(), isNot(contains(armed.code.value)));
      expect(armed.toString(), contains('****'));
    });

    test('本文件不 import shared_preferences：口令不许落明文 XML', () {
      final src = stripComments(
        File(
          '${projectRoot()}/lib/services/fnthink_credential_store.dart',
        ).readAsStringSync(),
      );
      expect(src, isNot(contains('shared_preferences')));
      expect(src, isNot(contains('SharedPreferences')));
    });

    test('位数与 ttl 都不写在代码里（只有一个出处：契约）', () {
      final src = stripComments(
        File(
          '${projectRoot()}/lib/services/fnthink_credential_store.dart',
        ).readAsStringSync(),
      );
      // 地址码 18 / 口令 20 / ttl 300 这三个数一旦在这里出现，就是在抄第二份。
      expect(RegExp(r'\b(18|20|300)\b').hasMatch(src), isFalse, reason: src);
    });
  });
}
