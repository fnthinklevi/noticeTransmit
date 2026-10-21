import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T140 层4 引：权限页 L3 那一格读的是「此刻这台的授权」，那就必须**在用户改完之后重取一次**。
///
/// 为什么钉源码而不是只靠行为用例：这一族坏了不崩、也不报错，表现是**同一页上两行自相矛盾**
/// （B1 那一格页面自读、跟着回前台改口；L3 那一格画的是进页那一刻注入的那份快照）。
/// 行为用例能钉住"回前台改口"这一支，但钉不住两件事：
///  - **下拉刷新那一条**（要 drag 才能触发，且它红的时候没人知道是"没刷这一格"还是"手势没成"）；
///  - **读法没有第二个作者**（页面一旦自己组装 `FnthinkL3GrantRow`，改契约词表时那一格静默漂移）。
void main() {
  final root = projectRoot();
  String read(String rel) =>
      stripComments(File('$root/$rel').readAsStringSync());

  final page = read('lib/pages/permission_settings_page.dart');
  final caller = read('lib/pages/main_page_actions.dart');

  test('注入的是「去取一次」这件事，不是取好的那一份', () {
    expect(
      page,
      contains('Future<List<FnthinkL3GrantRow>> Function()'),
      reason: '构造参数若是 List，页面画的就是进页那一刻的快照，回前台无从重算',
    );
    expect(
      RegExp(r'final\s+List<FnthinkL3GrantRow>\s+l3GrantRows\s*;')
          .hasMatch(page),
      isFalse,
      reason: '留一份注入的快照 = 长出第二个"此刻的读数"，两处迟早漂开',
    );
  });

  test('两个刷新点都必须重取那一格：回前台与下拉刷新', () {
    final resume = page.substring(page.indexOf('didChangeAppLifecycleState'));
    final resumeBody = resume.substring(0, resume.indexOf('\n  }'));
    expect(
      resumeBody.contains('_loadExactAlarmState()') &&
          resumeBody.contains('_loadL3GrantRows()'),
      isTrue,
      reason: '只刷新其中一份 ⇒ 一屏两句话：B1 说已授权、L3 那行还说没给',
    );

    expect(
      RegExp(r'onRefresh:\s*_refreshBoth').hasMatch(page),
      isTrue,
      reason: '下拉刷新若只转交外层那一次，刷新圈收下的是"这一格还是旧的"这句话',
    );
    final refresh = page.substring(page.indexOf('Future<void> _refreshBoth'));
    final refreshBody = refresh.substring(0, refresh.indexOf('\n  }'));
    expect(
      refreshBody.contains('widget.onRefresh()') &&
          refreshBody.contains('_loadL3GrantRows()'),
      isTrue,
      reason: '两件事必须同一刻做完再让刷新圈收下，否则"已刷新"是假的',
    );
  });

  test('读法与判态只有一个作者：页面不自己组装那几行', () {
    expect(
      RegExp(r'FnthinkL3GrantRow\s*\(').hasMatch(page),
      isFalse,
      reason: '页面自己造一行 = 第二份四态判据，改契约词表时那一格静默漂移',
    );
    expect(
      RegExp(r'collectL3GrantRows\s*\(').allMatches(page).length,
      0,
      reason: '组装那一步住在调用方（与"页面不自己去读"同一条纪律）',
    );
    expect(
      RegExp(r'collectL3GrantRows\s*\(').allMatches(caller).length,
      1,
      reason: '全仓唯一的组装处就是首页那一个装配点',
    );
  });
}
