import 'dart:math';

/// Crockford Base32（T26）。
///
/// 为什么用它而不是 hex / base64：地址码与配对口令是**要被人抄、要被二维码承载**的字符串。
/// hex 太长，base64 大小写敏感且含 `+ / =`（手抄必错）。Crockford 只用 32 个不易混的字符、
/// 不区分大小写、并且把 `I L O U` 排除掉（与 1 / 0 / V 混淆）。
///
/// ⚠ 字母表与"排除哪些字符"都来自契约（`identity.*.alphabet` / `excludedChars`）：
/// 换字母表等于换协议，代码里不许留第二份。
class CrockfordBase32 {
  /// 契约里的标准 Crockford 表（0-9 与 A-Z 去掉 I L O U）。
  static const String standardAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// 标准排除集（契约若写了别的东西，[fromContract] 会拒绝而不是将就）。
  static const String standardExcluded = 'ILOU';

  const CrockfordBase32(this.alphabet, this.excluded);

  /// 从契约取字母表。**不一致就抛**：静默按自己的表生成，产出的是对端解不开的码。
  static CrockfordBase32 fromContract({
    required String? alphabet,
    required String? excludedChars,
  }) {
    if (alphabet != 'crockford-base32') {
      throw ArgumentError.value(
        alphabet,
        'alphabet',
        '本包只实现 crockford-base32；换字母表是协议变更，必须先在契约与双端测试里落地',
      );
    }
    if (excludedChars != standardExcluded) {
      throw ArgumentError.value(
        excludedChars,
        'excludedChars',
        '排除集与实现里的标准 Crockford 表不一致（实现排除 $standardExcluded）',
      );
    }
    return const CrockfordBase32(standardAlphabet, standardExcluded);
  }

  final String alphabet;
  final String excluded;

  int get bitsPerChar => 5; // 32 = 2^5

  /// 生成 [length] 个字符。[random] 只用于测试注入 ——
  /// ⚠ 生产路径必须走 [random] 的默认值 `Random.secure()`：可预测的凭证等于没有凭证。
  String generate(int length, {Random? random}) {
    final r = random ?? Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.write(alphabet[r.nextInt(alphabet.length)]);
    }
    return buffer.toString();
  }

  /// 归一化：转大写、丢掉分隔符（空格与连字符）。返回 null = 含字母表以外的字符。
  String? normalize(String raw) {
    final upper = raw.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    for (final char in upper.split('')) {
      if (!alphabet.contains(char)) return null;
    }
    return upper;
  }

  bool isValid(String normalized, {required int length}) =>
      normalized.length == length &&
      normalized.split('').every(alphabet.contains);
}
