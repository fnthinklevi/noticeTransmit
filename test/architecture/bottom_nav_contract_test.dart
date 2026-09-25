import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// T13：底部导航 = 首页 / 通知引擎 / 更多。
///
/// 这里守的不是"长什么样"，而是**改名会把发版闸门打空**这件事：
/// 阶段 6 的点击脚本按中文文案 `find.text('首页')` 找 tab，而文案住在 ARB 里。
/// 两者一旦分叉，闸门不会报错，只会"找不到就跳过"——一个永远绿但什么都不点的闸门
/// 比没有闸门更危险（㊻ 那轮就是这么被骗过一次的）。所以把
/// 「导航顺序 / ARB 里的实际文案 / 闸门脚本里写死的字面量」钉成同一条契约。
void main() {
  String source(String rel) => File(rel).readAsStringSync();

  String gateSource(String name) => source('integration_test/$name');

  Map<String, dynamic> arb(String locale) =>
      jsonDecode(source('lib/l10n/arb/app_$locale.arb'))
          as Map<String, dynamic>;

  /// 取 `start` 与其后第一个 `end` 之间的片段；任一找不到就返回 ''（让断言红，而不是抛）
  String sliceBetween(String src, String start, String end) {
    final from = src.indexOf(start);
    if (from < 0) return '';
    final head = src.substring(from + start.length);
    final to = head.indexOf(end);
    return to < 0 ? head : head.substring(0, to);
  }

  /// main_page.dart 里 destinations 列表的实际顺序（按 label 表达式出现次序取）
  List<String> navLabelKeys(String src) => RegExp(r'label: l10n\.(\w+)')
      .allMatches(sliceBetween(src, 'destinations: [', '],\n'))
      .map((m) => m.group(1)!)
      .toList();

  test('三个 tab 的顺序就是 首页 / 通知引擎 / 更多', () {
    final keys = navLabelKeys(source('lib/pages/main_page.dart'));
    expect(keys, [
      'tabHome',
      'tabNotificationEngine',
      'tabMore',
    ], reason: '顺序变了就要同步改闸门脚本与本页契约，不许只改一边');
  });

  test('旧 tab 键（通知/电量）已删除，不留死键', () {
    // 留着不会报错，但会让下一个改名的人以为"再挂一个键也行"。
    // 电量作为 tab 消失不等于电量功能消失：它搬进「通知引擎」tab（T15）。
    for (final locale in ['zh', 'en']) {
      final keys = arb(locale).keys.toList();
      expect(
        keys,
        isNot(contains('tabNotification')),
        reason: '$locale 残留 tabNotification',
      );
      expect(
        keys,
        isNot(contains('tabBattery')),
        reason: '$locale 残留 tabBattery',
      );
    }
  });

  test('ARB 文案与闸门脚本里写死的字面量一一对应', () {
    final zh = arb('zh');
    final walkthrough = source(
      'integration_test/release_walkthrough_test.dart',
    );
    final smoke = source('integration_test/smoke_test.dart');

    // 每个 tab 的中文值必须以 find.text('<值>') 的形态出现在闸门里；
    // 通知引擎当前只在 walkthrough 被点（冒烟不覆盖它）。
    final tappedIn = {
      'tabHome': [walkthrough, smoke],
      'tabNotificationEngine': [walkthrough],
      'tabMore': [walkthrough, smoke],
    };
    for (final entry in tappedIn.entries) {
      final label = zh[entry.key] as String?;
      expect(label, isNotNull, reason: 'ARB 缺 ${entry.key}，闸门无从点起');
      for (final script in entry.value) {
        expect(
          script,
          contains("find.text('$label')"),
          reason:
              '${entry.key} 的文案是「$label」，但闸门脚本里没有对应的 find.text '
              '⇒ 改名只改了 UI，闸门从此点不到、却仍然全绿',
        );
      }
    }
  });

  test('每个被点的 tab 都存在"限定 NavigationBar"的写法', () {
    // 比对前折叠空白：格式化器会把 finder 折行或并成一行，按字面多行匹配会静默失效。
    final files = {
      'walkthrough': gateSource('release_walkthrough_test.dart'),
      'smoke': gateSource('smoke_test.dart'),
    };
    final tappedIn = {
      'tabHome': ['walkthrough', 'smoke'],
      'tabNotificationEngine': ['walkthrough'],
      'tabMore': ['walkthrough', 'smoke'],
    };
    final zh = arb('zh');
    tappedIn.forEach((key, names) {
      final label = zh[key]! as String;
      for (final name in names) {
        final flat = files[name]!.replaceAll(RegExp(r'\s+'), ' ');
        expect(
          flat,
          contains(
            "of: find.byType(NavigationBar), matching: find.text('$label')",
          ),
          reason: '$name 点「$label」tab 没有把 finder 限定在 NavigationBar 内',
        );
      }
    });
  });

  test('不许出现"裸点 tab"（上面那条只证明"某处有限定写法"，挡不住再裸点一处）', () {
    // 反证实测：把 5.9 的限定写法退回裸 find.text('首页')，上一条仍然绿 —— 因为
    // 6 节还有一处限定的首页点法。IndexedStack 让所有 tab 的文案常驻树上，裸点会
    // 落到不响应的那个元素上，红在下一句、排查方向被带偏，所以必须反向钉死。
    final labels = [
      arb('zh')['tabHome']! as String,
      arb('zh')['tabNotificationEngine']! as String,
      arb('zh')['tabMore']! as String,
    ];
    for (final name in ['release_walkthrough_test.dart', 'smoke_test.dart']) {
      final flat = gateSource(name).replaceAll(RegExp(r'\s+'), ' ');
      for (final label in labels) {
        final bare = RegExp(
          "(?:_tap\\(tester, |tester\\.tap\\()find\\.text\\('$label'\\)",
        );
        expect(
          bare.hasMatch(flat),
          isFalse,
          reason:
              '$name 里有裸点「$label」tab 的写法 ⇒ 必须 find.descendant 限定在 NavigationBar 内',
        );
      }
    }
  });
}
