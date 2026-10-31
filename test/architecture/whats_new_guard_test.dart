import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// T203 的形状守卫：首启那句「这次更新带来了什么」，**判据与排版都只有一份作者**。
///
/// 这一族最容易长的回来的三种形状，编译器都看不见：
///  ① 又开一个写入点（侧载路径、下载完成处各写一份 ⇒ 待读日志与实际装上的版本对不上）；
///  ② 界面自己拼一份"摘要＋折叠"（改了公共件的折叠形状，那枚弹层不会跟着变）；
///  ③ 界面自己按语言挑中英文（`pickUpdateChangelog` 之外长出第二份本地化裁决）。
void main() {
  final manager = File('lib/update_manager.dart').readAsStringSync();
  final actions = File('lib/pages/main_page_actions.dart').readAsStringSync();
  final zhArb = File('lib/l10n/arb/app_zh.arb').readAsStringSync();
  final enArb = File('lib/l10n/arb/app_en.arb').readAsStringSync();

  String stripComments(String src) =>
      src.split('\n').map((l) => l.split('//').first).join('\n');

  final managerSrc = stripComments(manager);
  final actionsSrc = stripComments(actions);

  /// lib/ 里某个片段的**总出现次数**（剥注释之后数，定义与调用都算进去）。
  int countInLib(String needle) {
    var total = 0;
    for (final f
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      total += stripComments(f.readAsStringSync()).split(needle).length - 1;
    }
    return total;
  }

  test('① 待读日志的写入点只有一处，且在安装入口之内、真正发起安装之前', () {
    expect(
      managerSrc.contains('Future<bool> stageWhatsNewChangelog('),
      isTrue,
      reason: '写入点没了？那这一整条都在测空气',
    );
    expect(
      countInLib('stageWhatsNewChangelog('),
      2,
      reason:
          '定义 1 次之外只许有 1 次调用；多一处就是第二个写入点 '
          '（待读日志迟早与实际装上的版本对不上）',
    );
    expect(
      countInLib('await stageWhatsNewChangelog('),
      1,
      reason: '调用点必须正好一处，且只能在安装那一发里',
    );

    final entry = managerSrc.indexOf('Future<bool> installApk(');
    final call = managerSrc.indexOf('await stageWhatsNewChangelog(');
    expect(entry, greaterThan(-1));
    expect(call > entry, isTrue, reason: '落盘没发生在安装入口之内 ⇒ 首启永远读不到待读日志');
    expect(
      managerSrc.substring(entry, call).contains('VersionCheckResult? update'),
      isTrue,
      reason: 'installApk 的参数面没了这一版（update）⇒ 侧载与在线升级分不开，写不写全凭猜',
    );
    expect(
      managerSrc.indexOf('return', entry) >= call,
      isTrue,
      reason: 'installApk 里有支路在落盘之前 return ⇒ 那一发升级就没了待读日志',
    );
    expect(
      call < managerSrc.indexOf('OpenFilex.open(', entry),
      isTrue,
      reason: '落盘要发生在真正发起安装之前：此刻本机装的还是旧版本，major/minor 那一判才判得准',
    );
  });

  test('② 弹层用的是同一份排版作者（不自己摘要、不自己折叠）', () {
    expect(
      actionsSrc.contains('UpdateChangelogBlock('),
      isTrue,
      reason: '首启那一枚没接公共件 ⇒ 摘要条数与折叠形状又变成两份',
    );
    for (final banned in [
      'updateChangelogSummary(',
      'updateChangelogHasMore(',
      'normalizeUpdateChangelog(',
    ]) {
      expect(
        actionsSrc,
        isNot(contains(banned)),
        reason: '$banned 在界面里出现 ⇒ 日志那半份长出第二个作者',
      );
    }
  });

  test('③ 语言裁决与"大版本"口径都不在界面里重写', () {
    for (final banned in [
      'pickUpdateChangelog(',
      'isMajorMinorUpgrade(',
      'parseAppVersionHead(',
      'pickWhatsNewChangelog(',
    ]) {
      expect(
        actionsSrc,
        isNot(contains(banned)),
        reason: '$banned 在界面里出现 ⇒ 判据从数据层搬到了页面，纯函数用例就管不到屏上那句话了',
      );
    }
    expect(actionsSrc, contains('readWhatsNewChangelog('));
    expect(actionsSrc, contains('markWhatsNewShown('));
  });

  test('④ 弹层走既有装配点，不自己搭对话框', () {
    expect(
      actionsSrc.contains('showExplainer('),
      isTrue,
      reason: 'T90 片26 那枚「长文说明＋一颗知道了」就是这一格该有的形状',
    );
    for (final banned in [
      'CupertinoAlertDialog(',
      'showDialog(',
      'AlertDialog(',
    ]) {
      expect(
        actionsSrc,
        isNot(contains(banned)),
        reason: '$banned ⇒ 又自搭一枚弹层（T90 那本台账只许变薄）',
      );
    }
  });

  test('⑤ 四枚键各只有一处字面量，且名字与值都对得上（改了值不会静默丢读数）', () {
    const expected = {
      'kWhatsNewVersionKey': 'whats_new_version',
      'kWhatsNewZhKey': 'whats_new_changelog_zh',
      'kWhatsNewEnKey': 'whats_new_changelog_en',
      'kWhatsNewShownKey': 'whats_new_shown_version',
    };
    final allLib = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => stripComments(f.readAsStringSync()))
        .join('\n');
    for (final entry in expected.entries) {
      expect(
        managerSrc.contains("const String ${entry.key} = '${entry.value}';"),
        isTrue,
        reason: '${entry.key} 不再是 ${entry.value} ⇒ 装完之后读回来的是空',
      );
      expect(
        allLib.split(entry.value).length - 1,
        1,
        reason: '${entry.value} 的字面量在 lib/ 里出现不止一次 ⇒ 键名有了第二份作者',
      );
      expect(
        countInLib(entry.key),
        greaterThan(1),
        reason: '${entry.key} 只出现在声明处 ⇒ 读写两边都没用它（多半是又抄了一遍字面量）',
      );
    }
  });

  test('⑥ "弹过"记的是版本号而不是布尔（每个大版本都还能再弹一次）', () {
    expect(
      managerSrc.contains('setString(kWhatsNewShownKey'),
      isTrue,
      reason: '记成布尔的话，这辈子只提醒一次 —— 与主备引导那枚同一条纪律就断了',
    );
    expect(managerSrc, isNot(contains('setBool(kWhatsNewShownKey')));
  });

  test('⑦ 标题在中英两份词条里都在', () {
    for (final arb in [zhArb, enArb]) {
      expect(
        arb.contains('"whatsNewTitle"'),
        isTrue,
        reason: '缺一份就是另一种语言的界面回落到中文（或反之）',
      );
    }
  });
}
