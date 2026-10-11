import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_presence_scheduler.dart';

/// T140 层2 察：那一行四档判据的唯一作者。
///
/// 为什么单独钉（而不是只靠页面用例）：真凶那一发走的是 `cancel()`，而 cancel 把
/// `nextRoundAt` **和** `cadenceSeconds` 一起清成 0 ⇒ "被撤过"与"从没排过"在那两个读数上
/// 长得一样。分开它们的只有 `everArmedAt`。这一族判错的表现不是崩，是**界面说了一件没发生的事**：
/// 把"刚开开关"报成故障（吓用户），或把故障报成"刚开起来"（用户等下去，永远等不到）。
void main() {
  FnthinkPresenceStatus status({
    int nextRoundAt = 0,
    int cadenceSeconds = 0,
    int everArmedAt = 0,
  }) => FnthinkPresenceStatus(
    nextRoundAt: nextRoundAt,
    cadenceSeconds: cadenceSeconds,
    everArmedAt: everArmedAt,
  );

  FnthinkPresenceLiveness judge({
    bool enabled = true,
    bool consented = true,
    required FnthinkPresenceStatus s,
  }) =>
      judgePresenceLiveness(enabled: enabled, consented: consented, status: s);

  test('排着就是活着：时间点与 cadence 都齐', () {
    expect(
      judge(s: status(nextRoundAt: 1_760_000_000_000, cadenceSeconds: 20)),
      FnthinkPresenceLiveness.armed,
    );
  });

  test('开关关着 ⇒ 本来就不该醒着，不报故障（哪怕原生什么都没排）', () {
    expect(
      judge(enabled: false, s: status(everArmedAt: 1)),
      FnthinkPresenceLiveness.configIncomplete,
      reason: '把"用户自己关了"报成"链死了"是假话，还会引他去按一枚没用的按钮',
    );
    expect(
      judge(consented: false, s: status(everArmedAt: 1)),
      FnthinkPresenceLiveness.configIncomplete,
    );
  });

  test('曾经醒过 ＋ 现在没排 ＋ 开关与同意都在 ⇒ 复起链已断（这一档才给「立即恢复」）', () {
    expect(
      judge(s: status(everArmedAt: 1_759_999_000_000)),
      FnthinkPresenceLiveness.dead,
      reason:
          '这正是真机那次的形状：06:07 被 cancel 之后 cadence 也归 0，'
          '只看 cadence 就会把它读成"从没排过"，用户等到天荒地老',
    );
  });

  test('从没排上过 ⇒ 是"还没排第一轮"，不是故障', () {
    expect(
      judge(s: status()),
      FnthinkPresenceLiveness.pendingFirstRound,
      reason: '闹钟是在每一轮结束时续排的，刚开开关那一刻必然还没排 —— 报故障就是吓用户',
    );
  });

  test('cadence 单独在、时间点为 0：仍按"曾经醒过"算断（cancel 会一起清，不留单独的 cadence）', () {
    expect(
      judge(s: status(cadenceSeconds: 20, everArmedAt: 1)),
      FnthinkPresenceLiveness.dead,
      reason: '这一档不许因为"还有 cadence"就退回 armed 分支去显示一个 0 点的时间',
    );
  });
}
