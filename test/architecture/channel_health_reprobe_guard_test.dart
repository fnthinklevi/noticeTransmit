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
}
