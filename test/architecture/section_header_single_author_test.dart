import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T146 片4：组标题这一族的画法只有一个作者（`FnthinkRowLabel`）。
///
/// ## 量出来的旧状态（2026-10-13 现读，`lib/pages` 全族扫描）
/// 「一组行上面那一行名目」原来有**四种写法**：
/// - 幻念三张清单页（设置页 6 处、名单页 1 处、发送页 1 处）走公共件 `FnthinkRowLabel`；
/// - `more_page` 与 `permission_settings_page` 各抄一枚**逐字相同**的私有 helper
///   （13px + `FontWeight.w500` + 次要字色，且**画不出 key**）；
/// - `update_server_page` 自己搭了一枚 12px/w600 的壳（与上面那些差 1px —— 那 1px 就是"两处各漂各的"）；
/// - `history_page._allSectionHeader` 是 13px/w600，但 key 挂在**外层 Padding** 上而不是那一格上。
/// 现在四家全部 delegate 到公共件：各页只交出**自己在版面里的留白**，画法与 key 由件给。
///
/// ## 这本账的牙
/// ① 每一枚"组标题 helper"都必须 delegate 到公共件 —— 全仓扫，长回自搭壳一律红。
/// ② 尺认得合成样本：① 绿的时候"全都合规"与"尺一枚都没认出来"同形（本仓栽过两次：提取式一收窄，
///   正则恒不匹配 ⇒ 差集恒空 ⇒ 绿着什么都没量到）。块状体、表达式体、合规写法三种样本都喂。
/// ③ 各页的**渲染点数**与台账相等（helper 页算调用点，直调页算公共件出现数）。
///   ⚠ 不算 `FnthinkRowLabel(` 的字面出现数：helper 页五处调用只展开成一枚字面件，那样数会少四倍。
/// ④ 十二枚组标题 keyName 一个都不重（两枚共用一个 key，点到的就不是要的那一枚）。
/// ⑤⑥⑦⑧ **闸门那一侧的读数**（片4 挪了 key 宿主之后现读补的四条）：闸门里"按 key 定位那一格、
///   再读它的文字"只许有一把尺（⑤ 两把宿主都读），它的每个调用点必须断非空（⑥），尺本身要认得
///   合成样本（⑦），而那一段钉的是件不是 key（⑧）。
///   起因不是新功能 —— key 挪到 `Text` 上之后，闸门只往下 `find.descendant` 读会恒得空串，
///   那句"段标题不许有数字"就变成对空串恒真：**设备上照样报绿，量的却是一件不存在的事**。
///
/// ⚠ 读源码一律先剥注释（`stripComments`）：这些 helper 头上就挂着解释性注释。
void main() {
  final root = projectRoot();

  /// 走 helper 的页：页 → helper 名。渲染点数 = 该名字的调用点数（扣掉定义那一处）。
  const delegated = <String, String>{
    'pages/more_page.dart': '_buildSectionHeader',
    'pages/permission_settings_page.dart': '_buildSectionHeader',
    'pages/update_server_page.dart': '_sectionHeader',
    'pages/history_page.dart': '_allSectionHeader',
  };

  /// 每一页画多少枚组标题（这本账就是剩余工作量，也是"偷偷改回自搭"的回退网）。
  const usage = <String, int>{
    'pages/more_page.dart': 5,
    'pages/permission_settings_page.dart': 5,
    'pages/update_server_page.dart': 2,
    'pages/history_page.dart': 3,
    'pages/fnthink_settings_page.dart': 7,
    'pages/fnthink_peers_page.dart': 1,
    'pages/fnthink_send_page.dart': 1,
  };

  /// 尺的本体：给定一页**剥注释后**的源码，返回其中没交给公共件的组标题 helper 名。
  ///
  /// 认法取"两空格缩进的成员声明 + 方法名以 SectionHeader 结尾"这一形状
  /// （`_buildSectionHeader`／`_sectionHeader`／`_allSectionHeader`／换名 `morePageSectionHeader` 都落网）。
  /// ⚠ 只认 `Widget ` 开头那一行：调用点（`child: _allSectionHeader(...)`）不是声明，
  ///   混进来的话"渲染点数"与"抄本"两件事都会跟着抖。
  /// ⚠ 方法体取到**下一个同级成员行**（`\n  ` 后紧跟非空白）为止：
  ///   取到第一个 `}` 会截早（体内就有 `}`，`Text(` 留在窗外 ⇒ 假绿），
  ///   取到文件末尾会串到下一枚 helper（别人的 `FnthinkRowLabel(` 被算进这一枚 ⇒ 假红）。
  List<String> sectionHeaderCopies(String strippedSource) {
    final copies = <String>[];
    final decl = RegExp(
      r'^  Widget\s+(\w*[Ss]ectionHeader)\s*[(=]',
      multiLine: true,
    );
    for (final m in decl.allMatches(strippedSource)) {
      final rest = strippedSource.substring(m.end);
      final nextMember = RegExp(r'\n  \S').firstMatch(rest);
      final body = nextMember == null
          ? rest
          : rest.substring(0, nextMember.start);
      if (!body.contains('FnthinkRowLabel(')) copies.add(m.group(1)!);
    }
    return copies;
  }

  Map<String, String> pageCode() => {
    for (final e in libCodeByRel(root).entries)
      if (e.key.startsWith('pages/')) e.key: e.value,
  };

  int renderPoints(String src, String helper) =>
      RegExp('$helper\\(').allMatches(src).length - 1;

  test('① 组标题 helper 一律 delegate 到公共件（全仓扫，自搭壳一律红）', () {
    final code = pageCode();
    for (final e in delegated.entries) {
      expect(code[e.key], isNotNull, reason: '${e.key} 读不到了（改名或挪走，账要一起改）');
    }
    final strays = <String, List<String>>{};
    for (final e in code.entries) {
      final found = sectionHeaderCopies(e.value);
      if (found.isNotEmpty) strays[e.key] = found;
    }
    expect(
      strays,
      isEmpty,
      reason:
          '$strays —— 有页的组标题 helper 没走公共件 ⇒ 画法回到"页自己搭一份"，'
          '字号与字重会各漂各的（w500 对 w600、12px 对 13px 就是这么活下来的）。'
          '真要留一枚不合的，就把它登记成具名例外并写明代价，别让它成为第四把尺',
    );
  });

  test('② 尺认得合成样本（防① 退化成"一枚都认不出＝恒绿"）', () {
    const blockCopy = '''
class _State extends State {
  Widget _buildSectionHeader(String title, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Text(
        title,
        style: TextStyle(fontSize: 13, color: AppColors.secondaryLabel(context)),
      ),
    );
  }

  Widget _buildGroup(List<Widget> children) => Column(children: children);
}
''';
    expect(sectionHeaderCopies(blockCopy), [
      '_buildSectionHeader',
    ], reason: '自搭壳的样本都抓不到 ⇒ ① 那条绿只说明"正则没匹配到任何东西"');

    const expressionCopy = '''
class _State extends State {
  Widget _sectionHeader(String text, BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text),
  );

  Widget _modeTile(String keyName) => Text(keyName);
}
''';
    expect(sectionHeaderCopies(expressionCopy), [
      '_sectionHeader',
    ], reason: '表达式体的 helper 漏网 ⇒ 尺只认块状体，下一把抄本换个写法就过去了');

    const compliant = '''
class _State extends State {
  Widget _buildSectionHeader(String title, {required String keyName}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: FnthinkRowLabel(keyName: keyName, label: title),
    );
  }

  Widget _buildGroup(List<Widget> children) => Column(children: children);
}
''';
    expect(
      sectionHeaderCopies(compliant),
      isEmpty,
      reason: '合规写法被判成抄本 ⇒ 这条守卫红得没有信息量，下次没人再读它',
    );
  });

  test('③ 各页的渲染点数与台账相等（这本账不许为空）', () {
    final code = pageCode();
    expect(usage, isNotEmpty);
    for (final e in usage.entries) {
      final src = code[e.key];
      expect(src, isNotNull, reason: '${e.key} 读不到了（改名或挪走，账要一起改）');
      final helper = delegated[e.key];
      final drawn = helper == null
          ? RegExp(r'FnthinkRowLabel\(').allMatches(src!).length
          : renderPoints(src!, helper);
      expect(
        drawn,
        e.value,
        reason:
            '${e.key} 画了 $drawn 枚组标题、台账记 ${e.value} 枚 —— '
            '多了说明新增长标题（要连同账一起改，说明这是有意加的），'
            '少了说明调用点被搬走或换成了自搭壳',
      );
    }
  });

  test('④ 十二枚组标题 keyName 一个都不重（共用 key，点到的就不是那一枚）', () {
    final code = pageCode();
    final seen = <String, String>{};
    final dups = <String, List<String>>{};
    for (final rel in [
      'pages/more_page.dart',
      'pages/permission_settings_page.dart',
      'pages/update_server_page.dart',
    ]) {
      final src = code[rel];
      expect(src, isNotNull, reason: '$rel 读不到了');
      for (final m in RegExp(
        r"keyName:\s*'([a-z][a-z0-9-]*section[a-z0-9-]*)'",
      ).allMatches(src!)) {
        final k = m.group(1)!;
        if (seen.containsKey(k)) dups[k] = [seen[k]!, rel];
        seen[k] = rel;
      }
    }
    expect(
      seen.length,
      12,
      reason:
          '组标题 key 读到 ${seen.length} 枚、应有 12 枚（更多页 5 + 权限页 5 + 更新服务器页 2）—— '
          '少一枚就是有一处调用点没传 keyName，公共件就画不出可定位的那一格',
    );
    expect(dups, isEmpty, reason: '重复的组标题 key：$dups');
  });

  // ── ⑤⑥⑦⑧：闸门那一侧的读数（T146 片4 现读引出来的，不是新立的功能）───────────
  // 片4 把这三段组标题的 key 从外层 `Padding` **挪到画出来的那一格**上（字符串逐字没动：
  // `history-all-header-<kind>`）。页面级那侧我当时就改了取法（两种宿主都读），
  // 但**闸门那一侧没跟着查** —— 而 `release_walkthrough_test.dart` 里那句"段标题不许有数字"
  // 用的正是"往下找一个 Text 读文字"这一把尺：key 一旦落在 `Text` 自己身上，
  // `find.descendant` 的集合就是**空的**，拼出来恒为 `''`，`RegExp(r'\d')` 对空串恒不匹配 ⇒
  // **闸门在设备上照样报绿，量的是谁也没做的一件事**（本仓记过多次的那类假绿）。
  // 这四条把这件事钉成静态判据：闸门不跑也拦得住，且不必等下一次整闸才发现。
  final gatePath = '$root/integration_test/release_walkthrough_test.dart';

  /// 找到 `idx` 所在的那个**顶层成员**（闸门那份文件里顶层函数一律从第 0 列开始）。
  String? enclosingTopLevelMember(String src, int idx) {
    int? start;
    int? end;
    for (final m in RegExp(r'^\S.*$', multiLine: true).allMatches(src)) {
      if (m.start <= idx) {
        start = m.start;
      } else {
        end = m.start;
        break;
      }
    }
    if (start == null) return null;
    return src.substring(start, end ?? src.length);
  }

  /// 尺的本体：闸门里"按 key 定位那一格、再往下找 `Text` 读文字"的那些取法。
  List<RegExpMatch> keyedTextReads(String gate) => RegExp(
    r'find\.descendant\(\s*of: (\w+),\s*matching: find\.byType\(Text\)\s*\)',
  ).allMatches(gate).toList();

  /// 那把尺所在的顶层成员。**只有恰好一处取法才认得出来**：
  ///   0 处 ⇒ 尺不存在（这本账会空转）；2 处以上 ⇒ 尺之外有人 inline 了一份读数。
  String? gateReaderBody(String gate) {
    final reads = keyedTextReads(gate);
    if (reads.length != 1) return null;
    return enclosingTopLevelMember(gate, reads.single.start);
  }

  String? gateReaderName(String gate) {
    final body = gateReaderBody(gate);
    if (body == null) return null;
    return RegExp(
      r'^String (\w+)\(',
      multiLine: true,
    ).firstMatch(body)?.group(1);
  }

  /// **判据一：两把宿主都要读。** 那一枚 `ValueKey` 可能挂在容器上，也可能挂在画出来的
  /// `Text` 自己身上（片4 之后就是后者），所以唯一那把尺必须**同时**直接读那一格自己。
  /// 只往下 `find.descendant` 读 ⇒ key 落在 `Text` 上时读数恒为空串，而"不许有数字"对空串恒真。
  List<String> hostProblems(String gate) {
    final reads = keyedTextReads(gate);
    if (reads.isEmpty) {
      return const ['闸门里一处"往下找 Text 读文字"都没有 ⇒ 尺没认到东西，这本账是空转的'];
    }
    if (reads.length > 1) {
      return [
        '闸门里有 ${reads.length} 处"往下找 Text"的取法 ⇒ 那把尺之外还有人 inline 了一份'
            '只认一种宿主的读数（key 落在 Text 上时它恒得空串）',
      ];
    }
    final name = gateReaderName(gate);
    if (name == null) {
      return const ['那一处取法所在的成员里认不出函数名（它得是顶层 `String xxx(` 那一族）'];
    }
    if (!RegExp('widgetList<Text>\\(\\s*\\w+\\s*\\)')
        .hasMatch(gateReaderBody(gate)!)) {
      return [
        '$name 只往下读、没直接读那一格自己 ⇒ key 挪到 `Text` 上之后恒得空串，'
            '闸门绿着量一件不存在的事',
      ];
    }
    return const [];
  }

  /// **判据二：读到空要喊。** 每一处拿这把尺的读数做判据之前，必须有一次 `isNotEmpty`；
  /// 否则空串（读不到那一格）与"读到了、里面没有数字"在闸门里是同一个绿。
  List<String> floorProblems(String gate) {
    final name = gateReaderName(gate);
    if (name == null) {
      return const ['认不出那把尺 ⇒ 调用点无从核对（"没量到"不许当成通过）'];
    }
    final calls = RegExp('final (\\w+) = $name\\(tester,')
        .allMatches(gate)
        .toList();
    if (calls.isEmpty) {
      return ['$name 定义了却没有一个调用点 ⇒ 闸门里那段读数不再走它（尺与用的人分了家）'];
    }
    final problems = <String>[];
    for (final u in calls) {
      final v = u.group(1)!;
      if (!RegExp('expect\\(\\s*$v,\\s*isNotEmpty').hasMatch(gate)) {
        problems.add('$name 的读数 $v 没有一次 isNotEmpty 断言 ⇒ 空串照样通过判据');
      }
    }
    return problems;
  }

  test('⑤ 闸门那把尺两把宿主都读（key 换了宿主也不能读成空）', () {
    final f = File(gatePath);
    expect(f.existsSync(), isTrue, reason: '$gatePath 读不到 ⇒ 下面几条会空转（改名要一起改）');
    expect(
      hostProblems(stripComments(f.readAsStringSync())),
      isEmpty,
      reason: '闸门读段标题的取法只认一种宿主 ⇒ 它在设备上会对空串报绿',
    );
  });

  test('⑥ 闸门那把尺的每个调用点都断了非空（不许对空串恒真）', () {
    final f = File(gatePath);
    expect(
      floorProblems(stripComments(f.readAsStringSync())),
      isEmpty,
      reason: '读数没断非空 ⇒ "段标题不许有数字"这一判今天量的是空串',
    );
  });

  test('⑦ 尺认得合成样本（防⑤⑥ 退化成"一处都没认出来＝恒绿"）', () {
    // 坏法一：inline 一份只往下读的取法（正是片4 之后闸门里那一幕）。
    const oneHostOnly = '''
void main() {
  testWidgets('x', (tester) async {
    final header = find.byKey(ValueKey('history-all-header-inbox'));
    final title = tester
        .widgetList<Text>(find.descendant(of: header, matching: find.byType(Text)))
        .map((w) => w.data ?? '')
        .join();
    expect(RegExp(r'\\d').hasMatch(title), isFalse);
  });
}
''';
    expect(
      hostProblems(oneHostOnly),
      isNotEmpty,
      reason: '闸门里 inline 一份"只往下读"的取法都抓不到 ⇒ ⑤ 那条绿得没有依据',
    );

    // 坏法二：尺本身合规，但调用点没断非空 ⇒ 空串恒过。
    const noFloor = '''
String _keyedTitle(WidgetTester t, Finder keyed) {
  final onCell = t.widgetList<Text>(keyed).map((w) => w.data ?? '').join();
  final underCell = t
      .widgetList<Text>(find.descendant(of: keyed, matching: find.byType(Text)))
      .map((w) => w.data ?? '')
      .join();
  return onCell + underCell;
}

void main() {
  testWidgets('x', (tester) async {
    final header = find.byKey(ValueKey('history-all-header-inbox'));
    final title = _keyedTitle(tester, header);
    expect(RegExp(r'\\d').hasMatch(title), isFalse);
  });
}
''';
    expect(
      floorProblems(noFloor),
      isNotEmpty,
      reason: '读数没断非空 ⇒ "不许有数字"对空串恒真，这一维必须红',
    );
    expect(
      hostProblems(noFloor),
      isEmpty,
      reason: '那把尺本身是合规的 ⇒ ⑤ 不许跟着红（两维各一条判据，混起来就说不清是哪件事坏了）',
    );

    // 坏法三：整份闸门里根本没有"往下找 Text"这回事 —— 尺一枚都认不出来时不许当通过。
    expect(
      hostProblems(
        'void main() {\n  testWidgets(\'x\', (tester) async {});\n}\n',
      ),
      isNotEmpty,
      reason: '尺认不出任何取法 ⇒ 这本账空转，必须红',
    );

    // 合规：尺只有一把、两把宿主都读、调用点断了非空 ⇒ 两维都不许红。
    const compliant = '''
String _keyedTitle(WidgetTester t, Finder keyed) {
  final onCell = t.widgetList<Text>(keyed).map((w) => w.data ?? '').join();
  final underCell = t
      .widgetList<Text>(find.descendant(of: keyed, matching: find.byType(Text)))
      .map((w) => w.data ?? '')
      .join();
  return onCell + underCell;
}

void main() {
  testWidgets('x', (tester) async {
    final header = find.byKey(ValueKey('history-all-header-inbox'));
    final title = _keyedTitle(tester, header);
    expect(title, isNotEmpty);
    expect(RegExp(r'\\d').hasMatch(title), isFalse);
  });
}
''';
    expect(
      hostProblems(compliant),
      isEmpty,
      reason: '合规写法被判成问题 ⇒ ⑤ 红得没有信息量（本仓不许这种守卫）',
    );
    expect(floorProblems(compliant), isEmpty, reason: '合规写法被判成问题 ⇒ ⑥ 红得没有信息量');
  });

  test('⑧ 闸门那一段钉的是件不是 key（换自搭壳也该红）', () {
    final f = File(gatePath);
    final gate = stripComments(f.readAsStringSync());
    expect(
      RegExp("ValueKey\\('history-all-header-\\\$kind'\\)").hasMatch(gate),
      isTrue,
      reason: '闸门不再按那三段的 key 定位 ⇒ 片4 挪了宿主这件事没人复验了（要一起改这本账）',
    );
    expect(
      RegExp(r'find\.byType\(FnthinkRowLabel\)').hasMatch(gate),
      isTrue,
      reason:
          '闸门只断"那一格还在"就够了吗 —— 不够：key 字符串逐字没动但换成页面自搭的壳，'
          '字号与字重就各漂各的。这一族在设备上也要钉件。',
    );
  });
}
