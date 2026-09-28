// fnthink 面的独立限流（#130 第一片）。
//
// 为什么必须在有端点之前就把 fnthink 从共享桶里拆出来 —— 这是我上一片（`bfafc2c`，开公网面）
// 自己带回来的缺陷：`store.rateLimitBucket()` 把任何 `/api/*` 都归进同一个 `api` 桶，
// 而那个桶的上限是 `RATE_LIMIT_GENERAL_MAX`（默认 60/分钟/每 IP）。于是
//  · 设备按 `presence.pollIntervalSeconds` 常规 poll 是 3 次/分钟，但 pending 提频
//    （`burstWhenPending` = 5s）是 12 次/分钟 —— 十几台设备就能把整桶吃满；
//  · 更要紧的是 `TRUST_PROXY` 没配时（默认 0 = 不信任何 X-Forwarded-For），Nginx 之后
//    **所有设备都算作同一个 IP** ⇒ 一次配置遗漏的表现是"推送与版本检查一起 429"，
//    而这正是本仓已经记过一次代价的那条旧教训 —— 这次是我亲手把新流量接到上面的。
// 拆桶之后：fnthink 的洪水只耗尽自己那一份额度，`/api/version/check`（升级通道）照常活着。
//
// 响应形状按协议走：状态码取契约 `statusCodes.rateLimited`、`Retry-After` 带秒数，
// 不复用后台那套 `{code:-4, message}` —— 那是管理面的错误契约，推给设备端就等于两端各抄一份形状。

'use strict';

const { statusCode, loadContract, assertSupported } = require('./contract');
const store = require('../store');

const contract = assertSupported(loadContract());
const WINDOW_MS = store.RATE_LIMIT_WINDOW_MS;

/// 键基数兜底：每个 IP 在这一层最多产生一条记录，但**不同 IP** 的数量仍随流量增长；
/// 沿用后台那条"先清过期、仍挤不进就不记账"的判据 —— 限流表本身不能变成
/// "一个请求换一条内存记录"的攻击面。
const MAX_KEYS = 20000;

function createFnthinkRateLimiter(maxRequests) {
  const max = Number(maxRequests);
  if (!Number.isFinite(max) || max <= 0) {
    throw new Error(
      'RATE_LIMIT_FNTHINK_MAX 必须是正整数（限流上限不许缺省成"不限"，也不许静默按 0 全拒）',
    );
  }
  const counters = new Map();

  const limiter = (req, res, next) => {
    const ip = store.getClientIp(req);
    const key = `${ip}:${store.rateLimitBucket(req.path)}`;
    const now = Date.now();

    let entry = counters.get(key);
    if (!entry || now - entry.windowStart > WINDOW_MS) {
      if (counters.size >= MAX_KEYS) {
        for (const [k, v] of counters) {
          if (now - v.windowStart > WINDOW_MS * 2) counters.delete(k);
        }
        if (counters.size >= MAX_KEYS) return next(); // 挤不进任何额度 ⇒ 这一发不记账
      }
      entry = { count: 0, windowStart: now };
      counters.set(key, entry);
    }

    entry.count += 1;
    if (entry.count > max) {
      res.set('Retry-After', String(Math.ceil((WINDOW_MS - (now - entry.windowStart)) / 1000)));
      // 体是空的：契约里 `receipts` 那八个词全是**投递结论**，没有哪一个能表示"被限流"，
      // 而 `statusCodes` 已经把 429 这一档定义清楚了 —— 宁可不带 body，也不发明一个回执词。
      return res.status(statusCode(contract, 'rateLimited')).json({});
    }
    next();
  };

  // 供守卫与测试读实际生效的口径（启动横幅也打这个数，别让人去猜 env 有没有生效）
  limiter.max = max;
  return limiter;
}

module.exports = { createFnthinkRateLimiter, MAX_KEYS, WINDOW_MS };
