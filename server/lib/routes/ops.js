// 幻念推送的运维入口（#130-A5）：列状态 / 冻结 / 解冻 / 吊销 / 一键全部失效 / 重建后废所有发送方
// / 列投递状态（T45 第一片，只读）。
//
// 为什么这一组只在管理面：这里做的是"人决定停掉某台设备"，而协议面动作的凭证是**设备自己签的名**。
// 把这套能力挂到公网面就得给服务端造一把签名钥匙 —— 那是往协议里悄悄新增一个信任根（T35 已经
// 为同一件事定过调子）。设备侧自己要的那些动作（重置口令、重建身份、划掉某个发送方）走 clientEvents。
//
// ⚠ **契约是懒取的，不在模块顶层读**。这一条是本片被既有用例当场抓出来的：写在 require 链上时，
//   "只上传 server/、契约文件不在"会让这个文件在 require 阶段抛 ENOENT，冒到顶层 ⇒ 整台服务起不来，
//   连带拖死 `/api/version`（所有设备的更新通道）—— 而那正是 `fnthink-routes.test.js` 里
//   "契约找不到 ⇒ /api/fnthink 明确 503 而 /api/version 照常 200"那条用例在防的事情。
//   所以这一段自己答 503，形状与协议面降级那条一致。
//
// 五条判据：
// ① **状态名一律从契约词汇表读**（devicestore 的四个 helper），这个文件里不出现任何设备档位名的
//    字面量，有源码守卫钉住。以前实现里有四处写死：契约加一档时它们不报错，只是静默地
//    "这一档没人认得，而记录照旧存在"。
// ② **回不去的那类动作要显式 confirm**（名单在契约 `ops.confirmationRequiredFor`），且确认校验排在
//    读表与写入之前。判据是"误点之后能不能原地撤销"，不是"看起来严重不严重"：freeze 随时可解 ⇒ 不要
//    确认；revoke / revokeAll / rebuildInvalidation 要对方重新配对 ⇒ 要。
// ③ **每个动作都回答"影响了谁 / 几台"**："0 台"与"没这个钮"在现场看起来一模一样。
// ④ **响应一律白名单挑字段**：设备表的一行里有公钥、配对口令摘要、grantsBy。一个 spread 就把它们
//    全端进管理面 —— 地址码确实是公开标识，但"这台设备收了哪些发送方的授权"不是。
// ⑤ 错误分两类不许混：**"这台设备不在表里"是用户输入**（404，管理面已鉴权，可以说清是哪台 ——
//    同形规则是给未认证面的），**其余异常一律往上抛**（那是代码或契约的问题，咽成 404 就是
//    "缺陷伪装成操作没生效"）。

const express = require('express');
const net = require('net');

const { asyncHandler, authMiddleware } = require('../middleware');
const {
  loadContract,
  assertSupported,
  isContractAvailabilityError,
} = require('../fnthink/contract');
const { alphabetFromContract, isValidAddressCode, normalize } = require('../fnthink/credentials');
const ds = require('../fnthink/devicestore');
const ms = require('../fnthink/messagestore');

const router = express.Router();

let cached = null;
function context() {
  if (!cached) {
    const contract = assertSupported(loadContract());
    cached = { contract, ops: ds.opsConfigFromContract(contract) };
  }
  return cached;
}

/// 把"协议层不可用"按协议面那一套装：503 + 同一个 error 体。非契约类异常照旧往上抛。
function withContext(handler) {
  return asyncHandler(async (req, res) => {
    let c;
    try {
      c = context();
    } catch (e) {
      if (!isContractAvailabilityError(e)) throw e;
      return res.status(503).json({ error: 'fnthink_protocol_unavailable' });
    }
    return handler(c, req, res);
  });
}

/// 管理面能看到的一行设备（**新增字段要过一遍"它是不是凭证或授权"**）。
function publicRecord(addressCode, record) {
  return {
    addressCode,
    name: record.name || '',
    status: record.status,
    createdAt: record.createdAt || null,
    lastSeenAt: record.lastSeenAt || null,
    statusChangedAt: record.statusChangedAt || null,
  };
}

function needsConfirm(ctx, action) {
  return ctx.ops.confirmationRequired.has(action);
}

/// 缺确认 ⇒ 立刻答复并返回 false。排在读表之前：任何写入都不该发生在校验之前。
function ensureConfirmed(ctx, req, res, action) {
  if (!needsConfirm(ctx, action) || (req.body || {}).confirm === true) return true;
  res.status(400).json({
    code: -1,
    message: `动作 ${action} 需要显式 confirm:true —— 它会让对方必须重新配对，误点撤销不了`,
  });
  return false;
}

/// 地址码先验形状再查表：把一串垃圾直接当键去查，404 里就会带上那串垃圾。
function targetAddress(ctx, req, res) {
  const raw = String((req.body || {}).addressCode || '');
  if (!isValidAddressCode(ctx.contract, raw)) {
    res.status(400).json({ code: -1, message: 'addressCode 形状不合法（按契约字母表与长度）' });
    return null;
  }
  return normalize(alphabetFromContract(ctx.contract), raw);
}

function singleDeviceAction(action, write) {
  return withContext((ctx, req, res) => {
    if (!ensureConfirmed(ctx, req, res, action)) return;
    const addressCode = targetAddress(ctx, req, res);
    if (!addressCode) return;
    const devices = ds.loadDevices();
    if (!devices[addressCode]) {
      res.status(404).json({ code: -1, message: `这台设备不在设备表里：${addressCode}` });
      return;
    }
    const record = write(ctx.contract, devices, addressCode, Date.now());
    console.log(`[fnthink:ops] ${action} ${addressCode} → ${record.status}`);
    res.json({
      code: 0,
      message: 'success',
      data: { action, affected: 1, device: publicRecord(addressCode, record) },
    });
  });
}

function bulkAction(action, write) {
  return withContext((ctx, req, res) => {
    if (!ensureConfirmed(ctx, req, res, action)) return;
    const devices = ds.loadDevices();
    const total = Object.keys(devices).length;
    const affected = write(ctx.contract, devices, Date.now());
    console.log(`[fnthink:ops] ${action} 影响 ${affected} 台（表内共 ${total} 台）`);
    res.json({ code: 0, message: 'success', data: { action, affected, total } });
  });
}

// 列设备状态：可按状态筛，上限取契约 ops.listMaxRows（不给"一次拉走整张表"的口）
router.get(
  '/fnthink/devices',
  authMiddleware,
  withContext((ctx, req, res) => {
    const wanted = req.query.status === undefined ? null : String(req.query.status);
    const table = (ctx.contract.revocation || {}).deviceStatuses || {};
    if (wanted !== null && !Object.prototype.hasOwnProperty.call(table, wanted)) {
      return res.status(400).json({
        code: -1,
        message: `status 必须是契约里的设备状态之一：${Object.keys(table).join(' / ')}`,
      });
    }
    const requested = Number(req.query.limit);
    const limit =
      Number.isInteger(requested) && requested > 0
        ? Math.min(requested, ctx.ops.listMaxRows)
        : ctx.ops.listMaxRows;
    const devices = ds.loadDevices();
    const statuses = {};
    for (const key of Object.keys(table)) statuses[key] = 0;
    const rows = [];
    for (const [addressCode, record] of Object.entries(devices)) {
      if (statuses[record.status] !== undefined) statuses[record.status] += 1;
      if (wanted && record.status !== wanted) continue;
      rows.push(publicRecord(addressCode, record));
    }
    const total = rows.length;
    return res.json({
      code: 0,
      message: 'success',
      data: {
        limit,
        total,
        returned: Math.min(total, limit),
        // truncated 必须显式给出：一份"没列全"的列表与一份"就只有这些"的列表，
        // 在运维读起来是完全相反的两个结论。
        truncated: total > limit,
        statuses,
        devices: rows.slice(0, limit),
      },
    });
  }),
);

// 冻结：留着记录与公钥，一条都不投，随时可解 —— 所以它不要 confirm
router.post(
  '/fnthink/devices/freeze',
  authMiddleware,
  singleDeviceAction('freeze', (contract, devices, addressCode, now) =>
    ds.freezeDevice(contract, devices, addressCode, now),
  ),
);

// 解冻：去处是契约里"允许投递"的那一档，不是在代码里写回某个状态字符串
router.post(
  '/fnthink/devices/resume',
  authMiddleware,
  singleDeviceAction('resume', (contract, devices, addressCode, now) =>
    ds.resumeDevice(contract, devices, addressCode, now),
  ),
);

router.post(
  '/fnthink/devices/revoke',
  authMiddleware,
  singleDeviceAction('revoke', (contract, devices, addressCode, now) =>
    ds.revokeDevice(contract, devices, addressCode, now),
  ),
);

// 一键全部失效：返回**被改动**的台数（0 台必须能看出来，那是"没有可动的了"而不是"钮坏了"）
router.post(
  '/fnthink/devices/revoke-all',
  authMiddleware,
  bulkAction('revokeAll', (contract, devices, now) => ds.revokeAllDevices(contract, devices, now)),
);

// 本机身份重建之后：所有在册发送方都要重新配对（记录不删，见 devicestore 那段注释）
router.post(
  '/fnthink/devices/rebuild-invalidation',
  authMiddleware,
  bulkAction('rebuildInvalidation', (contract, devices, now) =>
    ds.invalidatePeersAfterRebuild(contract, devices, now),
  ),
);

// ── 投递状态（T45 第一片）：只读列表 ─────────────────────────────────
// 为什么在管理面而不在协议面：这条视图回答的是"这条到底死在哪一步"，而协议面**没有这个角色** ——
// `delivery.senderPollsStatusEndpoint` 明写 false（T35 定的口径：回执由状态机当作一条消息推回发送端，
// 不让发送端轮询状态接口）。挂到协议面就得给"谁可以看别人的投递"再造一套判据，那是第二个信任根。
// 现在这一片只有运维在读，所以数据出处只有 messagestore 一张表，读口也只此一处。
//
// ⚠ 表里的 `body`（密信封）与 `dedupeIdDigest` 一律不端出去，逐字段挑见 `ms.publicMessage`。
// ⚠ 时间线（`trail`）记的是**状态机真的走过的那一步**：被忽略的事件不入列，入队与正文刷新不入列，
//    超过契约 `retention.auditTrail.maxPerMessage` 的从头部裁、裁掉几条记在 `trailDropped` 里。
//    所以"时间线短"与"没有历史"是两句话，而 `trail:null` 说的是第三种：这一行比留痕那一列更早。
router.get(
  '/fnthink/messages',
  authMiddleware,
  withContext((ctx, req, res) => {
    const states = (ctx.contract.delivery || {}).states || [];
    const wanted = req.query.state === undefined ? null : String(req.query.state);
    if (wanted !== null && !states.includes(wanted)) {
      return res.status(400).json({
        code: -1,
        message: `state 必须是契约里的投递状态之一：${states.join(' / ')}`,
      });
    }
    // 地址码先验形状再查表（与 targetAddress 同一条）：拿一串垃圾当键去筛，
    // 空列表会被读成"这台没发过消息"，而真实原因是筛错了键。
    let target = null;
    if (req.query.device !== undefined) {
      const raw = String(req.query.device);
      if (!isValidAddressCode(ctx.contract, raw)) {
        return res
          .status(400)
          .json({ code: -1, message: 'device 不是一个合法地址码（按契约字母表与长度）' });
      }
      target = normalize(alphabetFromContract(ctx.contract), raw);
    }
    const requested = Number(req.query.limit);
    const limit =
      Number.isInteger(requested) && requested > 0
        ? Math.min(requested, ctx.ops.listMaxRows)
        : ctx.ops.listMaxRows;

    const messages = ms.loadMessages();
    const devices = ds.loadDevices();
    // 档位计数**不受筛选影响**（先数后筛）：筛选后的那份计数会让运维把"这一档 3 条"
    // 读成"整张表 3 条"，而这两句话在"要不要冻结"上是相反的决定。
    const tally = {};
    for (const name of states) tally[name] = 0;
    const rows = [];
    for (const message of Object.values(messages)) {
      if (tally[message.state] !== undefined) tally[message.state] += 1;
      if (wanted && message.state !== wanted) continue;
      if (target && message.device !== target) continue;
      const row = ms.publicMessage(ctx.contract, message);
      // "已排队，最后在线 X" 里的那个 X：设备表有就带，没有就 null（这台从没登记过）。
      const device = devices[row.device];
      row.targetLastSeenAt = device ? device.lastSeenAt || null : null;
      rows.push(row);
    }
    // 排序定在这一处（最近有动静的在前）：不在这里定，下一个读口就会按 queuedAt 排，
    // 而"我刚发的那条怎么不见了"的现场正是 updatedAt 很新、queuedAt 很旧。
    rows.sort(
      (a, b) => (b.updatedAt || 0) - (a.updatedAt || 0) || (a.messageId < b.messageId ? -1 : 1),
    );
    const total = rows.length;
    return res.json({
      code: 0,
      message: 'success',
      data: {
        limit,
        total,
        returned: Math.min(total, limit),
        // truncated 必须显式给出（与列设备同一条）：一份"没列全"与一份"就只有这些"，
        // 在运维读起来是完全相反的两个结论。
        truncated: total > limit,
        states: tally,
        messages: rows.slice(0, limit),
      },
    });
  }),
);

// ── 端点（T38）：只读列表 + 吊销 ────────────────────────────────────
// 端点段（`endpoint`）缺失时**只有这两个口**答 503：设备那一组读的是 revocation + ops 段，
// 不该因为端点段没读到而一起挂 —— 与 A4/A5 定下的"各自只依赖自己要读的那一段"同一条。
function endpointConfigOf(ctx) {
  try {
    return ds.endpointConfigFromContract(ctx.contract);
  } catch (e) {
    if (!isContractAvailabilityError(e)) throw e;
    return null;
  }
}

router.get(
  '/fnthink/endpoints',
  authMiddleware,
  withContext((ctx, req, res) => {
    const epc = endpointConfigOf(ctx);
    if (!epc) return res.status(503).json({ error: 'fnthink_protocol_unavailable' });
    const endpoints = ds.loadEndpoints();
    const rows = Object.entries(endpoints).map(([id, record]) => ds.publicEndpoint(id, record));
    const statuses = {};
    for (const name of [epc.usableStatus, epc.revokedStatus]) statuses[name] = 0;
    for (const row of rows) if (statuses[row.status] !== undefined) statuses[row.status] += 1;
    const limit = ctx.ops.listMaxRows;
    const total = rows.length;
    return res.json({
      code: 0,
      message: 'success',
      data: {
        limit,
        total,
        returned: Math.min(total, limit),
        truncated: total > limit,
        statuses,
        // ⚠ 这里没有 secretDigest：摘要是可离线爆破的靶子，而明文口令只在创建/轮换那一次出现过。
        endpoints: rows.slice(0, limit),
      },
    });
  }),
);

// 端点单独吊销（补 T31 记的 ②）。现在它有真实的读者：端点鉴权按 status 白名单判，
// 不再是"写了一个状态而没人读"。
router.post(
  '/fnthink/endpoints/revoke',
  authMiddleware,
  withContext((ctx, req, res) => {
    const epc = endpointConfigOf(ctx);
    if (!epc) return res.status(503).json({ error: 'fnthink_protocol_unavailable' });
    if (!ensureConfirmed(ctx, req, res, 'revokeEndpoint')) return;
    const id = String((req.body || {}).endpointId || '');
    if (!id) return res.status(400).json({ code: -1, message: 'endpointId 不能为空' });
    const endpoints = ds.loadEndpoints();
    const out = ds.revokeEndpoint(ctx.contract, endpoints, id, Date.now(), epc);
    if (!out) {
      return res.status(404).json({ code: -1, message: `这个端点不在表里：${id}` });
    }
    console.log(`[fnthink:ops] revokeEndpoint ${id}`);
    return res.json({
      code: 0,
      message: 'success',
      // affected 与设备那一组同一个口径：已经吊销过再按一次是 0，不是"没反应"。
      data: { action: 'revokeEndpoint', affected: out.revoked ? 1 : 0, endpoint: out.endpoint },
    });
  }),
);

// ── 端点的写入口（创建 / 轮换 / 改策略）────────────────────────────
// 为什么这三个口现在就要有：T39–T41 把两条收单入口挂上了公网，而管理面只能**列**与**吊销**
// ⇒ 部署好的实例上没有任何办法铸出一条口令，"第三方能推"就只是一句文档话。
//
// ⚠ **明文口令只在这两个口的响应里出现一次**（创建与轮换各一次）。表里存的是摘要，列表口拿不到明文，
//   也没有任何接口能把它再取回来 —— 忘了就只能再轮换一次。所以这两个口**不许把响应体写进日志**：
//   "顺手 console 一行返回体"是最常见的一行代码，而它恰好把这一面唯一的秘密送进日志文件。
//
// 到上限、不在表里、参数不对都是**用户输入**那一类（400 / 404），不许冒成 500 —— 既是管理面的
// 既有口径（A5 判据⑤），也因为运维看到 500 会去查进程，而不是改自己抄错的那一行。

/// 轮换与改策略共用的前置：先认出这一行，再把"没这条"与"有但已经不能用"分清楚说。
/// 判定是白名单式的（必须是契约 `usableStatus`），与收单那一侧同一条规则。
function usableRow(epc, res, id) {
  if (!id) {
    res.status(400).json({ code: -1, message: 'endpointId 不能为空' });
    return null;
  }
  const endpoints = ds.loadEndpoints();
  const record = endpoints[id];
  if (!record) {
    res.status(404).json({ code: -1, message: `这个端点不在表里：${id}` });
    return null;
  }
  if (record.status !== epc.usableStatus) {
    // 不答 404：这一行确实在表里，答"不在"是把事实说反。也不许顺手把它改回可用 ——
    // 吊销是"这个入口从此不再存在"，要恢复就该新建一条（旧的调用日志与创建时间属于那一条记录）。
    res.status(400).json({
      code: -1,
      message: `这个端点已经是「${record.status}」那一档：轮换与设置只挂在还能用的端点上，要恢复请新建`,
    });
    return null;
  }
  return endpoints;
}

/// IP 白名单的每一项都得真的是个 IP。空数组按契约是"不限来源"（`ipAllowlistEmptyMeans=any`），
/// 而抄进一个 `10.0.0.0/24` 或带空格的东西，表现是"口令明明对，却一律 401" —— 那条与口令错同形，
/// 排查的人只会怀疑口令，不会怀疑自己抄错的那一行。
function ipAllowlistFrom(body, res) {
  if (body.ipAllowlist === undefined) return { ok: true, value: undefined };
  if (!Array.isArray(body.ipAllowlist)) {
    res.status(400).json({ code: -1, message: 'ipAllowlist 必须是数组（空数组 = 不限来源）' });
    return { ok: false };
  }
  const bad = body.ipAllowlist.filter((one) => net.isIP(String(one).trim()) === 0);
  if (bad.length) {
    res.status(400).json({
      code: -1,
      message:
        `ipAllowlist 里有不是 IP 的项：${bad.join(' / ')}（每一项必须是一整个 IPv4 或 IPv6 地址；` +
        '要放一台网段就先把来源固定成那个地址，这里不做 CIDR 匹配 —— 匹配规则一旦写进管理面，收单那一侧就得再写一份）',
    });
    return { ok: false };
  }
  return { ok: true, value: body.ipAllowlist.map((one) => String(one).trim()) };
}

router.post(
  '/fnthink/endpoints/create',
  authMiddleware,
  withContext((ctx, req, res) => {
    const epc = endpointConfigOf(ctx);
    if (!epc) return res.status(503).json({ error: 'fnthink_protocol_unavailable' });
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const owner = String(body.owner || '');
    if (!isValidAddressCode(ctx.contract, owner)) {
      return res
        .status(400)
        .json({ code: -1, message: 'owner 必须是一个合法的地址码（按契约字母表与位数）' });
    }
    // 先要这台设备登记过：对着一个还不存在的收件人铸入口，表现是第三方拿到 202、屏幕上什么都不出现，
    // 而消息一直排到过期 —— 那比"现在就报错"难解释得多。
    if (!ds.loadDevices()[owner]) {
      return res.status(400).json({
        code: -1,
        message: `这台设备还没登记：${owner}（端点只能投给它所属的那台设备，先在 App 里连上这台实例再建）`,
      });
    }
    const allow = ipAllowlistFrom(body, res);
    if (!allow.ok) return;
    const endpoints = ds.loadEndpoints();
    let out;
    try {
      out = ds.createEndpoint(
        ctx.contract,
        endpoints,
        { owner, name: body.name, postOnly: body.postOnly, ipAllowlist: allow.value },
        Date.now(),
        epc,
      );
    } catch (e) {
      // 到上限（每台 / 全局）是"这次没建成"，不是服务端坏了：只拒新的，绝不挤掉已有端点。
      if (e.code === ds.ENDPOINT_CAP_CODE) {
        return res.status(400).json({ code: -1, message: e.message });
      }
      throw e;
    }
    console.log(`[fnthink:ops] createEndpoint ${out.id} owner=${owner}`);
    return res.json({
      code: 0,
      message: 'success',
      data: {
        action: 'createEndpoint',
        affected: 1,
        endpoint: out.endpoint,
        // 明文口令只在这里出现这一次（表里只有摘要，列表口拿不到）。
        secret: out.secret,
        secretShownOnce: true,
      },
    });
  }),
);

router.post(
  '/fnthink/endpoints/rotate',
  authMiddleware,
  withContext((ctx, req, res) => {
    const epc = endpointConfigOf(ctx);
    if (!epc) return res.status(503).json({ error: 'fnthink_protocol_unavailable' });
    const id = String((req.body || {}).endpointId || '');
    const endpoints = usableRow(epc, res, id);
    if (!endpoints) return;
    const out = ds.rotateEndpoint(ctx.contract, endpoints, id, Date.now(), epc);
    // 轮换**不要** confirm：旧口令在宽限期内照样能推（契约 `endpoint.rotation.graceSeconds`），
    // 误点的代价是"多铸了一把新的"，那是能原地处理的 —— 与"要对方重新配对"那一类不是一回事。
    console.log(`[fnthink:ops] rotateEndpoint ${id}`);
    return res.json({
      code: 0,
      message: 'success',
      data: {
        action: 'rotateEndpoint',
        affected: 1,
        endpoint: out.endpoint,
        secret: out.secret,
        secretShownOnce: true,
        // 旧口令还能用到什么时候：运维要么现在就去换第三方那一份，要么知道自己还有个窗口。
        oldSecretValidUntil: out.endpoint.rotatingUntil,
        graceSeconds: epc.graceSeconds,
      },
    });
  }),
);

router.post(
  '/fnthink/endpoints/policy',
  authMiddleware,
  withContext((ctx, req, res) => {
    const epc = endpointConfigOf(ctx);
    if (!epc) return res.status(503).json({ error: 'fnthink_protocol_unavailable' });
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const id = String(body.endpointId || '');
    const endpoints = usableRow(epc, res, id);
    if (!endpoints) return;
    const allow = ipAllowlistFrom(body, res);
    if (!allow.ok) return;
    if (body.name !== undefined && typeof body.name !== 'string') {
      return res.status(400).json({ code: -1, message: 'name 要是一串文本' });
    }
    const endpoint = ds.setEndpointPolicy(
      ctx.contract,
      endpoints,
      id,
      { name: body.name, postOnly: body.postOnly, ipAllowlist: allow.value },
      epc,
    );
    console.log(`[fnthink:ops] setEndpointPolicy ${id}`);
    return res.json({
      code: 0,
      message: 'success',
      data: { action: 'setEndpointPolicy', affected: 1, endpoint },
    });
  }),
);

module.exports = router;
