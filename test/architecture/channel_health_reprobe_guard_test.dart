import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// #174 + #183：渠道健康度的**重探入口**与**主动节奏**，以及"目标构造只有一个作者"。
///
/// 为什么要这一族：`channelHealthState` 把"上次成功但过了时效"判成 `unknown`（T04 的判据，
/// 不动），而探测定点此前只有三个族页的进页刷新 —— 于是时效一过，首页那张卡与通道状态页
/// 一律显示「未知」，**没有任何一处会自己去重探**（用户报的就是这个）。#174 补了两个入口
/// （状态页进页 / 回前台），#183 把时效缩到 30 分钟并让它在冷启动与前台期间**自己跑**。
/// 这两处漏接的表现都是"过期的灯永远不亮"，而所有功能测试仍然绿（它们都不走"等过期"这条路）。
void main() {
  final root = projectRoot();
  String read(String rel) =>
      stripComments(File('$root/$rel').readAsStringSync());

  group('#174 两个重探入口', () {
    test('通道状态页进页要探一次（用户正看着"未知"的地方）', () {
      final page = read('lib/pages/channel_status_page.dart');
      expect(
        page,
        contains('probeChannelsAcrossFamilies('),
        reason: '状态页进页不重探 ⇒ 时效一过这一页永远显示"未知"，而它正是用户看状态的那一页',
      );
      expect(
        page,
        contains('void initState()'),
        reason: '重探要挂在进页那一刻（挂在 build 里会每帧发请求）',
      );
    });

    test('App 回前台要探一次（首页那张卡一直挂着的情形）', () {
      final main = read('lib/pages/main_page.dart');
      final resume = blockAfter(main, 'void didChangeAppLifecycleState');
      expect(
        resume,
        contains('AppLifecycleState.resumed'),
        reason: '这段是回前台分支 —— 别的分支（paused/inactive）不该发请求',
      );
      expect(
        resume,
        contains('_startHealthProbeCadence('),
        reason: '回前台不起那一轮 ⇒ 用户锁屏一晚上再打开，那张卡还是"未知"',
      );
      // 真正发请求的那一句在同一个 library 的 part 里（#183 把它收进了节奏函数）：
      expect(
        librarySource(root, 'lib/pages/main_page.dart'),
        contains('unawaited(probeChannelsAcrossFamilies());'),
        reason: '回前台那一轮必须是 stale-only 的（force 只属于下拉那一路）',
      );
    });

    test('目标构造只有一个作者：页面层不许再自己拼 ChannelProbeTarget', () {
      final lib = Directory('$root/lib');
      final offenders = <String>[];
      for (final f in lib.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final rel = f.path
            .replaceAll(r'\', '/')
            .substring(root.replaceAll(r'\', '/').length + 1);
        // 三个服务各自持有本族的构造；`channel_probe_service.dart` 是这一族类型的**声明处**
        // （`const ChannelProbeTarget({...})`），不是"某一族怎么探"的作者。
        // 除此以外的任何文件出现它 = 又多了一个"怎么探"的作者。
        if (rel == 'lib/services/webhook_service.dart' ||
            rel == 'lib/services/app_channel_service.dart' ||
            rel == 'lib/services/email_service.dart' ||
            rel == 'lib/services/channel_probe_service.dart') {
          continue;
        }
        if (stripComments(
          f.readAsStringSync(),
        ).contains('ChannelProbeTarget(')) {
          offenders.add(rel);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            '这些文件里出现了 `ChannelProbeTarget(`：目标怎么构造按族收在各服务里（#174），'
            '页面与"全族扫一遍"读同一份 —— 抄第二份的下场是两条路探的东西不一样，而谁也不报错',
      );
    });
  });

  group('#183 主动节奏（时效 30 分钟 + 打开软件就探）', () {
    test('时效缩到 30 分钟（挂着六小时前的成功不是状态）', () {
      final store = read('lib/services/channel_health_store.dart');
      expect(
        store,
        contains('static const staleness = Duration(minutes: 30);'),
        reason: '时效没缩到 30 分钟 ⇒ 用户报的那件事照旧',
      );
    });

    test('30 分钟这个数全 lib 只有一个出处', () {
      // 第二个「30 分钟」字面量一旦长出，周期与时效就开始各说各话（空档回来）。
      final offenders = <String>[];
      for (final f in Directory(
        '$root/lib',
      ).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final rel = f.path
            .replaceAll(r'\', '/')
            .substring(root.replaceAll(r'\', '/').length + 1);
        if (rel == 'lib/services/channel_health_store.dart') continue;
        if (stripComments(
          f.readAsStringSync(),
        ).contains('Duration(minutes: 30)')) {
          offenders.add(rel);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: '除单点之外还有人写死 30 分钟：$offenders ⇒ 改一处忘一处的空档',
      );
    });

    test('主动周期读的就是那个时效常量', () {
      final main = librarySource(root, 'lib/pages/main_page.dart');
      expect(
        main,
        contains('Timer.periodic('),
        reason: '没有定时器 ⇒ "30 分钟主动探一次"其实没人排（只有进页才动）',
      );
      expect(
        main,
        contains('ChannelHealthStore.staleness,'),
        reason: '周期没读时效常量 ⇒ 两个数会漂（过期了但下一轮还没到）',
      );
      expect(
        main,
        isNot(contains('Timer.periodic(Duration(')),
        reason: '周期写成字面量时长 = 第二份真值回来了',
      );
    });

    test('冷启动那一轮排在三个 loadChannels 之后', () {
      final postInit = blockAfter(
        read('lib/pages/main_page.dart'),
        'Future<void> _postInit()',
      );
      final cadence = postInit.indexOf('_startHealthProbeCadence()');
      final webhookLoaded = postInit.indexOf('_webhookService.loadChannels()');
      final emailLoaded = postInit.indexOf('emailService.loadChannels()');
      expect(
        cadence,
        greaterThanOrEqualTo(0),
        reason: '冷启动不起那一轮 ⇒ "打开软件立刻探"落空',
      );
      expect(
        cadence,
        greaterThan(webhookLoaded),
        reason: '探测目标读的是服务里的内存列表：排在 webhook 装载之前就是对着空列表交"无事可做"',
      );
      expect(cadence, greaterThan(emailLoaded), reason: '同上：邮件族也要先装载完');
    });

    test('退到后台与页面销毁都不留轮询', () {
      final main = read('lib/pages/main_page.dart');
      final lifecycle = blockAfter(main, 'void didChangeAppLifecycleState');
      expect(
        lifecycle,
        contains('_healthProbeTimer?.cancel();'),
        reason: '后台留着定时器 = 一份 ROM 眼里的"耗电常驻网络轮询"',
      );
      expect(
        blockAfter(main, 'void dispose()'),
        contains('_healthProbeTimer?.cancel();'),
        reason: 'dispose 不收 ⇒ 定时器继续持有已销毁的 State（每 30 分钟抛一次 setState）',
      );
    });
  });

  // T104 立过一条判据：「幻念族只进显示单点，绝不进自动重探」—— 理由是它当时**没有非侵入探针**，
  // 「顺手重探一次」＝替用户往对面那台设备发一条真通知（对面会收到）。T106 片③ 把非浸入探针
  // （`POST /probe`，服务端只查关系与档位、一条都不投）落了地，这条判据随之**改理由**：
  //  ① 原生那张表（`add('<族>', …)`，形状是「原生方法名 + 参数」）里**仍然没有**幻念 ——
  //     它的探针是一次签名事件，走自己那一条（`probeFnthinkChannels`）。判据本身没变，
  //     变的是"为什么不能进那一张表"；
  //  ② 那一族自己仍然**不长 `probeTargets`**：那个口是给上面那张表用的。
  group('T106 幻念第四族：进自动重探走自己那一条，不进原生那张表', () {
    test('原生探测表仍是那三族（幻念不走「原生方法名 + 参数」那条路）', () {
      final src = read('lib/services/active_channels.dart');
      // 探测链路的族名只看 `add('<族>', …)` 那几行 —— 折行/改参数形状不该让判据变红（base.md（75））。
      final probed = RegExp(
        "add\\('([^']+)'",
      ).allMatches(src).map((m) => m.group(1)!).toSet();
      expect(
        probed,
        equals({'webhook', 'app', 'email'}),
        reason:
            '原生那张表的族集合变了：多出 fnthink ⇒ 它会被当成"原生方法名 + 参数"那一类去探'
            '（而它得签一次名），少掉一族 ⇒ 过时效的那盏灯又没人管（#174 的病灶）',
      );
      expect(
        src,
        contains('probeFnthinkChannels('),
        reason: '幻念那一族的重探没了 ⇒ 它又回到"只有人手动测"，而 T106 已经把非浸入探针做出来了',
      );
      expect(
        src,
        isNot(contains("add('fnthink'")),
        reason: '族集合那条已经拦住了，这一条把"怎么加进来的"那一句也钉住（改天集合判据被人绕过时它还红）',
      );
    });

    test('这一族自己不长探测目标口（那个口的形状是给原生那张表用的）', () {
      final service = read('lib/services/fnthink_channel_service.dart');
      expect(
        service,
        isNot(contains('probeTargets')),
        reason:
            '`probeTargets` 的形状是「原生方法名 + 参数」，这一族没有原生方法可调 —— '
            '长出同名的口，下一个人就会把它塞进上面那张表，而那条循环根本不知道该怎么发一次签名事件',
      );
    });

    test('显示单点这一侧：第四族确实在清单里，且按 enabled 判', () {
      final body = blockAfter(
        read('lib/services/active_channels.dart'),
        'List<ActiveChannel> collectActiveChannels() {',
      );
      expect(
        body,
        contains("family: 'fnthink'"),
        reason: '一条启用中的幻念通道不在这份清单里 = 它照在转发而界面上看不见（T104 的病灶）',
      );
      expect(
        body,
        contains('where((c) => c.enabled)'),
        reason: '停用的通道不进这份清单（与另三族同一判据；停用≠可以显示成"正常"）',
      );
    });

    test('通道状态页分四组，但主备弹层仍只有那三族（这条快捷路没开）', () {
      final page = read('lib/pages/channel_status_page.dart');
      expect(
        page,
        contains("'fnthink'"),
        reason: '分组顺序里没有第四族 ⇒ 清单里有它而这一页不画它，两处又开始各说一套',
      );
      final sheet = blockAfter(page, 'Future<void> _showRoleSheet() async');
      expect(
        sheet,
        isNot(contains("'fnthink'")),
        reason:
            '这一族的角色改要走 `FnthinkChannelService.save()`（会连带重验目标），'
            '而弹层只有「这条通道已经不在了」一句可说 —— 在这里加一族等于让快捷路说假话',
      );
    });

    test('点幻念那一行必须有自己的 case（不许被 default 带去自建应用那页）', () {
      final actions = librarySource(root, 'lib/pages/main_page.dart');
      final opener = blockAfter(
        actions,
        'Future<void> _openChannelStatusPage()',
      );
      expect(
        opener,
        contains("case 'fnthink'"),
        reason:
            '按族分派漏了这一条时会走 `default` ⇒ 点幻念那行开的是「自建应用通道」那页：'
            '不崩、不报错，只是把人带到别的地方',
      );
    });

    test('装载与读缓存必须是同一个实例：除 DI 那处，全 lib 不许再 new', () {
      // T104 片② 的病灶不是编译错误：那份 `cachedChannels` 挂在**实例**上，各页各 new 一份时
      // "装载发生在这一份、清单读的是另一份"，表现是首页少一行而一行错误都不冒（全场测试照样绿）。
      final locator = read('lib/di/service_locator.dart');
      expect(
        locator,
        contains('registerLazySingleton<FnthinkChannelService>('),
        reason: '没注册 ⇒ `collectActiveChannels()` 那个 try 每次都被吞掉，第四族永远不上屏',
      );
      expect(
        librarySource(root, 'lib/pages/main_page.dart'),
        contains('GetIt.instance<FnthinkChannelService>()'),
        reason:
            '装载点（`_refreshFnthinkChannels()` 那一发 `list()`）必须落在 DI 那一个实例上 —— '
            '它自己 new 一份就是那份缓存的第二本账',
      );
      final offenders = <String>[];
      for (final f in Directory(
        '$root/lib',
      ).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final rel = f.path
            .replaceAll(r'\', '/')
            .substring(root.replaceAll(r'\', '/').length + 1);
        if (rel == 'lib/di/service_locator.dart') continue;
        if (stripComments(
          f.readAsStringSync(),
        ).contains('FnthinkChannelService()')) {
          offenders.add(rel);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: '这些文件又 new 了一份通道写咽喉：$offenders ⇒ 首页读的缓存与它们写的不是同一个',
      );
    });
  });
}
