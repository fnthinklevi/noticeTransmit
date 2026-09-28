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
/// 判据说的是"有没有被用"，不是"该不该存在"：有些词条是给还没做的页面预留的，
/// 删掉它们会把规划删掉。所以这里立的是**具名登记表**（`_reserved`）而不是清零 ——
/// 新增一个没人用的词条就会红；要留，就得写下它属于哪个任务号。清掉存量请把登记表那一行删掉。
///
/// 计数只认**剥掉注释之后**的代码：词条名字出现在注释里不算用过
/// （否则"我在 TODO 里提了一下"就能让它永久免检）。
///
/// ## 存量怎么往下走（T63-B 第二刀：数字换成名字）
/// 第一刀（`756ec9d`）修掉了"手写扩展被目录级排除打死"这个盲点，删了 18 条机械可证的改名孪生，
/// 存量 77 → 53（真实）→ 35。这一刀要处理的是剩下的 35 条 —— 它们**不能按"有没有调用点"判**，
/// 所以先把清单逐条取证（谁取代了它 / 取代它的那次提交是哪个），再决定删还是留。
///
/// 35 条全部有罪，但罪名分四种，都不是"看着没人用"能看出来的：
/// - **改名孪生**（`checkUpdateFailed` vs 活的 `updateCheckFailedWithError`、`downloadFailed` vs
///   `updateDownloadFailed`、`exportMsg` vs `exportConfirmDesc`）—— 第一刀那批的余下部分。
/// - **被别的功能形状取代**：`on`/`off` 输给 `enabled`/`disabled`；`appChannelN`/`channelN`
///   是"整表平铺页"时代的默认名，T07 拆成列表页 + 详情页后默认名换了三级来源；
///   `channelStateEnabled/Disabled` 被 `ChannelHealthBadge` 取代；`ruleAppPinned*` 被"快速选择"取代；
///   企业微信那四条被 `appChannel*` 一族 + 原生描述符取代；`webhookTemplate*` 被 ActionChip 取代。
/// - **暗示一个已经不申请的权限**（`storagePermissionRequired` / `storagePermissionMsg` /
///   `noStoragePermission`）：下载早就改走 DownloadManager + 应用私有目录，全仓只申请
///   `REQUEST_INSTALL_PACKAGES`。留着不是脏，是让用户以为我们要读他的存储。
/// - **调用点被删干净后的正文残留**（`appListPermDesc2`、`goEnablePermission`、`initRetry`、
///   `refreshRetry`、`loading`、`ruleAppPickScanEmpty`…）—— git log -S 能查到当年那行代码。
///
/// 判据自己也有第三个盲点，这次顺手修掉：**`on` 是被 Dart 关键字判活的**。`try {} on X catch`
/// 里的 `on` 是语法，不是成员访问，而"键名当标识符出现过就算用过"对它同样成立 ⇒ 这条键**永远**
/// 判活。全仓 968 条里撞关键字的只有它一条（别的短键都至少有一次 `.key` 访问），但"只有 1 条"
/// 是量出来的，不是假设的：关键字族现在必须有 `.key` 形式的访问才算用过。
/// ⚠ 仍然存在的边界：像 `id`、`name` 这类既非关键字、又恰好和局部变量重名的键，裸标识符判据会
/// 把它判活而实际没人用。要堵住只能上 AST，那是另一个任务的量 —— 今天的兜底是"登记表必须具名"。
///
/// 所以这一步之后**不再用数字当棘轮**：`_reserved` 是唯一允许存在的死词条名单，每一条都要写下
/// 它属于哪个任务（写不出任务号的，这次一律删）。数字会漂、名字不会 —— 而且接完了忘删登记行
/// 也会红（名单与实测集合双向比对），登记表变垃圾场这条路是堵住的。
///
/// 登记表现在是**空的**：唯一预留的那条 `mainBackupExcluded` 已经接上（#136，通道状态弹层里
/// 「不参与」档的解释行，与「未设置」的 `mainBackupUnsetNotice` 对称）。空表意味着从这一刻起
/// 零容忍 —— 新增一个没人用的词条，要么接上、要么删掉，没有第三种走法。
const Map<String, String> _reserved = {};

/// 这些词出现在代码里时**只可能是语法**，不可能是 l10n 调用点（`try {} on X catch`、
/// `for (x in y)`、`void main()`）。裸标识符判据对它们无效，必须看到 `.key` 才算用过。
const Set<String> _dartReservedWords = {
  'abstract',
  'as',
  'assert',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'default',
  'deferred',
  'do',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'for',
  'get',
  'hide',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'is',
  'library',
  'new',
  'null',
  'on',
  'operator',
  'part',
  'required',
  'rethrow',
  'return',
  'set',
  'show',
  'static',
  'super',
  'switch',
  'sync',
  'this',
  'throw',
  'true',
  'try',
  'typedef',
  'var',
  'void',
  'while',
  'with',
  'yield',
};

/// gen-l10n 会覆盖的那三个文件 —— 排除的**只有这些**，`lib/l10n/` 下别的 .dart 一律算代码。
const List<String> _generatedL10n = [
  '/lib/l10n/app_localizations.dart',
  '/lib/l10n/app_localizations_en.dart',
  '/lib/l10n/app_localizations_zh.dart',
];

/// 判据本体（独立成函数是为了能被合成样本反证）。
/// [arbKeys] ARB 里的键集合；[sourceText] 已剥注释的全部 lib/ 代码。
List<String> deadEntries(Iterable<String> arbKeys, String sourceText) {
  final bare = RegExp(
    r'[A-Za-z_][A-Za-z0-9_]*',
  ).allMatches(sourceText).map((m) => m.group(0)!).toSet();
  // 关键字族只认成员访问：`try {} on X catch` 里的 `on` 不是"用过了词条 on"。
  final memberAccessed = RegExp(
    r'\.([A-Za-z_][A-Za-z0-9_]*)',
  ).allMatches(sourceText).map((m) => m.group(1)!).toSet();
  bool used(String k) => _dartReservedWords.contains(k)
      ? memberAccessed.contains(k)
      : bare.contains(k);
  return arbKeys.where((k) => !used(k)).toList()..sort();
}

/// 登记表与实测死集合的比对（判据本体，独立成函数是为了能被合成样本反证）。
/// 空表 + 空死集合是今天的实际状态，"理由没任务号""名单漂了"这两条在真实数据上**点不着** ——
/// 只能靠合成样本证明它们不是装饰。
List<String> registryGaps({
  required Iterable<String> dead,
  required Map<String, String> reserved,
  required Iterable<String> arbKeys,
}) {
  final deadSet = dead.toSet();
  final arbSet = arbKeys.toSet();
  return [
    for (final k in dead.where((k) => !reserved.containsKey(k))) '未登记：$k',
    for (final k in reserved.keys.where((k) => !deadSet.contains(k)))
      '登记已过期（接上了就删那一行）：$k',
    for (final e in reserved.entries)
      if (!RegExp(r'(T\d+|#\d+)').hasMatch(e.value)) '理由没任务号：${e.key}',
    for (final k in reserved.keys)
      if (!arbSet.contains(k)) '名单漂了：$k',
  ]..sort();
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
      // #136 同一形状的第二例：主备弹层里「不参与」有档位有徽标却没有解释行（对称的
      // 「未设置」有 mainBackupUnsetNotice）。文案早就在字典里，缺的从来不是字。
      expect(dead, isNot(contains('mainBackupExcluded')));
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

    test('关键字族的裸标识符命中不算用过（`on` 那类假绿）', () {
      // `try {} on X catch` 里的 on 是语法。裸 token 判据对它失效 ⇒ 必须看到 `.on`。
      expect(
        deadEntries([
          'on',
        ], 'void f() { try { g(); } on Exception catch (_) {} }'),
        ['on'],
      );
      expect(deadEntries(['on'], 'void f() { print(l10n.on); }'), <String>[]);
      // 反向：非关键字**仍然**认裸标识符 —— 那个手写扩展就是靠裸名字用词条的
      // （`ConditionType.packageName => condPackage`）。收紧到"只认成员访问"
      // 会把第一刀修掉的盲点原样带回来。
      expect(
        deadEntries(['condPackage'], 'String m() => condPackage;'),
        <String>[],
      );
    });

    test('登记比对着真实数据必须一条问题都没有（空表 + 空死集合）', () {
      // 数字棘轮（`_ratchet`）已被这个名字登记表取代：数字会漂，名字不会。
      // #136 接上最后一条预留之后，"空"就是字面意思：**没有任何**词条可以
      // "先备着以后再说" —— 要么接上、要么删、要么写下它属于哪个还没做的任务号。
      expect(
        registryGaps(
          dead: dead,
          reserved: _reserved,
          arbKeys: messageKeys(arb),
        ),
        isEmpty,
        reason: '当前死集合：${dead.join(", ")}；登记表：${_reserved.keys.join(", ")}',
      );
    });

    test('登记表比对的四种问题都点得着（真实数据上点不着，只能合成）', () {
      // 今天的真实数据是"零死词条 + 空登记表"，下面四类问题**一条都触发不了**。
      // 不在这里用合成样本钉住，它们就会在无人察觉的情况下变成装饰 ——
      // "接完了忘删登记行"恰恰是最容易长期存在、又最没人看的那一类。
      const arbKeys = ['wired', 'leftover', 'ghost', 'noTask'];
      expect(registryGaps(dead: ['leftover'], reserved: {}, arbKeys: arbKeys), [
        '未登记：leftover',
      ]);
      expect(
        registryGaps(
          dead: [],
          reserved: {'wired': 'T63 已接上'},
          arbKeys: arbKeys,
        ),
        contains('登记已过期（接上了就删那一行）：wired'),
      );
      expect(
        registryGaps(
          dead: ['noTask'],
          reserved: {'noTask': '以后某个页面要用'},
          arbKeys: arbKeys,
        ),
        contains('理由没任务号：noTask'),
      );
      expect(
        registryGaps(
          dead: ['ghost'],
          reserved: {'ghost': 'T99 预留'},
          arbKeys: ['wired'],
        ),
        contains('名单漂了：ghost'),
      );
      // 反面对手：合法登记必须一条问题都不报，否则上面四条只是"总能红"的摆设。
      expect(
        registryGaps(
          dead: ['leftover'],
          reserved: {'leftover': 'W4 → #137：那一页还没接线'},
          arbKeys: arbKeys,
        ),
        isEmpty,
      );
    });

    test('T63-B 第二刀删掉的必须回不来（同名键再出现就红）', () {
      // 这批不是"改天再接"，是**已被取代**：留着只会让下个改文案的人改到错的那一把。
      // 如果有人把某条加回来，这条断言要求他先回答"取代它的那个UI去哪了"。
      for (final key in const [
        'on',
        'off',
        'loading',
        'checkUpdateFailed',
        'downloadFailed',
        'storagePermissionRequired',
        'appChannelN',
        'channelStateEnabled',
        'wecomAppTouserHint',
        'ruleAppPinnedNote',
      ]) {
        expect(arb.containsKey(key), isFalse, reason: '$key 是被取代的旧文案，不该回字典');
        expect(dead, isNot(contains(key)));
      }
    });
  });
}
