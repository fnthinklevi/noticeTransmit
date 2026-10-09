// 端点收单（#138 T39 + T40 + T41）：第三方往这台实例推一条通知的两条入口。
//
//   GET  /api/fnthink/p/<endpointId>/<secret>?title=&body=…      口令在路径段
//   POST /api/fnthink/p/<endpointId>  +  Authorization: Bearer <secret>
//   POST /api/fnthink/p/<endpointId>/probe  +  Authorization: Bearer <secret>
//        ↑ 端点档的**干跑**（T106 片①b）：同一条裁决链一步不少，只跳过 ⑥（没有载荷可判）
//          与 ⑧（不花端点额度），而调用方（routes.js）拿到 ok 之后**不 enqueue**。
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

/// 端点档的干跑（T106 片①b）：路径与三条策略都只从契约 endpoint.probe 读。
///
/// ⚠ 两条布尔用**装载即断**、一条留分支，这个分工是刻意的：
///  - `secretPlacement` 改向（口令进 URL）与 `writesCallLog` 改向（监测把自己要观察的那本
///    历史挤掉）都是缺陷，不是取舍 ⇒ 让它启动失败，而不是"实现里还留着那条分支"；
///  - `chargesIngressQuota` 是**产品取舍**（健康监测花不花被监测那条路的额度），真要改得连
///    `_why` 一起改，所以它出现在用的那一处（下面 ⑧），而不是一个把死的值。
/// ⚠ 尾段必须是固定字面量这一条不是洁癖：Express 按注册顺序匹配，而收单那条以 `:secret`
///   收尾。`/p/:id/<参数>` 会被收单先接走并把参数当成口令 —— 回 401，表现是"口令错了"，
///   实际是路由没接上。顺序本身没法由契约保证，所以注册顺序由用例钉（fnthink-endpoint-probe）。
function probeFromContract(contract) {
  const src = ((contract || {}).endpoint || {}).probe;
  if (!src || typeof src !== 'object') {
    throw shapeError('契约缺 endpoint.probe 段：端点档的干跑没有路径与策略的第二来源');
  }
  const bearerPath = String(src.bearerPath || '');
  const redact = String((contract.transport || {}).accessLogRedactPathPattern || '');
  if (!bearerPath || !redact || !bearerPath.startsWith(redact)) {
    throw shapeError(
      `endpoint.probe.bearerPath（${bearerPath}）必须落在 transport.accessLogRedactPathPattern` +
        `（${redact}）之内：这一条与口令同面，脱敏盖不住它就是把口令送进日志的那一半`,
    );
  }
  if (bearerPath.includes(':secret') || bearerPath.includes('?')) {
    throw shapeError(
      'endpoint.probe.bearerPath 既不许带 :secret 也不许带 query：探针会被自动重探反复打，' +
        '口令进 URL 等于给链路上每一层日志多送一份副本',
    );
  }
  const tail = bearerPath.split('/').filter(Boolean).pop() || '';
  if (tail.startsWith(':')) {
    throw shapeError(
      `endpoint.probe.bearerPath 的尾段必须是固定字面量（实际 ${tail}）：尾段是参数时它与 ` +
        'ingress.pathPattern 的 :secret 撞位，探针会打到收单那条并回 401',
    );
  }
  if (src.secretPlacement !== 'bearer-header') {
    throw shapeError(
      `endpoint.probe.secretPlacement 只能是 bearer-header（实际 ${src.secretPlacement}）：` +
        '口令出现在请求头里是这一发能被自动重探反复打的前提',
    );
  }
  if (src.writesCallLog !== false) {
    throw shapeError(
      'endpoint.probe.writesCallLog 只能是 false：调用日志回答的是「为什么那条没到」，' +
        '而探针从来不是一条「那一条」；它有界，自动重探会把自己要观察的那份历史挤掉',
    );
  }
  if (typeof src.chargesIngressQuota !== 'boolean') {
    throw shapeError(
      'endpoint.probe.chargesIngressQuota 必须是布尔：健康探测花不花被监测那条路的额度，' +
        '是一件要写下来并说清理由的决定，不是实现里顺手的一个 if',
    );
  }
  return {
    bearerPath,
    secretPlacement: src.secretPlacement,
    chargesIngressQuota: src.chargesIngressQuota,
    writesCallLog: src.writesCallLog,
  };
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
  // 第三方载荷那枚 `type` 的折价目标（T120）。两条都是**方向性**判据，不是"键在不在"：
  //  ① 折成的词必须在协议词表上 —— 折成一个词表外的词，等于把 unknown-type 那道闸往后推给
  //     设备，而设备那条路是签名面的裁决（对端自称的值能一路走到 apply）；
  //  ② 那一档的 minLevel 不许高于本面的档位上限 —— 否则"认不出就当它是个动作"，
  //     折价这一发本身就成了升权。缺省方向只能朝下。
  const table = (contract.capabilities || {}).messageTypes || {};
  const levels = (contract.capabilities || {}).levels || [];
  const unknownTypeAs = String(src.unknownTypeAs || '');
  const fallbackEntry = Object.prototype.hasOwnProperty.call(table, unknownTypeAs)
    ? table[unknownTypeAs]
    : null;
  if (!fallbackEntry || typeof fallbackEntry !== 'object') {
    throw shapeError(
      `endpoint.ingress.unknownTypeAs（${unknownTypeAs}）必须是 capabilities.messageTypes 里的一个词：` +
        '词表外的值要折成的是「协议里有定义的那一档」，不是再造一个新词',
    );
  }
  const fallbackCeiling = capabilities.endpointGrant(contract).maxLevel;
  if (
    capabilities.levelRank(levels, String(fallbackEntry.minLevel || '')) >
    capabilities.levelRank(levels, String(fallbackCeiling))
  ) {
    throw shapeError(
      `endpoint.ingress.unknownTypeAs 那一档的 minLevel（${fallbackEntry.minLevel}）不许高于 ` +
        `capabilities.endpointMaxLevel（${fallbackCeiling}）：折价只能朝下，朝上就是把每一条` +
        '读不懂的第三方推送都当成一次动作申请',
    );
  }
  if (typeof src.ignoreItemField !== 'boolean') {
    throw shapeError(
      'endpoint.ingress.ignoreItemField 必须是布尔：第三方载荷里的 item 到底当噪音还是当越权，' +
        '是一件要写下来并连同理由一起改的决定，不是实现里顺手的一个 if',
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
    unknownTypeAs,
    ignoreItemField: src.ignoreItemField,
    // 干跑（T106 片①b）的策略跟着 ingress 一起装配：同一份裁决、同一个配额计数器，
    // 只是不走 ⑥⑧ 与投递那三步。分两处读就得保证两处同时改，而那正是"探针说通、真发被拒"的起点。
    probe: probeFromContract(contract),
  };
}

/// 载荷里的 `type` → 协议词表里的那个词（T120）。折价**只发生在词表外**这一支：第三方把自己
/// 那条通知叫 `msg`／`alert`／`warning` 是它自己的分类法，不是向我们申请一个协议动作。词表内的
/// 值原样交给裁决 —— 档位与逐条清单在那里判，不在这里。
/// 契约给不出一个合法缺省词时返回空串：裁决会按 unknown-type 拒掉，这比在实现里藏一个
/// `'notice'` 安全 —— 那种写法在契约漂移时会静默放行，而这一条的判据正是"不替对端解释词表"。
function coerceIngressType(contract, raw) {
  const table = ((contract || {}).capabilities || {}).messageTypes || {};
  const value = String(raw === undefined || raw === null ? '' : raw);
  if (Object.prototype.hasOwnProperty.call(table, value)) return value;
  const fallback = String((((contract || {}).endpoint || {}).ingress || {}).unknownTypeAs || '');
  return Object.prototype.hasOwnProperty.call(table, fallback) ? fallback : '';
}

/// 外部字段 → 协议内部形状。别名表与"取第一个非空"都来自契约 `fieldTolerance`：
/// 每接一个平台都要改服务端，就是因为没有这一层。POST 正文覆盖同名的 query 参数。
/// ⚠ `type` 出去的是**词表内的那个词**（认不出的按契约折成 unknownTypeAs），不是载荷里原样那句 ——
/// 下游（裁决与落队）因此可以假定它永远合法，而第三方怎么写自己的分类都不影响它收不收得进。
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
    type: coerceIngressType(contract, one('type')),
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
  // 干跑（T106 片①b）：判序一步都不少，只少了「为此花掉什么」那三步 —— 不判载荷（探针没带载荷）、
  // 不花配额、不投递。⚠ 不许因为"反正不投递"就跳过 ①②③⑤⑦：那几条正是探针要回答的问题，
  // 跳一条就等于绿徽标配一条真发进不去的通知。
  const dryRun = input.dryRun === true;

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
  // ⑤ 能力边界（T41 + T120）：端点只能产 L1。**type 与 item 交给 capabilities.decideCapability 判**
  //    （那张档位表与词表只能有一份出处，这里再写一份 if 就是等着分叉）；而外部自称的 `level`
  //    是 decideCapability 不看的东西（它按 type 查 minLevel）⇒ 这一支必须单独判，否则
  //    "type=notice&level=L3" 会绕过一切把档位请求带上设备侧。
  //    ⚠ 到这里的 `message.type` 已经是词表内的词（`readIngress` 按契约 unknownTypeAs 折过价），
  //    所以这一格判的是「它要的那一档本面给不给得起」，不再判「它写的这个词我们认不认得」。
  //    契约里那句 unknownMessageType=reject 管的是签名面（对端是有身份的设备），不是这里。
  const ceiling = ingress.endpointGrant.maxLevel;
  const levels = (contract.capabilities || {}).levels || [];
  // `item` 是设备侧的动作钩子，而本面的授权清单恒为空 ⇒ 落队那一位恒写空串（routes.js）。
  // 契约 ignoreItemField=true 时它是第三方通知自己的一个字段名，按噪音忽略；false 时恢复旧行为
  // （带 item 一律按越权拒）。⚠ 这一支的成立前提是那条不转发 —— 前提漂了，这里必须改回拒。
  const item = ingress.ignoreItemField ? '' : message.item;
  const capability = capabilities.decideCapability(contract, {
    stage: 'intake',
    type: message.type,
    item,
    grant: ingress.endpointGrant,
  });
  // decideCapability 只在 need ≥ itemRequiredFromLevel 那一档才查 item（通知带不带 item 与档位
  // 裁决无关），所以 L1 这条路**不会**替我们拦住它。而端点这一侧的授权根本没有逐条清单
  // （endpointGrant.items 恒为空），契约没让它当噪音时只能按"超出授权"拒：
  // 收下再擦掉（路由那里硬写 item:''）就是静默丢，写集成的人会以为钩子生效了。
  const itemBeyondGrant = item !== '' && (ingress.endpointGrant.items || []).length === 0;
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
  //    ⚠ 干跑**整段跳过**：探针一个字段都不读，载荷永远是协议的默认形状（标题正文都空），
  //    按这一段的判据它必然"空载荷"——那不是结论而是"探针没在回答这个问题"。
  //    所以绿灯说的是「这条入口现在收得进一条默认形状的通知」，不是「我这一条具体的通知进得去」。
  if (!dryRun) {
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
  //    干跑**默认不记**（契约 endpoint.probe.chargesIngressQuota=false）：让健康监测花被监测
  //    那条路的额度，等于「探针把它监视的那条路挤死」—— 自动重探每轮 3 次、几条通道叠起来，
  //    先被 429 拦住的是 NAS 的真推送。⚠ 不记这一档不等于没人管洪水：面级那道按 IP 的闸门
  //    挂在路由之前（ratelimit.js），它不需要身份就能生效。
  if (!dryRun || ingress.probe.chargesIngressQuota) {
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
  }
  return {
    ok: true,
    // 干跑不回「真发会回哪个码」：那一发永远是 200 + 结论在正文（routes.js 那段）。
    // 写成 null 而不是留着 202 —— 留着，下一个读它的人会照 verdict.status 回，
    // 探针就变成"会 401 的那一种"，而这一面守的正是所有失败同形。
    status: dryRun ? null : statusCode(contract, 'queued'),
    receipt: null,
    endpointId: found.id,
    logEndpointId: found.id,
    logOutcome: dryRun ? 'probe_ok' : 'queued',
    dryRun,
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
  probeFromContract,
  readIngress,
  coerceIngressType,
  insecureAllowed,
  windowKey,
  MINUTE_MS,
  DAY_MS,
};
