import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_l3_local_state.dart';

/// T134 尾巴：`missing-grant` 改指**本机状态**后的唯一作者的行为用例。
/// 生产接线（service_locator）：monitoring ⇒ `NotificationService.serviceRunning`，
/// collect_inbox ⇒ 服务地址已配 + 中转同意。这里用替身读数钉三件事：
/// 两枚键各走各的读口、词表外 fail-closed、读数即真值（不缓存不重算）。
void main() {
  test('monitoring 走监听那份读数', () async {
    var called = 0;
    final state = FnthinkL3LocalState(
      monitoringInPlace: () async {
        called++;
        return true;
      },
      collectInboxInPlace: () async => fail('collect_inbox 的读口不该被调'),
    );
    expect(await state.inPlace('monitoring'), isTrue);
    expect(called, 1);
  });

  test('collect_inbox 走同意那份读数', () async {
    final state = FnthinkL3LocalState(
      monitoringInPlace: () async => fail('monitoring 的读口不该被调'),
      collectInboxInPlace: () async => false,
    );
    expect(await state.inPlace('collect_inbox'), isFalse);
  });

  test('词表外的 key fail-closed（不认得 ⇒ 不放行）', () async {
    final state = FnthinkL3LocalState(
      monitoringInPlace: () async => true,
      collectInboxInPlace: () async => true,
    );
    expect(await state.inPlace('wipe_everything'), isFalse);
  });
}
