// T185：长轮询的**进程内唤醒表**。
//
// 判据只有一条：一台设备在等货时，别每 25 秒重新发一次完整签名的 HTTP —— 服务端把请求
// hold 住，等真有它要拿的东西（新消息 / 回执 / 配对请求变化）再回答。
//
// ⚠ 这份表只在**单进程**里成立。本服务按单实例部署（Docker 一份 Node）；将来要横向扩，
//   这里必须换成跨进程的唤醒（Redis pub/sub 之类），否则设备连在 A 进程、消息落在 B 进程，
//   A 会一直 hold 到超时 —— 表现是「消息到了但最多晚一个 wait」而不是丢消息，仍是可接受的
//   降级，但不能假装它已经跨进程。
//
// ⚠ 不落盘、不记设备：等待是**一次请求的临时状态**，进程重启时那些连接本来就已经断了。

'use strict';

/// 设备地址码（已归一化）→ 该设备上正在等的 resolver 集合。
const waiters = new Map();

/// 同一台设备的**长连接订阅者**（T185 第二步的 SSE）。与 waiters 共用一次
/// `wakeDevice`：消息落盘时叫醒的既可能是「hold 着的 poll」，也可能是「挂着的流」。
const listeners = new Map();

function keyOf(device) {
  return String(device === undefined || device === null ? '' : device);
}

/**
 * 等这台设备下一次被唤醒，最多等 [timeoutMs]。返回 `true` = 被唤醒，`false` = 超时。
 *
 * 调用方必须在**已经取过一次货**之后才等（否则第一条消息可能刚好落在「取货」与
 * 「登记等待」之间，那一轮就要白等一个超时）。路由里的顺序正是如此。
 */
function waitForDevice(device, timeoutMs) {
  const key = keyOf(device);
  const wait = Math.max(0, Math.floor(Number(timeoutMs) || 0));
  if (key === '' || wait === 0) return Promise.resolve(false);

  return new Promise((resolve) => {
    const set = waiters.get(key) || new Set();
    waiters.set(key, set);
    let done = false;
    const finish = (woke) => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      set.delete(finish);
      if (set.size === 0) waiters.delete(key);
      resolve(woke);
    };
    // 先登记再起表：两者同一个 tick，不存在「表先响而 resolver 还没进集合」的窗口。
    const timer = setTimeout(() => finish(false), wait);
    set.add(finish);
  });
}

/// 订阅这台设备的唤醒（SSE 用）。返回取消订阅的函数 —— **必须**在连接关闭时调用，
/// 否则一台设备的每条连接都会在进程里留一行，直到进程重启。
function onWake(device, listener) {
  const key = keyOf(device);
  if (key === '' || typeof listener !== 'function') return () => {};
  const set = listeners.get(key) || new Set();
  listeners.set(key, set);
  set.add(listener);
  return () => {
    set.delete(listener);
    if (set.size === 0) listeners.delete(key);
  };
}

/// 叫醒这台设备上所有正在等的请求与订阅者。返回被叫醒的个数（日志/测试用，不参与判据）。
function wakeDevice(device) {
  const key = keyOf(device);
  const set = waiters.get(key);
  let count = 0;
  if (set) {
    count += set.size;
    for (const finish of Array.from(set)) finish(true);
  }
  const subs = listeners.get(key);
  if (subs) {
    count += subs.size;
    for (const fn of Array.from(subs)) {
      try {
        fn();
      } catch (e) {
        // 一条订阅者写失败（连接刚断）不该影响其它订阅者与 hold 中的 poll。
        console.error(`[fnthink:wake] 订阅者回调失败 device=${key}: ${e.message}`);
      }
    }
  }
  return count;
}

/// 当前等待中的请求数（测试用）。生产代码不读它。
function pendingWaiterCount() {
  let total = 0;
  for (const set of waiters.values()) total += set.size;
  return total;
}

/// 当前挂着的订阅者数（测试用）。生产代码不读它。
function subscriberCount() {
  let total = 0;
  for (const set of listeners.values()) total += set.size;
  return total;
}

module.exports = {
  waitForDevice,
  wakeDevice,
  onWake,
  pendingWaiterCount,
  subscriberCount,
};
