// 幻念推送服务端存储（T27）：设备表 + 端点表。
//
// 两条硬规矩，就是这个模块存在的理由：
//  ① **明文口令与私钥永不落盘** —— 写入只有 `saveDevices` / `saveEndpoints` 两个入口，
//     它们在落盘前深扫一遍结构，看到"像凭证却不是摘要"的字段就抛。不这么做的话，迟早有人
//     在设备记录上顺手多存一个 `pairingCode: '为了调试'`，而库一泄露那就是一条能直接
//     配对设备的记录。
//  ② **地址码不存在 与 口令不对，返回同一个形状** —— 否则服务端变成"哪些地址码有效"的
//     枚举器：地址码是公开可分享的标识，口令才是秘密。
//
// 落盘沿用 `store.js` 的原子写（tmp → rename），并按 0600 设权限。

'use strict';

const crypto = require('crypto');
const path = require('path');

const { DATA_DIR, readJsonFile } = require('../store');
const {
  alphabetFromContract,
  credentialDigest,
  isValidAddressCode,
  lengthFromContract,
  normalize,
} = require('./credentials');
const {
  FILE_MODE,
  assertNoPlaintextSecrets,
  contractForWrite,
  loadTable,
  looksLikeCredential,
  saveTable,
} = require('./table');

const DEVICE_FILE = path.join(DATA_DIR, 'fnthink_devices.json');
const NONCE_FILE = path.join(DATA_DIR, 'fnthink_nonces.json');
const ENDPOINT_FILE = path.join(DATA_DIR, 'fnthink_endpoints.json');

function loadDevices() {
  return loadTable(DEVICE_FILE, 'devices');
}

function loadEndpoints() {
  return loadTable(ENDPOINT_FILE, 'endpoints');
}

function saveDevices(table) {
  return saveTable(DEVICE_FILE, 'devices', table);
}

function saveEndpoints(table) {
  return saveTable(ENDPOINT_FILE, 'endpoints', table);
}

function keyOf(contract, addressCode) {
  return normalize(alphabetFromContract(contract), addressCode);
}

/// Ed25519 公钥：32 字节的 base64。落盘前必须核形状 —— 一把长度不对的"公钥"存进去，
/// 验签永远失败，而现场看起来一切都已经配好了。
function assertPublicKey(publicKey) {
  if (typeof publicKey !== 'string' || publicKey.trim() === '') throw new Error('公钥不能为空');
  const bytes = Buffer.from(publicKey.trim(), 'base64');
  if (bytes.length !== 32) {
    throw new Error(`公钥必须是 32 字节的 base64（解出 ${bytes.length} 字节）`);
  }
  return publicKey.trim();
}

function assertLevel(contract, level) {
  const levels = (contract.capabilities || {}).levels || [];
  if (!levels.includes(level)) {
    throw new Error(`能力级别 ${level} 不在契约的 ${levels.join('/')} 里`);
  }
  return level;
}

/// 登记设备。幂等 upsert，但**公钥不许静默替换**。
function registerDevice(contract, devices, input, now) {
  if (!isValidAddressCode(contract, input.addressCode)) {
    throw new Error(`不是合法的地址码（应为 ${lengthFromContract(contract, 'addressCode')} 位）`);
  }
  const key = keyOf(contract, input.addressCode);
  const publicKey = assertPublicKey(input.publicKey);
  // 缺省档从契约读（不在这里再写一个 'L1'：两处各存一份"默认给多少"，
  // 哪天改契约那一处，这里会静默地比契约宽）。
  const defaultLevel = ((contract.capabilities || {}).grantDefaults || {}).maxLevel;
  const level = assertLevel(contract, input.level || defaultLevel);
  const existing = devices[key];
  if (existing && existing.publicKey !== publicKey) {
    // 换公钥 = 换身份：走 T31 的重建 + 重新配对，让所有已配对发送方明确看到，
    // 不是在这里悄悄覆盖（那等于给劫持者一次不留痕迹的换手机会）。
    throw new Error(`地址码 ${key} 已绑定另一把公钥，拒绝静默替换`);
  }
  if (existing && existing.grant && existing.grant.maxLevel !== level) {
    // 登记是幂等的，但**授权不是可改的**：提高或降低一个已配对发送方的级别
    // 必须走"重新确认"那条路（T31），不能让一次 re-register 顺手改掉。
    throw new Error(
      `地址码 ${key} 的授权是 ${existing.grant.maxLevel}，不能在登记里改成 ${level}（要变更请走重新确认）`,
    );
  }
  const record = existing || { createdAt: now, status: 'active', lastSeenAt: null, owner: null };
  record.publicKey = publicKey;
  record.name = typeof input.name === 'string' ? input.name.slice(0, 60) : '';
  if (!record.grant) record.grant = { maxLevel: level, items: [], revision: 1, grantedAt: now };
  if (input.owner !== undefined) record.owner = input.owner;
  devices[key] = record;
  saveDevices(devices);
  return record;
}

// ── 状态与吊销（T31）──────────────────────────────────────────
// 三条判据写在这里：① 状态名只认契约那张表（打错字的方向必须是"抛"，不是"写进去以后没人认得"）；
// ② 吊销**只停投递、不删历史**（`dataNeverDeletedByRevoke`）—— 清历史要单独一次显式操作；
// ③ 变更都走这一个咽喉，别处不许再写 `record.status = ...`。

function assertDeviceStatus(contract, status) {
  const table = (contract.revocation || {}).deviceStatuses || {};
  if (!Object.prototype.hasOwnProperty.call(table, status)) {
    throw new Error(
      `设备状态 "${status}" 不在契约的 revocation.deviceStatuses 里（可取：${Object.keys(table).join(' / ')}）`,
    );
  }
  return status;
}

function setDeviceStatus(contract, devices, addressCode, status, now) {
  assertDeviceStatus(contract, status);
  const key = keyOf(contract, addressCode);
  const record = devices[key];
  if (!record) throw new Error('设备未登记（状态不能挂在没有记录的设备上）');
  record.status = status;
  record.statusChangedAt = now;
  if (status === 'revoked') record.revokedAt = now;
  saveDevices(devices);
  return record;
}

function revokeDevice(contract, devices, addressCode, now) {
  return setDeviceStatus(contract, devices, addressCode, 'revoked', now);
}

function freezeDevice(contract, devices, addressCode, now) {
  return setDeviceStatus(contract, devices, addressCode, 'frozen', now);
}

/// 一键全部失效。返回**被改动的台数**：按这个钮的人要能回答"它到底影响了谁"，
/// 而"0 台"与"没这个钮"在现场看起来是一样的。
function revokeAllDevices(contract, devices, now) {
  const keys = Object.keys(devices).filter((k) => devices[k].status !== 'revoked');
  for (const k of keys) {
    devices[k].status = 'revoked';
    devices[k].statusChangedAt = now;
    devices[k].revokedAt = now;
  }
  if (keys.length) saveDevices(devices);
  return keys.length;
}

/// 本机身份重建之后：所有已配对的发送方都要重新配对。
/// ⚠ 这里**不删记录**（公钥、名称、授权都留着）—— 重建后要看得见"曾经是谁"，
/// 也要能重新配对回去；变的只是"谁的签名都不算"这一件事。
function invalidatePeersAfterRebuild(contract, devices, now) {
  const changed = Object.keys(devices).filter((k) => devices[k].status === 'active');
  for (const k of changed) {
    devices[k].status = 'awaitingRepair';
    devices[k].statusChangedAt = now;
  }
  if (changed.length) saveDevices(devices);
  return changed.length;
}

/// 挂上一枚一次性配对口令：明文只在这一次调用里经过，落盘的只有摘要。/// 挂上一枚一次性配对口令：明文只在这一次调用里经过，落盘的只有摘要。
function armPairingCode(contract, devices, addressCode, pairingCode, now) {
  const record = devices[keyOf(contract, addressCode)];
  if (!record) throw new Error('设备未登记（口令不能挂在不存在的设备上）');
  const ttl = ((contract.identity || {}).pairingCode || {}).ttlSeconds;
  if (typeof ttl !== 'number' || ttl <= 0)
    throw new Error('契约缺 identity.pairingCode.ttlSeconds');
  record.pairing = {
    digest: credentialDigest(contract, 'pairingCode', pairingCode),
    expiresAt: now + ttl * 1000,
    consumedAt: null,
    rotatedAt: now,
  };
  saveDevices(devices);
  return record.pairing;
}

/// 校验并**消耗**配对口令。失败一律同一个形状（`ok:false` + `unauthorized`），
/// 不区分"没这台设备 / 口令错 / 已过期 / 已消耗"——见文件头第 ② 条。
function verifyPairingCode(contract, devices, addressCode, pairingCode, now) {
  const status = (contract.statusCodes || {}).unauthorized || 401;
  const fail = { ok: false, status };
  if (!isValidAddressCode(contract, addressCode)) return fail;
  const record = devices[keyOf(contract, addressCode)];
  if (!record || !record.pairing) return fail;
  let digest;
  try {
    digest = credentialDigest(contract, 'pairingCode', pairingCode);
  } catch (e) {
    return fail; // 形状不对与"口令错"同形，不给格式探测留口子
  }
  if (digest !== record.pairing.digest) return fail;
  if (now > record.pairing.expiresAt) return fail;
  const singleUse = ((contract.identity || {}).pairingCode || {}).singleUse;
  if (record.pairing.consumedAt !== null && singleUse) return fail;
  record.pairing.consumedAt = now;
  saveDevices(devices);
  return { ok: true, status };
}

function touchDevice(contract, devices, addressCode, now) {
  const record = devices[keyOf(contract, addressCode)];
  if (!record) return null;
  record.lastSeenAt = now;
  saveDevices(devices);
  return record;
}

/// 在线 = poll 即心跳：阈值 = 倍数 × 拉取间隔（契约 presence，不另设心跳协议）。
/// 从未上线的设备返回 false（`lastSeenAt` 为空），但**状态列仍是"未知"不是"离线"** ——
/// 那是 T42 显示层的三态，这里只回答"现在算不算在线"。
function isOnline(contract, record, now, pollIntervalSeconds) {
  if (!record || record.lastSeenAt === null || record.lastSeenAt === undefined) return false;
  const presence = contract.presence || {};
  const poll =
    pollIntervalSeconds === undefined
      ? (presence.pollIntervalSeconds || {}).default || null
      : pollIntervalSeconds;
  const multiplier = presence.onlineThresholdMultiplier;
  if (typeof poll !== 'number' || typeof multiplier !== 'number') {
    throw new Error('presence 段缺 pollIntervalSeconds.default 或 onlineThresholdMultiplier');
  }
  return now - record.lastSeenAt <= poll * multiplier * 1000;
}

/// 在线**三态**。`isOnline` 只回答"现在算不算在线"，它把"从未上线"与"掉线"都答 false ——
/// 而这两件在界面上必须是两件事（契约 `presence.unknownMeans`），把它们合成一个是把
/// "还没配过这台设备"显示成"那台设备离线了"。所以显示层调这个，别自己猜。
function devicePresence(contract, record, now, pollIntervalSeconds) {
  const states = (contract.presence || {}).states || [];
  if (!record || record.lastSeenAt === null || record.lastSeenAt === undefined) {
    return states.includes('unknown') ? 'unknown' : 'offline';
  }
  return isOnline(contract, record, now, pollIntervalSeconds) ? 'online' : 'offline';
}

/// 端点：长期口令同样只存摘要；/// 端点：长期口令同样只存摘要；"仅允许 POST"的默认值取契约 `transport.postOnlySwitch`。
function putEndpoint(contract, endpoints, input, now) {
  const id = typeof input.id === 'string' && input.id ? input.id : newEndpointId();
  const existing = endpoints[id];
  if (!input.secret && !existing) throw new Error('新建端点必须带口令（服务端只存它的摘要）');
  const record = existing || { createdAt: now, revokedAt: null };
  record.name = typeof input.name === 'string' ? input.name.slice(0, 60) : '';
  if (input.secret)
    record.secretDigest = credentialDigest(contract, 'endpointSecret', input.secret);
  const defaultPostOnly = !contract.transport || contract.transport.postOnlySwitch !== false;
  record.postOnly =
    input.postOnly === undefined
      ? existing
        ? record.postOnly
        : defaultPostOnly
      : !!input.postOnly;
  if (input.revoked === true) record.revokedAt = now;
  endpoints[id] = record;
  saveEndpoints(endpoints);
  return Object.assign({ id }, record);
}

function findEndpointBySecret(contract, endpoints, secret) {
  let digest;
  try {
    digest = credentialDigest(contract, 'endpointSecret', secret);
  } catch (e) {
    return null;
  }
  const hit = Object.entries(endpoints).find(
    ([, record]) => !record.revokedAt && record.secretDigest === digest,
  );
  return hit ? Object.assign({ id: hit[0] }, hit[1]) : null;
}

// ── nonce 去重（T29-B）─────────────────────────────────────────────
// 只存「发送方地址码|nonce → 到期时间」：地址码是公开标识，nonce 本身不是秘密。
// 去重表必须能活过重启 —— 只在内存里记一遍，等于每次进程重启就开一次重放窗口。

function loadNonces() {
  const raw = readJsonFile(NONCE_FILE, null);
  if (!raw || typeof raw !== 'object' || !raw.nonces || typeof raw.nonces !== 'object') return {};
  return raw.nonces;
}

function saveNonces(map) {
  return saveTable(NONCE_FILE, 'nonces', map);
}

function seenNonce(map, key, nowMs) {
  const entry = map[key];
  return !!entry && Number(entry.expiresAt) > nowMs;
}

/// 记住一枚 nonce 并顺手剪掉已到期的（表只会因重启而膨胀，不剪就是给未来留一次 OOM）。
function rememberNonce(map, key, nowMs, ttlSeconds) {
  if (!(ttlSeconds > 0)) throw new Error('nonceDedupeSeconds 必须是正数，实为 ' + ttlSeconds);
  for (const [k, entry] of Object.entries(map)) {
    if (Number(entry.expiresAt) <= nowMs) delete map[k];
  }
  map[key] = { expiresAt: nowMs + ttlSeconds * 1000, seenAt: nowMs };
  return map[key];
}

// ── 拒收留痕（T29-B）───────────────────────────────────────────
// 任务书那句"失败即丢并计数"：光丢不计数，被假签名打就是**静默**地丢，现场什么都看不出来。
// 这份计数是给显示层（"最近有 N 次冒充你的尝试"）用的。
// 故意**不落盘**：这条路径的输入是不用认证的垃圾包，每来一条写一次盘等于免费送攻击者
// 一个"发一个包 ⇒ 服务端一次磁盘写"的放大器。重启清零可接受 —— 它的价值在"正在被打的
// 当下能看见"，不是长期审计（真要审计是 T40 的配额与日志）。
const REJECT_KEY_CAP = 512;
// 冲刷足够久会把"被指名冒充"那条也挤掉 —— 这份是**当下的可见性**，不是长期审计账本。
// 要账本去 T40（配额 + 日志），别在这里加持久化：那等于把写盘代价转给未认证流量。
const REJECT_INVALID_KEY = '<不是合法地址码>';

/// 只有"形似某个真地址码"的尝试才单独记 —— 被指名冒充才有信号价值；
/// 长度/字符不对的输入统一进一个桶，免得给随机串留一份免费的名册。
function rejectKeyFor(contract, senderAddress) {
  if (!isValidAddressCode(contract, senderAddress || '')) return REJECT_INVALID_KEY;
  return normalize(alphabetFromContract(contract), senderAddress);
}

/// 记一笔并返回该键的最新计数。键数封顶（用常量而不是参数：让测试能绕过封顶，
/// 等于没测）：不封顶就是拿随机地址码免费涨内存。
function rememberReject(map, key, nowMs, reason) {
  const prev = map[key];
  map[key] = {
    count: (Number(prev && prev.count) || 0) + 1,
    lastAt: nowMs,
    lastReason: reason,
  };
  const keys = Object.keys(map);
  if (keys.length > REJECT_KEY_CAP) {
    keys.sort((a, b) => Number(map[a].lastAt) - Number(map[b].lastAt));
    for (const drop of keys.slice(0, keys.length - REJECT_KEY_CAP)) delete map[drop];
  }
  return map[key];
}

function newEndpointId() {
  return 'ep_' + crypto.randomBytes(9).toString('hex');
}

module.exports = {
  DEVICE_FILE,
  ENDPOINT_FILE,
  FILE_MODE,
  assertNoPlaintextSecrets,
  assertPublicKey,
  looksLikeCredential,
  loadDevices,
  loadEndpoints,
  saveDevices,
  saveEndpoints,
  registerDevice,
  assertDeviceStatus,
  freezeDevice,
  invalidatePeersAfterRebuild,
  revokeAllDevices,
  revokeDevice,
  setDeviceStatus,
  armPairingCode,
  verifyPairingCode,
  touchDevice,
  isOnline,
  devicePresence,
  putEndpoint,
  findEndpointBySecret,
  NONCE_FILE,
  loadNonces,
  saveNonces,
  seenNonce,
  rememberNonce,
  REJECT_INVALID_KEY,
  REJECT_KEY_CAP,
  rejectKeyFor,
  rememberReject,
};
