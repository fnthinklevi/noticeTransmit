import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// T47 守卫：收件保留策略的四个"不许再长第二份"。
/// ① 数值与档位只住 `FnthinkSettings`（界面与 prune 各读各的那一份）；
/// ② `pruneFnthinkInbox` 的读者只有收件服务（页面/别处不许直连）；
/// ③ 设置页那一格的形状（picker 用的是同一份档位表）；
/// ④ 每枚 prefs 键都得在备份那一格有着落（片2 撞出来的那条：新键写完忘了接备份，
///    表现是换机后一切正常、只有收件保留悄悄回到缺省）。
String read(String path) => File(path).readAsStringSync();

String strip(String code) => code
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final settings = strip(read('lib/services/fnthink_settings.dart'));
  final service = strip(read('lib/services/fnthink_inbox_service.dart'));
  final page = strip(read('lib/pages/fnthink_settings_page.dart'));
  final mainActions = strip(read('lib/pages/main_page_actions.dart'));
  final backup = strip(read('lib/services/fnthink_backup.dart'));

  test('档位/缺省/资源闸只住 settings 一处', () {
    expect(
      settings,
      contains('static const List<int> retentionChoices'),
      reason: '锚点：档位表不在 = 本守卫空转',
    );
    expect(
      settings,
      contains('static const int inboxMaxRows'),
      reason: '锚点：资源闸不在 = 本守卫空转',
    );
    // 界面只许引用，不许抄数字：四档与 20000 在设置页与主页动作里都是零命中。
    for (final where in [
      {'f': page},
      {'f': mainActions},
    ]) {
      final src = where['f'] == 'page' ? page : mainActions;
      expect(
        src,
        isNot(contains('[7, 30, 90, 365]')),
        reason: '档位表抄了一份 ⇒ 契约调档（本仓没有）之外的人为调档只改一半',
      );
      expect(src, isNot(contains('20000')), reason: '资源闸数值抄了一份 ⇒ 两处各变一半');
    }
  });

  test('pruneFnthinkInbox 的读者只有收件服务', () {
    expect(service, contains('pruneFnthinkInbox('), reason: '锚点：服务层没调 = 本守卫空转');
    expect(mainActions, contains('pruneRetention()'), reason: '触发点走的是服务层那一个口子');
    expect(
      mainActions,
      isNot(contains('pruneFnthinkInbox(')),
      reason: '页面动作层直连表的 SQL 参数 = 第二个调用方',
    );
  });

  test('设置页那一格的形状（picker 与档位表同源）', () {
    expect(
      page,
      contains('showIosOptionPicker<int>'),
      reason: '锚点：picker 不在 = 本守卫对页面空转',
    );
    expect(
      page,
      contains('FnthinkSettings.retentionChoices'),
      reason: '选项必须从唯一作者的档位表现取，不抄一份',
    );
    expect(
      page,
      contains('fnthink-retention-pick'),
      reason: '行内动作有 key（页面级用例与闸门按它点）',
    );
  });

  test('每枚 prefs 键都要在备份那一格有着落', () {
    // 尺子从声明处现取，不抄一份名单：抄的那一份会在加键那天就过期（守卫仍然绿）。
    final keys = RegExp(r'static const (key[A-Za-z0-9_]+)\s*=')
        .allMatches(settings)
        .map((m) => m.group(1)!)
        .toSet();
    expect(keys, isNotEmpty, reason: '锚点：一枚键都没取到 = 本守卫对谁都放行');
    // 具名例外：今天一枚都没有。将来真有"故意不进备份"的键，要连着理由一起登记在这里，
    // 而不是让守卫闭嘴 —— 静默漏掉的症状是"换机后一切正常，只有这一档回到缺省"。
    const deliberatelyExcluded = <String, String>{};
    for (final key in keys.difference(deliberatelyExcluded.keys.toSet())) {
      expect(
        backup,
        contains('FnthinkSettings.$key'),
        reason: '$key 没进幻念推送那一格 ⇒ 恢复后它悄悄用缺省，界面上看不出少过东西',
      );
    }
    for (final e in deliberatelyExcluded.entries) {
      expect(
        e.value.length,
        greaterThan(9),
        reason: '${e.key} 的排除理由只有一句空话：这条例外不该存在',
      );
    }
  });

  test('保留扫过那一发：谁 prune 谁就得重取首页未读数', () {
    final at = mainActions.indexOf('pruneRetention()');
    expect(at, greaterThan(-1), reason: '锚点：触发点不在 = 本守卫对谁都放行');
    // 窗口取「prune 之后到下一个成员开头」，不取花括号配对：`.then((pruned) { … })` 里那对
    // 括号不是成员边界，配对法会在这儿截早（本仓那类提取式假绿，T124 一轮里撞过两次）。
    final end = mainActions.indexOf('Future<void> _getDeviceInfo()', at);
    expect(end, greaterThan(at), reason: '窗口右端锚点丢了 ⇒ 守卫量的是半截函数');
    final window = mainActions.substring(at, end);
    expect(
      window,
      contains('_refreshFnthinkInboxUnread'),
      reason:
          '这一发是 unawaited 的一扫，扫完删了东西没人重取 ⇒ 首页那张卡举着一个已经不存在的数'
          '（闸门 4.3 第一轮红的正是这个形状：数在扫之前取、行在扫之后读）',
    );
    expect(window, contains('byAge'), reason: '按龄那一半没读');
    expect(window, contains('byCap'), reason: '上限挤位那一半没读 ⇒ 那一档静默，症状与上面同一条');
  });

  test('反向自检：全仓跑保留扫的只有首页那一发', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => strip(f.readAsStringSync()).contains('pruneRetention('))
        .map((f) => f.path.replaceAll(Platform.pathSeparator, '/'))
        .toSet();
    expect(
      files,
      {
        'lib/services/fnthink_inbox_service.dart',
        'lib/pages/main_page_actions.dart',
      },
      reason:
          '扫这一表的地方长出第二处 ⇒ 每一处都得自己管"删过就要重取读数"，'
          '而那一判今天只钉在首页那一发（这一条是判据①的覆盖面，不是装饰）',
    );
  });
}
