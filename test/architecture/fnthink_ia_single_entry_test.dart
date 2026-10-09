import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T107：幻念推送那一族**只长一棵树**（形状守卫）。
///
/// 判据不打在"这一行画得好不好"上，打在**同一张页有没有两个入口**上：
/// 两条路进同一页 ⇒ 改了一处会忘另一处，而"从哪进决定看得见什么"正是 #271 那条
/// 装配点守卫反对的事。旧的两条路径（通道列表页右上角那枚齿轮、设置页里那行「接入端点」）
/// 是**真删**的，所以这里断的是反面 —— 反面断言必须配一条"页面本身还在"的正向自证，
/// 否则"把整页删掉"也能让它变绿（本仓记过这一类假绿）。
void main() {
  final root = projectRoot();
  final prefix = '$root${Platform.pathSeparator}';

  String rel(String path) =>
      path.substring(prefix.length).replaceAll('\\', '/');
  String read(String relative) =>
      stripComments(File('$root/$relative').readAsStringSync());

  final codeByPath = <String, String>{
    for (final f
        in Directory('$root/lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')))
      rel(f.path): stripComments(f.readAsStringSync()),
  };

  /// 剥注释后，`lib/` 里含 [needle] 的文件（相对路径，已排序）。
  List<String> hitting(String needle) =>
      codeByPath.entries
          .where((e) => e.value.contains(needle))
          .map((e) => e.key)
          .toList()
        ..sort();

  group('T107：幻念推送的入口只有一处', () {
    // 尺自己先自证：扫描必须是真扫到了东西，"只有一处"才有意义。
    test('尺没空转：lib 扫得到文件，且认得一处已知存在的装配点', () {
      expect(
        codeByPath.length,
        greaterThan(100),
        reason: '只扫到 ${codeByPath.length} 个文件 ⇒ 目录口径漂了，下面的"恰好一处"全是摆设',
      );
      // 通道列表页的两个装配点（更多页那一支 + 通知引擎那一行）是既成事实，用它验提取能命中。
      expect(
        hitting('page: FnthinkChannelListPage('),
        const <String>['lib/pages/notification_engine_page.dart'],
        reason: '这一枚都提不到 ⇒ 提取按的是不存在的写法，"恰好一处"会永远绿',
      );
    });

    test('设置页与端点页各只有一个入口，都在通知引擎那一块里', () {
      for (final (page, ownFile, assembly) in const [
        (
          'FnthinkSettingsPage',
          'lib/pages/fnthink_settings_page.dart',
          'page: const FnthinkSettingsPage()',
        ),
        (
          'FnthinkEndpointPage',
          'lib/pages/fnthink_endpoint_page.dart',
          'page: const FnthinkEndpointPage()',
        ),
      ]) {
        // 自己的构造声明（`const X({super.key...})`）也算一处，所以期望集合是"本页 + hub"两文件，
        // 而**调用**那一处只许在 hub —— 断调用形状，不数出现次数（措辞与折行会变，形状不会）。
        expect(
          hitting('$page('),
          orderedEquals([ownFile, 'lib/pages/notification_engine_page.dart']),
          reason: '$page 的构造点集合变了 ⇒ 那一页又多了一个入口，或者页面被搬走了',
        );
        expect(
          read('lib/pages/notification_engine_page.dart'),
          contains(assembly),
          reason:
              '通知引擎那一行没有直接把 $page 作为目标 ⇒ "入口只有一处"这句没了落点，'
              '下一次就会有人再补一条捷径',
        );
      }
    });

    test('旧路径真删①：通道列表页不再挂通往设置页的齿轮', () {
      final list = read('lib/pages/fnthink_channel_list_page.dart');
      expect(
        list,
        isNot(contains("'fnthink-channel-settings'")),
        reason: '列表页右上角又长出齿轮 ⇒ 设置页回到两条路，T107 白做',
      );
      expect(
        list,
        isNot(contains("import 'fnthink_settings_page.dart'")),
        reason: '那一页现在连类型都不该认识它',
      );
      // 反向自证：删的是那一枚齿轮，不是整页 —— 标题与列表本身必须还在。
      // 没有这一条，"把这一页整个删掉"也能让上面两条 isNot 变绿（本仓记过这一类假绿）。
      expect(
        list,
        contains('l10n.fnthinkPushChannel'),
        reason: '页面没了 ⇒ 上面那两条 isNot 是"整页被删"造出来的假绿',
      );
    });

    test('旧路径真删②：设置页不再留通往端点页的那一行', () {
      final settings = read('lib/pages/fnthink_settings_page.dart');
      expect(
        settings,
        isNot(contains("'fnthink-endpoint-entry'")),
        reason: '设置页里又留一行通往端点页 ⇒ 同一张页两个入口，改一处忘一处',
      );
      expect(
        settings,
        isNot(contains("import 'fnthink_endpoint_page.dart'")),
        reason: '这一页不该还认识那张页：它只答"这台设备是谁、对着哪台服务器"',
      );
      // 反向自证：搬走的是那一行，不是这一页本身。
      expect(
        settings,
        contains("'fnthink-address-code'"),
        reason: '身份那一格没了 ⇒ 上面的 isNot 是删过头造出来的假绿',
      );
    });

    test('那一块卡片六行都在，且新增的两行各有自己的 key', () {
      final hub = read('lib/pages/notification_engine_page.dart');
      for (final key in const [
        'engine-fnthink-peers',
        'engine-fnthink-receive',
        'engine-fnthink-channels',
        'engine-fnthink-remote',
        'engine-fnthink-settings',
        'engine-fnthink-endpoint',
      ]) {
        expect(
          hub,
          contains("ValueKey('$key')"),
          reason: '$key 那一行没了 ⇒ 幻念那一族又缺一扇门（闸门按它走那一页）',
        );
      }
    });

    /// T117（维护者 2026-10-09 第 1 条）：这一组的先后**按 key 序列**断，不按中文措辞 ——
    /// 措辞漂了守卫就瞎了，而顺序是"哪一扇门先被看见"的实际形状。
    /// ⚠ 断的是**先后**不是行号：加一行注释、抽一个方法都不该让它红（那是钉抄本不是钉契约）。
    test('这一组的先后＝T117 拍的那条：接收→配对→通道→远程→端点→设置', () {
      final hub = read('lib/pages/notification_engine_page.dart');
      const wanted = [
        'engine-fnthink-receive',
        'engine-fnthink-peers',
        'engine-fnthink-channels',
        'engine-fnthink-remote',
        'engine-fnthink-endpoint',
        'engine-fnthink-settings',
      ];
      final at = <String, int>{
        for (final key in wanted) key: hub.indexOf("ValueKey('$key')"),
      };
      expect(
        at.values.every((i) => i >= 0),
        isTrue,
        reason:
            '少一行 ⇒ 顺序断言会退化成"排剩下的"，先要求六扇门都在：'
            '${at.entries.where((e) => e.value < 0).map((e) => e.key).toList()}',
      );
      final actual = at.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      expect(
        actual.map((e) => e.key).toList(),
        wanted,
        reason:
            '这一组的先后被改了。设置放最后（它是出口不是日常），'
            '接收放最前（开关在那一页里），配对紧随——它是收起来之后的第一步',
      );
    });

    test('两行的标题与目标页同源：都用那一张页自己的词条', () {
      // 「行标题」与「页标题」读同一枚 ARB 词条 —— 两边各写一份就是"改了行没改页"的源头
      // （T111 给「设备配对」立的同一条纪律，这里把它扩展到新增的两行）。
      final hub = read('lib/pages/notification_engine_page.dart');
      final settings = read('lib/pages/fnthink_settings_page.dart');
      final endpoint = read('lib/pages/fnthink_endpoint_page.dart');
      expect(
        hub,
        allOf(
          contains('title: l10n.fnthinkSettingsTitle'),
          contains('title: l10n.fnthinkEndpointTitle'),
        ),
        reason: '那一行换了词条 ⇒ 行与页各说各的名字，改名一次改不全',
      );
      expect(
        settings,
        contains('l10n.fnthinkSettingsTitle'),
        reason: '设置页不再画那枚标题 ⇒ 行与页的同源断了，两边可以各漂各的',
      );
      expect(
        endpoint,
        contains('title: Text(l10n.fnthinkEndpointTitle)'),
        reason: '端点页不再画那枚标题 ⇒ 同上',
      );
    });
  });
}
