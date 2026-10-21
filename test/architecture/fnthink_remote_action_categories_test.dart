import 'dart:io';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/services/fnthink_grant_items.dart';
import 'package:notice_transmit/services/fnthink_remote_action_categories.dart';

import '../support/source_guards.dart';

/// T146 片1（维护者 2026-10-12 裁定 5：命令清单「当前过于杂乱」）。
///
/// 分组维落在设备侧一张映射表（已拍板＝设备侧，不动契约），所以"这张表漂移了没人知道"
/// 就是本文件的职责：
/// ① 双向差集 —— 契约加一项而这里没跟上 ⇒ 那一枚会被塞进「未分类」，
///    界面上看着像"分类就这么定的"，而真话是这张表落后了。这一条要红。
/// ② 反向也要红 —— 这里留一项契约已删的，等于给一个不存在的动作配标题。
/// ③ 组标题不许在页面里长成字面量（同一件事两处各写一句，是本仓治过很多轮的病）。
/// ④ chip 的 key 仍是契约动作名 —— 那六处"按 key 点"的用例钉着行为，
///    这里只钉"分组之后 key 形状没被改"这一条正面断言。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final contract = FnthinkContract.readFile();
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  final vocabulary = <String>{
    ...contract.l2Actions,
    ...contract.l3Settings.keys,
  };
  String page() => stripComments(
    File('${projectRoot()}/lib/pages/fnthink_send_page.dart')
        .readAsStringSync(),
  );
  // 同意屏那一格（名单页）：T146 片2 的最后一格 —— 18 行一维平铺到这一页才收口。
  String peersPage() => stripComments(
    File('${projectRoot()}/lib/pages/fnthink_peers_page.dart')
        .readAsStringSync(),
  );
  String table() => stripComments(
    File('${projectRoot()}/lib/services/fnthink_remote_action_categories.dart')
        .readAsStringSync(),
  );

  group('这张表与契约的动作集双向差集', () {
    test('契约里有、表里没配 ⇒ 红（漂移会被塞进未分类，看着像故意的）', () {
      final missing =
          vocabulary
              .where((a) => !kFnthinkRemoteActionCategories.containsKey(a))
              .toList()
            ..sort();
      expect(missing, isEmpty, reason: '这些动作没归类：$missing —— 给它们补一行归组，或从契约里删掉');
    });

    test('表里有、契约已删 ⇒ 红（这张表开始自己长词）', () {
      final stale =
          kFnthinkRemoteActionCategories.keys
              .where((a) => !vocabulary.contains(a))
              .toList()
            ..sort();
      expect(stale, isEmpty, reason: '线上没有这些动作：$stale');
    });

    test('每一组都有人用，每一个用到的组都有标题', () {
      final used = kFnthinkRemoteActionCategories.values.toSet();
      final titled = kFnthinkRemoteCategoryTitles.keys.toSet()..remove('');
      expect(
        used.difference(titled),
        isEmpty,
        reason: '有条目归到某一组但那组没标题 ⇒ 页面上那一栏只剩空标题',
      );
      expect(
        titled.difference(used),
        isEmpty,
        reason: '配了标题却一组都没有：要么删掉，要么这一组真的用得上',
      );
    });
  });

  group('分组这件事本身', () {
    test('L1 那一档（18 枚平铺）分成几栏，栏栏非空、一项不丢', () {
      final actions = <String>[
        ...contract.l2Actions,
        ...contract.l3Settings.keys,
      ];
      final groups = fnthinkRemoteActionGroups(actions);
      expect(groups, hasLength(kFnthinkRemoteCategoryOrder.length));
      for (final g in groups) {
        expect(g.actions, isNotEmpty, reason: '空栏不该出现：${g.slug}');
        expect(fnthinkRemoteCategoryTitle(l10n, g.slug), isNotEmpty);
      }
      expect(
        groups.expand((g) => g.actions).toSet(),
        actions.toSet(),
        reason: '分了组却少一项 = 清单被裁了，那不是分类',
      );
    });

    test('未分类排最后（漂移看得见，但不挡正常那一串）', () {
      final groups = fnthinkRemoteActionGroups([
        'listener:start',
        'brand-new:thing',
      ]);
      expect(groups.first.slug, 'listening');
      expect(groups.last.slug, '');
      expect(
        fnthinkRemoteCategoryTitle(l10n, ''),
        isNotEmpty,
        reason: '未分类那一栏也得有名字，不能是一句空标题',
      );
    });

    test('行的那一维与动作的那一维同序同数（同意屏与发送页看到的是同一把尺）', () {
      final rows = pairItemRows(contract);
      final groups = fnthinkRemoteItemGroups(rows, (row) => row.base);
      expect(
        groups.map((g) => g.slug).toList(),
        fnthinkRemoteActionGroups([...rows.map((row) => row.base)])
            .map((g) => g.slug)
            .toList(),
        reason:
            '两张清单页的栏次必须一致。不一致的表现是"同一台设备在两页上把同一件事'
            '放在不同位置"，用户来回找 —— 这正是裁定 5 说的"过于杂乱"里没被治掉的那一半',
      );
      final groupedBases = groups
          .expand((g) => g.items)
          .map((row) => row.base)
          .toSet();
      expect(
        groupedBases,
        rows.map((row) => row.base).toSet(),
        reason: '分栏只改画在哪一栏底下；项少了或多了都不是分类',
      );
      expect(
        groups.expand((g) => g.items).length,
        rows.length,
        reason: '同一项被画进两栏 ⇒ 勾一次等于勾两次，而屏幕上看不出来',
      );
      final allBases = rows.map((row) => row.base).toList();
      for (final group in groups) {
        final inGroup = group.items.map((row) => row.base).toSet();
        expect(
          group.items.map((row) => row.base).toList(),
          allBases.where(inGroup.contains).toList(),
          reason:
              '${group.slug} 那一栏内部被重排了 —— 栏内序的作者只有一个（`pairItemRows` '
              '给出来的契约登记序）。再排一次就长出第二把序（T146 格④）',
        );
      }
    });

    test('页面画的是**整组**的动作（分栏不许变成截断）', () {
      expect(
        page(),
        contains('for (final action in group.actions)'),
        reason:
            '渲染吃的是这一组的全部动作。哪里出现 `take(...)`／`skip(...)`，'
            '清单就在那里少画几枚 —— 而"分组更清爽"看起来正好把它盖住了',
      );
    });

    test('chip 的 key 仍是契约动作名（分组不许改定位串）', () {
      expect(
        page(),
        contains(r"keyName: 'remote-send-action-$action'"),
        reason: '按 key 点 chip 的用例有六处，key 形状一改就全成"页面坏了"的假红',
      );
    });

    test('组标题不在页面里写成字面量，且页面真的走那张表', () {
      final src = page();
      for (final literal in const ['监听与转发', '通道与状态', '查找内容', '设备动作', '系统与权限']) {
        expect(
          src,
          isNot(contains("'$literal'")),
          reason:
              '标题从 ARB 与这张表取；页面里再写一遍就是第二份'
              '可以朝不同方向写错的实现（$literal）',
        );
      }
      expect(src, contains('fnthinkRemoteCategoryTitle('));
      expect(src, contains('fnthinkRemoteActionGroups('));
    });
  });

  group('两张清单页同形（T146 片2 的最后一格：同意屏那 18 行也分栏）', () {
    test('同意屏那一格吃的是那张表，不自己归组也不自己排第二把序', () {
      final src = peersPage();
      expect(
        src,
        contains('fnthinkRemoteItemGroups('),
        reason:
            '行的归组走表的作者。页面自己 `groupBy`／自己写 map ⇒ 两张页会对同一个动作'
            '给出两个组名，而用户是连着看这两页的',
      );
      expect(
        src,
        contains('fnthinkRemoteCategoryTitle('),
        reason: '标题从那张表取；自己拼一句就是第三套人话（差异③ 那个形状）',
      );
    });

    test('分栏不许变成截断：两张页画的都是**整组**的行', () {
      expect(
        page(),
        contains('for (final action in group.actions)'),
        reason: '发送页那一档渲染吃整组动作；出现 take/skip 就是"分组更清爽"盖住了少画几枚',
      );
      expect(
        peersPage(),
        contains('for (final row in group.items)'),
        reason:
            '同意屏那张表少画一项 ＝ 替用户少给一项授权（`fnthink_settings_page_test.dart` '
            '里"画的是契约派生的全量"那条钉的就是这件事，分栏之后仍要成立）',
      );
    });

    test('两页的组标题走同一枚件', () {
      for (final src in [page(), peersPage()]) {
        expect(
          src,
          contains('FnthinkRowLabel('),
          reason:
              '「一组的名目」这件东西全仓只该有一种画法（`FnthinkRowLabel`）。'
              '发送页此前用 `FnthinkNote`（12px 正文小字）当标题，两张清单页就读出两种层级',
        );
      }
    });

    test('两页都不把组名写成页内字面量', () {
      for (final src in [page(), peersPage()]) {
        for (final literal in const [
          '监听与转发',
          '通道与状态',
          '查找内容',
          '设备动作',
          '系统与权限',
        ]) {
          expect(
            src,
            isNot(contains("'$literal'")),
            reason: '标题从 ARB 与那张表取；页面里再写一遍就是可以朝不同方向写错的第二份（$literal）',
          );
        }
      }
    });

    test('归组与排序在这张表的文件里只有一份实现', () {
      final src = table();
      final copies = RegExp(RegExp.escape('kFnthinkRemoteCategoryOrder.where('))
          .allMatches(src)
          .length;
      expect(
        copies,
        1,
        reason:
            '把那份"排序 + 未分类垫底"抄进第二个函数 ⇒ 两张清单页会各有自己的序，'
            '而"同一份清单在两张页上顺序不一样"在界面上读起来像"那页少了几项"（T146 格④）',
      );
      // 一处定义 + 两个公开入口各一次调用。数目漂了就说明某一入口不再走它
      // （判数目不判措辞：显式写类型参数 `_byCategoryInOrder<String>(...)` 不算漂移）。
      final uses = RegExp(RegExp.escape('_byCategoryInOrder'))
          .allMatches(src)
          .length;
      expect(uses, 3, reason: '两个入口都得走那一份实现；少一次就是有人把分堆又抄了一遍');
    });

    test('分栏一个字都没动定位串', () {
      expect(
        peersPage(),
        contains(r"'fnthink-pair-item-${request.requestId}-${row.base}'"),
        reason:
            '勾逐项的 key 仍由契约动作名拼出 —— 那批"按 key 勾／断言"的用例钉的是行为，'
            'key 形状一改就全红成"页面坏了"，看不出是分类',
      );
    });
  });
}
