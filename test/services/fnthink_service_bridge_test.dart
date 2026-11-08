import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_service_bridge.dart';

/// T197 片3：服务引擎与 UI 的交接判据。
///
/// 这一位只回答"UI 心跳还新不新鲜"——判错的两个方向都很糟：
///  - 过松（把过期读成新鲜）⇒ 服务引擎永远不接管，锁屏后回到 60 秒兜底；
///  - 过紧（把新鲜读成过期）⇒ UI 还活着时服务引擎也开一条循环，重复 poll/ack。
void main() {
  test('null / 0 一律不新鲜', () {
    expect(fnthinkUiAlive(null, 100000), isFalse);
    expect(fnthinkUiAlive(0, 100000), isFalse);
  });

  test('窗口内新鲜，窗口边界外不新鲜', () {
    const at = 1000000;
    const freshMs = 30 * 1000;
    expect(fnthinkUiAlive(at, at + freshMs - 1), isTrue);
    expect(
      fnthinkUiAlive(at, at + freshMs),
      isFalse,
      reason: '正好 30 秒边界按过期算：两条循环同时跑的代价高于多接管一轮',
    );
    expect(fnthinkUiAlive(at, at + 1), isTrue);
  });
}
