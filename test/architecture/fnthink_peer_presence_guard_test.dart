import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fnthink_push/fnthink_push.dart';

/// T156 片2 的源码守卫。
///
/// 这一片的四句话各由一个结构化位置钉住：
///  ① 内核的五个字段名只从 `presence.peerReadout` 现取；
///  ② 缺 `peers` 键是失败（不许 `?? []` 把"没读到"变成"你没有"）；
///  ③ 页面的每一行只走显示作者，不碰 `lastSeenAt` / `ageSeconds`（年龄是服务端算好的）；
///  ④ `unknown` 与 `notShared` 两句都不是"离线"。

String _strip(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

String _read(String rel) => _strip(File(rel).readAsStringSync());

String _window(String src, String start, String end) {
  final at = src.indexOf(start);
  expect(at, greaterThanOrEqualTo(0), reason: '未找到 $start');
  final endAt = src.indexOf(end, at);
  expect(endAt, greaterThan(at), reason: '未找到 $start 之后的 $end');
  return src.substring(at, endAt);
}

void main() {
  final kernel = _read('packages/fnthink_push/lib/src/receive_kernel.dart');
  final receiver = _read('lib/services/fnthink_receiver_service.dart');
  final page = _read('lib/pages/fnthink_peers_page.dart');
  final display = _read('lib/services/fnthink_peer_presence_display.dart');
  final zh = File('lib/l10n/arb/app_zh.arb').readAsStringSync();
  final en = File('lib/l10n/arb/app_en.arb').readAsStringSync();
  final contract = FnthinkContract.readFile();

  test('内核五个字段名只从 presence.peerReadout 现取', () {
    final body = _window(
      kernel,
      'Future<FnthinkPeerPresenceResult> peerPresence() async {',
      '  Map<String, Object?> endpointRevokeFields(',
    );
    for (final key in [
      'peersField',
      'addressCodeField',
      'presenceField',
      'lastSeenField',
      'ageField',
    ]) {
      expect(body, contains('readout.$key'), reason: '$key 不是从读口现取的');
    }
    for (final literal in [
      "'peers'",
      "'addressCode'",
      "'presence'",
      "'lastSeenAt'",
      "'ageSeconds'",
    ]) {
      expect(body, isNot(contains(literal)), reason: '$literal 是第二份字段名');
    }
  });

  test('缺 peers 键是失败，不许 ?? [] 当成空清单', () {
    final body = _window(
      kernel,
      'Future<FnthinkPeerPresenceResult> peerPresence() async {',
      '  Map<String, Object?> endpointRevokeFields(',
    );
    expect(body, contains('raw is! List'));
    // 口径只钉 peers 那一行：nonce 工厂的 `??` 是合法的，扫全体的 `??` 会误伤。
    expect(body, contains('final raw = reply.body[readout.peersField];'));
    expect(body, isNot(contains('readout.peersField] ??')));
    expect(body, contains('contract.presenceUnknownState'));
    expect(body, contains('contract.presenceStates'));
  });

  test('装配期登记了这条路径', () {
    expect(receiver, contains("'peerPresence'"));
  });

  test('页面只走显示作者，不碰原始时间戳', () {
    expect(page, contains('fnthinkPeerPresenceView('));
    expect(page, contains('fnthinkPeerPresenceLine('));
    expect(page, contains("'fnthink-peer-presence-"));
    expect(page, contains("'fnthink-peer-presence-failed'"));
    expect(page, contains("'fnthink-peer-presence-loading'"));
    expect(page, isNot(contains('lastSeenAt')));
    expect(page, isNot(contains('ageSeconds')));
  });

  test('显示作者覆盖六档，岁数只来自服务端秒数', () {
    for (final kind in [
      'online',
      'offline',
      'unknown',
      'notShared',
      'loading',
      'unavailable',
    ]) {
      expect(display, contains('FnthinkPeerPresenceKind.$kind'));
    }
    expect(display, contains('contract.presenceOnlineState'));
    expect(display, contains('contract.presenceOfflineState'));
    expect(display, contains('contract.presenceUnknownState'));
    expect(display, isNot(contains('DateTime.now')));
    expect(display, isNot(contains('lastSeenAt')));
  });

  test('unknown 与 notShared 的文案不是离线', () {
    for (final arb in [zh, en]) {
      for (final key in [
        'fnthinkPeerPresenceOnline',
        'fnthinkPeerPresenceOffline',
        'fnthinkPeerPresenceUnknown',
        'fnthinkPeerPresenceNotShared',
      ]) {
        expect(arb, contains('"$key"'), reason: '缺 $key');
      }
    }
    final zhUnknown = RegExp(
      r'"fnthinkPeerPresenceUnknown": "([^"]*)"',
    ).firstMatch(zh)!.group(1)!;
    final zhNotShared = RegExp(
      r'"fnthinkPeerPresenceNotShared": "([^"]*)"',
    ).firstMatch(zh)!.group(1)!;
    expect(zhUnknown, contains('还没上过线'));
    expect(zhNotShared, contains('没有共享'));
    expect(zhUnknown, isNot(contains('离线')));
    expect(zhNotShared, isNot(contains('离线')));
  });

  test('三态 getter 指向契约那三枚词', () {
    expect(contract.presenceStates, hasLength(3));
    expect(contract.presenceOnlineState, 'online');
    expect(contract.presenceOfflineState, 'offline');
    expect(contract.presenceUnknownState, 'unknown');
  });
}
