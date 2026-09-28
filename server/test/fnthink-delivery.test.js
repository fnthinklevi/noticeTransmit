'use strict';

// 投递状态机（T34）的 **Node 侧**向量断言。Dart 那一半在
// packages/fnthink_push/test/delivery_test.dart，两边吃同一份
// protocol/fnthink-vectors-v1.json 的 delivery 段。
//
// 这条链一半在服务端（排队、到期、挤位）一半在设备上（ack、重发）。两边判得不一样时
// 不会报错，只会变成「设备以为还能重试、服务端已经转 waiting_online」—— 而中间态
// 意味着那条消息的正文一直留着删不掉。共享向量就是为了让这种分叉在 CI 里红，
// 而不是在用户手机上红。

const fs = require('fs');
const path = require('path');

const { loadContract, assertSupported } = require('../lib/fnthink/contract');
const delivery = require('../lib/fnthink/delivery');

const contract = assertSupported(loadContract());
const vectors = JSON.parse(
  fs.readFileSync(path.join(__dirname, '..', '..', 'protocol', 'fnthink-vectors-v1.json'), 'utf8'),
);
const cases = vectors.delivery;

const statesOf = () => contract.delivery.states;
const eventsOf = () => contract.delivery.events;

describe('投递状态机向量（Node 侧，T34-A）', () => {
  test('向量非空，且状态/事件都取自契约', () => {
    expect(cases.length).toBeGreaterThan(0);
    for (const c of cases) {
      expect(statesOf()).toContain(c.given.state);
      expect(eventsOf()).toContain(c.given.event);
      expect(statesOf()).toContain(c.expect.state);
      if (c.expect.receipt) expect(contract.receipts).toContain(c.expect.receipt);
    }
  });

  test.each(cases.map((c) => [c.id, c]))('%s：逐字段对上', (_id, c) => {
    const got = delivery.advance(contract, c.given);
    expect(got).toEqual({
      state: c.expect.state,
      attempts: c.expect.attempts,
      receipt: c.expect.receipt,
      deleteBody: c.expect.deleteBody,
      resend: c.expect.resend,
      ignored: c.expect.ignored,
    });
  });

  test('覆盖：契约迁移表每条边都至少被一例走到', () => {
    const covered = new Set(
      cases.filter((c) => !c.expect.ignored).map((c) => `${c.given.state}->${c.expect.state}`),
    );
    const missing = [];
    for (const [from, targets] of Object.entries(contract.delivery.transitions)) {
      for (const to of targets) if (!covered.has(`${from}->${to}`)) missing.push(`${from}->${to}`);
    }
    expect(missing).toEqual([]);
  });

  test('乱序与迟到：状态、尝试数、回执都不动，且没有副作用', () => {
    for (const c of cases.filter((x) => x.expect.ignored)) {
      const got = delivery.advance(contract, c.given);
      expect(got.state).toBe(c.given.state);
      expect(got.attempts).toBe(c.given.attempts);
      expect(got.receipt).toBeNull();
      expect(got.deleteBody).toBe(false);
      expect(got.ignored).toBe(`ignored:${c.given.state}+${c.given.event}`);
    }
  });

  test('未知状态 / 未知事件直接抛（编程错误，不是网络噪声）', () => {
    expect(() =>
      delivery.advance(contract, { state: 'teleporting', event: 'dispatch', attempts: 0 }),
    ).toThrow();
    expect(() =>
      delivery.advance(contract, { state: 'queued', event: 'reboot', attempts: 0 }),
    ).toThrow();
  });
});

describe('正文释放与保留上限（T34-A）', () => {
  test('每个终态都释放正文，非终态都不释放', () => {
    const terminals = contract.delivery.terminalStates;
    expect(terminals.length).toBeGreaterThan(0);
    for (const s of statesOf()) {
      const isTerminal = terminals.includes(s);
      expect(delivery.releasesBody(contract, s)).toBe(isTerminal);
    }
  });

  test('重试预算：1 次首投 + 契约的 deliveryRetryTotal', () => {
    expect(delivery.maxAttempts(contract)).toBe(contract.limits.deliveryRetryTotal + 1);
    expect(delivery.maxAttempts(contract)).toBe(3);
  });

  test('补发路向二选一（并存就是同一条消息提醒两次）', () => {
    const budget = delivery.maxAttempts(contract);
    const withBackup = delivery.advance(contract, {
      state: 'delivering',
      event: 'no_ack',
      attempts: budget,
      hasBackupChannel: true,
    });
    const withoutBackup = delivery.advance(contract, {
      state: 'delivering',
      event: 'no_ack',
      attempts: budget,
    });
    expect(withBackup.resend).toBe(contract.waitingOnline.withBackupChannel);
    expect(withoutBackup.resend).toBe(contract.waitingOnline.withoutBackupChannel);
    expect(withBackup.resend).not.toBe(withoutBackup.resend);
  });

  test('挤位：算出要丢几条最旧的，每条都带 dropped 回执', () => {
    const max = contract.retention.pendingPerDeviceMax;
    expect(max).toBe(200);
    expect(delivery.evictCount(contract, max - 1)).toBe(0);
    expect(delivery.evictCount(contract, max)).toBe(1);
    expect(delivery.evictCount(contract, max + 4, 3)).toBe(7);
    expect(delivery.evictionReceipts(contract)).toEqual([contract.retention.overflowReceipt]);
    expect(contract.retention.overflowReceipt).toBe('dropped');
  });

  test('到期判定按契约的 maxRetentionDays，边界是"到点即过期"', () => {
    const dayMs = 24 * 60 * 60 * 1000;
    const days = contract.retention.maxRetentionDays;
    expect(delivery.isExpired(contract, 0, days * dayMs - 1)).toBe(false);
    expect(delivery.isExpired(contract, 0, days * dayMs)).toBe(true);
  });

  test('终态没有出边；初态取自契约', () => {
    expect(delivery.initialState(contract)).toBe(contract.delivery.initialState);
    for (const t of contract.delivery.terminalStates) {
      expect(delivery.isTerminal(contract, t)).toBe(true);
      expect(delivery.canTransition(contract, t, 'queued')).toBe(false);
    }
  });
});
