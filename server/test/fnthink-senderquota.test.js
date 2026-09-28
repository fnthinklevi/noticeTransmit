// #130-A2：按发送方计的配额（主键 = 已证明身份的设备地址）。
//
// 这一片要守的三件事：
//  ① **主键是设备地址，不是 IP** —— 反代之后"手机 + 手表 + 家里三台"共用一个源，
//     按 IP 计会让它们互相挤额度（A1 收成 6/分那一次就是这么红的）；
//  ② **计额点只能在验签之后** —— 请求体里的 sender 在验签前只是个字符串，
//     按它计额的后果是 DoS 转移：攻击者拿受害者的地址发洪水，被 429 的是受害者；
//  ③ **没有端点漏接** —— 名单在契约里（ratelimit 推导），接线在 routes 里，
//     两边靠静态守卫对齐；漏一个的表现是"某条端点看起来有配额，其实只受面的总量闸门管"。
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const bcrypt = require('bcryptjs');

process.env.NODE_ENV = 'test';
process.env.PORT = '0';
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'nt-fnthink-sq-'));
process.env.ADMIN_TOKEN_HASH = bcrypt.hashSync('test-admin-token-for-sq', 10);
process.env.ENCRYPTION_KEY = 'a'.repeat(64);

const { loadContract, assertSupported, statusCode } = require('../lib/fnthink/contract');
const { windowsFor } = require('../lib/fnthink/ratelimit');
const { createSenderQuota } = require('../lib/fnthink/senderquota');

const contract = assertSupported(loadContract());
const windows = windowsFor(contract);
const RATE_LIMITED = statusCode(contract, 'rateLimited');

/// 造一份"小额度"的窗口（真额度是 60/分、5000/天，打满一次要几百个请求，而这里要测的是判定本身）
const tiny = (map) => ({ ...windows, senderWindows: new Map(map) });

describe('按发送方计的配额（#130-A2）', () => {
  test('同一台设备超了分钟额度 ⇒ 429 + Retry-After + 空 body', () => {
    const charge = createSenderQuota(tiny([['poll', { perMinute: 2, perDay: null }]])).charge;
    expect(charge('poll', 'AAAA', 1_000_000)).toBeNull();
    expect(charge('poll', 'AAAA', 1_000_000)).toBeNull();
    const over = charge('poll', 'AAAA', 1_000_000);
    expect(over.status).toBe(RATE_LIMITED);
    expect(over.window).toBe('minute');
    expect(over.retryAfter).toBeGreaterThan(0);
    expect(over.retryAfter).toBeLessThanOrEqual(60);
  });

  test('换一台设备就是另一份额度（主键是地址，不是 IP）', () => {
    const charge = createSenderQuota(tiny([['poll', { perMinute: 1, perDay: null }]])).charge;
    expect(charge('poll', 'AAAA', 1_000_000)).toBeNull();
    expect(charge('poll', 'AAAA', 1_000_000)).not.toBeNull();
    // 同一时刻、同一 IP（本层根本不知道 IP）—— 另一台设备照常
    expect(charge('poll', 'BBBB', 1_000_000)).toBeNull();
  });

  test('日档只在配了 perDay 的那一档存在，且 Retry-After 按天窗口算', () => {
    const charge = createSenderQuota(tiny([['message', { perMinute: 100, perDay: 2 }]])).charge;
    expect(charge('message', 'AAAA', 1_000_000)).toBeNull();
    expect(charge('message', 'AAAA', 1_000_000)).toBeNull();
    const over = charge('message', 'AAAA', 1_000_000);
    expect(over.window).toBe('day');
    expect(over.retryAfter).toBeGreaterThan(60);
    expect(over.retryAfter).toBeLessThanOrEqual(24 * 3600);
  });

  test('名单里没有的端点这一层不管（register 与未登记的都归 IP 层）', () => {
    const charge = createSenderQuota(tiny([])).charge;
    expect(charge('register', 'AAAA', 1_000_000)).toBeNull();
    expect(charge('neverHeardOfIt', 'AAAA', 1_000_000)).toBeNull();
  });

  test('数字全部来自契约：轮询那档是推导值，message 那档是固定值', () => {
    const derived = windows.senderWindows.get('poll');
    expect(derived.perMinute).toBe(windows.pollPerMinute);
    expect(derived.perDay).toBeNull();
    const fixed = windows.senderWindows.get('message');
    expect(fixed.perMinute).toBe(contract.limits.perSenderPerMinute);
    expect(fixed.perDay).toBe(contract.limits.perSenderPerDay);
    // 按设备那一档不许比匿名那档还紧（A1 的教训：比匿名档紧 ⇒ 先卡住的是自己人）
    expect(fixed.perMinute).toBeGreaterThanOrEqual(contract.limits.unauthenticatedPerMinute);
  });

  test('拦下时的响应形状：Retry-After + 契约里的码 + 空 body', () => {
    const reject = createSenderQuota(tiny([['ack', { perMinute: 1, perDay: null }]]));
    const calls = [];
    const res = {
      set: (k, v) => calls.push(['set', k, v]),
      status(code) {
        calls.push(['status', code]);
        return this;
      },
      json(body) {
        calls.push(['json', body]);
      },
    };
    expect(reject(res, 'ack', 'AAAA', 1_000_000)).toBe(false);
    expect(reject(res, 'ack', 'AAAA', 1_000_000)).toBe(true);
    expect(calls).toContainEqual(['set', 'Retry-After', expect.any(String)]);
    expect(calls).toContainEqual(['status', RATE_LIMITED]);
    expect(calls).toContainEqual(['json', {}]);
  });

  test('每个按发送方计的端点都必须在 routes.js 里有计额点（漏接＝静默只剩面闸门）', () => {
    const src = fs.readFileSync(path.join(__dirname, '../lib/fnthink/routes.js'), 'utf8');
    for (const kind of windows.senderWindows.keys()) {
      expect(src).toContain(`rejectIfOverQuota(res, '${kind}'`);
    }
  });

  test('计额点必须排在业务副作用之前（排在写表之后 = 拿额度当审计而不是闸门）', () => {
    const src = fs.readFileSync(path.join(__dirname, '../lib/fnthink/routes.js'), 'utf8');
    // 只在 /message 这一处判形状：它是唯一有"写表"这一步的入口，也最容易被人"顺手后置"。
    // 用 lastIndexOf 而不是 indexOf：后者只看得见第一处计额点，在后面补一处"审计式"的调用照样通过。
    const enqueueAt = src.indexOf('enqueue(');
    const lastChargeOfMessage = src.lastIndexOf("rejectIfOverQuota(res, 'message'");
    expect(enqueueAt).toBeGreaterThan(-1);
    expect(lastChargeOfMessage).toBeGreaterThan(-1);
    expect(lastChargeOfMessage).toBeLessThan(enqueueAt);
  });

  test('实现里没有第二份数字（额度只能从契约经 windowsFor 来）', () => {
    const src = fs.readFileSync(path.join(__dirname, '../lib/fnthink/senderquota.js'), 'utf8');
    expect(src).toContain('windowsFor');
    expect(src).not.toMatch(/perMinute:\s*\d/);
    expect(src).not.toMatch(/perDay:\s*\d/);
  });
});
