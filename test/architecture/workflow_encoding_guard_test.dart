import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// `.github/workflows/*` 的**文件字节**守卫。
///
/// 2026-11-28 的事故：`analyze.yml` 开头有**两个** UTF-8 BOM（`EF BB BF` ×2）。
/// GitHub 的 workflow parser 跳过一个、把第二个当成正文 ⇒ 整份文件被读成另一棵树，
/// 报 `Unexpected value 'n' / 'ermissions' / 'obs'` 与
/// `Required property is missing: jobs`；Actions 里**一个 job 都没跑**。
/// 而本地 YAML 解析器只把它当成一个怪 key（`'\uFEFFname'`）——
/// 这正是"本机绿、CI 连门都没开"的一类：坏的不是某条业务判据，是**门本身没被解析**。
///
/// 钉两件（各管一种看不见的坏法）：
///  ① **BOM 只能在 offset 0 出现一次**：第二个 BOM / 文件中段的 BOM 都会让
///     解析器把后一段当成正文，而编辑器看起来一切正常；
///  ② **每份 workflow 必须有列首 `jobs:`**：根键真的在根上。BOM 把整份文件
///     推歪、或有人顺手缩进一层，`jobs` 就不在根映射里了 —— GitHub 的报错
///     会指向文件第一行，读起来像"明明有 jobs"。
void main() {
  final root = projectRoot();
  final dir = Directory('$root/.github/workflows');

  /// UTF-8 BOM 的三字节序列在本文件里出现的位置。
  ///
  /// 判据是**位置集合**而不是"开头是不是两个"：文件中段混进一个 BOM
  /// （复制粘贴、某些编辑器"保留签名"）同样是解析器眼里的一段正文。
  List<int> bomOffsets(List<int> bytes) {
    final out = <int>[];
    for (var i = 0; i + 2 < bytes.length; i++) {
      if (bytes[i] == 0xEF && bytes[i + 1] == 0xBB && bytes[i + 2] == 0xBF) {
        out.add(i);
      }
    }
    return out;
  }

  test('① 每份 workflow 的 BOM 只能在 offset 0 出现一次', () {
    expect(dir.existsSync(), isTrue, reason: '找不到 .github/workflows ⇒ 这条尺在扫空气');
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.yml') || f.path.endsWith('.yaml'))
        .toList();
    expect(
      files.length,
      greaterThanOrEqualTo(5),
      reason: '只扫到 ${files.length} 份 workflow ⇒ 路径或扩展名变了，先确认再谈"没有坏 BOM"',
    );
    final bad = <String>[];
    for (final f in files) {
      final offsets = bomOffsets(f.readAsBytesSync());
      if (offsets.isEmpty) continue;
      if (offsets.length == 1 && offsets.single == 0) continue;
      bad.add(
        '  · ${f.path.split(Platform.pathSeparator).last}：BOM 出现在 $offsets',
      );
    }
    expect(
      bad,
      isEmpty,
      reason:
          '这些 workflow 文件里的 BOM 不止"开头那一个"：\n${bad.join('\n')}\n'
          'GitHub 的 workflow parser 会把多出来的那个当正文，'
          '表现是整份 workflow 解析失败（一个 job 都不跑），而编辑器里看不出任何异常。',
    );
  });

  test('② 每份 workflow 都有列首 jobs:（根键没有被推下去）', () {
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.yml') || f.path.endsWith('.yaml'))
        .toList();
    final missing = <String>[];
    for (final f in files) {
      final src = f.readAsStringSync();
      if (!RegExp(r'^jobs:\s*$', multiLine: true).hasMatch(src)) {
        missing.add('  · ${f.path.split(Platform.pathSeparator).last}');
      }
    }
    expect(
      missing,
      isEmpty,
      reason:
          '这些 workflow 没有列首 `jobs:`：\n${missing.join('\n')}\n'
          'GitHub 会在文件第一行报 `Required property is missing: jobs` —— '
          '读起来像"明明有 jobs"，真正的原因是它已经不在根映射里。',
    );
  });

  test('③ 尺自己先自证：四种 BOM 形状都判得对', () {
    final none = utf8.encode('name: x\njobs:\n');
    final single = utf8.encode('\uFEFFname: x\njobs:\n');
    final double = utf8.encode('\uFEFF\uFEFFname: x\njobs:\n');
    final middle = utf8.encode('name: x\n\uFEFFjobs:\n');
    expect(bomOffsets(none), isEmpty, reason: '无 BOM 被报成有 ⇒ ① 全是假红');
    expect(bomOffsets(single), const [0], reason: '单个开头 BOM 是合法的，判错会逼人改掉正常的文件');
    expect(bomOffsets(double), const [0, 3], reason: '双 BOM 认不出 ⇒ 事故原样可以再进来');
    expect(bomOffsets(middle), const [8], reason: '文件中段的 BOM 认不出 ⇒ ① 只挡了开头那一种');
  });
}
