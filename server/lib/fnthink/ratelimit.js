// fnthink 面的独立限流（#130 第一片 + A1 第二片）。
//
// 为什么必须在有端点之前就把 fnthink 从共享桶里拆出来 —— 那是 `bfafc2c`（开公网面）自己
// 带回来的缺陷：`store.rateLimitBucket()` 把任何 `/api/*` 都归进同一个 `api` 桶，上限是
// `RATE_LIMIT_GENERAL_MAX`（默认 60/分钟/每 IP）。于是
//  · 设备按 `presence.pollIntervalSeconds` 常规 poll 是 3 次/分钟，但 pending 提频
//    （`burstWhenPending` = 5s）是 12 次/分钟 —— 十几台设备就能把整桶吃满；
//  · 更要紧的是 `TRUST_PROXY` 没配时（默认 0 = 不信任何 X-Forwarded-For），Nginx 之后
//    **所有设备都算作同一个 IP** ⇒ 一次配置遗漏的表现是"推送与版本检查一起 429"，
//    而这正是本仓已经记过一次代价的那条旧教训。
// 拆桶之后：fnthink 的洪水只耗尽自己那一份额度，`/api/version/check`（升级通道）照常活着。
//
// A1 补第二件事：**契约里那两个数原先只写了大小，没写"量谁"**（endpointPerMinute /
// endpointPerDay），于是实现整个绕开它们改用环境变量 ⇒ 两份真值。而照字面把 15/分、500/天
// 套到所有端点上会立刻炸：常态 20 秒一次的轮询本来就是 4320 次/天，比 500 大一个数量级。
// 现在三层各管一件事，每层的"量谁"都写在契约上：
//   层 1（整个面 / 每 IP）  = 环境变量 `RATE_LIMIT_FNTHINK_MAX`，防一个 IP 扇出打一万个端点；
//   层 2（`limits.perEndpoint`）= **身份还没证明**的那一类（目前只有 register），分钟 + 日两档，
//     取的数已随定名改成 `unauthenticatedPerMinute` / `unauthenticatedPerDay`；
//   层 3（`limits.cadenceGoverned`）= 轮询类，分钟档**从 presence 的节奏参数推导**，日档故意不设；
//   `limits.perSenderOnly` = 签名已能证明是谁的操作（配对三步）+ 产品主路径 /message。
//   这一组**不许按 IP 计**：手机 + 手表 + 家里三台在 Nginx 之后是同一个源，共用一份"控制类"
//   额度等于把「同时配对两台」判成攻击 —— 本仓 7 条配对路由用例第一次跑就是这么红的，
//   不是推演。真正的按发送方（设备地址）配额是 A2 的活；在那之前这一组只受层 1 管。
//   为什么列成名单而不是在实现里写 if (path === '/message')：漏登记的端点会被按最紧的一档
//   拦下并留痕点名，而写死的分支只会静默地不受任何专项限流。
// ⚠ 数字也改了：原先 15 ≥ 轮询推导额度 60÷5+2=14，即"身份未证明的那一类反而比正常轮询宽松"，
// 次序是反的 ⇒ 收到 6。而旧名 `endpointPerMinute` 读起来像"所有端点共用一把尺"，
// 那个读法本身就是错的 —— 名字错了，下一个人就会照着错的那个实现。
//
// 响应形状按协议走：状态码取契约 `statusCodes.rateLimited`、`Retry-After` 带秒数，
// 不复用后台那套 `{code:-4, message}` —— 那是管理面的错误契约，推给设备端等于两端各抄一份。

'use strict';

const { statusCode, loadContract, assertSupported, shapeError } = require('./contract');
const { sharedTracker, FACE_KIND } = require('./anomaly');
const store = require('../store');

const contract = assertSupported(loadContract());
const WINDOW_MS = store.RATE_LIMIT_WINDOW_MS;
const DAY_MS = 24 * 60 * 60 * 1000;

/// 键基数兜底：记录数随"不同 IP × 不同端点"增长，沿用后台那条"先清过期、仍挤不进就不记账"
/// 的判据 —— 限流表本身不能变成"一个请求换一条内存记录"的攻击面。
const MAX_KEYS = 20000;

/// URL 段 → 契约里的事件种类：端点用短横线，契约键用驼峰（`pair-arm` ↔ `pairArm`）。
/// ⚠ 不另列一份端点清单：守卫拿路由真实挂载的路径来对这张名单（见 fnthink-ratelimit.test.js）。
function endpointKindOf(path) {
  const tail = String(path).split('?')[0].split('/').filter(Boolean).pop();
  if (!tail) return '';
  return tail.replace(/-([a-z])/g, (_, c) => c.toUpperCase());
}

function pickAt(src, path) {
  return path.reduce(
    (node, key) => (node && typeof node === 'object' ? node[key] : undefined),
    src,
  );
}

/// 从契约推导各档窗口。**取不到正数就抛**，不许缺省成"不限"：一份读不出数字的契约表，
/// 正确行为是启动失败，不是悄悄把所有端点放进无限档。
function windowsFor(src) {
  const intOf = (path) => {
    const v = pickAt(src, path);
    if (!Number.isInteger(v) || v <= 0) {
      throw shapeError(`限流推导取不到正整数：${path.join('.')}（实际 ${v}）`);
    }
    return v;
  };
  const listOf = (path) => {
    const v = pickAt(src, path);
    if (!Array.isArray(v)) {
      throw shapeError(`${path.join('.')} 必须是数组：限流不知道"量谁"就会各自猜`);
    }
    return v.map(String);
  };
  const control = listOf(['limits', 'perEndpoint']);
  const cadence = listOf(['limits', 'cadenceGoverned']);
  const senderOnly = listOf(['limits', 'perSenderOnly']);
  if (!control.length) {
    throw shapeError('limits.perEndpoint 不能为空：那两个数字总得有一组端点归它管');
  }
  const seen = new Map();
  const clash = [];
  for (const [name, keys] of Object.entries({
    perEndpoint: control,
    cadenceGoverned: cadence,
    perSenderOnly: senderOnly,
  })) {
    for (const k of keys) {
      if (seen.has(k)) clash.push(`${k}（${seen.get(k)} 与 ${name}）`);
      else seen.set(k, name);
    }
  }
  if (clash.length) {
    throw shapeError(
      `limits 的端点名单重叠：${clash.join('、')} ⇒ 同一个端点两把尺子，` +
        '谁先响取决于实现顺序，那是"看起来更严其实更宽"的形状',
    );
  }
  const perMinute = intOf(['limits', 'unauthenticatedPerMinute']);
  const perDay = intOf(['limits', 'unauthenticatedPerDay']);
  const senderPerMinute = intOf(['limits', 'perSenderPerMinute']);
  const senderPerDay = intOf(['limits', 'perSenderPerDay']);
  if (senderPerMinute < perMinute) {
    throw shapeError(
      `limits.perSenderPerMinute=${senderPerMinute} 比按 IP 的 unauthenticatedPerMinute=${perMinute} 还紧：` +
        '已证明身份的端点按设备地址计，这一档的意义是"跑飞保护"而不是反垃圾 —— 比匿名档还紧，' +
        '先被卡住的只会是自己人（A1 那次 7 条配对用例就是替这种用户红的）',
    );
  }
  const burst = intOf(['presence', 'burstWhenPending', 'intervalSeconds']);
  const slack = intOf(['limits', 'pollBurstSlack']);
  // 轮询侧额度是**推导**出来的，不是第四个凭空的数：提频 5 秒一次 ⇒ 12 次/分，
  // 再加 pollBurstSlack 份余量（提频与常态切换的那一分钟里，两种节奏会重叠计数）。
  const pollPerMinute = Math.ceil(60 / burst) + slack;
  if (perMinute < pollPerMinute) {
    throw shapeError(
      `limits.unauthenticatedPerMinute=${perMinute} 严于轮询推导额度（${pollPerMinute}）：` +
        '按 IP 计的端点额度只能当洪水闸 —— 卡紧它误伤的是「家里一次装四台设备」的诚实用户，' +
        '而攻击者换一个 IP 的成本是零。未认证写入的兜底是 limits.devicesMax 与面的总量闸门',
    );
  }
  return {
    controlKinds: new Set(control),
    cadenceKinds: new Set(cadence),
    senderOnlyKinds: new Set(senderOnly),
    controlWindow: { perMinute, perDay },
    cadenceWindow: { perMinute: pollPerMinute },
    pollPerMinute,
    // A2：按**发送方设备地址**计的那两档（验签之后才记，见 senderquota.js）。
    // perSenderOnly 用契约里固定的一对数；cadenceGoverned 用从 presence 推导的数、日档不设。
    senderWindows: new Map([
      ...senderOnly.map((k) => [k, { perMinute: senderPerMinute, perDay: senderPerDay }]),
      ...cadence.map((k) => [k, { perMinute: pollPerMinute, perDay: null }]),
    ]),
  };
}

const contractWindows = windowsFor(contract);

function createFnthinkRateLimiter(maxRequests, overrideWindows, options = {}) {
  const max = Number(maxRequests);
  if (!Number.isFinite(max) || max <= 0) {
    throw new Error(
      'RATE_LIMIT_FNTHINK_MAX 必须是正整数（限流上限不许缺省成"不限"，也不许静默按 0 全拒）',
    );
  }
  // ⚠ [observe] 只给测试注入，缺省就是进程内那份告警环（A4）：告警与闸门必须读**同一个**计数器，
  //   另开一份计数就是第二份真值，表现是"已经超额了而告警说没事"。
  // ⚠ 同样在**构造期**取单例（与 senderquota.js 那条同因）：契约缺 alerts 段必须在这里抛，
  //   才能被 lib/app.js 的降级 catch 接住，而不是让每条请求变成 500。
  const tracker = sharedTracker();
  const observe = options.observe || ((event) => tracker.observe(event));
  // 第二份窗口只给测试注入用（日档 500 次不可能在单测里真打满）。
  // ⚠ 缺省仍然是**契约推导的那一份**：留一个"测试专用"的入口不等于生产能绕过它。
  const windows = overrideWindows || contractWindows;
  /** key → { count, windowStart, expiresAt }；过期判定按**窗口结束**，不按固定 WINDOW_MS ——
   *  日档的窗口长度是 DAY_MS，用 2×分钟去扫会把日计数器在两分钟后当垃圾清掉。 */
  const counters = new Map();
  const warned = new Set();

  function deny(res, now, entry, spanMs, note) {
    res.set('Retry-After', String(Math.ceil((spanMs - (now - entry.windowStart)) / 1000)));
    if (note && !warned.has(note)) {
      warned.add(note);
      // 没登记进任何名单的端点：按控制类（最紧的那把）量，并**留痕点名**，不静默。
      console.warn(`[fnthink:ratelimit] 端点种类未登记，已按控制类额度拦下：${note}`);
    }
    // 体是空的：契约里 `receipts` 那八个词全是**投递结论**，没有哪一个能表示"被限流"，
    // 而 `statusCodes` 已经把 429 这一档定义清楚了 —— 宁可不带 body，也不发明一个回执词。
    return res.status(statusCode(contract, 'rateLimited')).json({});
  }

  /// 取（必要时新建）一个窗口计数器。返回 null = 表已满且清不出空间 ⇒ 这一发不记账。
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
        if (counters.size >= MAX_KEYS) return null;
      }
      entry = { count: 0, windowStart: now, expiresAt: now + windowMs };
      counters.set(key, entry);
    }
    return entry;
  }

  const limiter = (req, res, next) => {
    const ip = store.getClientIp(req);
    const now = Date.now();
    const kind = endpointKindOf(req.path);

    // 层 1：整个 fnthink 面按 IP 的总量闸门（原来那把，行为不变）。
    const faceKey = `${ip}:${store.rateLimitBucket(req.path)}`;
    const face = windowEntry(faceKey, now, WINDOW_MS);
    if (face) {
      face.count += 1;
      const overFace = face.count > max;
      // 层 1 的数字来自环境变量而不是契约，所以这里给它一个明确的 kind（FACE_KIND）：
      // 否则"一个 IP 扇出打一万个端点"与"某个端点被玩坏"在告警里长成同一个样子。
      observe({
        subjectKind: 'ip',
        subject: ip,
        kind: FACE_KIND,
        window: 'minute',
        count: face.count,
        limit: max,
        denied: overFace,
        at: now,
      });
      if (overFace) return deny(res, now, face, WINDOW_MS);
    }

    // 已证明身份的端点（poll / ack / 配对三步 / message）一律**不在这层按 IP 记**：
    // 它们的主键是设备地址，计额点在验签之后（senderquota.js）。留在这里按 IP 记，
    // 反代之后"手机 + 手表 + 家里三台"共用一个源时先被卡住的是自己人 —— A1 那次 7 条红就是这个形状。
    if (windows.senderWindows.has(kind)) return next();

    const isControl = windows.controlKinds.has(kind);
    // 未登记的种类 ⇒ 按控制类量（宁可限紧），并留痕。
    const window = windows.controlWindow;
    const note = isControl ? null : kind;

    const minuteKey = `${ip}:${kind}:m`;
    const minute = windowEntry(minuteKey, now, WINDOW_MS);
    if (minute) {
      minute.count += 1;
      const overMinute = minute.count > window.perMinute;
      observe({
        subjectKind: 'ip',
        subject: ip,
        kind,
        window: 'minute',
        count: minute.count,
        limit: window.perMinute,
        denied: overMinute,
        at: now,
      });
      if (overMinute) return deny(res, now, minute, WINDOW_MS, note);
    }
    if (isControl) {
      // 日档把日期编进键里，换日自然换新计数器（旧键由过期清扫回收）。
      const dayKey = `${ip}:${kind}:d:${Math.floor(now / DAY_MS)}`;
      const day = windowEntry(dayKey, now, DAY_MS);
      if (day) {
        day.count += 1;
        const overDay = day.count > window.perDay;
        observe({
          subjectKind: 'ip',
          subject: ip,
          kind,
          window: 'day',
          count: day.count,
          limit: window.perDay,
          denied: overDay,
          at: now,
        });
        if (overDay) return deny(res, now, day, DAY_MS);
      }
    }
    next();
  };

  // 供守卫与测试读实际生效的口径（启动横幅也打这些数，别让人去猜 env 与契约谁生效）
  limiter.max = max;
  limiter.windows = windows;
  return limiter;
}

/// 给启动横幅与运维看的"这个端点受哪一档管"。它必须**由同一份 windows 说出来**，
/// 而不是在 server.js 里再抄一句"限流 N/分钟/每 IP" —— 三档各管不同端点之后，
/// 那句笼统的话对 /poll 和 /register 都是错的，而运维照着错的日志去调 env 只会更糟。
function describeKind(kind) {
  const sender = contractWindows.senderWindows.get(kind);
  if (sender) {
    const day = sender.perDay ? ` · ${sender.perDay}/天` : '（无日档）';
    const from = contractWindows.cadenceKinds.has(kind) ? '数字从 presence 节奏推导' : '契约固定值';
    return `按设备地址 ${sender.perMinute}/分钟${day}（${from}，验签后计）`;
  }
  if (contractWindows.controlKinds.has(kind)) {
    return `按 IP ${contractWindows.controlWindow.perMinute}/分钟 · ${contractWindows.controlWindow.perDay}/天（身份未证明，只能按 IP）`;
  }
  return `未登记 ⇒ 按最紧的一档（${contractWindows.controlWindow.perMinute}/分钟）拦下并留痕点名`;
}

module.exports = {
  createFnthinkRateLimiter,
  windowsFor,
  endpointKindOf,
  describeKind,
  MAX_KEYS,
  DAY_MS,
  WINDOW_MS,
};
