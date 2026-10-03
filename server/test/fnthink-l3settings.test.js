// T51：L3 能力表的**服务端那一半**（设置项词表 + 纯解析 + 回执词）。
//
// 与 Dart 的 test/services/fnthink_l3_settings_test.dart 是同一套判据的两侧断言，
// 两侧读同一份 protocol/fnthink-v1.json —— 不是各带一份夹具，因为这一层最怕的
// 缺陷正是"两端对同一份契约给出了不同的答案"。
//
// 服务端这一侧**不执行**（T30 那条红线：服务端看不见屏幕前的那个人），
// 所以这里只断言解析与回执；执行在设备侧那一半的用例里。

'use strict';

const path = require('path');
const fs = require('fs');

const { assertSupported, loadContract } = require('../lib/fnthink/contract');
const {
  l3ReceiptFor,
  l3SettingsKnownToServer,
  parseL3Item,
} = require('../lib/fnthink/l3settings');

const CONTRACT_PATH = path.join(__dirname, '..', '..', 'protocol', 'fnthink-v1.json');

describe('L3 设置词表（契约是唯一出处，T51）', () => {
  const raw = JSON.parse(fs.readFileSync(CONTRACT_PATH, 'utf8'));
  const settings = raw.capabilities.l3.settings;

  test('仓库里那份契约这一包解释得了（否则下面这些用例都在测空气）', () => {
    // ⚠ Node 侧**没有** validate()：那张表的自洽判据是 Dart 的 FnthinkContract.validate。
    // 这一侧只判"解释得了"（assertSupported）—— 两边合起来才覆盖得住。
    expect(() => assertSupported(loadContract())).not.toThrow();
  });

  test('九项，且每一项都带 mode 与 native', () => {
    expect(Object.keys(settings)).toHaveLength(9);
    for (const [key, spec] of Object.entries(settings)) {
      expect(typeof spec.mode).toBe('string');
      expect(spec.mode).not.toBe('');
      expect(typeof spec.native).toBe('string');
      expect(spec.native).not.toBe('');
      expect(raw.capabilities.l3.modes).toContain(spec.mode);
      expect(key).not.toBe('');
    }
  });

  test('两种形态都有实例，且只有这两种', () => {
    expect(raw.capabilities.l3.modes).toEqual(['grant', 'toggle']);
    const modes = Object.values(settings).map((s) => s.mode);
    expect(modes).toContain('grant');
    expect(modes).toContain('toggle');
    expect(l3SettingsKnownToServer(raw)).toBe(true);
  });

  test('先有授权才谈得上翻的项都在表里，且都是 toggle', () => {
    const needs = raw.capabilities.l3.requiresExistingGrantFrom;
    expect(needs.length).toBeGreaterThan(0);
    for (const key of needs) {
      expect(settings[key]).toBeDefined();
      expect(settings[key].mode).toBe('toggle');
    }
  });

  test('执行失败回的那一个词在顶层 receipts 词表里', () => {
    expect(raw.capabilities.l3.settingsReceipt).toBe('failed_action');
    expect(raw.receipts).toContain(raw.capabilities.l3.settingsReceipt);
  });

  test('messageTypes.setting 仍映射到 L3（设置表存在而 type 侧不指向它 = 没有读者）', () => {
    expect(raw.capabilities.messageTypes.setting.minLevel).toBe('L3');
  });
});

describe('parseL3Item：四种拒的理由各不相同', () => {
  const c = JSON.parse(fs.readFileSync(CONTRACT_PATH, 'utf8'));

  test('认得出的两项各解析出设置项（确认过之后）', () => {
    expect(parseL3Item(c, 'write_settings', { confirmedThisTime: true })).toEqual({
      ok: true,
      setting: { key: 'write_settings', mode: 'grant', native: 'requestWriteSettings' },
    });
    expect(
      parseL3Item(c, 'monitoring', {
        confirmedThisTime: true,
        grantedKeys: ['monitoring'],
      }),
    ).toEqual({
      ok: true,
      setting: { key: 'monitoring', mode: 'toggle', native: 'toggleMonitoring' },
    });
  });

  test('item 为空 ⇒ missing-item（不猜一个设置项出来）', () => {
    for (const given of [undefined, null, '']) {
      expect(parseL3Item(c, given, { confirmedThisTime: true })).toEqual({
        ok: false,
        reason: 'missing-item',
      });
    }
  });

  test('词表外的项 ⇒ unknown-setting:<名>，不静默跳过', () => {
    // ⚠ 本组最要紧的一条：跳过它 = 对端可以拿编出来的设置名试这台设备的边界
    expect(parseL3Item(c, 'wipe_everything', { confirmedThisTime: true })).toEqual({
      ok: false,
      reason: 'unknown-setting:wipe_everything',
    });
  });

  test('没确认 ⇒ confirm-required（且没有免确认这条路）', () => {
    expect(parseL3Item(c, 'write_settings', {})).toEqual({
      ok: false,
      reason: 'confirm-required',
    });
    expect(c.capabilities.l3.allowSkipConfirm).toBe(false);
  });

  test('先有授权才谈得上翻的项，缺授权就是缺（不自动去拿）', () => {
    expect(
      parseL3Item(c, 'monitoring', { confirmedThisTime: true, grantedKeys: [] }),
    ).toEqual({ ok: false, reason: 'missing-grant:monitoring' });
    expect(
      parseL3Item(c, 'monitoring', {
        confirmedThisTime: true,
        grantedKeys: ['monitoring'],
      }).ok,
    ).toBe(true);
  });

  test('不需要预授权的 grant 项不查已授权清单', () => {
    expect(
      parseL3Item(c, 'battery_optimization', {
        confirmedThisTime: true,
        grantedKeys: [],
      }).ok,
    ).toBe(true);
  });

  test('未确认与缺授权是两件事（合并之后用户只看到"没反应"）', () => {
    const noConfirm = parseL3Item(c, 'monitoring', {});
    const noGrant = parseL3Item(c, 'monitoring', {
      confirmedThisTime: true,
      grantedKeys: [],
    });
    expect(noConfirm.reason).toBe('confirm-required');
    expect(noGrant.reason).toBe('missing-grant:monitoring');
  });
});

describe('回执：成功与失败对外各是哪一个词', () => {
  const c = JSON.parse(fs.readFileSync(CONTRACT_PATH, 'utf8'));

  test('成功 ⇒ delivered，失败 ⇒ 契约那一个词', () => {
    expect(l3ReceiptFor(c, { ok: true })).toBe('delivered');
    expect(l3ReceiptFor(c, { ok: false, reason: 'missing-grant:monitoring' })).toBe(
      'failed_action',
    );
  });

  test('本地细节只进 reason，不进对外那个词', () => {
    const w = l3ReceiptFor(c, { ok: false, reason: 'not-applied:write_settings' });
    expect(w).not.toContain('write_settings');
    expect(w).toBe('failed_action');
  });

  test('契约缺 settingsReceipt 时退回 failed_action 而不是空串', () => {
    const broken = JSON.parse(JSON.stringify(c));
    delete broken.capabilities.l3.settingsReceipt;
    expect(l3ReceiptFor(broken, { ok: false })).toBe('failed_action');
  });
});
