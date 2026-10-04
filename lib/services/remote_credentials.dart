import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:fnthink_push/fnthink_push.dart';

/// 远程执行的**凭据**（片3a）：高级密钥（自定义或随机）与 TOTP（接收端持有种子）。
///
/// ⚠ 两条不可省的纪律，本文件都遵守：
///  ① **本机不存明文**：高级密钥只存 `sha256(salt || key)`；TOTP 的种子是**校验用的**，所以
///     必须存在本机（否则 B 无法校验 A 的 6 位码）—— 但它只在本机加密的 prefs 里（见服务层），
///     **不进服务端、不进留痕、不进回执**（契约 `execution.forbiddenFields` 与
///     `privacy.auditStoresMetadataOnly` 两条红线）。
///  ② **TOTP 是标准算法**（RFC 6238 / RFC 4226 + RFC 4648 base32），不是"自己拼一个 6 位数"：
///     发送端用**任意**标准验证器 App 录的凭据，必须与这里算出来的码一致 —— 所以用 RFC 的
///     **官方向量**做用例（见 `remote_credentials_test.dart`），而不是"自己算一遍和自己比"。

/// base32 字母表（RFC 4648 §6，无填充 —— 验证器 App 的通行做法）。
const String _b32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/// 把字节编成 base32（无 `=` 填充）。
String base32Encode(List<int> bytes) {
  final out = StringBuffer();
  var buffer = 0;
  var bits = 0;
  for (final b in bytes) {
    buffer = (buffer << 8) | (b & 0xff);
    bits += 8;
    while (bits >= 5) {
      out.write(_b32[(buffer >> (bits - 5)) & 0x1f]);
      bits -= 5;
    }
  }
  if (bits > 0) out.write(_b32[(buffer << (5 - bits)) & 0x1f]);
  return out.toString();
}

/// base32 → 字节（忽略大小写与 `=` 填充；遇到字母表外的字符**抛**而不静默跳过）。
///
/// ⚠ 静默跳过会让一个拼错的种子"看起来能用"：码一直不对，而真因（种子抄错几个字符）没人看见。
List<int> base32Decode(String encoded) {
  final clean = encoded.toUpperCase().replaceAll('=', '').replaceAll(' ', '');
  final out = <int>[];
  var buffer = 0;
  var bits = 0;
  for (final ch in clean.split('')) {
    final v = _b32.indexOf(ch);
    if (v < 0) {
      throw FormatException('base32 里有字母表外的字符：$ch', encoded);
    }
    buffer = (buffer << 5) | v;
    bits += 5;
    if (bits >= 8) {
      out.add((buffer >> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return out;
}

/// 生成一枚高级密钥（随机；用户也可在设置页自定义）。
///
/// ⚠ 长度取契约 `remoteExecution.auth.keyMinLength`（今天 8），并按 base32 字母表取值
/// —— 这样它可以直接当 TOTP 种子用同一个录入框，**省掉"这串到底是密钥还是种子"的困惑**。
String generateRemoteKey(FnthinkContract contract, Random random) {
  final min =
      contract.intOf(const [
        'capabilities',
        'remoteExecution',
        'auth',
        'keyMinLength',
      ]) ??
      8;
  // 每 5 bit 一枚字符 ⇒ 8 字符 ≈ 40 bit。随机密钥给 26 字符（130 bit），
  // 远超任何暴力猜测；长度不是安全参数，熵才是（所以不按 minLength 卡死）。
  const chars = 26;
  final out = StringBuffer();
  for (var i = 0; i < chars; i++) {
    out.write(_b32[random.nextInt(32)]);
  }
  if (chars < min) {
    throw StateError('生成的密钥长度 $chars < 契约要求的 keyMinLength=$min');
  }
  return out.toString();
}

/// 本机安装盐（16 字节随机 base32）。
///
/// ⚠ 为什么要盐：用户**可以自定义**密钥，自定义就可能是低熵口令（"12345678"），
/// 而裸 sha256 对低熵串是可以被彩虹表直接查的 —— 有了安装盐，同一个口令在两台设备上的
/// 哈希不同，批量猜解也讨不到通用表。
String generateInstallSalt(Random random) =>
    base32Encode(List<int>.generate(16, (_) => random.nextInt(256)));

/// 高级密钥的存法：`sha256(salt || key)` 的十六进制小写。
///
/// ⚠ **不是** KDF（PBKDF2/Argon2）：那类是为"人能背下来的口令"设计的，
/// 而这一条默认是 130 bit 随机串（自带的盐就已经让彩虹表失效）。若用户自定义了低熵口令，
/// 强度靠的是那把安装盐 + 本机认证（T49 的锁屏/生物）而不是 KDF —— 这条取舍写在这里，
/// 免得后人以为是"忘了加 KDF"。
String hashRemoteKey(String key, String saltHexOrBase32) =>
    _sha256Hex(utf8.encode('$saltHexOrBase32|$key'));

bool verifyRemoteKey({
  required String presented,
  required String salt,
  required String storedHash,
}) {
  if (presented.isEmpty) return false;
  // ⚠ 定长比较：短路比较在时序上会漏"前几位对了"这一段信息。
  final a = hashRemoteKey(presented, salt);
  if (a.length != storedHash.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ storedHash.codeUnitAt(i);
  }
  return diff == 0;
}

/// RFC 4226 的 HOTP（计数器 = 时间步）。
int hotp(List<int> secret, int counter, int digits) {
  // ⚠ **计数器是 8 字节大端**（RFC 4226 §5.1）。写成 4 字节时，HMAC 的输入就少了四个前导零，
  // 而 HMAC 对"消息里多了几个 0"是敏感的 —— 于是算出来的码每一位都可能不同，
  // 表现是"我的 App 里能自洽，但任何标准验证器 App 都不认"。
  // 这条是本文件唯一一处"少写几个字节就全错"的地方，也是必须对着 RFC 向量测的原因。
  final msg = <int>[
    (counter >> 56) & 0xff,
    (counter >> 48) & 0xff,
    (counter >> 40) & 0xff,
    (counter >> 32) & 0xff,
    (counter >> 24) & 0xff,
    (counter >> 16) & 0xff,
    (counter >> 8) & 0xff,
    counter & 0xff,
  ];
  final mac = _hmacSha1(secret, msg);
  final offset = mac[mac.length - 1] & 0x0f;
  final bin =
      ((mac[offset] & 0x7f) << 24) |
      ((mac[offset + 1] & 0xff) << 16) |
      ((mac[offset + 2] & 0xff) << 8) |
      (mac[offset + 3] & 0xff);
  final mod = pow(10, digits).toInt();
  return bin % mod;
}

/// 某一时刻的 TOTP 码（RFC 6238）。
///
/// ⚠ 步长用**整数**除法（`atMs ~/ 1000 ~/ period`）而不是浮点。
/// ⚠ **这条注释原来的说法是错的**（8.180 实测）：我写过"浮点在步长边界附近会落到隔壁步"，
/// 但对每一个可表示的时间戳，整数除法与浮点 + floor 的结果都相同 —— C5 那发植入
/// （把整数除法改成浮点）零失败，说明**这条差异不可观察**，那不是它值得存在的理由。
/// 现在留着的理由只有一个，而且是实话：毫秒与秒先各自整除、步长再整除，
/// 读起来就是"时间戳 → 秒 → 步"，不需要读者自己去想浮点误差。
String totpCodeAt(
  String secretBase32, {
  required int atMs,
  required int digits,
  required int periodSeconds,
}) {
  final step = (atMs ~/ 1000) ~/ periodSeconds;
  final code = hotp(base32Decode(secretBase32), step, digits);
  return code.toString().padLeft(digits, '0');
}

/// 验证一个 TOTP 码，容忍 `window` 个步长的时钟偏移（两端设备时间不可能完全一致）。
///
/// ⚠ 默认 ±1 步是行业惯例（RFC 建议）；**不接受更大的窗口** —— 窗口放到 3 就意味着一个码
/// 在 2.5 分钟里都能用，那不叫二步验证。
bool verifyTotpCode(
  String secretBase32, {
  required String presented,
  required int atMs,
  required int digits,
  required int periodSeconds,
  int window = 1,
}) {
  final code = presented.trim();
  if (code.length != digits || int.tryParse(code) == null) return false;
  final step = (atMs ~/ 1000) ~/ periodSeconds;
  for (var w = -window; w <= window; w++) {
    if (hotp(
          base32Decode(secretBase32),
          step + w,
          digits,
        ).toString().padLeft(digits, '0') ==
        code) {
      return true;
    }
  }
  return false;
}

/// `otpauth://totp/…` 链接（验证器 App 的标准录入格式）。
///
/// ⚠ issuer 与 label 里的 `:` 与 `,` 要按规范转义，否则 App 解析出来的账号名会被截断 ——
/// 表现是"扫进去的账号名不对"，而用户只会以为是 App 的问题。
String otpAuthUri({
  required String secretBase32,
  required String account,
  required String issuer,
  int digits = 6,
  int periodSeconds = 30,
}) {
  final label = Uri.encodeComponent('$issuer:$account');
  return Uri(
    scheme: 'otpauth',
    host: 'totp',
    path: '/$label',
    queryParameters: {
      'secret': secretBase32,
      'issuer': issuer,
      'digits': '$digits',
      'period': '$periodSeconds',
    },
  ).toString();
}

// ── 底层：sha256 与 hmac-sha1（用仓里已有的 package:crypto）─────────────────
// 放在文件末尾是为了让上面的算法读起来是"标准的样子"，不夹着实现细节。

String _sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

List<int> _hmacSha1(List<int> key, List<int> message) =>
    Hmac(sha1, key).convert(message).bytes;
