import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_pairing_lifecycle.dart';

/// T171：配对口令在本机屏幕上的四档。
///
/// 优先级是**用过 > 过期 > 没上到服务器 > 有效 > 不知道**：用过那一枚即使还没到 TTL
/// 也不该再显示成"现在能用"；不知道不猜成有效。
void main() {
  test('用过优先于一切', () {
    expect(
      fnthinkPairingLifecycleOf(
        consumed: true,
        looksExpired: true,
        acked: false,
      ),
      FnthinkPairingLifecycle.consumed,
    );
  });

  test('过期优先于没上到服务器', () {
    expect(
      fnthinkPairingLifecycleOf(
        consumed: false,
        looksExpired: true,
        acked: false,
      ),
      FnthinkPairingLifecycle.expired,
    );
  });

  test('服务器没收到 ⇒ 已失效（不是过期）', () {
    expect(
      fnthinkPairingLifecycleOf(
        consumed: false,
        looksExpired: false,
        acked: false,
      ),
      FnthinkPairingLifecycle.notPublished,
    );
  });

  test('读数不全 ⇒ 不知道，不猜成有效', () {
    for (final v in [
      fnthinkPairingLifecycleOf(
        consumed: false,
        looksExpired: null,
        acked: true,
      ),
      fnthinkPairingLifecycleOf(
        consumed: false,
        looksExpired: false,
        acked: null,
      ),
    ]) {
      expect(v, FnthinkPairingLifecycle.unknown);
    }
  });

  test('未用过、未过期、服务器已确认 ⇒ 有效', () {
    expect(
      fnthinkPairingLifecycleOf(
        consumed: false,
        looksExpired: false,
        acked: true,
      ),
      FnthinkPairingLifecycle.active,
    );
  });
}
