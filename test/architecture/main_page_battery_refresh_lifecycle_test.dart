import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// 首页电量卡的刷新表必须跟着前台/后台走（后台空闲降 CPU 第 4 项）。
///
/// 这张卡每 30 秒发一次 `getBatteryStatus`。旧接线只在 `_postInit` 起表、`dispose` 停表，
/// 用户按 Home 后页面根本没销毁，表照跑 —— 后台没人看这张卡，却持续产生平台通道往返。
///
/// 这类缺陷没有功能症状：读数仍然正确、界面仍然正常，只是电池在后台被一点点吃掉。
/// 所以这里钉住生命周期两支各自的动作，且要求回前台**先补一次读数**（不然最多 30 秒旧值）。
void main() {
  final root = projectRoot();
  final main = stripComments(librarySource(root, 'lib/pages/main_page.dart'));

  test('后台停表、回前台起表并立刻补一次读数', () {
    final lifecycle = blockAfter(main, 'void didChangeAppLifecycleState');
    final pausedAt = lifecycle.indexOf('AppLifecycleState.paused');
    expect(pausedAt, greaterThan(0), reason: '生命周期里找不到 paused 分支：守卫的分段锚点已失效');
    final foreground = lifecycle.substring(0, pausedAt);
    final background = lifecycle.substring(pausedAt);

    expect(
      foreground,
      contains('_batteryService.startRefreshTimer()'),
      reason: '回前台不起表 ⇒ 首页电量卡停在后台前那一刻，直到用户手动下拉/重进页面',
    );
    expect(
      foreground,
      contains('_batteryService.refreshStatus()'),
      reason: '只起表不补读数 ⇒ 回前台最多先显示 30 秒旧值（用户看到的正是"电量没变"）',
    );
    expect(
      background,
      contains('_batteryService.stopRefreshTimer()'),
      reason: '后台不停表 ⇒ 每 30 秒一次 `getBatteryStatus`，纯 UI 读数却持续唤醒进程',
    );
  });

  test('initState 仍然负责冷启动起表（别把回前台那条当成唯一作者）', () {
    expect(
      main,
      contains('_batteryService.startRefreshTimer()'),
      reason: '冷启动必须起表；否则从未进过后台的用户根本看不到电量刷新',
    );
  });
}
