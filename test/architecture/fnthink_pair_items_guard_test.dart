import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_pair_items.dart';

import '../support/source_guards.dart';

/// T134 片3：那张勾选表的**接缝守卫**。
///
/// 行为那半边由 `test/widgets/fnthink_settings_page_test.dart` 里那六条钉（勾了才进载荷、
/// 不勾是空数组、拒绝不带清单）。这里钉的是行为用例钉不住的那一维：
/// **名单是不是只有一个出处**。页面级用例永远测不出"有人嫌派生麻烦，直接在界面里抄了十行" ——
/// 抄的那份在今天的契约下与派生那份逐字相同，所以每一条都绿；等契约加一项，那一格就悄悄不出现，
/// 而界面上读起来与"用户没勾"一模一样。这条线在本仓已经被踩过多轮（模板变量、动作表、族清单）。
void main() {
  final root = projectRoot();
  // `librarySource` 要的是"从仓库根算起的路径"，而 `libCodeByRel` 给的键是 `lib/` 之后的那段。
  // 两个名字分开写，是因为把它们合成一个的时候，守卫会去读一个不存在的路径（然后以"没找到"通过）。
  const pagePath = 'lib/pages/fnthink_peers_page.dart';
  const pageKey = 'pages/fnthink_peers_page.dart';
  const selfKey = 'services/fnthink_pair_items.dart';
  final contract = FnthinkContract.readFile();

  /// 契约那两张表的**全部**项名（含要参数的那几项）—— 页面里出现其中任何一个字面量都是抄的。
  final allVocabulary = <String>[
    ...contract.l2Actions,
    ...contract.l3Settings.keys,
  ];

  test('页面里不许出现任何一项的词表字面量：名单只能派生', () {
    final code = stripComments(librarySource(root, pagePath));
    for (final item in allVocabulary) {
      expect(
        code,
        isNot(contains("'$item'")),
        reason:
            '$item 被抄进了页面 —— 契约加一项时这一格会静默缺席，'
            '而"派生"那条判据（pairItemCandidates）不会红',
      );
    }
    // 反向自证：不许用"把那一段整块删掉"来满足上面那条。
    expect(
      code,
      contains('pairItemCandidates('),
      reason: '页面必须仍从派生取名单；删掉调用点会让上面那组断言全部空洞通过',
    );
  });

  test('pairItemCandidates 的调用点只有两处：那张页与本机那份逐条判据', () {
    final hits = <String>[
      // 注意 `libCodeByRel` 已经把注释剥过一层，且**定义那一行本身也含这个名字**，
      // 所以这里比的是"除定义文件之外还有谁调它"。
      for (final entry in libCodeByRel(root).entries)
        if (entry.value.contains('pairItemCandidates(') && entry.key != selfKey)
          entry.key,
    ];
    // 第二个读者是 T128 片2 的 `rejectBySenderGrant`，而它要的不是"该画哪些项"，
    // 是"**清单表达得了哪些项**"：那份形状上的减法必须是同一份，否则
    // 同意屏给勾的集合与判据认的集合会各自漂（漂的那一侧永远是"用户明明勾了却被拒"）。
    expect(hits.toSet(), {
      pageKey,
      'services/fnthink_sender_grant.dart',
    }, reason: '再多一处调用＝多一份"这一项算不算能被勾"的判断');
    expect(hits.length, 2, reason: '上面那个集合挡不住同一文件被数两遍');
  });

  test('协调者交出去的是变量，不是又写死的空清单', () {
    final code = stripComments(
      librarySource(root, 'lib/services/fnthink_receive_coordinator.dart'),
    );
    expect(
      code,
      isNot(contains('items: const <String>[]')),
      reason:
          '片1 的占位写法。留着它，那张表勾什么都到不了载荷，'
          '而屏幕上那句"已同意"是真的 —— 最难查的那种静默',
    );
    final passed = RegExp(
      r'items:\s*([A-Za-z_][A-Za-z0-9_]*)\s*[,)]',
    ).firstMatch(code);
    expect(passed, isNotNull, reason: 'pairConfirm 那一发现在交的是字面量（或根本没交）');
  });

  test('派生用的那份纯文件不许反过来依赖界面', () {
    // 这一族有过一次教训：把 DB 层要读的词表放进 lib/services/ 会倒置层次。
    // 这里钉的是另一头：派生层不许 import 页面/控件，否则它就成了界面的第二份形状。
    final code = stripComments(
      librarySource(root, 'lib/services/fnthink_pair_items.dart'),
    );
    expect(code, isNot(contains('flutter/material.dart')));
    expect(code, isNot(contains('pages/')));
    // 纯函数确实纯：除契约与 dart:core 之外不碰 IO / 平台通道。
    expect(code, isNot(contains('MethodChannel')));
  });

  test('派生结果的形状与页面读它的方式一致（本页只读名单，不读标签）', () {
    // 标签另有一位作者（kFnthinkRemoteActionLabels）：这里钉的是"派生层不产文案"，
    // 否则中英两套会在服务层里漏出中文（这条纪律在 l3_grants 那层已经立过）。
    expect(pairItemCandidates(contract), everyElement(isA<String>()));
    expect(
      stripComments(
        librarySource(root, 'lib/services/fnthink_pair_items.dart'),
      ),
      isNot(contains('AppLocalizations')),
    );
  });

  // 这条不是守卫，是**读数登记**：这张表今天覆盖 18 项里的哪几项，是片3 唯一的边界。
  test('可勾项的条数从契约现读（当前口径：无参数的那几项）', () {
    final got = pairItemCandidates(contract);
    expect(got.length, allVocabulary.length - 8);
    expect(
      allVocabulary.length - got.length,
      contract.l2ActionsRequiringArgument.length +
          contract.l3Settings.values.where((s) => s.isToggle).length,
      reason: '差额必须逐字解释得清：少画的那几项就是"要填参数的"那几项，一项不多一项不少',
    );
  });
}
