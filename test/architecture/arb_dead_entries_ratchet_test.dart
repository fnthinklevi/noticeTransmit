import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// ARB 死词条棘轮（**只降不升**）—— T63。
///
/// 为什么不是"删掉那一条就完事"：动手前先量了一遍，仓库里有 **77 个**词条没有任何调用点，
/// 而任务书写的是 1 个。更要紧的是其中一批不是"留着以后用"，而是**改名前的孪生残留**：
/// `checkUpdateFailed` / `updateCheckFailed`、`latestVer` / `updateLatestVersionLabel`
/// 同时存在，改文案的人只会改到自己搜到的那一个上，另一个继续躺在字典里当"看起来是配置"的暗雷。
///
/// 判据说的是"有没有被用"，不是"该不该存在"：有些词条是给还没做的 W3 页面预留的，
/// 删掉它们会把规划删掉。所以这里立棘轮而不是清零 —— 新增一个没人用的词条就会红，
/// 清掉存量请把 `_ratchet` 一起改小，并在 commit 里说明那批词条是真的不需要了。
///
/// 计数只认**剥掉注释之后**的代码：词条名字出现在注释里不算用过
/// （否则"我在 TODO 里提了一下"就能让它永久免检）。
const int _ratchet = 77;

/// 判据本体（独立成函数是为了能被合成样本反证）。
/// [arbKeys] ARB 里的键集合；[sourceText] 已剥注释的全部 lib/ 代码。
List<String> deadEntries(Iterable<String> arbKeys, String sourceText) {
  final used = RegExp(
    r'[A-Za-z_][A-Za-z0-9_]*',
  ).allMatches(sourceText).map((m) => m.group(0)!).toSet();
  return arbKeys.where((k) => !used.contains(k)).toList()..sort();
}

/// 只数真正的词条键：元数据（`@name`、`@@localeName`）与占位符描述不算。
Iterable<String> messageKeys(Map<String, Object?> arb) =>
    arb.keys.where((k) => !k.startsWith('@') && k != 'placeholder');

void main() {
  final root = projectRoot();
  final arb = Map<String, Object?>.from(
    jsonDecode(File('$root/lib/l10n/arb/app_zh.arb').readAsStringSync())
        as Map<String, Object?>,
  );
  final libDir = Directory('$root/lib');
  final sources = <String>[];
  for (final f in libDir.listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    // 生成物本身含每一个键，算进去就等于永不判红（这是守卫自己的假绿面）
    if (f.path.replaceAll(r'\', '/').contains('/lib/l10n/')) continue;
    sources.add(stripComments(f.readAsStringSync()));
  }
  final dead = deadEntries(messageKeys(arb), sources.join('\n'));

  group('ARB 死词条棘轮', () {
    test('判据本身能判红也能判绿（否则守卫是摆设）', () {
      const source = 'void f() { print(l10n.usedHere); }';
      expect(deadEntries(['usedHere', 'neverUsed'], source), ['neverUsed']);
      // 只在注释里提过 ⇒ 仍算死词条。调用方负责先剥注释（与 main() 里的用法一致），
      // 判据只管「名字在不在代码里」—— 少了这一步，一句 TODO 就能让词条永久免检。
      expect(
        deadEntries([
          'onlyInComment',
        ], stripComments('// onlyInComment 以后要用' + '\n' + 'void f() {}')),
        ['onlyInComment'],
      );
      // 反面对手：把键名写进字符串字面量也不该被当成"用过"？
      // 这条**故意不管**：检测"名字出现在代码里"已经够用，再往上做 AST 就是另一个任务的量。
      expect(deadEntries(['inString'], "void f() => 'inString';"), <String>[]);
    });

    test('扫描确实覆盖到 lib/（提取失效即假绿）', () {
      expect(
        sources.length,
        greaterThan(50),
        reason: '只扫到 ${sources.length} 个文件 ⇒ 目录遍历失效，本文件已失去保护作用',
      );
      expect(arb.length, greaterThan(900));
    });

    test('T63 接线的那条必须已经活了：pageInitFailed 不再是死词条', () {
      // 它曾经是死的：ARB 里备好"页面初始化失败: {e}"，而 main_page 的装配链 catch
      // 只 debugPrint 了一行 —— 用户看到的是一个半初始化的应用和一句解释都没有。
      expect(dead, isNot(contains('pageInitFailed')));
    });

    test('死词条数 <= 棘轮值 $_ratchet', () {
      expect(
        dead.length,
        lessThanOrEqualTo(_ratchet),
        reason:
            '新增了没人用的 ARB 词条（当前 ${dead.length}，上限 $_ratchet）。'
            '要么接上它，要么把它删掉；\n'
            '当前清单（按字母序）：\n${dead.join("\n")}',
      );
    });
  });
}
