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
///
/// ## 存量怎么往下走（T63-B 第一刀：77 这个数里，24 条是守卫自己看错的）
/// 先把数摆正：修掉下面的排除规则之后，同一份 ARB 的真实死词条数是 **53**，不是 77 ——
/// 那 24 条一直活着，只是活在被整个 `lib/l10n/` 一起排除掉的**手写**扩展里
/// （`app_localizations_enum_helpers.dart`：枚举 → 词条的映射，gen-l10n 不碰它）。
/// 判据"说没人用而实际在用"比多留 24 条贵得多：下一只手就会照着清单去删。
/// 这一刀的第一版就是这么删掉了 `condPackage` / `condPriority` / `actionSilent`，
/// 重生成生成物之后编译当场红 —— 而本地不重生成时它是绿的（隔了一道的假绿）。
///
/// 真正删掉的 18 条是**机械可证**的那一批：同一个中文文案在字典里有两把键，一把有调用点、
/// 另一把没有 —— 改名留下的孪生（`latestVer` / `updateLatestVersionLabel` 这种）。留着它们的
/// 下场不是脏，是改文案的人只改到自己搜到的那一把，另一把继续当"看起来是配置"的暗雷。
///
/// ⚠ 剩下 35 条**不能这样一刀切**：里头既有"W3 那几页还没接线所以暂时没人用"（真该留着），
/// 也有"Dart 侧文案已经换成原生导出描述符所以再没人用"（该删）。这两种从"有没有调用点"上
/// 看不出来，只能逐条对着路线图问"哪一页要用它"。所以下一步不是降数字，而是把这张清单
/// 变成**带任务号的登记表**：每条预留都要写下它属于哪个任务，写不出来的就是该删的那一类。
const int _ratchet = 35;

/// gen-l10n 会覆盖的那三个文件 —— 排除的**只有这些**，`lib/l10n/` 下别的 .dart 一律算代码。
const List<String> _generatedL10n = [
  '/lib/l10n/app_localizations.dart',
  '/lib/l10n/app_localizations_en.dart',
  '/lib/l10n/app_localizations_zh.dart',
];

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
    // 生成物本身含每一个键，算进去就等于永不判红（这是守卫自己的假绿面）。
    // ⚠ 但排除只能按"是不是 gen-l10n 覆盖出来的那三个文件"，不能把整个 lib/l10n/ 一枪打死：
    //   `app_localizations_enum_helpers.dart` 是**手写**的（枚举 → 词条的映射，gen-l10n 不碰它），
    //   它引用着一批词条。整目录排除时这些键会被判成死词条 —— T63-B 的第一刀就是这么删掉了
    //   `condPackage` / `condPriority` / `actionSilent`，编译当场红（那还算好的：本地生成物
    //   没重生成时不红，CI 重生成之后才红，那是隔了一道的假绿）。
    final normalized = f.path.replaceAll(r'\', '/');
    if (_generatedL10n.any(normalized.endsWith)) continue;
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
        ], stripComments('// onlyInComment 以后要用\nvoid f() {}')),
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

    test('只被手写扩展 app_localizations_enum_helpers 用到的键 ⇒ 不算死词条', () {
      // T63-B 第一刀的真实教训：这三条当时被判成"与活键文案相同的改名残留"，删掉之后
      // gen-l10n 重生成 → 编译红。它们不是残留，是**在用**，只是用它们的那个文件住在
      // lib/l10n/ 下、被"排除生成物"那条规则一起排掉了。判据的盲点比存量更贵。
      for (final key in ['condPackage', 'condPriority', 'actionSilent']) {
        expect(
          dead,
          isNot(contains(key)),
          reason: '$key 只在 lib/l10n/ 那个手写的枚举扩展里被用到 ⇒ 它是活的',
        );
      }
    });

    test('排除生成物那条规则不许退回"整个 lib/l10n 一枪打死"', () {
      // 反证钉在这里而不是只写注释：谁把范围放宽回目录级，上面那条用例立刻红，
      // 而这条把"为什么"留在读得到的地方（新生成的文件名不会自动被排除）。
      final helpers = File(
        '$root/lib/l10n/app_localizations_enum_helpers.dart',
      );
      expect(helpers.existsSync(), isTrue, reason: '那个手写扩展被挪走了：这条守卫要一起改');
      expect(
        _generatedL10n.any(
          (p) => helpers.path.replaceAll(r'\', '/').endsWith(p),
        ),
        isFalse,
        reason: '手写文件不能进生成物名单',
      );
      expect(
        _generatedL10n.every((p) => File('$root$p').existsSync()),
        isTrue,
        reason: '名单里那三个都是真的生成物：少一个就说明名单漂了',
      );
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
