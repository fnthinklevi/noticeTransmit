// 配对请求表（#131 第二片 2B）：`pair` 那一步在服务端留下的「等 A 本机确认」的记录。
//
// 三条决定这张表为什么不并入别处的理由，写在头里：
//  ① **不进 messagestore**：那张表每一条都要回答「投给谁的什么内容」，还要过 capabilities 的
//     type 词表。配对请求没有正文，硬塞就得把口令写进 body —— 那是让落盘闸门去守一条
//     本该由设计守的规矩（而且请求的"收件人"要能看见它，不等于它是一条消息）。
//  ② **明文口令一个字节都不落**：记录里只有它的摘要（契约 `pairRequest.neverStored` 钉着，
//     `table.js` 的深扫再守一遍）。A poll 到这条时拿自己手上那枚算一次摘要比一下，
//     就能确认「这就是我刚挂出去的那枚」，不需要服务端复述明文。
//  ③ **服务端从不批准**：`approved` / `denied` 只能由 A 自己的签名写进来（第三片）。
//     这个模块自己能把 pending 变成的只有 expired —— 谁哪天在这里加一次 approve，
//     就等于把 `pairing.autoApprove=false` 那条红线改成注释。
//
// 键是随机 id，不是地址码：一台设备可以挂很多枚口令、被很多人扫，用地址码当键就是
// 让后来者覆盖前一条 —— 而 A 屏幕上还挂着前一条的二维码。

'use strict';

const crypto = require('crypto');
const path = require('path');

const { DATA_DIR } = require('../store');
const { resolvePath } = require('./contract');
const { alphabetFromContract, normalize } = require('./credentials');
const { loadTable, saveTable } = require('./table');

const REQUEST_FILE = path.join(DATA_DIR, 'fnthink_pair_requests.json');
const ID_BYTES = 9;

function loadRequests() {
  return loadTable(REQUEST_FILE, 'pairRequests');
}

function saveRequests(requests) {
  return saveTable(REQUEST_FILE, 'pairRequests', requests);
}

/// 契约里那一段必须存在且成形。**不补默认值**：补了就是在代码里发明一份第二真值，
/// 而这张表的形状（存什么、不存什么、活多久、谁能看见）全都该由契约说。
function requestSpec(contract) {
  const spec = contract.pairRequest;
  if (!spec || typeof spec !== 'object' || Array.isArray(spec)) {
    throw new Error('契约缺 pairRequest 段（创建了东西却没定义它长什么样）');
  }
  return spec;
}

function positiveInt(contract, spec, key) {
  const value = spec[key];
  if (typeof value !== 'number' || !Number.isInteger(value) || value <= 0) {
    throw new Error(`pairRequest.${key} 必须是正整数，实为 ${JSON.stringify(value)}`);
  }
  return value;
}

function ttlMs(contract, spec) {
  const dotted = spec.ttlSecondsFrom;
  const seconds = resolvePath(contract, dotted);
  if (typeof seconds !== 'number' || seconds <= 0) {
    throw new Error(
      `pairRequest.ttlSecondsFrom=${JSON.stringify(dotted)} 没指到一个正数秒：` +
        '另设一个 TTL 就会出现「口令还活着而请求已消失」',
    );
  }
  return seconds * 1000;
}

function initialStatus(contract, spec) {
  const status = spec.initialStatus;
  const statuses = spec.statuses || [];
  if (!statuses.includes(status) || (spec.terminalStatuses || []).includes(status)) {
    throw new Error(
      `pairRequest.initialStatus=${JSON.stringify(status)} 必须是 statuses 里那个非终态，实为 ${statuses.join('/')}`,
    );
  }
  return status;
}

function keyOf(contract, addressCode) {
  return normalize(alphabetFromContract(contract), addressCode);
}

/// 到期的 pending 标成 expired。返回改动的条数（"这次一条都没剪"也要能说出来，
/// 不然没人知道自己看到的空清单是没请求还是请求全被剪了）。
function expireDue(contract, requests, now) {
  const spec = requestSpec(contract);
  const pending = initialStatus(contract, spec);
  const expiredName = (spec.terminalStatuses || []).includes('expired') ? 'expired' : null;
  if (!expiredName)
    throw new Error('契约 pairRequest.terminalStatuses 里没有 expired：请求到期了却没处可去');
  let changed = 0;
  for (const record of Object.values(requests)) {
    if (record.status === pending && Number(record.expiresAt) <= now) {
      record.status = expiredName;
      record.statusChangedAt = now;
      changed += 1;
    }
  }
  if (changed) saveRequests(requests);
  return changed;
}

/// 新建一条待确认请求。返回 `{ok:false, reason}` 而不是抛：容量类拒绝是预期行为，
/// 不是代码 bug —— 把它抛出去会让路由只能按 500 处理，而那是"实例满了"不是"服务端坏了"。
function createRequest(contract, requests, input, now) {
  const spec = requestSpec(contract);
  const pending = initialStatus(contract, spec);
  expireDue(contract, requests, now);
  for (const field of ['target', 'requester', 'requesterPublicKey', 'level', 'codeDigest']) {
    if (typeof input[field] !== 'string' || input[field] === '') {
      throw new Error(`配对请求缺 ${field}（这张表的每一行都要能回答"谁向谁请求了什么"）`);
    }
  }
  // 先剪掉"早已终态且早已过期"的那些，再判全局上限：不然一台跑了几年的实例
  // 会因为一堆历史成就是记录而开始拒绝新配对，而那份历史对谁都没有意义了。
  const terminal = spec.terminalStatuses || [];
  for (const [id, record] of Object.entries(requests)) {
    if (terminal.includes(record.status) && Number(record.expiresAt) <= now) delete requests[id];
  }
  const perTarget = Object.values(requests).filter(
    (record) => record.status === pending && record.target === input.target,
  ).length;
  const perDevice = positiveInt(contract, spec, 'perDeviceLimit');
  if (perTarget >= perDevice) {
    return { ok: false, reason: 'per-device-limit', pending: perTarget, limit: perDevice };
  }
  const globalLimit = positiveInt(contract, spec, 'globalLimit');
  if (Object.keys(requests).length >= globalLimit) {
    // 到上限**拒绝新的**，不挤掉任何一条 pending：被挤掉的那条对应的二维码还挂在 A 的屏幕上，
    // 而 A 确认一个自己没见过的请求，比配对失败危险得多。
    return { ok: false, reason: 'global-limit', total: Object.keys(requests).length };
  }
  const id = 'pr_' + crypto.randomBytes(ID_BYTES).toString('hex');
  requests[id] = {
    id,
    target: input.target,
    requester: input.requester,
    requesterPublicKey: input.requesterPublicKey,
    level: input.level,
    codeDigest: input.codeDigest,
    createdAt: now,
    expiresAt: now + ttlMs(contract, spec),
    status: pending,
  };
  saveRequests(requests);
  return { ok: true, request: requests[id] };
}

/// poll 响应里那个键名。**不回落成字面量**：路由拼键名时如果这里返回 undefined，
/// 响应里就会出现一个 "undefined" 键，而"请求取到了却挂在没人读的键上"与"没取到"在设备上看不出区别。
function pollKey(contract) {
  const spec = requestSpec(contract);
  const via = spec.visibleVia;
  const key = spec.pollKey;
  if (via === 'poll' && (typeof key !== 'string' || key === '')) {
    throw new Error(
      '契约 pairRequest.visibleVia=poll 却没写 pollKey（请求落进了表里，却没人取得到它）',
    );
  }
  if (via !== 'poll') {
    throw new Error(`pairRequest.visibleVia=${JSON.stringify(via)}：本实现只会走 poll`);
  }
  return key;
}

/// 一台设备 poll 到的待确认请求。**显式挑字段**：将来记录里多一个内部键（比如留痕用的原因）
/// 不会顺手出现在响应里。target 不回显（问的人就是它）。
function pendingFor(contract, requests, addressCode, now) {
  const spec = requestSpec(contract);
  const pending = initialStatus(contract, spec);
  expireDue(contract, requests, now);
  const me = keyOf(contract, addressCode);
  return Object.values(requests)
    .filter((record) => record.status === pending && record.target === me)
    .sort((a, b) => Number(a.createdAt) - Number(b.createdAt))
    .map((record) => ({
      id: record.id,
      requester: record.requester,
      requesterPublicKey: record.requesterPublicKey,
      level: record.level,
      codeDigest: record.codeDigest,
      createdAt: record.createdAt,
      expiresAt: record.expiresAt,
    }));
}

module.exports = {
  ID_BYTES,
  REQUEST_FILE,
  createRequest,
  expireDue,
  initialStatus,
  loadRequests,
  pendingFor,
  pollKey,
  requestSpec,
  saveRequests,
};
