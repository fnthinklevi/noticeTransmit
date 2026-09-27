import 'dart:convert';

import 'contract.dart';

/// 签名规范化字节序列（T26 先把"编码规则"钉住，T29 才有东西可签）。
///
/// 顺序与分隔符都来自契约：`signature.canonicalOrder` + `signature.separator`。
/// 换序就是换签名 —— 两端各按各的顺序拼，表现是"验签永远失败"，而报文看起来一模一样。
class CanonicalMessage {
  /// 按契约顺序把 [fields] 拼成待签字节。
  ///
  /// 两种情况**必须**报错而不是将就：
  ///  - 缺字段：留空串会让"没填 body"与"body 是空"签出同一个值，语义不同却不可区分；
  ///  - 字段值里含分隔符：拼接边界随之歧义，攻击者可以拿 `body="x\u0000y"` 造出与
  ///    `type/target` 挪位后完全相同的字节串 —— 那是签名伪造的入口，不是边角情况。
  static List<int> bytes(
    FnthinkContract contract,
    Map<String, Object?> fields,
  ) {
    final order = contract.canonicalOrder;
    if (order.isEmpty) {
      throw StateError('契约缺 signature.canonicalOrder');
    }
    final separator = contract.signatureSeparator;
    final parts = <String>[];
    for (final key in order) {
      final value = fields[key];
      if (value == null) {
        // 字段名必须出现在 message 本体里：很多日志只打 e.message，那时"缺了哪个字段"不能丢。
        throw ArgumentError('签名字段 "$key" 缺失（不补空串：那会让"没填"与"填了空值"签出同一个字节串）');
      }
      final text = '$value';
      if (separator.isNotEmpty && text.contains(separator)) {
        throw ArgumentError(
          '签名字段 "$key" 的值含分隔符，拼接边界会歧义'
          '（可被用来伪造出另一组字段的字节串）',
        );
      }
      parts.add(text);
    }
    return utf8.encode(parts.join(separator));
  }

  /// 参与签名的字段名（= 契约顺序）。给调用方做"多余字段不进签名"的检查用。
  static List<String> signedFields(FnthinkContract contract) =>
      List.unmodifiable(contract.canonicalOrder);
}
