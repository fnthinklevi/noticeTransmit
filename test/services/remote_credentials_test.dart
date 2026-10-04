import 'dart:math';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/remote_credentials.dart';

/// 片3a：远程执行凭据（高级密钥 + TOTP）。
///
/// ⚠ **TOTP 用 RFC 6238 的官方向量**，不是"自己算一遍和自己比"：这一层的全部意义是
/// 发送端用**任意标准验证器 App**（Google Authenticator / 1Password / Aegis…）录的凭据，
/// 所以只有对着 RFC 的已知答案才能证明"这边算出来的码，别人 App 也认"。
/// 那份测试密钥是 RFC 里的 ASCII `12345678901234567890`，它的 base32 是
/// `GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ`（20 字节）。
void main() {
  final contract = FnthinkContract.readFile();
  const rfcSecret =
      'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'; // "12345678901234567890"
  const digits = 6;
  const period = 30;

  group('base32（RFC 4648 §6，无填充）', () {
    test('编解码往返一致', () {
      final bytes = List<int>.generate(20, (i) => (i * 37 + 11) & 0xff);
      expect(base32Decode(base32Encode(bytes)), bytes);
    });

    test('RFC 6238 那份测试密钥编出来就是它给的那串', () {
      expect(base32Encode('12345678901234567890'.codeUnits), rfcSecret);
    });

    test('字母表外的字符 ⇒ 抛（静默跳过会让拼错的种子"看起来能用"）', () {
      expect(() => base32Decode('ABC!DEF'), throwsFormatException);
    });

    test('小写与 `=` 填充都能解（人手抄一遍时最容易带进来的两种）', () {
      expect(base32Decode('gezdgnbv'), base32Decode('GEZDGNBV=='));
    });
  });

  group('TOTP：对着 RFC 6238 的官方向量', () {
    // (T 秒, 8 位码) —— 8 位那条是为了证明 HOTP 内核与 RFC 逐位一致，
    // 6 位码只是把 8 位截掉高两位（验证器 App 显示的就是它）。
    const vectors = <(int, String)>[
      (59, '94287082'),
      (1111111109, '07081804'),
      (1111111111, '14050471'),
      (1234567890, '89005924'),
      (2000000000, '69279037'),
      (20000000000, '65353130'),
    ];

    test('8 位码逐条对上 RFC 的表', () {
      for (final (t, expected) in vectors) {
        expect(
          hotp(
            base32Decode(rfcSecret),
            t ~/ period,
            8,
          ).toString().padLeft(8, '0'),
          expected,
          reason: 'T=$t 秒这条对不上 RFC 6238 的表 ⇒ 别的验证器 App 也认不出这个码',
        );
      }
    });

    test('6 位码（验证器显示的那一截）逐条对上', () {
      for (final (t, eight) in vectors) {
        expect(
          totpCodeAt(
            rfcSecret,
            atMs: t * 1000,
            digits: digits,
            periodSeconds: period,
          ),
          eight.substring(2),
          reason: 'T=$t 秒这条的 6 位截断不对',
        );
      }
    });

    test('步长边界：同一时刻在窗口内是同一个码，过了步长就换', () {
      // ⚠ 这一条钉的是「用整除取步长」：浮点除法在边界附近会落到隔壁步，
      // 于是「还有 1 秒」和「刚过期」给出同一个码。
      final before = totpCodeAt(
        rfcSecret,
        atMs: 30000 - 1,
        digits: digits,
        periodSeconds: period,
      );
      final after = totpCodeAt(
        rfcSecret,
        atMs: 30000,
        digits: digits,
        periodSeconds: period,
      );
      expect(before, isNot(after));
      // 同一时刻重复算两次必须一致（确定性）
      expect(
        totpCodeAt(
          rfcSecret,
          atMs: 1234567890000,
          digits: digits,
          periodSeconds: period,
        ),
        totpCodeAt(
          rfcSecret,
          atMs: 1234567890000,
          digits: digits,
          periodSeconds: period,
        ),
      );
    });

    test('校验：当前码过、错码不过、容忍 ±1 步、超过 ±1 不认', () {
      const now = 1111111109 * 1000;
      final code = totpCodeAt(
        rfcSecret,
        atMs: now,
        digits: digits,
        periodSeconds: period,
      );
      expect(
        verifyTotpCode(
          rfcSecret,
          presented: code,
          atMs: now,
          digits: digits,
          periodSeconds: period,
        ),
        isTrue,
      );
      // 上一/下一步的码：窗口内接受
      final prev = totpCodeAt(
        rfcSecret,
        atMs: now - period * 1000,
        digits: digits,
        periodSeconds: period,
      );
      expect(
        verifyTotpCode(
          rfcSecret,
          presented: prev,
          atMs: now,
          digits: digits,
          periodSeconds: period,
        ),
        isTrue,
        reason: '两端设备时钟不可能完全一致，±1 步是 RFC 建议的宽限',
      );
      // 三步之外的码：不认（窗口放到 3 就等于一个码管 2.5 分钟，那不叫二步验证）
      final far = totpCodeAt(
        rfcSecret,
        atMs: now + period * 1000 * 3,
        digits: digits,
        periodSeconds: period,
      );
      expect(
        verifyTotpCode(
          rfcSecret,
          presented: far,
          atMs: now,
          digits: digits,
          periodSeconds: period,
        ),
        isFalse,
      );
    });

    test('长度不对或非数字的码 ⇒ 不过（不拿去截断比较，省一次无谓的 HOTP）', () {
      const now = 1111111109 * 1000;
      for (final bad in ['', '12345', '1234567', 'abcdef']) {
        expect(
          verifyTotpCode(
            rfcSecret,
            presented: bad,
            atMs: now,
            digits: digits,
            periodSeconds: period,
          ),
          isFalse,
          reason: '「$bad」不该被当码',
        );
      }
    });
  });

  group('高级密钥', () {
    test('随机生成的那一串长度与字母表都对，且两次生成不同', () {
      // ⚠ 两次生成要用**同一个在推进的**随机源：各 new 一个同种子的 Random 会给出同一个值，
      // 那条「两次不同」就成了自证的假断言（同种子的两次调用必然相同）。
      final rnd = Random(7);
      final a = generateRemoteKey(contract, rnd);
      final b = generateRemoteKey(contract, rnd);
      expect(
        a.length,
        greaterThanOrEqualTo(
          contract.intOf(const [
                'capabilities',
                'remoteExecution',
                'auth',
                'keyMinLength',
              ]) ??
              8,
        ),
      );
      expect(a, matches(RegExp(r'^[A-Z2-7]+$')));
      expect(a, isNot(b));
    });

    test('存的是哈希不是明文，且加盐后同一个密钥在两台设备上哈希不同', () {
      const key = 'ABCD2345EFGH6789';
      final s1 = generateInstallSalt(Random(1));
      final s2 = generateInstallSalt(Random(2));
      final h1 = hashRemoteKey(key, s1);
      final h2 = hashRemoteKey(key, s2);
      expect(h1, isNot(contains(key)));
      expect(h1, isNot(h2), reason: '没有安装盐的话，两个设备上的哈希一样 ⇒ 彩虹表通吃');
      expect(h1, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('校验：对的对、空串的不过、长度不同的不过', () {
      const key = 'ABCD2345EFGH6789';
      final salt = generateInstallSalt(Random(3));
      final stored = hashRemoteKey(key, salt);
      expect(
        verifyRemoteKey(presented: key, salt: salt, storedHash: stored),
        isTrue,
      );
      expect(
        verifyRemoteKey(presented: '', salt: salt, storedHash: stored),
        isFalse,
      );
      expect(
        verifyRemoteKey(presented: key, salt: salt, storedHash: 'short'),
        isFalse,
        reason: '存的值长度不对时不能抛，也不能当成对',
      );
    });
  });

  group('otpauth 链接（验证器 App 的标准录入格式）', () {
    test('里面带 secret / issuer / digits / period，账号名里的 : 已转义', () {
      final uri = otpAuthUri(
        secretBase32: rfcSecret,
        account: 'device-B',
        issuer: '通知推送助手',
        digits: digits,
        periodSeconds: period,
      );
      expect(uri, startsWith('otpauth://totp/'));
      expect(uri, contains('secret=$rfcSecret'));
      expect(uri, contains('issuer='));
      expect(uri, contains('digits=6'));
      expect(uri, contains('period=30'));
      // label 里的冒号要转义，否则 App 解析出来的账号名会被截断（表现为"扫进去名字不对"）
      expect(uri, contains('%3A'));
    });
  });
}
