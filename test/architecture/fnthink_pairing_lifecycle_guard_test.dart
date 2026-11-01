import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// T171：口令生命周期的接线。
///
/// 决定是**不做服务端 revoke**（只删本机显示）；本守卫钉的是"状态显示与重新生成真的接上"，
/// 以及"删除本机码那一发不假装撤销了服务器那一枚"（它只清本地）。
///
/// T214：身份那一格搬进共享卡（设置页与配对页挂同一件），所以四档与两枚动作的读物
/// 从设置页换成 `lib/widgets/fnthink_identity_card.dart`；动作那一半的两个清标记点
/// 仍在设置页（配对页也能挂口令，所以两页都要清）。
void main() {
  String read(String rel) => File(rel).readAsStringSync();

  test('共享身份卡画四档并在非有效时给「重新生成」', () {
    final card = read('lib/widgets/fnthink_identity_card.dart');
    expect(card, contains("'fnthink-pairing-lifecycle'"));
    expect(card, contains("'fnthink-pairing-regenerate'"));
    expect(card, contains('fnthinkPairingLifecycleOf('));
    expect(card, contains('_lifecycleText('));
  });

  test('成功同意一次才标记用过；重新挂/清除都会清掉标记', () {
    final peers = read('lib/pages/fnthink_peers_page.dart');
    final answerAt = peers.indexOf('Future<void> _answer(');
    final answer = peers.substring(answerAt);
    expect(answer, contains('if (approve && answer.ok)'));
    expect(answer, contains('FnthinkPairingLifecycleStore.markConsumed()'));

    final settings = read('lib/pages/fnthink_settings_page.dart');
    final armAt = settings.indexOf(
      'Future<FnthinkArmedPairingCode?> _armPairingForCard(',
    );
    final revokeAt = settings.indexOf('Future<void> _clearPairingForCard(');
    expect(armAt, greaterThan(0));
    expect(revokeAt, greaterThan(armAt));
    expect(
      settings.substring(armAt, revokeAt),
      contains('FnthinkPairingLifecycleStore.clear()'),
    );
    expect(
      settings.substring(revokeAt),
      contains('FnthinkPairingLifecycleStore.clear()'),
    );

    // T214：配对页也能挂口令 ⇒ 它那一份挂出同样要清掉上一枚的「用过」。
    final peersArmAt = peers.indexOf(
      'Future<FnthinkArmedPairingCode?> _armPairingForCard(',
    );
    expect(peersArmAt, greaterThan(0));
    expect(
      peers.substring(
        peersArmAt,
        peers.indexOf('Future<void> _setSenderMode('),
      ),
      contains('FnthinkPairingLifecycleStore.clear()'),
    );
  });

  test('删除本机口令不调用任何服务端撤销路由（本轮决定不做 revoke）', () {
    final settings = read('lib/pages/fnthink_settings_page.dart');
    final revokeAt = settings.indexOf('Future<void> _clearPairingForCard(');
    final revoke = settings.substring(
      revokeAt,
      settings.indexOf('Future<void> _resetAddressForCard('),
    );
    expect(revoke, isNot(contains('pairRevoke')));
    expect(revoke, isNot(contains('revokePairing')));
    expect(revoke, contains('credentials.clearPairingCode()'));
  });
}
