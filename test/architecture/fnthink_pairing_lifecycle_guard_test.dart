import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// T171：口令生命周期的接线。
///
/// 决定是**不做服务端 revoke**（只删本机显示）；本守卫钉的是"状态显示与重新生成真的接上"，
/// 以及"删除本机码那一发不假装撤销了服务器那一枚"（它只清本地）。
void main() {
  String read(String rel) => File(rel).readAsStringSync();

  test('设置页画四档并在非有效时给「重新生成」', () {
    final page = read('lib/pages/fnthink_settings_page.dart');
    expect(page, contains("'fnthink-pairing-lifecycle'"));
    expect(page, contains("'fnthink-pairing-regenerate'"));
    expect(page, contains('fnthinkPairingLifecycleOf('));
    expect(page, contains('_pairingLifecycleText('));
  });

  test('成功同意一次才标记用过；重新挂/清除都会清掉标记', () {
    final peers = read('lib/pages/fnthink_peers_page.dart');
    final answerAt = peers.indexOf('Future<void> _answer(');
    final answer = peers.substring(answerAt);
    expect(answer, contains('if (approve && answer.ok)'));
    expect(answer, contains('FnthinkPairingLifecycleStore.markConsumed()'));

    final settings = read('lib/pages/fnthink_settings_page.dart');
    final armAt = settings.indexOf('Future<void> _armPairingCode(');
    final clearAt = settings.indexOf('Future<void> _clearPairingCode(');
    expect(armAt, greaterThan(0));
    expect(clearAt, greaterThan(armAt));
    expect(
      settings.substring(armAt, clearAt),
      contains('FnthinkPairingLifecycleStore.clear()'),
    );
    expect(
      settings.substring(clearAt),
      contains('FnthinkPairingLifecycleStore.clear()'),
    );
  });

  test('删除本机口令不调用任何服务端撤销路由（本轮决定不做 revoke）', () {
    final settings = read('lib/pages/fnthink_settings_page.dart');
    final clearAt = settings.indexOf('Future<void> _clearPairingCode(');
    final clear = settings.substring(
      clearAt,
      settings.indexOf('Future<void> _editHost('),
    );
    expect(clear, isNot(contains('pairRevoke')));
    expect(clear, isNot(contains('revokePairing')));
    expect(clear, contains('credentials.clearPairingCode()'));
  });
}
