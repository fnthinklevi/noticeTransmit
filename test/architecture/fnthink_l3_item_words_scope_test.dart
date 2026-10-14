import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T146 片6（格③ 的现读结论 + 那一格真正欠的那判）：权限页那三项词表与对面那张词表**不许合，也不许串台**。
///
/// ## 为什么"同一枚 `monitoring` 两套人话"不能靠合表来治
/// 立行时记的是「`monitoring` 在两张表里叫两样 ⇒ 过于杂乱」。现读之后是**两个主语**：
///  - `kFnthinkRemoteActionLabels`（对面视角）：`monitoring` 叫「开／关对面的通知转发总开关」——
///    那句答的是**这条指令会对对面那台做什么**，读它的人正在决定要不要发出去。
///  - 权限页 `_l3ItemTitle`（本机视角）：`monitoring` 叫「通知转发监听」——
///    那句答的是**这台机器现在有没有这项授权**，读它的人正在去系统里开。
/// 合成一张表 ⇒ 权限页那一行会写成「开／关对面的通知转发总开关」，而那一页通篇在讲"这台给了没有"，
/// **那是界面替用户编的一句它没做的事**。⇒ 本守卫钉的是"各归各位、不许串台"，不是"只许一张表"。
///
/// ## 那一格真正欠的是"少一项没人喊"
/// 对面那张表有双向差集守卫（契约加一项而表里没配 ⇒ 当场红）。这一页的三处 switch
/// （标题／图标／落点）今天**一枚守卫都没有**：契约加第 7 项时，
/// 标题退成裸 key（看得见，但没人喊）、图标退成默认那枚，而落点那一处直接落进 `_ => null` ——
/// **那一行永远不给出口，界面上一切正常**。⇒ ①②③ 三条各钉一处，差集判据（多一项也红）。
void main() {
  final root = projectRoot();
  final contract = FnthinkContract.readFile();
  final page = stripComments(
    librarySource(root, 'lib/pages/permission_settings_page.dart'),
  );

  final settings = contract.l3Settings.keys.toSet();

  /// 取某一处 switch 的 case 键集合（只认字符串字面量那形，枚举分支不算）。
  Set<String> caseKeys(String signature) {
    final block = blockAfter(page, signature);
    return {
      for (final m in RegExp(r"'([a-z][a-z0-9_]+)'\s*=>").allMatches(block))
        m.group(1)!,
    };
  }

  /// 落点那一处**允许少**：那两项的开关住在「幻念推送」页，给跳转反而制造"点了没反应"。
  /// 但"少哪几项"必须逐条在册 —— 新加一项却掉进 `_ => null` 时，这一条必须红。
  const kNoJumpItems = {'monitoring', 'collect_inbox'};

  /// 对面视角那张表的读者（幻念那几页）—— 串台判据扫的就是这几份。
  const remotePages = [
    'lib/pages/fnthink_send_page.dart',
    'lib/pages/fnthink_peers_page.dart',
    'lib/pages/remote_history_page.dart',
    'lib/pages/remote_credential_settings_page.dart',
  ];

  test('① 标题那一处覆盖契约全量（少一项＝那一行只剩裸 key，多一项＝画一个不存在的设置）', () {
    final titled = caseKeys('String _l3ItemTitle(');
    expect(
      settings.difference(titled),
      isEmpty,
      reason: '契约里有而这一页没配词条 ⇒ 屏上是一枚生词，而没人喊（本页此刻零守卫）',
    );
    expect(
      titled.difference(settings),
      isEmpty,
      reason: '这一页多配了一项 ⇒ 画出来的是一台压根没有的设置项',
    );
  });

  test('② 图标那一处同样覆盖全量（漏了不崩、只是静默换一枚默认图）', () {
    final icons = caseKeys('IconData _l3Icon(');
    expect(
      settings.difference(icons),
      isEmpty,
      reason:
          '图标漏一项不会被任何用例逮到：那一行照画，只是换成缺省那枚 —— '
          '同一份清单在屏幕上被认成两样东西，正是裁定 5 说的那种乱',
    );
    expect(
      icons.difference(settings),
      isEmpty,
      reason: '图标表里多出来的一项不在契约里 ⇒ 这一族在本页长出了第二个名单',
    );
  });

  test('③ 落点那一处：在册的都有来路，没在册的必须逐条登记理由', () {
    final jumpable = caseKeys('VoidCallback? _l3Jump(');
    expect(
      jumpable.intersection(kNoJumpItems),
      isEmpty,
      reason: '这两项的开关住在「幻念推送」页；给这一下＝制造"点了没反应"那一类缺陷',
    );
    expect(
      settings.difference(jumpable.union(kNoJumpItems)),
      isEmpty,
      reason:
          '契约新增一项而这里既没给落点、也没登记"为什么不给" ⇒ 它掉进 `_ => null`，'
          '那一行永远没有出口，而界面上一切正常（本仓反复砸过的静默降级）',
    );
  });

  test('④ 两张词表不许串台：本机那张只住这一页，对面那张不许写进这一页', () {
    // 正向自证（负向断言不许瞎掉）：两张表此刻**各有真读者**，否则"不许出现"永远成立。
    expect(
      page.contains('l10n.l3Item'),
      isTrue,
      reason: '这一页已经不用自己的那张表了 ⇒ 下面那条"对面那张不许进来"是空断言',
    );
    final remoteSources = [
      for (final rel in remotePages) stripComments(librarySource(root, rel)),
    ];
    expect(
      remoteSources.any((s) => s.contains('fnthinkRemoteActionLabel(')),
      isTrue,
      reason: '对面那张表零读者 ⇒ 这一族已经没人吃它了，串台判据得改写',
    );

    expect(
      page.contains('fnthinkRemoteActionLabel('),
      isFalse,
      reason: '权限页吃对面那张表 ⇒ 本机那一行会被写成"开／关**对面**的…那句"（主语串了）',
    );
    expect(
      page.contains('remoteSetting'),
      isFalse,
      reason: '同上：直接引对面那张表的词条，等于在这一页替对面说话',
    );
    for (var i = 0; i < remotePages.length; i++) {
      expect(
        remoteSources[i].contains('l10n.l3Item'),
        isFalse,
        reason:
            '${remotePages[i]} 吃本机那张表 ⇒ 发送/名单那一屏会说成"这台有没有授权"，'
            '而那几页答的是"这条指令会对对面做什么"（差异③ 的另一半）',
      );
    }
  });

  test('⑤ 尺认得合成样本（防 ①②③ 退化成"恒不匹配＝恒绿"）', () {
    const sample = '''
String _l3ItemTitle(AppLocalizations l10n, String key) => switch (key) {
  'notification' => l10n.notifAccessPerm,
  'brand_new_thing' => l10n.l3ItemBrandNew,
  _ => key,
};
''';
    final found = {
      for (final m in RegExp(r"'([a-z][a-z0-9_]+)'\s*=>").allMatches(sample))
        m.group(1)!,
    };
    expect(found, {'notification', 'brand_new_thing'});
    // 枚举分支（四态那句）不许被当成字符串 case：`=>` 左边没有引号那一形就不是词表项。
    const enumSwitch = '''
String s() => switch (state) {
  FnthinkL3GrantState.granted => onText,
  FnthinkL3GrantState.missing => missingText,
};
''';
    expect(
      RegExp(r"'([a-z][a-z0-9_]+)'\s*=>").hasMatch(enumSwitch),
      isFalse,
      reason: '枚举分支也被抽进键集 ⇒ 三处 switch 的差集掺进不属于词表的东西',
    );
    // 下限：尺今天真从页面里抽得出东西（空集会让 ①②③ 同时假绿）。
    expect(caseKeys('String _l3ItemTitle('), isNotEmpty);
    expect(caseKeys('IconData _l3Icon('), isNotEmpty);
    expect(settings, hasLength(greaterThanOrEqualTo(6)));
  });
}
