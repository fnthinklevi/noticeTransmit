import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// T177：一键自检的两条接线。
///
/// 自检必须**同时**问两件事：`peerPresence` 读口与当前 host 的 `/health`。
/// 只问一件时，屏幕上那句"正常"会替另一件没做的事作保 —— 而这两个恰好是
/// 「服务器版本旧」最容易分开现形的两面（机器在答 HTTP，但路由没有）。
void main() {
  String read(String rel) => File(rel).readAsStringSync();

  test('设置页那一枚自检真的调用两个读口', () {
    final page = read('lib/pages/fnthink_settings_page.dart');
    expect(page, contains("'fnthink-host-selfcheck'"));
    final start = page.indexOf('Future<void> _runSelfCheck(');
    expect(start, greaterThan(0));
    final body = page.substring(
      start,
      page.indexOf('Future<void> _probeCurrentHost('),
    );
    expect(body, contains('_probeCurrentHost()'));
    expect(body, contains('peerPresence()'));
    expect(body, contains('fnthinkPeerPresenceFailedLine('));
  });

  test('404 的翻译住在显示作者里，页面不自己判', () {
    final display = read('lib/services/fnthink_peer_presence_display.dart');
    expect(display, contains('peer-presence-http:404'));
    expect(display, contains('fnthinkPeerPresenceMissingRoute'));
    final page = read('lib/pages/fnthink_settings_page.dart');
    expect(page, isNot(contains("'peer-presence-http:404'")));
  });
}
