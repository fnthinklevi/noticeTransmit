import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_remote_gate.dart';

/// T97 片C：远程控制那一行的**前置三选一**（纯函数）。
///
/// 判的是"缺哪一条"这件事本身 —— hub 那一行灰不灰、副标题写哪一句，全从这四个值来。
/// 顺序有判据：三层都缺时必须报**最外层**（接收），用户照着修一层就能看到下一层；
/// 报错了层，用户会去改一个本来开着的开关。
void main() {
  test('三层都满足 ⇒ ready', () {
    expect(
      fnthinkRemoteGate(
        receiveEnabled: true,
        consented: true,
        remoteEnabled: true,
      ),
      FnthinkRemoteGate.ready,
    );
  });

  test('接收关着 ⇒ receiveOff（这是最外层）', () {
    expect(
      fnthinkRemoteGate(
        receiveEnabled: false,
        consented: true,
        remoteEnabled: true,
      ),
      FnthinkRemoteGate.receiveOff,
    );
  });

  test('接收开着但没过同意门 ⇒ notConsented', () {
    expect(
      fnthinkRemoteGate(
        receiveEnabled: true,
        consented: false,
        remoteEnabled: true,
      ),
      FnthinkRemoteGate.notConsented,
    );
  });

  test('过了同意门但自己的开关关着 ⇒ switchOff（默认就是这一档）', () {
    expect(
      fnthinkRemoteGate(
        receiveEnabled: true,
        consented: true,
        remoteEnabled: false,
      ),
      FnthinkRemoteGate.switchOff,
    );
  });

  test('三层都缺 ⇒ 报最外层那一条（不许报成「远程执行关着」）', () {
    expect(
      fnthinkRemoteGate(
        receiveEnabled: false,
        consented: false,
        remoteEnabled: false,
      ),
      FnthinkRemoteGate.receiveOff,
      reason: '顺序反了的话，用户会去开一个「本来就开着的开关」来试',
    );
  });
}
