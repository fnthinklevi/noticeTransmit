'use strict';

/**
 * `store.js` 原子写的两条判据（T29-B 顺带修的那个潜伏缺陷）。
 *
 * 触发场景是实测出来的：devicestore 每配一次对就写一次盘，Windows 上出现
 * `EPERM: operation not permitted, rename x.tmp -> x.json`（原行为 600 次 3 遇，
 * 立刻重试就能成）。当时的两个选择是"把它当偶发忽略"或者"承认写盘会瞬时失败并补一次重试" ——
 * 选了后者，因为**写盘失败被咽下来**的代价是"配对看起来成功了"。
 *
 * 这几条用例用 spy 制造同样的错误，因此 Linux（CI）与 Windows（本机）都跑得动。
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const bcrypt = require('bcryptjs');

process.env.NODE_ENV = 'test';
process.env.ADMIN_TOKEN_HASH = bcrypt.hashSync('test-admin-token-for-store', 10);
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'nt-store-test-'));

const { writeJsonFile } = require('../lib/store');

const realRename = fs.renameSync;

function eperm() {
  const e = new Error('EPERM: operation not permitted');
  e.code = 'EPERM';
  throw e;
}

function failRenames(times, code) {
  let calls = 0;
  fs.renameSync = (a, b) => {
    calls += 1;
    if (calls <= times) {
      const e = new Error(`${code}: injected`);
      e.code = code;
      throw e;
    }
    return realRename(a, b);
  };
  return () => calls;
}

describe('store.js 原子写', () => {
  afterEach(() => {
    fs.renameSync = realRename;
  });

  test('瞬时 EPERM 之后能写成（不是"这一次就是丢了"）', () => {
    const target = path.join(process.env.DATA_DIR, 'transient.json');
    const calls = failRenames(2, 'EPERM');
    expect(writeJsonFile(target, { ok: 1 }, { mode: 0o600 })).toBe(true);
    expect(calls()).toBe(3);
    expect(JSON.parse(fs.readFileSync(target, 'utf8'))).toEqual({ ok: 1 });
  });

  test('一直失败就返回 false —— 重试不许把"没落盘"洗成"写好了"', () => {
    const target = path.join(process.env.DATA_DIR, 'always.json');
    fs.renameSync = eperm;
    expect(writeJsonFile(target, { ok: 1 })).toBe(false);
    expect(fs.existsSync(target)).toBe(false);
  });

  test('重试有上限，且非瞬时错误码一次就停', () => {
    const calls = failRenames(99, 'EPERM');
    expect(writeJsonFile(path.join(process.env.DATA_DIR, 'cap.json'), { a: 1 })).toBe(false);
    expect(calls()).toBeLessThanOrEqual(5); // 上限写死在 RENAME_ATTEMPTS，不许变成"卡到用户烦"

    fs.renameSync = realRename;
    const once = failRenames(99, 'ENOENT');
    expect(writeJsonFile(path.join(process.env.DATA_DIR, 'other.json'), { a: 1 })).toBe(false);
    expect(once()).toBe(1); // ENOENT 不是占用，重试只会掩盖真因
  });

  test('传了 mode 会走 chmod（权限收紧这件事不许静默失效）', () => {
    const target = path.join(process.env.DATA_DIR, 'mode.json');
    let chmodded = null;
    const realChmod = fs.chmodSync;
    fs.chmodSync = (p, mode) => {
      chmodded = mode;
      return realChmod(p, mode);
    };
    try {
      expect(writeJsonFile(target, { a: 1 }, { mode: 0o600 })).toBe(true);
      expect(chmodded).toBe(0o600);
    } finally {
      fs.chmodSync = realChmod;
    }
  });
});
