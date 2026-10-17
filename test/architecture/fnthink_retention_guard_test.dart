import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// T47 守卫：收件保留策略的三个"不许再长第二份"。
/// ① 数值与档位只住 `FnthinkSettings`（界面与 prune 各读各的那一份）；
/// ② `pruneFnthinkInbox` 的读者只有收件服务（页面/别处不许直连）；
/// ③ 设置页那一格的形状（picker 用的是同一份档位表）。
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
}
