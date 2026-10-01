import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// #174：渠道健康度过期之后的**两个重探入口**，以及"目标构造只有一个作者"。
///
/// 为什么要这一族：`channelHealthState` 把"上次成功但超过 6h"判成 `unknown`（T04 的判据，
/// 不动），而探测定点此前只有三个族页的进页刷新 —— 于是 6h 一过，首页那张卡与通道状态页
/// 一律显示「未知」，**没有任何一处会自己去重探**（用户报的就是这个）。修法是在用户看状态的
/// 两个地方各补一次 stale-only 重探；这两处漏接的表现是"过期的灯永远不亮"，
/// 而所有功能测试仍然绿（它们都不走"等 6 小时"这条路）。
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
        reason: '状态页进页不重探 ⇒ 6h 一过这一页永远显示"未知"，而它正是用户看状态的那一页',
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
        contains('probeChannelsAcrossFamilies('),
        reason: '回前台不重探 ⇒ 用户锁屏一晚上再打开，那张卡还是"未知"',
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
}
