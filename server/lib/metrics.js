'use strict';
/**
 * T187 片1：服务端指标面 —— Prometheus 文本 exposition，零新依赖。
 *
 * 为什么不引 prom-client（roadmap §6 定的"手写"，理由记在这儿免得下次又被"顺手升级"）：
 * 本仓服务端的依赖面刻意只有六枚（bcryptjs/cors/dotenv/express/otplib/qrcode），而这里
 * 只需要**计数器 + 直方图 + 采集时求值**三种原语；prom-client 多给的是指数分桶、聚合器
 * 这些从没要过的形态，代价是多一条依赖链要跟着 CVE 走。
 *
 * 三族：
 *  · 进程面 `notice_process_*` —— 抓取时现算（uptime / heap / rss / 事件循环滞后 / 版本）。
 *  · HTTP 面 `notice_http_*`  —— 挂在链条最前面的 finish 钩子：计数 + 时延直方图 + 在飞数。
 *  · 安全面 `notice_security_*` —— 认证失败 / 因封锁被拒 / 封锁真的发生了。
 *
 * ⚠ 基数与隐私纪律（三条都是判据，不是口头约定；各有一条用例与一条植入对着它们）：
 *  1. 标签**只有**路由模板（`req.baseUrl + req.route.path`，段里是 `:param` 名而不是取值）、
 *     HTTP 方法白名单、状态码。没匹配到路由的请求一律归到 `store.rateLimitBucket` 那四个桶，
 *     **永不**把原始 path/query 写进标签 —— 否则一条随机路径就是一条永久新时间序列（内存无上限），
 *     而地址码与端点密钥恰好住在路径段里（`/api/fnthink/p/:endpointId/:secret`）。
 *  2. 指标里**没有**正文、凭据、token、地址码：文本渲染只碰本模块登记的数。
 *  3. 一个家族的系列数封顶 `MAX_SERIES_PER_FAMILY`；超出的新标签组合丢弃并计入
 *     `notice_metrics_series_overflow_total` —— 丢弃必须看得见，不能静默变成"这条线没了"。
 *
 * 两个开关（都在**请求时**读 env，不缓存进模块，与 `lib/routes/echo.js` 同一条理由：
 * 测试逐条换环境不用重启进程）：
 *  · `METRICS_ENABLED` 缺省＝开；`0/false/no/off`（大小写不敏感）＝既不采集也不出声。
 *  · `METRICS_TOKEN` 没配 ⇒ `/metrics` 透传给应用级 404，与未知路由**同形**。这是刻意选的
 *    fail-closed 默认，不是漏配：本仓实测过"反代静态根=代码目录"把 totp.json/sessions.json
 *    暴露出去那一次（#139），而指标面天生是"给外面看的运维读数"。
 *  ⚠ 同时在这里定稿 roadmap 欠的第三态：**`/metrics` 不进 IP 封锁豁免名单**。豁免只给
 *    "误封代价大于滥用代价"的口（/health 是整机心跳、/api/version 是所有设备的更新检查、
 *    /api/fnthink 靠签名而非封 IP 保护）；指标面恰好相反——被洪水打正是最需要留痕的场景，
 *    而封掉它只损失读数，不损失任何用户功能。
 */

const { monitorEventLoopDelay } = require('perf_hooks');

const express = require('express');

const { tokenMatches } = require('./token_compare');

// ========== 开关 ==========

const FALSY = new Set(['0', 'false', 'no', 'off']);

/** 采集与出声的总开关：缺省开（roadmap 拍的"默认开"），显式假值才关。 */
function isCollectEnabled() {
  const raw = process.env.METRICS_ENABLED;
  if (raw === undefined || String(raw).trim() === '') return true;
  return !FALSY.has(String(raw).trim().toLowerCase());
}

/** 读口口令；没配或全空白 ⇒ 空串（＝端点不存在）。两侧都 trim：`.env` 里尾随空格是经典"配了却永远 401"。 */
function metricsToken() {
  const raw = process.env.METRICS_TOKEN;
  return typeof raw === 'string' ? raw.trim() : '';
}

// ========== 名称与标签的形状约束 ==========

const NAME_SHAPE = /^[a-zA-Z_:][a-zA-Z0-9_:]*$/;
const LABEL_NAME_SHAPE = /^[a-zA-Z_][a-zA-Z0-9_]*$/;
// 标签值可能被失控长度（未来的 bug、外来的怪字符串）撑爆：截断而不是抛，
// 抛会让指标面在异常输入面前自己 500，而那正是排障时最不需要的东西。
const LABEL_VALUE_MAX = 120;
const MAX_SERIES_PER_FAMILY = 500;
// HTTP 方法来自请求行，攻击者可任意伪造 ⇒ 只认这九枚，其余折成 OTHER（否则一发一个方法名
// 的洪水就是"每条请求新建一条永久时间序列"，与标签带原始 path 是同一种事故）。
const HTTP_METHODS = new Set([
  'GET',
  'HEAD',
  'POST',
  'PUT',
  'PATCH',
  'DELETE',
  'OPTIONS',
  'CONNECT',
  'TRACE',
]);
// 路由模板允许 `:`（参数名）而不允许空格/百分号/查询串 —— 真出现意外形状就折成 other，
// 不冒原始路径。
const ROUTE_SHAPE = /^\/[A-Za-z0-9_:/.\-]{0,120}$/;

function assertName(name) {
  if (typeof name !== 'string' || !NAME_SHAPE.test(name)) {
    throw new TypeError(`不是合法的指标名：${String(name)}`);
  }
}

function escapeLabelValue(value) {
  return String(value)
    .slice(0, LABEL_VALUE_MAX)
    .replace(/\\/g, '\\\\')
    .replace(/"/g, '\\"')
    .replace(/\n/g, '\\n');
}

function escapeHelp(text) {
  return String(text).replace(/\\/g, '\\\\').replace(/\n/g, '\\n');
}

function formatValue(v) {
  const n = Number(v);
  if (Number.isNaN(n)) return 'NaN';
  if (n === Number.POSITIVE_INFINITY) return '+Inf';
  if (n === Number.NEGATIVE_INFINITY) return '-Inf';
  return String(n);
}

// ========== 注册表 ==========

// 声明顺序即渲染顺序：三族各成一段，人肉 curl 时读得动。
const registry = new Map();
const warnedExtraLabels = new Set();

function declare(name, type, help, labelNames) {
  assertName(name);
  const ln = labelNames || [];
  for (const one of ln) {
    if (typeof one !== 'string' || !LABEL_NAME_SHAPE.test(one)) {
      throw new TypeError(`不是合法的标签名：${String(one)}`);
    }
  }
  if (registry.has(name)) {
    // 重复声明多半是"同一个指标在两处各写一份"——那正是本片要消灭的形状，崩在加载期。
    throw new Error(`指标重复声明：${name}`);
  }
  const family = { name, type, help, labelNames: ln, series: new Map() };
  registry.set(name, family);
  return family;
}

/**
 * 把调用方给的标签收敛成"家族声明的那几枚、按声明顺序"的键串。
 * 多余键忽略并一次性打日志（不静默）；缺失键取空串——空串是"这一维没读数"，
 * 而整枚标签忽隐忽现会让同一家族出现两种形状的样本行，解析端按不同指标处理。
 */
function labelKeyOf(family, labels) {
  const given = labels && typeof labels === 'object' ? labels : {};
  const extra = Object.keys(given).filter((k) => !family.labelNames.includes(k));
  if (extra.length > 0) {
    const tag = `${family.name}:${extra.join(',')}`;
    if (!warnedExtraLabels.has(tag)) {
      warnedExtraLabels.add(tag);
      console.error(
        `[metrics] 忽略未声明的标签：${family.name} 收到 ${extra.join(',')}（只认 ${
          family.labelNames.join(',') || '无标签'
        }）`,
      );
    }
  }
  return family.labelNames
    .map((ln) => {
      const v = given[ln];
      return `${ln}="${escapeLabelValue(v === undefined || v === null ? '' : v)}"`;
    })
    .join(',');
}

function seriesOf(family, labels) {
  const key = labelKeyOf(family, labels);
  let s = family.series.get(key);
  if (s) return s;
  if (family.series.size >= MAX_SERIES_PER_FAMILY) {
    // 丢弃必须看得见：这条计数就是"指标面自己溢出了"的读数。
    const overflow = registry.get('notice_metrics_series_overflow_total');
    if (overflow && family !== overflow) incSeries(overflow, { family: family.name }, 1);
    return null;
  }
  s = { labels: key, value: 0, buckets: null, sum: 0, count: 0 };
  family.series.set(key, s);
  return s;
}

function incSeries(family, labels, delta) {
  const s = seriesOf(family, labels);
  if (!s) return;
  const v = Number(delta);
  if (!Number.isFinite(v)) return;
  s.value = (s.value || 0) + v;
}

// ---- 三种原语 ----

/** 单调计数器。名字自带 `_total` 后缀由调用方写全（自动补＝两处权威，早晚一边补一边不补）。 */
function counter(name, { help, labelNames = [] }) {
  const family = declare(name, 'counter', help, labelNames);
  return {
    inc(labelsOrDelta, delta) {
      if (typeof labelsOrDelta === 'number') return incSeries(family, null, labelsOrDelta);
      incSeries(family, labelsOrDelta, delta === undefined ? 1 : delta);
    },
  };
}

/**
 * 直方图：分桶上界（毫秒/字节皆可，由单位写进 HELP）+ 隐式 +Inf。
 * 观测值落在"第一个 ≥ 它的上界"桶里，同时所有更大的桶也 +1（Prometheus 的 `_bucket` 是**累积**的）。
 */
function histogram(name, { help, labelNames = [], buckets }) {
  const sorted = [...new Set(buckets.filter((b) => Number.isFinite(b) && b >= 0))].sort(
    (a, b) => a - b,
  );
  if (sorted.length === 0) throw new Error(`直方图没有可用分桶：${name}`);
  const family = declare(name, 'histogram', help, labelNames);
  family.buckets = sorted;
  return {
    observe(valueOrLabels, maybeValue) {
      const value = typeof valueOrLabels === 'object' ? maybeValue : valueOrLabels;
      const labels = typeof valueOrLabels === 'object' ? valueOrLabels : null;
      const v = Number(value);
      if (!Number.isFinite(v) || v < 0) return;
      const s = seriesOf(family, labels);
      if (!s) return;
      if (!s.buckets) s.buckets = new Array(sorted.length).fill(0);
      for (let i = 0; i < sorted.length; i++) {
        if (v <= sorted[i]) s.buckets[i] += 1;
      }
      s.sum += v;
      s.count += 1;
    },
  };
}

/**
 * 采集时求值的仪表：抓取那一刻才算，因为这一族的真相只存在于"此刻"（heap、在飞请求数、
 * 事件循环滞后）。collect 返回一个数（无标签家族）或 `[{labels, value}]`；
 * 返回 null/undefined ⇒ 这一次不出这一族（读不到就说读不到，不编一个 0 充数）。
 */
function collectorGauge(name, { help, labelNames = [] }, collect) {
  const family = declare(name, 'gauge', help, labelNames);
  family.collect = collect;
  return family;
}

// ========== 进程面 ==========

// 事件循环滞后：perf_hooks 的采样器（Node 内置，零依赖）。窗口＝上次抓取至今，
// 抓完就 reset —— 与 HELP 里写的那句是同一件事，不谎称"全程"。
const eventLoopDelay = monitorEventLoopDelay({ resolution: 20 });
eventLoopDelay.enable();

collectorGauge(
  'notice_process_up',
  { help: 'Always 1 while the process serves the scrape; Prometheus derives `up` itself.' },
  () => 1,
);

collectorGauge(
  'notice_process_uptime_seconds',
  { help: 'Process uptime in seconds since the Node runtime started.' },
  () => Number(process.uptime().toFixed(3)),
);

collectorGauge(
  'notice_process_heap_used_bytes',
  { help: 'Live heap bytes (process.memoryUsage).' },
  () => process.memoryUsage().heapUsed,
);

collectorGauge(
  'notice_process_heap_total_bytes',
  { help: 'Total heap space bytes (process.memoryUsage).' },
  () => process.memoryUsage().heapTotal,
);

collectorGauge(
  'notice_process_rss_bytes',
  { help: 'Resident set size bytes (process.memoryUsage).' },
  () => process.memoryUsage().rss,
);

collectorGauge(
  'notice_process_event_loop_lag_ms',
  {
    help: 'Event loop delay quantiles in ms, window since the previous scrape (reset each scrape).',
    labelNames: ['quantile'],
  },
  () => {
    if (!eventLoopDelay.count || eventLoopDelay.count <= 0) return null;
    const rows = [
      { labels: { quantile: '0.5' }, value: eventLoopDelay.percentile(50) },
      { labels: { quantile: '0.9' }, value: eventLoopDelay.percentile(90) },
      { labels: { quantile: '0.99' }, value: eventLoopDelay.percentile(99) },
    ].map((r) => ({ labels: r.labels, value: Number((r.value / 1e6).toFixed(3)) }));
    eventLoopDelay.reset();
    return rows;
  },
);

collectorGauge(
  'notice_process_build_info',
  {
    help: 'Constant 1, labelled with the Node runtime version of this instance.',
    labelNames: ['node'],
  },
  () => [{ labels: { node: process.version }, value: 1 }],
);

// ========== HTTP 面 ==========

const httpRequests = counter('notice_http_requests_total', {
  help: 'Requests finished, labelled by route template, HTTP method and response status code.',
  labelNames: ['route', 'method', 'status'],
});

const httpDurationMs = histogram('notice_http_request_duration_ms', {
  help: 'Time from request entry to response finish, in ms. Long polling and streaming include their whole hold.',
  labelNames: ['route', 'method'],
  buckets: [1, 2.5, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000, 30000],
});

let inflightRequests = 0;

collectorGauge(
  'notice_http_inflight_requests',
  { help: 'Requests currently inside the middleware chain at scrape time.' },
  () => inflightRequests,
);

// ========== 安全面 ==========

const AUTH_FAILURE_KINDS = ['admin_token', 'login_2fa', 'recovery_rebind'];

const securityAuthFailures = counter('notice_security_auth_failures_total', {
  help: `Credential check failures on the login/rebind routes, by kind. Closed vocabulary: ${AUTH_FAILURE_KINDS.join(', ')}. Ordinary 401s from the API gate are not counted here (use notice_http_requests_total{status="401"}).`,
  labelNames: ['kind'],
});
// 封闭词表先各记一个 0：缺序列在 PromQL 里是"没有这条线"而不是 0，
// 告警规则要写 `absent()` 才不瞎 —— 与其让每个自部署者各补一次，不如出声时就带上。
for (const kind of AUTH_FAILURE_KINDS) securityAuthFailures.inc({ kind }, 0);

const securityIpBlockRefusals = counter('notice_security_ip_block_refusals_total', {
  help: 'Requests refused because the client IP is blocked (both entry points).',
});
securityIpBlockRefusals.inc(0);

const securityIpBlocksApplied = counter('notice_security_ip_blocks_applied_total', {
  help: 'Times a failed-credential streak actually resulted in an IP block being written.',
});
securityIpBlocksApplied.inc(0);

const seriesOverflow = counter('notice_metrics_series_overflow_total', {
  help: 'New label sets dropped because a family hit its series cap.',
  labelNames: ['family'],
});

// ========== 渲染 ==========

function renderSeriesLines(family, s, extraLabel) {
  const base = s.labels; // 已是 `k="v",k2="v2"` 的形状
  const labelPart = extraLabel === undefined ? base : [base, extraLabel].filter(Boolean).join(',');
  return labelPart ? `{${labelPart}}` : '';
}

/** 整份 exposition。纯函数：只读注册表与本进程的读数，不吃任何请求内容。 */
function render() {
  const lines = [];
  for (const family of registry.values()) {
    if (family.type === 'gauge' && typeof family.collect === 'function') {
      let rows;
      try {
        const r = family.collect();
        rows = typeof r === 'number' ? [{ labels: null, value: r }] : r;
      } catch (e) {
        console.error(`[metrics] 采集器失败，本族这一次不出：${family.name} - ${e.message}`);
        rows = null;
      }
      if (rows === null || rows === undefined) continue;
      lines.push(`# HELP ${family.name} ${escapeHelp(family.help)}`);
      lines.push(`# TYPE ${family.name} ${family.type}`);
      for (const row of rows) {
        const value = Number(row && row.value);
        if (!Number.isFinite(value)) continue;
        lines.push(
          `${family.name}${renderSeriesLines(family, { labels: labelKeyOf(family, row.labels) })} ${formatValue(value)}`,
        );
      }
      continue;
    }

    lines.push(`# HELP ${family.name} ${escapeHelp(family.help)}`);
    lines.push(`# TYPE ${family.name} ${family.type}`);
    const keys = [...family.series.keys()].sort();
    if (family.type === 'histogram') {
      for (const key of keys) {
        const s = family.series.get(key);
        for (let i = 0; i < family.buckets.length; i++) {
          lines.push(
            `${family.name}_bucket${renderSeriesLines(family, s, `le="${formatValue(family.buckets[i])}"`)} ${formatValue(s.buckets[i])}`,
          );
        }
        lines.push(
          `${family.name}_bucket${renderSeriesLines(family, s, 'le="+Inf"')} ${formatValue(s.count)}`,
        );
        lines.push(`${family.name}_sum${renderSeriesLines(family, s)} ${formatValue(s.sum)}`);
        lines.push(`${family.name}_count${renderSeriesLines(family, s)} ${formatValue(s.count)}`);
      }
      continue;
    }
    for (const key of keys) {
      const s = family.series.get(key);
      lines.push(`${family.name}${renderSeriesLines(family, s)} ${formatValue(s.value)}`);
    }
  }
  return `${lines.join('\n')}\n`;
}

// ========== 中间件与读口 ==========

/**
 * 路由标签：匹配到路由 ⇒ `baseUrl + route.path`（模板，段里是参数名）；
 * 没匹配 ⇒ 用调用方注入的桶（`store.rateLimitBucket` 的四枚固定值）。
 * ⚠ 这里出现的每一个字符串都必须是代码或常量控制的，不能是请求里的原始路径。
 */
function routeLabelOf(req, bucketOf) {
  const template =
    req.route && typeof req.route.path === 'string'
      ? `${req.baseUrl || ''}${req.route.path}`
      : null;
  if (template !== null) {
    // 去掉挂载点带来的尾斜杠（`/metrics` + `/` ⇒ `/metrics/`）：Express 默认非严格路由，
    // 同一个口带不带斜杠是同一个路由，留着就会把一个入口拆成两条时间序列。
    const normalized = template.length > 1 ? template.replace(/\/+$/, '') : template;
    return ROUTE_SHAPE.test(normalized) ? normalized : 'other';
  }
  if (typeof bucketOf === 'function') {
    const bucket = bucketOf(req.path);
    if (typeof bucket === 'string' && bucket !== '') return bucket;
  }
  return 'other';
}

function methodLabelOf(method) {
  const m = String(method || '').toUpperCase();
  return HTTP_METHODS.has(m) ? m : 'OTHER';
}

/**
 * 采集钩子。必须挂在整条链**最前面**：被 CORS 拒、被体积闸拒、被 IP 封锁、被限流的每一发
 * 都要留痕——排障时最想看见的恰好是"被打爆的那一段"，而它全发生在原有中间件之前。
 */
function createMetricsMiddleware({ bucketOf } = {}) {
  return (req, res, next) => {
    if (!isCollectEnabled()) return next();
    inflightRequests += 1;
    const started = process.hrtime.bigint();
    let counted = false;
    const finish = () => {
      if (counted) return;
      counted = true;
      inflightRequests -= 1;
      try {
        const route = routeLabelOf(req, bucketOf);
        const method = methodLabelOf(req.method);
        httpRequests.inc({ route, method, status: String(res.statusCode) });
        const ms = Number(process.hrtime.bigint() - started) / 1e6;
        httpDurationMs.observe({ route, method }, Number(ms.toFixed(3)));
      } catch (e) {
        // 指标面出任何问题都不许把这一发请求带下去。
        console.error(`[metrics] 记账失败：${e.message}`);
      }
    };
    // finish＝响应写完；close 兜住"客户端中途断线、永远不 finish"的那一发（在飞数不还回去就会漂）。
    res.on('finish', finish);
    res.on('close', finish);
    next();
  };
}

/**
 * `/metrics` 读口。两道门都在请求时读 env：
 *  1. `METRICS_ENABLED` 关 或 `METRICS_TOKEN` 没配 ⇒ `next()` 透传给应用级 404，与未知路由同形；
 *  2. 带了 token 但不对 ⇒ 401，且只回一句话（不回显任何比对了什么）。
 */
function createMetricsRouter() {
  const router = express.Router();

  router.get('/', (req, res, next) => {
    const expected = metricsToken();
    if (!isCollectEnabled() || expected === '') return next();
    const raw = req.get('authorization') || '';
    // 方案名大小写不敏感（RFC 7235），只认 `Bearer`：token **不**从 query 走 ——
    // 那会把它落进反代的 access log，与 T89"口令不进日志"直接冲突。
    const m = /^Bearer\s+(.+)$/i.exec(raw);
    const bearer = m ? m[1].trim() : '';
    if (!tokenMatches(bearer, expected)) {
      return res.status(401).json({ error: 'unauthorized' });
    }
    res.setHeader('Content-Type', 'text/plain; version=0.0.4; charset=utf-8');
    // 指标是"此刻的读数"：缓存它等于让告警规则读到过期数据，而反代默认会缓存 200。
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate');
    return res.status(200).send(render());
  });

  return router;
}

module.exports = {
  AUTH_FAILURE_KINDS,
  HTTP_METHODS,
  LABEL_VALUE_MAX,
  MAX_SERIES_PER_FAMILY,
  ROUTE_SHAPE,
  collectorGauge,
  counter,
  createMetricsMiddleware,
  createMetricsRouter,
  histogram,
  isCollectEnabled,
  methodLabelOf,
  metricsToken,
  render,
  routeLabelOf,
  security: {
    authFailures: securityAuthFailures,
    ipBlockRefusals: securityIpBlockRefusals,
    ipBlocksApplied: securityIpBlocksApplied,
    seriesOverflow,
  },
};
