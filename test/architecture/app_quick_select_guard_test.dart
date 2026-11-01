import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T209：应用快速选择目录只能有**一处定义**，三处页面都得读它。
///
/// 抽目录这件事真正会失败的方式不是"抽错"，而是"抽了之后又有人在自己页里抄一份"：
/// 那时三处会各自给出一组不同的"快速选择"，而没有任何用例会红——因为每页自己都"自洽"。
void main() {
  final root = projectRoot();
  String read(String rel) =>
      stripComments(File('$root/$rel').readAsStringSync());

  const authorRel = 'lib/services/app_quick_select.dart';
  const ruleRel = 'lib/pages/rule_edit_page.dart';
  const filterRel = 'lib/pages/app_filter_page.dart';
  const triggerRel = 'lib/pages/remote_trigger_filter_page.dart';

  test('目录只在唯一作者里定义：页面里不许再抄包名', () {
    final author = read(authorRel);
    for (final pkg in const [
      'com.tencent.mm',
      'com.android.mms',
      'com.android.dialer',
      'com.google.android.gm',
    ]) {
      expect(author, contains("'$pkg'"), reason: '目录作者里缺了 $pkg');
      for (final page in const [ruleRel, filterRel, triggerRel]) {
        expect(
          read(page),
          isNot(contains("'$pkg'")),
          reason: '$page 又抄了一份目录：三处会各自漂移',
        );
      }
    }
    // 旧私有常量的名字也不许复活。
    expect(read(ruleRel), isNot(contains('_kQuick')));
  });

  test('三处页面都读同一份判据', () {
    expect(
      read(ruleRel),
      contains('appQuickGroupOf('),
      reason: '规则编辑页应改为读公共分组判据',
    );
    for (final page in const [filterRel, triggerRel]) {
      final src = read(page);
      expect(src, contains('AppQuickSelectBar('), reason: '$page 没接快速选择那一排');
      expect(
        src,
        contains('appQuickGroupsOfInstalled('),
        reason: '$page 没读公共目录 → 它自己数了一份',
      );
      expect(src, contains('_toggleQuickGroup'), reason: '$page 缺"点一下整组"的落点');
    }
  });
}
