import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// 启动装配顺序与集成冒烟测试自身的不变式（v1.62）。
///
/// 这三条都是 `integration_test/smoke_test.dart` 在真机上跑出来的**真实缺陷**，
/// 而那条工作流是 `workflow_dispatch`（仅手动触发）——所以必须有一份能在每次 PR
/// 上跑起来的静态守卫，否则同类退化又要等手动跑才发现。
///
/// 1. **语言必须先于装配链初始化**：通道显示名取 `LocaleService.currentLocale`，
///    而 `LocaleService` 默认 system 模式。原先 `init()` 挂在 `MyApp` 的
///    `_onServicesInitialized`（= splash 装配完之后），于是系统语言非中文、应用内
///    选中文的用户，装配期渲染出来的通道名是英文。
///    v1.62 之前这里还有一个更重的后果：**送达状态的存储键就是显示名**，装配期按
///    系统语言写 `webhook:DingTalk`、实时回传再写 `webhook:钉钉` ⇒ 同一条记录中英
///    双键（历史重复徽标 / 旧键永远「发送中」）。DB v11 起存储键改为与语言无关的
///    `chan:<slug>`（见 channel_display），该缺陷类别从根上消除；本条守卫保留，
///    守的是显示层以及任何"装配期就要读语言"的新步骤。
/// 2. **冒烟测试必须自己钉定语言**：它 pump 的是真 `MyApp()`，语言取自 prefs /
///    系统 locale；模拟器默认 en，则全部中文 `find.text` 落空。
/// 3. **测试里的控件 finder 要跟着应用走**：应用已把 Material `Switch` 全量换成
///    `CupertinoSwitch`，且历史页是 Material 路由（`pageBack()` 只认 Cupertino 背键）。
void main() {
  final root = projectRoot();
  final splash = stripComments(
    File('$root/lib/pages/splash_page.dart').readAsStringSync(),
  );
  final smoke = stripComments(
    File('$root/integration_test/smoke_test.dart').readAsStringSync(),
  );

  group('启动装配顺序', () {
    test('splash 在 loadRecords 之前 await LocaleService.init()', () {
      final init = splash.indexOf('LocaleService>().init()');
      final load = splash.indexOf('notificationService.loadRecords()');
      expect(
        init,
        greaterThanOrEqualTo(0),
        reason: 'splash 里找不到 LocaleService.init()',
      );
      expect(
        load,
        greaterThanOrEqualTo(0),
        reason: 'splash 里找不到 loadRecords() 调用',
      );
      expect(
        init,
        lessThan(load),
        reason:
            '语言初始化必须早于记录装配：否则装配期（drain 补更新、历史首帧）按系统语言'
            '渲染通道名，与用户设置不一致',
      );
      // 按整行判定，不用固定长度的回看窗口：`await GetIt.instance<LocaleService>()`
      // 前面的字面量宽度会随泛型/重命名变化，窗口写法会自己产生假阳性。
      expect(
        _lineOf(splash, init),
        contains('await'),
        reason: '缺 await：顺序仍会赛跑',
      );
    });
  });

  group('集成冒烟测试自身的前提', () {
    test('必须显式预置应用语言（否则模拟器英文 locale 让中文断言全落空）', () {
      expect(
        smoke,
        contains("'app_language': 'zh'"),
        reason: 'smoke_test 未钉语言：断言依赖中文文案，会随设备 locale 漂移',
      );
    });

    test('开关 finder 用 CupertinoSwitch（应用已全量替换 Material Switch）', () {
      expect(
        smoke,
        isNot(contains('find.byType(Switch)')),
        reason: 'Material Switch 在应用里已不存在，该 finder 恒为 0',
      );
      expect(smoke, contains('find.byType(CupertinoSwitch)'));
    });

    test('Material 路由返回不用 pageBack（它只认 Cupertino 背键）', () {
      expect(
        smoke,
        isNot(contains('tester.pageBack()')),
        reason:
            '历史页是 Material 路由；pageBack 依赖 CupertinoNavigationBarBackButton / '
            "英文 tooltip，中文环境下必失败",
      );
    });

    test('测试补初始化 WorkManager（本文件不跑应用 main()）', () {
      expect(
        smoke,
        contains('Workmanager().initialize('),
        reason:
            '绕过应用 main() 时 WorkManager 平台侧未初始化，'
            'ArchiveWorker 注册任务会抛 MissingPlugin 类异常',
      );
    });
  });
}

/// 返回 [source] 中包含偏移 [offset] 的那一整行。
String _lineOf(String source, int offset) {
  final start = source.lastIndexOf('\n', offset) + 1;
  final end = source.indexOf('\n', offset);
  return source.substring(start, end < 0 ? source.length : end);
}
