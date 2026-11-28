// T185：长轮询唤醒表的单元测试。
//
// 这一层只回答两件事：等待会在「被叫醒」或「超时」时结束；结束时那张表要回到空 ——
// 表漏一行就是一条永远挂在进程里的 resolver（wait 25 秒、每小时 144 条，泄漏得很慢，
// 但每一轮 poll 都会多一个）。路由层的行为在 `fnthink-routes.test.js` 的长轮询那一段。
'use strict';

const {
  waitForDevice,
  wakeDevice,
  onWake,
  pendingWaiterCount,
  subscriberCount,
} = require('../lib/fnthink/waiters');

describe('长轮询唤醒表（T185）', () => {
  test('叫醒在等的请求：返回 true，且表回到空', async () => {
    const waiting = waitForDevice('DEV-A', 5000);
    expect(pendingWaiterCount()).toBe(1);
    expect(wakeDevice('DEV-A')).toBe(1);
    await expect(waiting).resolves.toBe(true);
    expect(pendingWaiterCount()).toBe(0);
  });

  test('没人叫醒 ⇒ 到点返回 false，表也回到空', async () => {
    const t0 = Date.now();
    await expect(waitForDevice('DEV-B', 80)).resolves.toBe(false);
    expect(Date.now() - t0).toBeGreaterThanOrEqual(60);
    expect(pendingWaiterCount()).toBe(0);
  });

  test('同一台可以同时挂多个请求（多标签/多进程各一条），一并叫醒', async () => {
    const a = waitForDevice('DEV-C', 5000);
    const b = waitForDevice('DEV-C', 5000);
    expect(pendingWaiterCount()).toBe(2);
    expect(wakeDevice('DEV-C')).toBe(2);
    await expect(Promise.all([a, b])).resolves.toEqual([true, true]);
    expect(pendingWaiterCount()).toBe(0);
  });

  test('叫醒一个没人等的设备是空操作（不建表、不报错）', () => {
    expect(wakeDevice('DEV-NOBODY')).toBe(0);
    expect(wakeDevice('')).toBe(0);
    expect(pendingWaiterCount()).toBe(0);
  });

  test('T219：有 hold 中的请求就不敲门铃；没人 hold 时门铃照常响', async () => {
    const rang = [];
    const offD = onWake('DEV-D', () => rang.push('d'));
    const waiting = waitForDevice('DEV-D', 5000);

    // hold 那一发的响应里带着全部新东西（消息/回执/配对面）⇒ 不必再送一条 SSE。
    // 双路信号会让客户端在门铃回调里 abort 那条正带着货的长轮询（180 秒真空）。
    expect(wakeDevice('DEV-D')).toBe(1);
    expect(rang).toEqual([]);
    await expect(waiting).resolves.toBe(true);
    offD();

    // 没有 waiter 了 ⇒ 门铃是唯一的即时性来源，必须响。
    const offE = onWake('DEV-E', () => rang.push('e'));
    expect(wakeDevice('DEV-E')).toBe(1);
    expect(rang).toEqual(['e']);
    offE();
    expect(subscriberCount()).toBe(0);
  });
});
