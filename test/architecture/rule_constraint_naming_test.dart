import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T23-A：「规则引擎」→「规则约束」这条定名的契约。
///
/// 改名是本批唯一的产品语义变化，而它的失效模式全是**静默**的：
/// 1. 只改 ARB 不跑 `gen-l10n` ⇒ 界面还是旧文案，而所有读 ARB 的守卫全绿；
/// 2. 只改中文不改英文（或反之）⇒ 一半用户仍然看到两个名字，且没人会报错；
/// 3. 闸门按中文字面量点入口（`_openMoreRow(tester, '规则约束')`）⇒ 文案再变一次，
///    闸门"找不到就跳过"，从此这一节不再被点而仍是绿的（㊻ 那轮实测过同型骗局）。
///
/// ⚠ 判据一律从 ARB **取值再去比对**，不把新名字再抄成第三份字面量 —— 否则这里也变成
///   一处需要同步的抄本（本批要消灭的正是这种东西）。
void main() {
  final root = projectRoot();
  String read(String rel) =>
      File('$root/$rel').readAsStringSync().replaceAll('\r\n', '\n');

  Map<String, dynamic> arb(String locale) =>
      jsonDecode(read('lib/l10n/arb/app_$locale.arb')) as Map<String, dynamic>;

  /// 旧名（中英、含大小写变体）。用户可见文案里一处都不该再出现。
  const oldTerms = ['规则引擎', 'Rule Engine', 'rule engine', 'Rule engine'];

  group('用户可见文案不再叫规则引擎', () {
    test('ARB 的**值**里不许再出现旧名（键名保留，那是内部标识符）', () {
      for (final locale in const ['zh', 'en']) {
        final data = arb(locale);
        final hits = <String>[];
        data.forEach((key, value) {
          // `@key` 是元数据（description 等），写给开发者看，不算用户可见文案。
          if (key.startsWith('@') || value is! String) return;
          if (oldTerms.any(value.contains)) hits.add(key);
        });
        expect(
          hits,
          isEmpty,
          reason:
              '$locale 这些词条的值还写着旧名：$hits ⇒ 定名只做了一半，'
              '同一个功能在界面上有两个名字（键名不改是本次的边界，改到键名要另议）',
        );
      }
    });

    test('生成物与 ARB 同步（改了 arb 忘了 gen-l10n = 界面还是旧文案）', () {
      // 这条是本守卫存在的核心理由：上面那条只证明 arb/ 改了，而 App 渲染的是
      // lib/l10n/app_localizations_<locale>.dart。
      for (final locale in const ['zh', 'en']) {
        final data = arb(locale);
        final generated = read('lib/l10n/app_localizations_$locale.dart');
        for (final key in const [
          'ruleEngine',
          'ruleGuideTitle',
          'ruleAppPinnedNote',
          'testerFilteredNote',
        ]) {
          final value = data[key]! as String;
          expect(
            generated,
            contains(value),
            reason:
                'ARB 的 $key 是「$value」，但生成物里没有 ⇒ 跑 `flutter gen-l10n`；'
                '只改 arb 的提交在真机上显示的还是旧文案',
          );
        }
        expect(
          generated,
          isNot(contains('=> \'${locale == 'zh' ? '规则引擎' : 'Rule Engine'}\'')),
          reason: '$locale 生成物里还有旧名的 getter 直值 ⇒ 与 ARB 已分叉',
        );
      }
      // 反向锚点：新名字确实进了生成物，否则"不含旧名"可能只是因为文件是空的。
      expect(read('lib/l10n/app_localizations_zh.dart'), contains('规则约束'));
      expect(
        read('lib/l10n/app_localizations_en.dart'),
        contains('Rule Constraints'),
      );
    });

    test('两个总开关式长文案（隐私）也一起改了', () {
      // 隐私页那两条是超长拼接串，整值比对不现实，按"旧名子串必须消失"判。
      for (final locale in const ['zh', 'en']) {
        final data = arb(locale);
        for (final key in const ['privacyInfoContent', 'privacyPermContent']) {
          final value = data[key]! as String;
          expect(
            oldTerms.any(value.contains),
            isFalse,
            reason: '$key 里还留着旧名 ⇒ 权限/隐私说明与功能入口叫法不一致',
          );
          // 正向锚点：整条文案没被误删空。
          expect(value.length, greaterThan(200), reason: '$key 短得不像一条完整说明');
        }
      }
    });
  });

  group('入口文案与闸门必须同源', () {
    test('更多页入口取的是 ARB 键，不是硬编码字面量', () {
      final page = stripComments(read('lib/pages/more_page.dart'));
      expect(
        page,
        contains('title: l10n.ruleEngine'),
        reason: '入口标题不再走 l10n ⇒ 又变成一份不受守卫的抄本（改 ARB 不再生效）',
      );
      for (final term in oldTerms) {
        expect(
          page,
          isNot(contains('\'$term\'')),
          reason: 'more_page 里出现了硬编码的「$term」',
        );
      }
    });

    test('闸门点「更多 → 规则约束」用的字面量 == ARB 当前值', () {
      final label = arb('zh')['ruleEngine']! as String;
      final walkthrough = read(
        'integration_test/release_walkthrough_test.dart',
      );
      expect(
        walkthrough,
        contains("_openMoreRow(tester, '$label')"),
        reason:
            'ARB 是「$label」，闸门点的却不是它 ⇒ 这一整节（编辑/新建/删除规则、'
            '测试器、模板库）在闸门里静默失配，闸门还会显示全绿',
      );
      // 反向锚点：至少被点三次（5.7 / 5.8 / 5.9），一次都不点就是整节退出覆盖面。
      expect(
        RegExp(
          "_openMoreRow\\(tester, '$label'\\)",
        ).allMatches(walkthrough).length,
        greaterThanOrEqualTo(3),
        reason: '入口被点的次数变少 ⇒ 有整节规则测试退出了闸门',
      );
      // 发版清单里那句"入口都被点过"的名单也必须跟着走。
      expect(
        stripComments(
          read('test/architecture/release_gate_emulator_test.dart'),
        ),
        contains("'$label'"),
        reason: '入口名单还写着旧名 ⇒ 那份清单已经不再约束真正的闸门',
      );
    });

    test('旧名没被换成"再抄一遍"的第二份抄本（站点与 README 同步）', () {
      // 站点 i18n 是**以中文原文为键**的字典，改中文必须同批改键，否则英文站静默显示中文。
      // 这里只钉"旧名不再出现"，键/值配对由 tools/check_site_i18n.py 覆盖。
      for (final rel in const [
        'server/public/index.html',
        'server/public/i18n.js',
        'README.md',
        'README-en.md',
        '.github/ISSUE_TEMPLATE/bug_report.md',
        '.github/ISSUE_TEMPLATE/feature_request.md',
      ]) {
        final src = read(rel);
        expect(
          oldTerms.any(src.contains),
          isFalse,
          reason: '$rel 里还有旧名 ⇒ 对外说明与应用内叫法分叉',
        );
      }
      expect(read('server/public/i18n.js'), contains('规则约束'));
      expect(read('server/public/i18n.js'), contains('Rule Constraints'));
    });
  });

  group('守卫自己', () {
    test('反证：把旧名塞回任一判据的形状，必须判红', () {
      // 逐条给出"旧形状"，确认这些判据不是恒真的装饰。
      final withOldZhValue = {
        'ruleEngine': '规则引擎',
        '@meta': {'description': 'x'},
      };
      final hits = withOldZhValue.entries
          .where(
            (e) =>
                !e.key.startsWith('@') &&
                oldTerms.any((e.value as String).contains),
          )
          .map((e) => e.key)
          .toList();
      expect(hits, ['ruleEngine'], reason: 'ARB 值扫描对"值里含旧名"不敏感 ⇒ 判据是摆设');
      // 元数据里出现旧名**不算**命中（否则本批会被自己的 description 挡住）。
      expect(
        {
          '@ruleEngine': {'description': '规则引擎入口'},
        }.entries.any(
          (e) =>
              !e.key.startsWith('@') &&
              e.value is String &&
              oldTerms.any((e.value as String).contains),
        ),
        isFalse,
      );
      // 生成物与 ARB 分叉的形状：ARB 新、生成物旧 ⇒ 必须被"contains(值)"抓到。
      expect(
        'String get ruleEngine => \'规则引擎\';'.contains('规则约束'),
        isFalse,
        reason: '生成物同步判据抓不到"只改了 arb" ⇒ 那条判据是假的',
      );
      // 闸门字面量分叉的形状。
      expect(
        "_openMoreRow(tester, '规则引擎')".contains("_openMoreRow(tester, '规则约束')"),
        isFalse,
      );
    });
  });
}
