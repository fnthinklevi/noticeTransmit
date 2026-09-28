// 端点收单（#138 T39 + T40 + T41）：第三方往这台实例推一条通知的两条入口。
//
//   GET  /api/fnthink/p/<endpointId>/<secret>?title=&body=…      口令在路径段
//   POST /api/fnthink/p/<endpointId>  +  Authorization: Bearer <secret>
//
// 它与签名面（/message）的区别决定了这里几乎所有规则：那边发的是**设备**（有身份、有私钥、
// poll 时能被认出来），这边只是一把**共享长期口令**（服务端只有摘要，泄露无法归因，也没有
// "重放窗口只有 5 分钟"那层保护）。所以这里三条特有的东西，每条都不是风格选择：
//
// ⚠ **口令只进路径段，不进 query**：URL 会被 access log、浏览器历史与中间代理各留一份副本，
//    而 query 常常不在脱敏范围内。契约 endpoint.ingress.pathPattern 与
//    transport.accessLogRedactPathPattern 的前缀关系由 validate 钉住 —— 脱敏规则盖不住这个
//    路径，就等于把长期口令写进别人的日志里。
// ⚠ **配额按端点计，且计额点在口令验完之后**：按 IP 计会让"一个出口后面挂多个端点"互相挤额度
//    （A1 那 7 条配对用例红在 429 上就是这个形状）；按**未验证**的 endpointId 计更糟 —— 那是
//    DoS 转移：攻击者拿别人的端点 id 发洪水，被 429 的是那个受害者。
// ⚠ **不存在的端点、口令错、IP 不在白名单三者逐字节同形**（契约 statusCodes.indistinguishable
//    早就声明过这一对，这里把 IP 那一支也并进来）：否则这一面就是一台"哪些端点存在 / 哪个来源
//    被允许"的枚举器。而**能力边界与载荷形状是验过口令之后**才说的（对方需要知道怎么改）。
//
// 还有一条容易写反的：载荷超限是 **400 明确拒**，不是"截断后收下"。通知正文被剪掉一半而
// 发送方以为发成功了，比拒收难排查得多 —— 这是产品不变量里"不静默丢"那一半。

'use strict';

const { statusCode, shapeError, pickField } = require('./contract');
const { isValidAddressCode } = require('./credentials');
const capabilities = require('./capabilities');
const ds = require('./devicestore');
const { sharedTracker } = require('./anomaly');

const MINUTE_MS = 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

/// 内网/本地直连 http 的显式逃生阀。**默认关**：HTTPS-only 是协议承诺（口令在路径段里，
/// 明文传输等于把它送给链路上任何人）。放 env 而不放契约，是因为它是部署事实不是协议事实。
function insecureAllowed() {
  const raw = String(process.env.FNTHINK_ALLOW_INSECURE_ENDPOINT || '').toLowerCase();
  return raw === '1' || raw === 'true' || raw === 'yes';
}

/// ingress 段的数字与语义一律从契约读。取不到就抛**可降级**的 SHAPE。
function ingressFromContract(contract) {
  const ep = (contract || {}).endpoint || {};
  const src = ep.ingress;
  if (!src || typeof src !== 'object') {
    throw shapeError('契约缺 endpoint.ingress 段：端点收单的配额、上限与同形规则没有第二个来源');
  }
  const intOf = (value, name, max) => {
    const n = Number(value);
    if (!Number.isInteger(n) || n <= 0 || (max !== undefined && n > max)) {
      throw shapeError(
        `endpoint.ingress.${name} 必须是正整数${max !== undefined ? `且 ≤ ${max}` : ''}（实际 ${value}）`,
      );
    }
    return n;
  };
  const quota = src.quota || {};
  const perMinute = intOf(quota.perMinute, 'quota.perMinute');
  const perDay = intOf(quota.perDay, 'quota.perDay');
  if (perDay <= perMinute) {
    throw shapeError(
      `endpoint.ingress.quota 的日额度必须大于分钟额度（${perDay} ≤ ${perMinute}）：` +
        '白天额度比分钟额度还小，正常用一天就会被自己的配额拦住',
    );
  }
  if (src.targetSource !== 'owner-device-record' || src.maySpecifyTarget !== false) {
    throw shapeError(
      'endpoint.ingress 必须把投递目标锁在"端点所属那台设备"（targetSource=owner-device-record、' +
        'maySpecifyTarget=false）：允许外部指定 target，等于一把口令泄露就能骚扰整台实例',
    );
  }
  if (src.insecureTransport !== 'reject') {
    throw shapeError(
      'endpoint.ingress.insecureTransport 只能是 reject：明文传输时口令裸奔在路径段里，' +
        '"默认允许 + 偶尔提醒"不是这条承诺的表达方式',
    );
  }
  const pathPattern = String(src.pathPattern || '');
  const postPath = String(src.postBearerPath || '');
  const redact = String((contract.transport || {}).accessLogRedactPathPattern || '');
  if (!redact || !pathPattern.startsWith(redact) || !postPath.startsWith(redact)) {
    throw shapeError(
      `endpoint.ingress 的两条路径必须落在 transport.accessLogRedactPathPattern（${redact}）之内：` +
        '脱敏规则盖不住这个路径，就等于把长期口令写进别人的 access log',
    );
  }
  const maxBodyChars = intOf(src.maxBodyChars, 'maxBodyChars');
  const byteCap = Number((contract.limits || {}).requestBodyMaxBytes || 0);
  if (byteCap > 0 && maxBodyChars > byteCap) {
    throw shapeError(
      `endpoint.ingress.maxBodyChars(${maxBodyChars}) 大于 limits.requestBodyMaxBytes(${byteCap})：` +
        '字符数上限比字节闸还宽等于没有这条限制，而读契约的人会以为它管着什么',
    );
  }
  const grant = capabilities.endpointGrant(contract);
  return {
    pathPattern,
    postBearerPath: postPath,
    perMinute,
    perDay,
    methodStatus: Number(src.postOnlyMethodStatus ?? ep.postOnlyMethodStatus),
    maxTitleChars: intOf(src.maxTitleChars, 'maxTitleChars'),
    maxBodyChars,
    endpointGrant: grant,
    capabilityReceipt: String(src.rejectedCapabilityReceipt || 'rejected_capability'),
  };
}

/// 外部字段 → 协议内部形状。别名表与"取第一个非空"都来自契约 `fieldTolerance`：
/// 每接一个平台都要改服务端，就是因为没有这一层。POST 正文覆盖同名的 query 参数。
function readIngress(contract, query, body) {
  const source = Object.assign({}, query || {}, body || {});
  const one = (key) => {
    const v = source[key];
    if (v === undefined || v === null) return '';
    return typeof v === 'string' ? v : String(v);
  };
  const tags = Array.isArray(source.tags)
    ? source.tags.map(String)
    : one('tags') === ''
      ? []
      : one('tags')
          .split(',')
          .map((s) => s.trim())
          .filter(Boolean);
  return {
    title: pickField(contract, 'title', source),
    body: pickField(contract, 'body', source),
    type: one('type') === '' ? 'notice' : one('type'),
    level: one('level'),
    item: one('item'),
    island: one('island'),
    tags,
    ttlSeconds: one('ttl'),
    dedupeId: one('dedupe') || one('dedupe_id'),
  };
}

/// 一个窗口计数器的取键（分钟与日两档，键里带端点 id 与结论）。
function windowKey(endpointId, name, now) {
  return name === 'minute' ? `${endpointId}:m` : `${endpointId}:d:${Math.floor(now / DAY_MS)}`;
}

/// 端点级配额：内存计数、按端点计、到上限拒。与 IP 层同一套"挤不进就不记账"的兜底
/// （限流表本身不能变成"一个请求换一条内存记录"的攻击面）。
function createEndpointQuota(ingress, observe) {
  const windows = new Map();
  const MAX_KEYS = 20000;

  function entry(key, now, spanMs) {
    let hit = windows.get(key);
    if (hit && hit.expiresAt <= now) {
      windows.delete(key);
      hit = null;
    }
    if (!hit) {
      if (windows.size >= MAX_KEYS) {
        for (const [k, v] of windows) if (v.expiresAt <= now) windows.delete(k);
        if (windows.size >= MAX_KEYS) return null;
      }
      hit = { count: 0, windowStart: now, expiresAt: now + spanMs };
      windows.set(key, hit);
    }
    return hit;
  }

  /// 返回 null = 放行；否则给出该回的码。计额与告警读同一个计数器（与 A4 同一条规矩）。
  function charge(endpointId, now) {
    const limits = [
      ['minute', ingress.perMinute, MINUTE_MS],
      ['day', ingress.perDay, DAY_MS],
    ];
    for (const [name, max, span] of limits) {
      const hit = entry(windowKey(endpointId, name, now), now, span);
      if (!hit) continue;
      hit.count += 1;
      const denied = hit.count > max;
      observe({
        subjectKind: 'endpoint',
        subject: endpointId,
        kind: 'message',
        window: name,
        count: hit.count,
        limit: max,
        denied,
        at: now,
      });
      if (denied) {
        return {
          retryAfter: Math.ceil((span - (now - hit.windowStart)) / 1000),
          window: name,
        };
      }
    }
    return null;
  }

  const quota = charge;
  quota.MAX_KEYS = MAX_KEYS;
  return quota;
}

/// 收单裁决。**顺序就是判据**：先传输、再凭证（含存在性与来源白名单，三者同形）、
/// 再方法、再能力、再载荷形状、最后才记配额 —— 每一步都只在"上一步已经证明有权知道下一步"之后说话。
///
/// 每个结论都带一个 `logOutcome`：它是**运维词**而不是协议词（所以不进契约 `receipts`，也不出现在
/// 任何对外响应里）。有它才有意义 —— 端点侧最常见的求助是"为什么那条没到"，而对外同形之后，
/// 不在内部区分"口令错 / IP 不在白名单 / 端点不存在"就没法回答。
function decideIngress(contract, ingress, state, input) {
  const unauthorized = statusCode(contract, 'unauthorized');
  const { endpoints, endpointId, secret, message, secure, ip, method, now } = input;

  // ① 明文传输：口令在路径段里 ⇒ 先拒，且不给任何细节（403 空 body，理由见文件头）。
  if (!secure && !insecureAllowed()) {
    return {
      ok: false,
      status: statusCode(contract, 'forbidden'),
      receipt: null,
      endpointId: null,
      logEndpointId: null,
      logOutcome: 'rejected_transport',
    };
  }
  // ②③ 端点存在 + 口令对 + 来源在 IP 白名单内：三者**逐字节同形**（401 空 body）。
  const found = ds.findEndpointBySecret(contract, endpoints, secret, now, state.endpointCfg);
  if (!found) {
    return {
      ok: false,
      status: unauthorized,
      receipt: null,
      indistinguishable: true,
      endpointId,
      logEndpointId: null,
      logOutcome: 'unknown_endpoint',
    };
  }
  if (!ds.endpointIpAllowed(found, ip)) {
    return {
      ok: false,
      status: unauthorized,
      receipt: null,
      indistinguishable: true,
      endpointId: found.id,
      logEndpointId: found.id,
      logOutcome: 'rejected_ip',
    };
  }
  // ④ postOnly：GET 形态把口令写进了 URL，端点自己关掉了这条路 ⇒ 405（码也来自契约）。
  if (found.postOnly && String(method).toUpperCase() === 'GET') {
    return {
      ok: false,
      status: ingress.methodStatus,
      receipt: null,
      endpointId: found.id,
      logEndpointId: found.id,
      logOutcome: 'rejected_method',
    };
  }
  // ⑤ 能力边界（T41）：端点只能产 L1。**type 与 item 交给 capabilities.decideCapability 判**
  //    （那张档位表与词表只能有一份出处，这里再写一份 if 就是等着分叉）；而外部自称的 `level`
  //    是 decideCapability 不看的东西（它按 type 查 minLevel）⇒ 这一支必须单独判，否则
  //    "type=notice&level=L3" 会绕过一切把档位请求带上设备侧。
  const ceiling = ingress.endpointGrant.maxLevel;
  const levels = (contract.capabilities || {}).levels || [];
  const capability = capabilities.decideCapability(contract, {
    stage: 'intake',
    type: message.type,
    item: message.item,
    grant: ingress.endpointGrant,
  });
  // decideCapability 只在 need ≥ itemRequiredFromLevel 那一档才查 item（通知带不带 item 与档位
  // 裁决无关），所以 L1 这条路**不会**替我们拦住它。但端点这一侧的授权根本没有逐条清单
  // （endpointGrant.items 恒为空），外部塞进来的 item 只能按"超出授权"拒：
  // 收下再擦掉（routes 那里硬写 item:''）就是静默丢，而设备侧的规则可能正按 item 匹配 ——
  // 与"借真消息挂假标题"是同一个形状，只是这一次是借真通知挂动作钩子。
  const itemBeyondGrant = message.item !== '' && (ingress.endpointGrant.items || []).length === 0;
  if (
    !capability.allowed ||
    itemBeyondGrant ||
    (message.level !== '' &&
      capabilities.levelRank(levels, message.level) > capabilities.levelRank(levels, ceiling))
  ) {
    return {
      ok: false,
      status: statusCode(contract, 'forbidden'),
      receipt: ingress.capabilityReceipt,
      endpointId: found.id,
      logEndpointId: found.id,
      logOutcome: 'rejected_capability',
    };
  }
  // ⑥ 载荷形状：正文与标题都空 = 一条没有内容的通知；超限 = 明确拒，不截断。
  if (message.title.trim() === '' && message.body.trim() === '') {
    return {
      ok: false,
      status: statusCode(contract, 'badRequest'),
      receipt: null,
      endpointId: found.id,
      logEndpointId: found.id,
      logOutcome: 'empty_payload',
    };
  }
  if (
    [...message.title].length > ingress.maxTitleChars ||
    [...message.body].length > ingress.maxBodyChars
  ) {
    return {
      ok: false,
      status: statusCode(contract, 'badRequest'),
      receipt: null,
      endpointId: found.id,
      logEndpointId: found.id,
      logOutcome: 'payload_too_large',
    };
  }
  // ⑦ 目标只许是这台端点所属的设备（契约 maySpecifyTarget=false 的执行处）。
  const target = typeof found.owner === 'string' ? found.owner : '';
  if (!isValidTarget(contract, target)) {
    return {
      ok: false,
      status: statusCode(contract, 'forbidden'),
      receipt: null,
      endpointId: found.id,
      logEndpointId: found.id,
      // 这是端点自己的配置事实（没绑过设备），与攻击者无关 ⇒ 内部说清，对外仍是 403 空 body。
      logOutcome: 'unbound_endpoint',
    };
  }
  // ⑧ 配额：只在以上都过了之后记一发（在此之前记 = 让攻击者替受害者花额度）。
  const over = state.charge(found.id, now);
  if (over) {
    return {
      ok: false,
      status: statusCode(contract, 'rateLimited'),
      receipt: null,
      retryAfter: over.retryAfter,
      endpointId: found.id,
      logEndpointId: found.id,
      logOutcome: 'rate_limited',
    };
  }
  return {
    ok: true,
    status: statusCode(contract, 'queued'),
    receipt: null,
    endpointId: found.id,
    logEndpointId: found.id,
    logOutcome: 'queued',
    target,
    usedRotated: found.usedRotated === true,
  };
}

function isValidTarget(contract, value) {
  // 地址码形状由契约字母表与位数管（credentials.isValidAddressCode），这里不另写一份规则。
  return isValidAddressCode(contract, value);
}

/// 路由用的装配：一份 ingress + 一个配额计数器（进程内）。
function createEndpointIngress(contract) {
  const ingress = ingressFromContract(contract);
  const observe = (event) => sharedTracker().observe(event);
  const state = {
    ingress,
    charge: createEndpointQuota(ingress, observe),
    endpointCfg: ds.endpointConfigFromContract(contract),
  };
  return { ingress, state, decide: (input) => decideIngress(contract, ingress, state, input) };
}

module.exports = {
  createEndpointIngress,
  decideIngress,
  createEndpointQuota,
  ingressFromContract,
  readIngress,
  insecureAllowed,
  windowKey,
  MINUTE_MS,
  DAY_MS,
};
