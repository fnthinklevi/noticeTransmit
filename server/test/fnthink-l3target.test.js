/**
 * L3 item 目标值（`itemMayCarryTarget`）—— 两端**同一组形状**的那一半（Node 侧）。
 * ⚠ 与 `test/services/fnthink_l3_settings_test.dart` 逐条对应：
 *   两份都改或都不改，否则两端口径会漂，而漂了只有真发一次才看得见。
 */
const { parseL3Item } = require('../lib/fnthink/l3settings.js');
const contract = require('../../protocol/fnthink-v1.json');

const confirmed = { confirmedThisTime: true };

describe('L3 item 目标值（契约 l3.itemMayCarryTarget）', () => {
  test('裸 key 收，且目标值是 null（沿用旧语义：读当前再翻，不幂等）', () => {
    const r = parseL3Item(contract, 'monitoring', confirmed);
    expect(r.ok).toBe(true);
    expect(r.setting.key).toBe('monitoring');
    expect(r.setting.target).toBeNull();
  });

  test('<key>/on ⇒ 目标值 true（幂等那一档）', () => {
    const r = parseL3Item(contract, 'monitoring/on', confirmed);
    expect(r.ok).toBe(true);
    expect(r.setting.key).toBe('monitoring');
    expect(r.setting.target).toBe(true);
  });

  test('<key>/off ⇒ 目标值 false', () => {
    const r = parseL3Item(contract, 'collect_inbox/off', confirmed);
    expect(r.ok).toBe(true);
    expect(r.setting.target).toBe(false);
  });

  test('⚠ 大小写不同 ⇒ 不拆（unknown-setting 带整串，不是猜）', () => {
    // 「宽容归一」会把拼错的参数变成一次真实的启停，而重投会把它再启停一次。
    const r = parseL3Item(contract, 'monitoring/ON', confirmed);
    expect(r.ok).toBe(false);
    expect(r.reason).toBe('unknown-setting:monitoring/ON');
  });

  test('尾部不是目标值词 ⇒ 不拆，仍按整串查词表', () => {
    expect(parseL3Item(contract, 'monitoring/enabled', confirmed).ok).toBe(false);
  });

  test('不存在的 key 带目标值 ⇒ 拒的理由说的是拆出来的那个 key', () => {
    const r = parseL3Item(contract, 'nope/off', confirmed);
    expect(r.ok).toBe(false);
    expect(r.reason).toBe('unknown-setting:nope');
  });

  test('grant 项也能带目标值（协议不按 mode 限制；设备侧忽略它）', () => {
    const r = parseL3Item(contract, 'exact_alarm/on', confirmed);
    expect(r.ok).toBe(true);
    expect(r.setting.mode).toBe('grant');
    expect(r.setting.target).toBe(true);
  });

  test('前置授权那一格仍然按**拆出来的 key** 判', () => {
    // ⚠ grantedKeys 给了（即使是空数组）那一格才判。
    const none = { confirmedThisTime: true, grantedKeys: [] };
    const bare = parseL3Item(contract, 'collect_inbox', none);
    expect(bare.reason).toBe('missing-grant:collect_inbox');
    // 带目标值的那一条：拆出 key 后同样拒——
    // 否则帱名带了 /on 就能绕过授权判定。
    const withTarget = parseL3Item(contract, 'collect_inbox/on', none);
    expect(withTarget.reason).toBe('missing-grant:collect_inbox');
  });
});
