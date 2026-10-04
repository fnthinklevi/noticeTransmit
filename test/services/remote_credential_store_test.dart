import 'dart:math';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_remote_execution.dart';
import 'package:notice_transmit/services/remote_credential_store.dart';
import 'package:notice_transmit/services/remote_credentials.dart';
import 'package:notice_transmit/services/secure_storage_service.dart';

/// 内存替身：让这一组能在 `flutter test`（无 AndroidKeyStore）里跑真加密存取那一层。
class _MemStorage implements SecureStorageService {
  final Map<String, String> data = {};

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> delete(String key) async => data.remove(key);

  @override
  Future<void> clearAll() async => data.clear();

  @override
  Future<void> saveWebhookUrls(List<String> urls) async {}

  @override
  Future<List<String>> loadWebhookUrls() async => const [];

  @override
  Future<void> saveWebhookChannels(String jsonStr) async {}

  @override
  Future<String?> loadWebhookChannels() async => null;
}

/// 远程执行 片3b：凭据的本机存法与校验（**这一组全是安全面**）。
///
/// 钉的是七件：
///  ① 本机**不存明文密钥**（只存 `sha256(salt|key)`）；
///  ② 有哈希没盐 ⇒ **抛**，不当"还没设过"（否则用户重设一把之后旧的还在别人手里）；
///  ③ 生成的那一把当场能对，换一个对不上；
///  ④ 自定义密钥太短 ⇒ 抛（不悄悄截断也不补长）；
///  ⑤ TOTP 种子缺失 ⇒ `totpValid` **一律 false**（fail-closed：没配过的设备不该被打开）；
///  ⑥ 换 TOTP 种子 = 已录进验证器的那枚作废，而新种子能算出自己的码；
///  ⑦ 开了开关但一把凭据都没有 ⇒ L3 一条都进不来（`l3Unreachable`）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final contract = FnthinkContract.readFile();
  late _MemStorage storage;
  late RemoteCredentialStore store;
  // 固定时刻：TOTP 是按时间步算的，注入时钟才不用睡真表。
  var nowMs = 1700000000000;

  setUp(() {
    storage = _MemStorage();
    store = RemoteCredentialStore(
      contract: contract,
      storage: storage,
      random: Random(20261004),
      clockMs: () => nowMs,
    );
  });

  group('本机不存明文', () {
    test('生成一把之后，存储里找不到那串明文', () async {
      final issue = await store.generateKey();
      expect(
        issue.key.length,
        greaterThanOrEqualTo(contract.remoteExecutionKeyMinLength),
      );
      final blob = storage.data.values.join('|');
      expect(
        blob.contains(issue.key),
        isFalse,
        reason: '明文密钥落盘 = 任何能读那个文件的人都能控制这台设备',
      );
    });

    test('存储里存的是哈希与盐两样，且盐不为空', () async {
      await store.generateKey();
      expect(storage.data[RemoteCredentialStore.keyHashKey], isNotNull);
      expect(storage.data[RemoteCredentialStore.saltKey], isNotEmpty);
      expect(
        storage.data.values,
        isNot(contains(RemoteCredentialStore.totpSecretKey)),
      );
    });

    test('生成的那一把当场能对上，换一个对不上', () async {
      final issue = await store.generateKey();
      expect(await store.keyMatches(issue.key), isTrue);
      expect(await store.keyMatches('${issue.key}x'), isFalse);
      expect(await store.keyMatches(''), isFalse);
    });

    test('两次生成给的是两把不同的密钥（不返回同一枚）', () async {
      final a = await store.generateKey();
      final b = await store.generateKey();
      expect(a.key, isNot(b.key));
      expect(await store.keyMatches(a.key), isFalse, reason: '换过之后旧的那把应当作废');
    });

    test('同一枚密钥在两台机器（不同盐）上哈希不同', () async {
      final a = await store.generateKey();
      final other = RemoteCredentialStore(
        contract: contract,
        storage: _MemStorage(),
        random: Random(7),
        clockMs: () => nowMs,
      );
      final b = await other.generateKey();
      expect(hashRemoteKey(a.key, a.salt), isNot(hashRemoteKey(a.key, b.salt)));
    });
  });

  group('存量坏了要喊，不当"还没设过"', () {
    test('有哈希没盐 ⇒ 读的时候抛（不是回 null）', () async {
      storage.data[RemoteCredentialStore.keyHashKey] = 'deadbeef';
      await expectLater(
        store.read(),
        throwsA(isA<RemoteCredentialCorrupted>()),
      );
    });

    test('坏了这件事在 state() 里报出来，与"还没设过"是两句不同的话', () async {
      storage.data[RemoteCredentialStore.keyHashKey] = 'deadbeef';
      final read = await store.state(enabled: true, delaySeconds: 10);
      expect(read.problem, isNotNull);
      expect(read.entry, isNull, reason: '坏了不等于"还没设过"：后者会让用户重设一把，而旧的还在别人手里');
      expect(read.l3Unreachable, isFalse, reason: '坏了那一档要走"重置"，不是"还没设"');
    });

    test('什么都没设时：entry 为 null、problem 为 null、l3Unreachable 为真', () async {
      final read = await store.state(enabled: true, delaySeconds: 10);
      expect(read.entry, isNull);
      expect(read.problem, isNull);
      expect(read.hasKey, isFalse);
      expect(read.hasTotp, isFalse);
      expect(read.l3Unreachable, isTrue);
    });

    test('关了开关时即便没凭据也不是"进不来"（那是 L3 那句话的前提）', () async {
      final read = await store.state(enabled: false, delaySeconds: 10);
      expect(read.l3Unreachable, isFalse);
    });
  });

  group('自定义密钥', () {
    test('够长的那把写进去之后能对上', () async {
      await store.setCustomKey('my-long-key-1234');
      expect(await store.keyMatches('my-long-key-1234'), isTrue);
      expect(await store.keyMatches('my-long-key-12345'), isFalse);
    });

    test('长度不够契约要求就抛，且不写盘', () async {
      final short = 'a' * (contract.remoteExecutionKeyMinLength - 1);
      await expectLater(
        store.setCustomKey(short),
        throwsA(isA<RemoteCredentialInvalid>()),
      );
      expect(await store.read(), isNull);
    });

    test('恰好够长就收（边界那一档不是越界）', () async {
      final exact = 'a' * contract.remoteExecutionKeyMinLength;
      await store.setCustomKey(exact);
      expect(await store.keyMatches(exact), isTrue);
    });

    test('前后空格被裁掉之后才对得上（用户复制时常常带着）', () async {
      await store.setCustomKey('my-long-key-1234');
      expect(await store.keyMatches('  my-long-key-1234  '), isFalse);
      expect(await store.keyMatches('my-long-key-1234'), isTrue);
    });
  });

  group('TOTP 种子：存在本机且缺失即 fail-closed', () {
    test('生成的那枚种子能算出自己的码（对着 RFC 6238 的形状）', () async {
      final issue = await store.generateTotp(account: '8K3FJ6QPTM9WZ4VHNS');
      final shape = contract.remoteExecutionTotpShape;
      final expected = totpCodeAt(
        issue.secret,
        atMs: nowMs,
        digits: shape.digits,
        periodSeconds: shape.periodSeconds,
      );
      expect(await store.totpValid(expected), isTrue);
      expect(expected.length, shape.digits);
    });

    test('没设种子时任何码都不认（fail-closed）', () async {
      expect(await store.totpValid('123456'), isFalse);
      expect(await store.totpValid(''), isFalse);
    });

    test('错的码一律拒', () async {
      final issue = await store.generateTotp(account: 'x');
      final shape = contract.remoteExecutionTotpShape;
      final real = totpCodeAt(
        issue.secret,
        atMs: nowMs,
        digits: shape.digits,
        periodSeconds: shape.periodSeconds,
      );
      final wrong = real == '000000' ? '111111' : '000000';
      expect(await store.totpValid(wrong), isFalse);
    });

    test('otpauth 链接能带出种子、位数与步长（验���器 App 的标准录入格式）', () async {
      final issue = await store.generateTotp(account: '8K3FJ6QPTM9WZ4VHNS');
      expect(issue.uri, startsWith('otpauth://totp/'));
      expect(issue.uri, contains('secret=${issue.secret}'));
      expect(
        issue.uri,
        contains('digits=${contract.remoteExecutionTotpShape.digits}'),
      );
      expect(
        issue.uri,
        contains('period=${contract.remoteExecutionTotpShape.periodSeconds}'),
      );
    });

    test('换种子之后新码能认、旧码不认（旧的那枚已作废）', () async {
      final first = await store.generateTotp(account: 'x');
      final shape = contract.remoteExecutionTotpShape;
      final oldCode = totpCodeAt(
        first.secret,
        atMs: nowMs,
        digits: shape.digits,
        periodSeconds: shape.periodSeconds,
      );
      final second = await store.generateTotp(account: 'x');
      expect(second.secret, isNot(first.secret));
      expect(await store.totpValid(oldCode), isFalse);
      final newCode = totpCodeAt(
        second.secret,
        atMs: nowMs,
        digits: shape.digits,
        periodSeconds: shape.periodSeconds,
      );
      expect(await store.totpValid(newCode), isTrue);
    });

    test('撤掉种子之后任何码都不认', () async {
      await store.generateKey();
      final issue = await store.generateTotp(account: 'x');
      final shape = contract.remoteExecutionTotpShape;
      final code = totpCodeAt(
        issue.secret,
        atMs: nowMs,
        digits: shape.digits,
        periodSeconds: shape.periodSeconds,
      );
      expect(await store.totpValid(code), isTrue, reason: '锚点：撤之前这一码是认的');
      await store.clearTotp();
      final read = await store.read();
      expect(read?.hasTotp, isFalse, reason: '只剩密钥那一份，entry 不该是 null');
      expect(read?.hasKey, isTrue);
      expect(await store.totpValid(code), isFalse);
    });

    test('越出 ±1 步窗口的旧码不认（两步之外就不算时钟偏移了）', () async {
      final issue = await store.generateTotp(account: 'x');
      final shape = contract.remoteExecutionTotpShape;
      final first = totpCodeAt(
        issue.secret,
        atMs: nowMs,
        digits: shape.digits,
        periodSeconds: shape.periodSeconds,
      );
      expect(await store.totpValid(first), isTrue, reason: '锚点：当下这一码是认的');
      nowMs += shape.periodSeconds * 1000;
      expect(
        await store.totpValid(first),
        isTrue,
        reason: '差一步仍认：那是允许的时钟偏移（默认窗口 ±1）',
      );
      nowMs += shape.periodSeconds * 1000;
      expect(
        await store.totpValid(first),
        isFalse,
        reason: '差两步就不认：再宽就是「一个码在两分钟里都能用」，那不叫二步验证',
      );
    });
  });

  group('撤回', () {
    test('撤掉密钥之后哈希与盐都不在', () async {
      await store.generateKey();
      await store.clearKey();
      expect(
        storage.data.containsKey(RemoteCredentialStore.keyHashKey),
        isFalse,
      );
      expect(await store.keyMatches('anything'), isFalse);
    });

    test('全撤之后连盐一起没（留着它等于上次那把的哈希还在算）', () async {
      await store.generateKey();
      await store.generateTotp(account: 'x');
      await store.clearAll();
      expect(storage.data.containsKey(RemoteCredentialStore.saltKey), isFalse);
      expect(
        storage.data.containsKey(RemoteCredentialStore.totpSecretKey),
        isFalse,
      );
      expect(await store.read(), isNull);
    });

    test('撤掉密钥不影响已录的 TOTP（两件凭据互不派生）', () async {
      await store.generateKey();
      final issue = await store.generateTotp(account: 'x');
      final shape = contract.remoteExecutionTotpShape;
      await store.clearKey();
      final code = totpCodeAt(
        issue.secret,
        atMs: nowMs,
        digits: shape.digits,
        periodSeconds: shape.periodSeconds,
      );
      expect(await store.totpValid(code), isTrue);
    });
  });

  group('接到片2 的凭据校验上', () {
    test('本类就是那个 probe：对的过、错的拒、没带按级别分', () async {
      final issue = await store.generateKey();
      final probe = remoteCredentialProbe(store);
      expect(
        await checkRemoteExecutionAuth(
          contract,
          level: 'L2',
          key: issue.key,
          totpCode: null,
          probe: probe,
        ),
        isA<RemoteExecutionAuthOk>(),
      );
      expect(
        await checkRemoteExecutionAuth(
          contract,
          level: 'L3',
          key: 'wrong-key-entirely',
          totpCode: null,
          probe: probe,
        ),
        isA<RemoteExecutionAuthRejected>(),
      );
    });

    test('L3 不带凭据一律拒（契约 l3Requires:true）', () async {
      await store.generateKey();
      expect(
        await checkRemoteExecutionAuth(
          contract,
          level: 'L3',
          key: null,
          totpCode: null,
          probe: remoteCredentialProbe(store),
        ),
        isA<RemoteExecutionAuthRejected>(),
      );
    });

    test('L2 不带凭据放行（契约 l2Requires:false）', () async {
      expect(
        await checkRemoteExecutionAuth(
          contract,
          level: 'L2',
          key: null,
          totpCode: null,
          probe: remoteCredentialProbe(store),
        ),
        isA<RemoteExecutionAuthOk>(),
      );
    });

    test('L3 带对的 TOTP 码过', () async {
      final issue = await store.generateTotp(account: 'x');
      final shape = contract.remoteExecutionTotpShape;
      final code = totpCodeAt(
        issue.secret,
        atMs: nowMs,
        digits: shape.digits,
        periodSeconds: shape.periodSeconds,
      );
      expect(
        await checkRemoteExecutionAuth(
          contract,
          level: 'L3',
          key: null,
          totpCode: code,
          probe: remoteCredentialProbe(store),
        ),
        isA<RemoteExecutionAuthOk>(),
      );
    });
  });

  group('契约驱动的那些数（不写死）', () {
    test('keyMinLength 与 totp 的位数/步长都从契约来', () {
      expect(contract.remoteExecutionKeyMinLength, 8);
      expect(contract.remoteExecutionTotpShape.digits, 6);
      expect(contract.remoteExecutionTotpShape.periodSeconds, 30);
      expect(contract.remoteExecutionOnMissingOrWrong, 'reject');
      expect(contract.remoteExecutionAuthModes, containsAll(['key', 'totp']));
    });

    test('契约缺 totp 位数或步长时抛（不成对补默认 = 代码在发明协议）', () {
      final caps = contract.raw['capabilities']! as Map<String, Object?>;
      final remote = caps['remoteExecution']! as Map<String, Object?>;
      final auth = remote['auth']! as Map<String, Object?>;
      final broken = FnthinkContract({
        ...contract.raw,
        'capabilities': {
          ...caps,
          'remoteExecution': {
            ...remote,
            'auth': {...auth}..remove('totpDigits'),
          },
        },
      });
      expect(() => broken.remoteExecutionTotpShape, throwsA(isA<StateError>()));
    });

    test('契约缺 keyMinLength 时抛（长度是安全参数，不补）', () {
      final caps = contract.raw['capabilities']! as Map<String, Object?>;
      final remote = caps['remoteExecution']! as Map<String, Object?>;
      final auth = remote['auth']! as Map<String, Object?>;
      final broken = FnthinkContract({
        ...contract.raw,
        'capabilities': {
          ...caps,
          'remoteExecution': {
            ...remote,
            'auth': {...auth}..remove('keyMinLength'),
          },
        },
      });
      expect(
        () => broken.remoteExecutionKeyMinLength,
        throwsA(isA<StateError>()),
      );
    });
  });
}
