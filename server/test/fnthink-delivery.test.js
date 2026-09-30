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
      // 步里带回是哪一个事件推进的（T45 第二片的留痕读这一格）。它**不进共享向量表**：
      // 向量表说的是"哪个状态遇哪个事件走到哪"，而事件名本来就是 given 的一部分，
      // 写进 expect 那份就是把同一个数抄两遍。
      event: c.given.event,
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

/// 「取走了没等到 ack」的恢复（#178 真机现形的那条路）。Dart 那一半在
/// packages/fnthink_push/test/delivery_test.dart，两边读契约同一个 ackDeadlineSeconds。
///
/// 为什么这一组不进共享向量：共享向量只覆盖「状态×事件 → 迁移」这一张表，而这一档是
/// **时间判据**（超过多少秒算没等到 ack），形状与那张表不同 —— 混进去会让覆盖率校验失真。
/// 两边各断言一遍同样的边界（到点即算超时 / 差一点不算），是同一道纪律的两种写法。
describe('ack 超时判据（Node 侧，#178）', () => {
  const deadline = delivery.ackDeadlineSeconds(contract);

  test('档位取自契约，且远大于一轮 poll（太紧会把正常往返误判成丢 ack）', () => {
    expect(deadline).toBe(contract.delivery.ackDeadlineSeconds);
    expect(deadline).toBeGreaterThan(0);
    expect(deadline).toBeGreaterThanOrEqual(contract.presence.pollIntervalSeconds.max * 3);
  });

  test('到点即算超时，差一点不算（边界是"到点即过"）', () => {
    const since = 1000 * 1000;
    const inflight = (state) => ({ state, updatedAt: since });
    expect(
      delivery.isAckOverdue(contract, inflight('delivering'), since + deadline * 1000 - 1),
    ).toBe(false);
    expect(delivery.isAckOverdue(contract, inflight('delivering'), since + deadline * 1000)).toBe(
      true,
    );
  });

  test('只有 delivering 才算超时：没发出去的（queued）与终态都不该被判成 no_ack', () => {
    const since = 1000 * 1000;
    const far = since + deadline * 1000 * 10;
    for (const state of ['queued', 'waiting_online', 'delivered', 'expired', 'dropped']) {
      expect(delivery.isAckOverdue(contract, { state, updatedAt: since }, far)).toBe(false);
    }
  });

  test('没有进入 delivering 的时刻就不猜（缺 updatedAt 一律不算超时）', () => {
    expect(delivery.isAckOverdue(contract, { state: 'delivering' }, Date.now())).toBe(false);
    expect(
      delivery.isAckOverdue(contract, { state: 'delivering', updatedAt: null }, Date.now()),
    ).toBe(false);
  });

  test('缺了 ackDeadlineSeconds 就抛（不补默认：不扫就等于永不失联）', () => {
    const broken = { ...contract, delivery: { ...contract.delivery } };
    delete broken.delivery.ackDeadlineSeconds;
    expect(() => delivery.ackDeadlineSeconds(broken)).toThrow(/ackDeadlineSeconds/);
    const zero = { ...contract, delivery: { ...contract.delivery, ackDeadlineSeconds: 0 } };
    expect(() => delivery.ackDeadlineSeconds(zero)).toThrow(/ackDeadlineSeconds/);
  });
});
