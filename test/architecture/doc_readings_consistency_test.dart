import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// 公开文档里的**手写读数**与仓库真实值的一致性守卫。
///
/// 背景（2026-11-22 审计）：`gen_readings.py` 只校平 `<!-- readings:v1 -->` 标记块，
/// 标记块之外的正文读数没人管 ⇒ README 四处写「1677 词条」（实际 1765）、
/// 「51 条黄金用例」（实际 66）；SECURITY 的支持版本停在 v1.5.76（实际 1.6.8）；
/// NOTICE 引用了不存在的 `protocol/fnthink-v1.md`。这些漂移不会让任何测试变红，
/// 但直接削弱"读数单一来源"的可信度。
///
/// 本守卫把**正文里的**四类读数钉在真实值上：l10n 词条数、规则黄金用例数、
/// SECURITY 支持版本、NOTICE 引用的协议文件存在性。
void main() {
  final root = projectRoot();

  String read(String rel) => File('$root/$rel').readAsStringSync();

  test('README 正文的「N 词条」每一处都等于 ARB 实际键数', () {
    final arb = jsonDecode(read('lib/l10n/arb/app_zh.arb')) as Map;
    final keys = arb.keys
        .where((k) => !k.startsWith('@') && k != '@@locale')
        .length;
    final hits = RegExp(r'(\d+)\s*词条')
        .allMatches(read('README.md'))
        .map((m) => int.parse(m.group(1)!))
        .toList();
    expect(hits, isNotEmpty, reason: 'README 里一处「N 词条」都没有 ⇒ 这条守卫是空转');
    for (final n in hits) {
      expect(n, keys, reason: 'README 写「$n 词条」，ARB 实际 $keys 条 ⇒ 正文与读数表各说一段');
    }
  });

  test('README 中英双语的黄金用例数都等于夹具实际条数', () {
    final fixture =
        jsonDecode(read('test/fixtures/rule_engine_golden.json')) as Map;
    final cases = (fixture['cases'] as List).length;
    for (final (file, re) in [
      ('README.md', RegExp(r'(\d+)\s*条黄金用例')),
      ('README-en.md', RegExp(r'(\d+)\s+golden cases')),
    ]) {
      final hits = re
          .allMatches(read(file))
          .map((m) => int.parse(m.group(1)!))
          .toList();
      expect(hits, isNotEmpty, reason: '$file 里找不到黄金用例读数 ⇒ 守卫空转');
      for (final n in hits) {
        expect(n, cases, reason: '$file 写 $n 条黄金用例，夹具实际 $cases 条');
      }
    }
  });

  test('SECURITY 中英双语的受支持版本等于 pubspec 版本', () {
    final pubspec = read('pubspec.yaml');
    final m = RegExp(
      r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(m, isNotNull, reason: 'pubspec.yaml 读不出版本号 ⇒ 守卫无从比对');
    final version = m!.group(1)!;
    final build = m.group(2)!;
    expect(
      read('SECURITY.md'),
      contains('v$version（build $build）'),
      reason: 'SECURITY.md 的支持版本与 pubspec 漂移（安全政策写了一个错误的受支持版本）',
    );
    expect(
      read('SECURITY-en.md'),
      contains('v$version (build $build)'),
      reason: 'SECURITY-en.md 的支持版本与 pubspec 漂移（security policy names a wrong supported version）',
    );
  });

  test('NOTICE 引用的每一个 protocol 文件都真实存在', () {
    final refs = RegExp(r'protocol/[A-Za-z0-9._-]+')
        .allMatches(read('NOTICE'))
        .map((m) => m.group(0)!)
        .toSet();
    expect(refs, isNotEmpty, reason: 'NOTICE 里一个 protocol 文件都没引用 ⇒ 守卫空转');
    for (final ref in refs) {
      expect(
        File('$root/$ref').existsSync(),
        isTrue,
        reason: 'NOTICE 引用了不存在的 $ref —— 法律文件里的断链可被审计',
      );
    }
  });
}
