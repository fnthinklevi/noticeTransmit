import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_grant_items.dart';
import 'package:notice_transmit/services/fnthink_pair_items.dart';

import '../support/source_guards.dart';

/// T134 片3 + 片4：那张勾选表的**接缝守卫**。
///
/// 行为那半边由 `test/widgets/fnthink_settings_page_test.dart` 那十几条钉（勾了才进载荷、
/// 不勾是空数组、拒绝不带清单、参数没填全勾不动、参数一改勾就掉）。这里钉的是行为用例
/// 钉不住的那一维：**名单与形状是不是只有一个出处**。
/// 页面级用例永远测不出"有人嫌派生麻烦，直接在界面里抄了十行" —— 抄的那份在今天的契约下
/// 与派生那份逐字相同，所以每一条都绿；等契约加一项，那一格就悄悄不出现，而界面上读起来
/// 与"用户没勾"一模一样。这条线在本仓已经被踩过多轮（模板变量、动作表、族清单）。
void main() {
  final root = projectRoot();
  // `librarySource` 要的是"从仓库根算起的路径"，而 `libCodeByRel` 给的键是 `lib/` 之后的那段。
  // 两个名字分开写，是因为把它们合成一个的时候，守卫会去读一个不存在的路径（然后以"没找到"通过）。
  const pagePath = 'lib/pages/fnthink_peers_page.dart';
  const pageKey = 'pages/fnthink_peers_page.dart';
  const rowsKey = 'services/fnthink_grant_items.dart';
  const levelKey = 'services/fnthink_pair_items.dart';
  final contract = FnthinkContract.readFile();

  /// 契约那两张表的**全部项名** + 三种参数形状里的**取值**（族、两个目标词）。
  /// 页面里出现其中任何一个字面量都是抄的。
  final allVocabulary = <String>[
    ...contract.l2Actions,
    ...contract.l3Settings.keys,
    ...contract.l2ChannelTargetFamilies,
    ...contract.l2ChannelTargetWords,
    ...contract.l3ItemTargetWords,
  ];

  test('页面里不许出现任何一项的词表字面量：名单与取值都只能派生', () {
    final code = stripComments(librarySource(root, pagePath));
    for (final item in allVocabulary) {
      expect(
        code,
        isNot(contains("'$item'")),
        reason:
            '$item 被抄进了页面 —— 契约加一项时这一格会静默缺席，'
            '而"派生"那条判据（pairItemRows）不会红',
      );
    }
    // 分隔符也不许写进界面：整串的拼法只有一个作者（`grantItemWire`），
    // 界面里出现一枚 '/' 就是第四份形状，而它是**看不见**的那一份（勾出去的串没人复算）。
    expect(
      code,
      isNot(contains("'${contract.grantItemSeparator}'")),
      reason: '页面自己拼斜杠 ⇒ 契约换分隔符时这一处不跟着换，串就切不出唯一结果',
    );
    // 反向自证：不许用"把那一段整块删掉"来满足上面那些条。
    expect(
      code,
      contains('pairItemRows('),
      reason: '页面必须仍从派生取名单；删掉调用点会让上面那组断言全部空洞通过',
    );
    expect(
      code,
      contains('grantItemProblem('),
      reason: '"这一格能不能勾"必须由那唯一一枚判据给，界面不许自己凑"填全了没有"',
    );
  });

  test('派生层的调用点各有唯一一处读者（名单、词表基名、能不能勾）', () {
    final code = libCodeByRel(root);
    // 三份账各数各的：合成一个"这几个名字一共出现几次"会造假绿
    // （多一处 pairItemRows 会被少一处 grantItemProblem 抵掉）。
    expect(
      [
        for (final e in code.entries)
          if (e.value.contains('pairItemRows(') && e.key != rowsKey) e.key,
      ],
      // 第二个读者是守卫自己（本文件读它不算）与页面。
      {pageKey},
      reason: '再多一处＝多一份"这一项算不算能被勾"的判断',
    );
    expect(
      [
        for (final e in code.entries)
          if (e.value.contains('grantItemBases(') && e.key != rowsKey) e.key,
      ],
      {'services/fnthink_sender_grant.dart'},
      reason: '逐条判据要的是"清单管得着哪些名字"，除它之外不该有人这么问',
    );
    expect(
      [
        for (final e in code.entries)
          if (e.value.contains('grantItemProblem(') && e.key != rowsKey) e.key,
      ],
      {pageKey, 'services/fnthink_receive_coordinator.dart'},
      reason:
          '一处是"这一格现在勾不勾得上"，一处是"答复发出去之前先看一眼"——'
          '第三处出现就意味着有一份勾逐项的判据没在这两个位置上',
    );
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
    final passed = RegExp(r'items:\s*([A-Za-z_][A-Za-z0-9_]*)\s*[,)]')
        .firstMatch(code);
    expect(passed, isNotNull, reason: 'pairConfirm 那一发现在交的是字面量（或根本没交）');
  });

  test('两份派生文件都不许反过来依赖界面', () {
    // 这一族有过一次教训：把 DB 层要读的词表放进 lib/services/ 会倒置层次。
    // 这里钉的是另一头：派生层不许 import 页面/控件，否则它就成了界面的第二份形状。
    for (final rel in [levelKey, rowsKey]) {
      final code = stripComments(librarySource(root, 'lib/$rel'));
      expect(code, isNot(contains('flutter/material.dart')), reason: rel);
      expect(code, isNot(contains('pages/')), reason: rel);
      expect(code, isNot(contains('AppLocalizations')), reason: rel);
    }
    // 档位/取值域那一份是真的纯：除契约之外不碰 IO / 平台通道。
    expect(
      stripComments(librarySource(root, 'lib/$levelKey')),
      isNot(contains('MethodChannel')),
    );
  });

  test('派生结果覆盖两张词表的全量，每一项的来路都说得清', () {
    // 这条不是"数个数"，是**登记**：片4 之后这张表不再做减法，
    // 那么"少一项"就只能是缺陷，而"多一项"意味着界面在画契约不认识的东西。
    final rows = pairItemRows(contract);
    expect(rows.length, contract.l2Actions.length + contract.l3Settings.length);
    final byKind = <String, int>{};
    for (final row in rows) {
      byKind[row.kind.name] = (byKind[row.kind.name] ?? 0) + 1;
    }
    expect(
      byKind['none'],
      contract.l2Actions.length -
          contract.l2ActionsRequiringArgument.length +
          contract.l3Settings.values.where((s) => !s.isToggle).length,
    );
    expect(byKind['count'], 1, reason: '「要几条」现在只可能是 notifications:report 一项');
    expect(
      byKind['keyword'],
      contract.l2ActionsRequiringArgument.length - 2,
      reason: '要参数的那六项里，除去 count 与 channelTarget 剩下的都是 keyword',
    );
    expect(byKind['channelTarget'], 1);
    expect(
      byKind['toggle'],
      contract.l3Settings.values.where((s) => s.isToggle).length,
    );
    // 每一项都落在契约声明的取值域里（与 `pairItemRows` 末尾那次自证同源，
    // 这里钉的是"守卫读的与实现读的是同一份取值域"）。
    final vocabulary = contract.pairConfirmItemsVocabulary;
    expect(vocabulary, isNotEmpty, reason: '取值域空着 ⇒ 上面那组 kind 计数全是空中楼阁');
    for (final row in rows) {
      expect(
        pairItemVocabulary(contract),
        contains(row.base),
        reason: '${row.base} 是界面画得出来、服务端却不认识的形状',
      );
    }
  });
}
