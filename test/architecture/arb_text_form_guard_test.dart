import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// base.md §3.6 / §9.4 的 ARB 文本形态守卫：
/// - 两份 ARB 逐 key 同步（含占位符集合）；
/// - 英文值里不残留中文（语言名 `langChinese` 是母语自称，放行）；
/// - 中文值里不用 ASCII 冒号/逗号（URL、时间、数字分隔除外）；
/// - 英文值里不用全角标点；
/// - 技术术语（`.nbackup`、算法名）不进用户可见文案；隐私政策全文是合规要求的例外。
void main() {
  final root = projectRoot();
  final zh = jsonDecode(
    File('$root/lib/l10n/arb/app_zh.arb').readAsStringSync(),
  ) as Map<String, dynamic>;
  final en = jsonDecode(
    File('$root/lib/l10n/arb/app_en.arb').readAsStringSync(),
  ) as Map<String, dynamic>;

  Set<String> keys(Map<String, dynamic> arb) =>
      arb.keys.where((k) => !k.startsWith('@')).toSet();

  bool isCjk(String ch) {
    final c = ch.codeUnitAt(0);
    return (c >= 0x3400 && c <= 0x9fff) || (c >= 0xf900 && c <= 0xfaff);
  }

  bool isDigit(String ch) {
    final c = ch.codeUnitAt(0);
    return c >= 0x30 && c <= 0x39;
  }

  final cjk = RegExp(r'[\u3400-\u9fff\uF900-\uFAFF]');
  final fullwidth = RegExp(r'[，。；：！？（）【】「」《》]');
  final placeholder = RegExp(r'\{([A-Za-z0-9_]+)\}');

  List<String> asciiPunctuationOffenders(String key, String value) {
    final out = <String>[];
    for (var i = 0; i < value.length; i++) {
      final ch = value[i];
      if (ch != ':' && ch != ',') continue;
      final near = value.substring(
        i - 8 < 0 ? 0 : i - 8,
        i + 9 > value.length ? value.length : i + 9,
      );
      if (near.contains('http://') || near.contains('https://')) continue;
      if (i > 0 &&
          i + 1 < value.length &&
          isDigit(value[i - 1]) &&
          isDigit(value[i + 1])) {
        continue;
      }
      final nearCjk =
          (i > 0 && isCjk(value[i - 1])) ||
          (i + 1 < value.length && isCjk(value[i + 1]));
      if (nearCjk) out.add('$key@$i');
    }
    return out;
  }

  test('两份 ARB 逐 key 同步', () {
    expect(keys(zh).difference(keys(en)), isEmpty, reason: '中文有、英文没有');
    expect(keys(en).difference(keys(zh)), isEmpty, reason: '英文有、中文没有');
  });

  test('占位符集合逐 key 相同', () {
    final offenders = <String>[];
    for (final k in keys(zh).intersection(keys(en))) {
      final pz = placeholder
          .allMatches(zh[k].toString())
          .map((m) => m.group(1))
          .toSet();
      final pe = placeholder
          .allMatches(en[k].toString())
          .map((m) => m.group(1))
          .toSet();
      if (pz.difference(pe).isNotEmpty || pe.difference(pz).isNotEmpty) {
        offenders.add('$k zh=$pz en=$pe');
      }
    }
    expect(offenders, isEmpty, reason: '占位符少了会在运行时印出字面量 {x}');
  });

  test('英文值里不残留中文（语言名除外）', () {
    final offenders = [
      for (final k in keys(en))
        if (k != 'langChinese' && cjk.hasMatch(en[k].toString())) k,
    ];
    expect(offenders, isEmpty, reason: '英文界面会直接露出中文；语言名用母语自称是唯一例外');
  });

  test('英文值里不用全角标点', () {
    final offenders = [
      for (final k in keys(en))
        if (fullwidth.hasMatch(en[k].toString())) k,
    ];
    expect(offenders, isEmpty);
  });

  test('中文值里的 ASCII 冒号/逗号不紧贴中文（URL/时间/数字除外）', () {
    final offenders = <String>[
      for (final k in keys(zh))
        ...asciiPunctuationOffenders(k, zh[k].toString()),
    ];
    expect(offenders, isEmpty, reason: '中文正文用全角「：」「，」；时间 22:00 与 URL 里的冒号不算');
  });

  test('尺认得合成样本', () {
    expect(asciiPunctuationOffenders('k', '保存失败: {e}'), isNotEmpty);
    expect(asciiPunctuationOffenders('k', '例如: com.example.app'), isNotEmpty);
    expect(asciiPunctuationOffenders('k', '如 22:00 推送'), isEmpty);
    expect(asciiPunctuationOffenders('k', '地址 https://a.b/c'), isEmpty);
    expect(asciiPunctuationOffenders('k', '保存失败：{e}'), isEmpty);
  });

  test('`.nbackup` 不进用户可见文案', () {
    final offenders = [
      for (final map in [zh, en])
        for (final k in keys(map))
          if (map[k].toString().contains('.nbackup')) k,
    ];
    expect(
      offenders,
      isEmpty,
      reason: 'base.md §9.4 的反例就是 `.nbackup 文件`；说「备份文件」即可',
    );
  });

  test('算法名只允许出现在隐私政策全文里', () {
    const names = [
      'AES-256',
      'AES',
      'GCM',
      'PBKDF2',
      'HMAC',
      'SHA-256',
      'SHA256',
      'sqlcipher',
      'base64',
    ];
    final offenders = <String>[
      for (final map in [zh, en])
        for (final k in keys(map))
          if (!k.startsWith('privacy') &&
              names.any((n) => map[k].toString().contains(n)))
            k,
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'base.md §9.4：加密强度/算法名是实现细节，用户只需要知道「文件有密码保护」。'
          '隐私政策全文为合规披露保留技术事实，按 key 前缀 privacy 放行。',
    );
  });
}
