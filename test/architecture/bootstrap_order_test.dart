import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// 装配顺序与集成冒烟测试自身的不变式（v1.62 起）。
/// 1–3 是 `integration_test/smoke_test.dart` 在真机上跑出来的**真实缺陷**，4 是第 5 步
/// 描述符改造引入新的装配依赖后补的顺序约束。那条工作流是 `workflow_dispatch`
/// （仅手动触发）——所以必须有一份能在每次 PR 上跑起来的静态守卫，
/// 否则同类退化又要等手动跑才发现。
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
/// 4. **通道描述符先于通道页可达**（第 5 步）：设置页的表单字段、类型列表、secret/模板
///    显隐全按 `getChannelDescriptors` 渲染。装配链不 await 它，第一个打开设置页的人
///    就会看到一张缺字段的表单（保存还可能把已存配置写空）。
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

    test('splash 在通道页可达之前拉好通道描述符（第 5 步）', () {
      final load = splash.indexOf('ChannelDescriptorService>().load()');
      final goto = splash.indexOf('widget.onInitCompleted()');
      expect(
        load,
        greaterThanOrEqualTo(0),
        reason: 'splash 里没有拉取描述符：设置页会带着空 schema 打开',
      );
      expect(goto, greaterThanOrEqualTo(0), reason: '找不到装配终点');
      expect(load, lessThan(goto), reason: 'onInitCompleted 之后通道页即可达，描述符必须先到手');
      expect(
        _lineOf(splash, load),
        contains('await'),
        reason: '缺 await：装配链与描述符拉取赛跑',
      );
      expect(
        File('$root/lib/di/service_locator.dart').readAsStringSync(),
        contains('registerLazySingleton<ChannelDescriptorService>'),
        reason: '没注册就在 splash 装配链里 GetIt.instance，直接抛异常打断启动',
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
