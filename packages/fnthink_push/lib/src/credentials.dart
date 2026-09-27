import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'contract.dart';
import 'crockford.dart';

/// 凭证三件套里的两件套（T26）：设备地址码与一次性配对口令。
///
/// 两者的**位数、有效期、是否一次性**都从契约读，代码里不写死 —— 写死的那一份会在契约
/// 变更后继续按老规则生成，而对端已按新规则校验，表现成"配对永远失败"且两边各自都对。
///
/// 第三件套（Ed25519 身份密钥对）在原生侧（AndroidKeyStore），不在这里。

/// 地址码：公开标识，可分享、可进二维码、可被搜索 —— 但它**不是**凭证，单独拥有它
/// 不能授权任何推送（推送要的是签名，私钥在对端设备上）。
class FnthinkAddressCode {
  FnthinkAddressCode._(this.value);

  /// 生成一枚新地址码。[random] 只为测试可注入而存在，缺省 `Random.secure()` ——
  /// 可预测的标识尚可忍，可预测的凭证等于没有凭证，所以生产路径不给传别的可能。
  factory FnthinkAddressCode.generate(
    FnthinkContract contract, {
    Random? random,
  }) {
    final length = contract.identityLength('addressCode');
    return FnthinkAddressCode._(
      _alphabet(contract).generate(length, random: random),
    );
  }

  /// 解析外部输入（大小写不敏感，允许空格与连字符）。不合法返回 null 而不抛：
  /// 用户手抄错一个字符是常态，调用方要的是"能不能用"。
  static FnthinkAddressCode? parse(FnthinkContract contract, String raw) {
    final alphabet = _alphabet(contract);
    final normalized = alphabet.normalize(raw);
    if (normalized == null ||
        !alphabet.isValid(
          normalized,
          length: contract.identityLength('addressCode'),
        )) {
      return null;
    }
    return FnthinkAddressCode._(normalized);
  }

  /// 归一化后的值（大写、无分隔符）。落库与比对都用它。
  final String value;

  /// 给人看的分组形式（每 6 位一段）。⚠ 只是显示形式，比较一律用 [value]。
  String get formatted => _group(value, 6);

  @override
  bool operator ==(Object other) =>
      other is FnthinkAddressCode && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'FnthinkAddressCode($formatted)';
}

/// 一次性配对口令。它等同密码：泄露即等于把设备交出去，所以短期 + 单次 + 可重置。
class FnthinkPairingCode {
  FnthinkPairingCode._(this.value, this.ttlSeconds, this.singleUse);

  factory FnthinkPairingCode.generate(
    FnthinkContract contract, {
    Random? random,
  }) => FnthinkPairingCode._(
    _alphabet(
      contract,
    ).generate(contract.identityLength('pairingCode'), random: random),
    contract.identityTtlSeconds('pairingCode'),
    contract.identityBool('pairingCode', 'singleUse'),
  );

  static FnthinkPairingCode? parse(FnthinkContract contract, String raw) {
    final alphabet = _alphabet(contract);
    final normalized = alphabet.normalize(raw);
    if (normalized == null ||
        !alphabet.isValid(
          normalized,
          length: contract.identityLength('pairingCode'),
        )) {
      return null;
    }
    return FnthinkPairingCode._(
      normalized,
      contract.identityTtlSeconds('pairingCode'),
      contract.identityBool('pairingCode', 'singleUse'),
    );
  }

  final String value;

  /// 有效期（秒）。计时归服务端：设备侧只显示"5 分钟内有效"，不拿本机时钟判定。
  final int? ttlSeconds;

  /// 配对即消耗。契约若把它写成 false，这里会照实带出来 —— 由签发方拒绝，
  /// 而不是本包偷偷"替契约改正"。
  final bool? singleUse;

  String get formatted => _group(value, 5);

  @override
  bool operator ==(Object other) =>
      other is FnthinkPairingCode && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'FnthinkPairingCode($formatted)';
}

CrockfordBase32 _alphabet(FnthinkContract contract) =>
    CrockfordBase32.fromContract(
      alphabet: contract.str(const ['identity', 'addressCode', 'alphabet']),
      excludedChars: contract.str(const [
        'identity',
        'addressCode',
        'excludedChars',
      ]),
    );

/// 凭证摘要：sha256(归一化值) 的十六进制小写 —— 与服务端 `credentialDigest` 同一套字节。
///
/// 两端算出不同摘要的表现不是报错，而是"设备显示口令、服务端说没这条记录"，
/// 所以这条由 `protocol/fnthink-vectors-v1.json` 双端各断言一遍。
///
/// [which] 就是契约 `identity` 下的键名，这里**先完整校验再算**：不合法一律抛。
/// 放过空串会算出一个稳定的摘要，于是"没填"和"填了个空"命中同一条记录。
String fnthinkCredentialDigest(
  FnthinkContract contract,
  String which,
  String raw,
) {
  final normalized = _alphabet(contract).normalize(raw);
  final length = contract.identityLength(which);
  if (normalized == null || normalized.length != length) {
    throw ArgumentError(
      '不是合法的 identity.$which（应为 $length 位 Crockford base32），拒绝计算摘要',
    );
  }
  // Digest.toString() 就是小写十六进制（package:crypto 的既定行为）；
  // 万一哪天不是了，向量测试会立刻红，不会静默换成另一种摘要。
  return sha256.convert(utf8.encode(normalized)).toString();
}

String _group(String value, int size) {
  final parts = <String>[];
  for (var i = 0; i < value.length; i += size) {
    final end = i + size > value.length ? value.length : i + size;
    parts.add(value.substring(i, end));
  }
  return parts.join('-');
}
