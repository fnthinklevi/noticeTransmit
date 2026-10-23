import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// T176：后台收取自检的四条接线（源码形状守卫）。
///
/// 这几件事都是"错了不会报错、只是用户锁屏之后收不到"：
///  ① 最近一次**成功**收取的时刻只在 ok 那一支写；失败也写 ⇒ 自检永远说"刚刚收过"；
///  ② 回前台补一轮的那一发真的接在根页面的 resume 上；
///  ③ 原生自检读口按**同一份** WorkManager 唯一工作名查状态；
///  ④ 对端离线那一档补一句"排队等上线"，不让「离线」被读成「发不出去」。
///
/// 行为验证要真机锁屏 30 分钟（已登记为该任务的设备侧欠账）；这里钉的是接线不许断。
void main() {
  String read(String rel) => File(rel).readAsStringSync();

  test('上次收取只在成功那一支写，失败不覆盖', () {
    final src = read('lib/services/fnthink_receive_coordinator.dart');
    expect(src, contains('kFnthinkLastRoundAtKey'));
    final noteStart = src.indexOf('void _noteRound(');
    expect(noteStart, greaterThan(0));
    final body = src.substring(noteStart);
    final okAt = body.indexOf('report.status == FnthinkPollStatus.ok');
    final markAt = body.indexOf('_markLastRound()');
    expect(okAt, greaterThanOrEqualTo(0));
    expect(markAt, greaterThan(okAt), reason: '失败那一轮也写「上次收取」⇒ 自检把一次失败说成收过货');
  });

  test('回前台补一轮接在根页面 resume 上', () {
    final src = read('lib/pages/main_page.dart');
    final resumeAt = src.indexOf('void didChangeAppLifecycleState');
    expect(resumeAt, greaterThanOrEqualTo(0));
    final resume = src.substring(resumeAt);
    expect(
      resume,
      contains('coordinator.receiveOnce()'),
      reason: '回前台只重读状态、不补一轮 ⇒ 后台那一轮没跑时用户要等到下一个闹钟',
    );
  });

  test('原生自检读口查的是同一份 WorkManager 唯一工作名', () {
    final handler = read(
      'android/app/src/main/kotlin/com/fnthink/notice/channels/FnthinkChannelHandler.kt',
    );
    expect(handler, contains('FnthinkPresenceWorker.UNIQUE_WORK'));
    expect(handler, contains('FnthinkFanoutWorker.UNIQUE_WORK'));
    expect(handler, contains('fanoutQueue'));
    final receiver = read(
      'android/app/src/main/kotlin/com/fnthink/notice/FnthinkPresenceReceiver.kt',
    );
    expect(
      receiver,
      contains('FnthinkPresenceWorker.UNIQUE_WORK'),
      reason: '收货 worker 与自检读口各写一份名字 ⇒ 改名之后自检永远回 none',
    );
    expect(
      receiver,
      isNot(contains('"fnthink-presence-round"')),
      reason: '唯一工作名又长出了第二个字面量',
    );
  });

  test('对端离线那一档补「排队等上线」一句', () {
    final src = read('lib/services/fnthink_peer_presence_display.dart');
    expect(src, contains('fnthinkPeerPresenceDeliveryNote('));
    expect(src, contains('fnthinkPeerPresenceOfflineQueued'));
    final page = read('lib/pages/fnthink_peers_page.dart');
    expect(page, contains('fnthinkPeerPresenceDeliveryNote('));
    expect(page, contains("'fnthink-peer-presence-queued-"));
  });

  test('收取页画出自检三行与两条授权引导', () {
    final page = read('lib/pages/fnthink_receive_page.dart');
    for (final key in const [
      "'fnthink-last-round-at'",
      "'fnthink-work-chain'",
      "'fnthink-grant-exact-alarm'",
      "'fnthink-grant-battery-opt'",
    ]) {
      expect(page, contains(key), reason: '$key 那一格不见了');
    }
    expect(page, contains('_coordinator.lastRoundAt()'));
    expect(page, contains('checkAllPermissions()'));
  });
}
