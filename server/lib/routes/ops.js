// 幻念推送的运维入口（#130-A5）：列状态 / 冻结 / 解冻 / 吊销 / 一键全部失效 / 重建后废所有发送方。
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

const { asyncHandler, authMiddleware } = require('../middleware');
const {
  loadContract,
  assertSupported,
  isContractAvailabilityError,
} = require('../fnthink/contract');
const { alphabetFromContract, isValidAddressCode, normalize } = require('../fnthink/credentials');
const ds = require('../fnthink/devicestore');

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

// 列设备状态：可按状态筛，上限取契约 ops.deviceListMax（不给"一次拉走整张表"的口）
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
        ? Math.min(requested, ctx.ops.deviceListMax)
        : ctx.ops.deviceListMax;
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

module.exports = router;
