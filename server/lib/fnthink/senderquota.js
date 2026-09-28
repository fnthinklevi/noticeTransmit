// 按发送方计的配额（#130-A2）——主键是**已证明身份的设备地址**，不是 IP。
//
// 为什么必须等验签之后才能计：请求体里的 `sender` 在验签之前只是一个字符串。按它计额的后果
// 不是"少拦了"，而是 **DoS 转移**：攻击者用受害者的地址发洪水，被 429 的是那个受害者。
// 所以这一层只有一处合法调用位置：**裁决/验签返回 ok 之后、业务副作用之前**。
//
// 为什么不能继续按 IP 计（A1 那一版就是这么写的）：真实部署里手机 + 手表 + 家里三台设备
// 在 Nginx 之后是同一个源，共用一份"每 IP 的端点额度"时，「同时配对两台」被判成攻击 ——
// A1 收成 6/分那一次，7 条配对路由用例就是替这种用户红的。⇒ 已证明身份的端点全部按设备地址计，
// 按 IP 那一档只留给 `register`（提交者还没有身份，那是唯一只能按 IP 计的一类）。
//
// 数字全部来自契约（`limits.perSenderPerMinute/Day` 与从 presence 推导的轮询额度），
// 这里不写任何字面量：A1 刚在限流上犯过"实现绕开契约自己定数"的错。
//
// ⚠ 被拦下时那一发 nonce 已经被登记（nonce 去重在裁决内部）。所以设备重试必须换 nonce ——
// 这与"签名时间容差内的重放"是同一件事，而设备端每次请求本来就生成新 nonce。

'use strict';

const { statusCode, loadContract, assertSupported } = require('./contract');
const { windowsFor } = require('./ratelimit');
const { sharedTracker } = require('./anomaly');

const DAY_MS = 24 * 60 * 60 * 1000;
const MINUTE_MS = 60 * 1000;

/// 键基数兜底：`sender`s 理论上被 devicesMax 框住，但"记录数不随请求数增长"这条得自己守住。
const MAX_KEYS = 20000;

/// ⚠ [observe] 只给测试注入用，缺省就是进程内那份告警环（anomaly.js）：留一个"测试专用"的
///   入口不等于生产能绕过它 —— 与 overrideWindows 同一个道理。
function createSenderQuota(overrideWindows, options = {}) {
  const contract = assertSupported(loadContract());
  const windows = overrideWindows || windowsFor(contract);
  const code = statusCode(contract, 'rateLimited');
  // ⚠ **构造期**就取单例，而不是等第一条请求：契约缺 alerts 段时 alertsFromContract 抛的是
  //   "可降级"的 SHAPE，只有让它发生在 lib/app.js 那段 try 里，结果才是"只降级这一段 + 横幅
  //   说破原因"。留到运行期就变成每条请求一个 500 —— 而 500 在设备端看起来像"服务器坏了"，
  //   会把一个永远不可能成功的请求重试三遍（A3 刚为同一个形状付过代价）。
  const tracker = sharedTracker();
  const observe = options.observe || ((event) => tracker.observe(event));
  const counters = new Map();

  function windowEntry(key, now, windowMs) {
    let entry = counters.get(key);
    if (entry && entry.expiresAt <= now) {
      counters.delete(key);
      entry = null;
    }
    if (!entry) {
      if (counters.size >= MAX_KEYS) {
        for (const [k, v] of counters) {
          if (v.expiresAt <= now) counters.delete(k);
        }
        if (counters.size >= MAX_KEYS) return null; // 挤不进 ⇒ 这一发不记账（与 IP 层同一判据）
      }
      entry = { count: 0, windowStart: now, expiresAt: now + windowMs };
      counters.set(key, entry);
    }
    return entry;
  }

  /// 记一发并判是否超限。返回 null = 放行；否则给出该回的码与 Retry-After 秒数。
  /// [sender] 必须是**规范化之后的地址码**（裁决层给的，不是请求体里那个字符串）。
  function charge(kind, sender, now) {
    const window = windows.senderWindows.get(kind);
    if (!window) return null; // 不在这两档里的端点（register / 未登记）由 IP 层管
    const when = now || Date.now();
    const minute = windowEntry(`${sender}:${kind}:m`, when, MINUTE_MS);
    if (minute) {
      minute.count += 1;
      const overMinute = minute.count > window.perMinute;
      // 告警与拦截读**同一个计数器**：拦下时记 denied，跨过契约那条 near 线时记 near。
      // 另开一份计数就是第二份真值，而它的表现是"日志里已经超额了，告警却说没事"。
      observe({
        subjectKind: 'device',
        subject: sender,
        kind,
        window: 'minute',
        count: minute.count,
        limit: window.perMinute,
        denied: overMinute,
        at: when,
      });
      if (overMinute) {
        return {
          status: code,
          retryAfter: Math.ceil((MINUTE_MS - (when - minute.windowStart)) / 1000),
          window: 'minute',
        };
      }
    }
    if (window.perDay) {
      const day = windowEntry(`${sender}:${kind}:d:${Math.floor(when / DAY_MS)}`, when, DAY_MS);
      if (day) {
        day.count += 1;
        const overDay = day.count > window.perDay;
        observe({
          subjectKind: 'device',
          subject: sender,
          kind,
          window: 'day',
          count: day.count,
          limit: window.perDay,
          denied: overDay,
          at: when,
        });
        if (overDay) {
          return {
            status: code,
            retryAfter: Math.ceil((DAY_MS - (when - day.windowStart)) / 1000),
            window: 'day',
          };
        }
      }
    }
    return null;
  }

  /// 路由里那一行的形状：拦下就直接答复，调用方 `if (rejectIfOverQuota(...)) return;`。
  function rejectIfOverQuota(res, kind, sender, now) {
    const over = charge(kind, sender, now);
    if (!over) return false;
    res.set('Retry-After', String(over.retryAfter));
    // body 为空：契约 `receipts` 那八个词全是投递结论，没有哪一个能表示"被你自己的配额拦了"。
    res.status(over.status).json({});
    return true;
  }

  rejectIfOverQuota.charge = charge;
  rejectIfOverQuota.windows = windows;
  return rejectIfOverQuota;
}

module.exports = { createSenderQuota, MAX_KEYS };
