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

const { DATA_DIR, readJsonFile, writeJsonFile } = require('../store');
const { assertSupported, loadContract } = require('./contract');
const {
  alphabetFromContract,
  credentialDigest,
  isValidAddressCode,
  lengthFromContract,
  normalize,
} = require('./credentials');

const DEVICE_FILE = path.join(DATA_DIR, 'fnthink_devices.json');
const ENDPOINT_FILE = path.join(DATA_DIR, 'fnthink_endpoints.json');
const FILE_MODE = 0o600;
const TABLE_VERSION = 1;

/// 会被当成"存了明文凭证"的字段名；以 `Digest` 结尾的除外（那正是允许落盘的形式）。
const SECRETISH = /pairingcode|secret|token|privatekey|passphrase|pin/i;
const DIGEST_ONLY = /digest$/i;
const HEX64 = /^[0-9a-f]{64}$/;

/** 深扫结构，拒绝任何"像凭证却不是摘要"的字段。 */
function assertNoPlaintextSecrets(contract, node, trail) {
  const where = trail || '$';
  if (Array.isArray(node)) {
    node.forEach((item, i) => assertNoPlaintextSecrets(contract, item, `${where}[${i}]`));
    return;
  }
  if (node && typeof node === 'object') {
    for (const [key, value] of Object.entries(node)) {
      const at = `${where}.${key}`;
      if (SECRETISH.test(key) && !DIGEST_ONLY.test(key)) {
        throw new Error(`${at} 看起来是明文凭证，一律不落盘（要存就存摘要，键名以 Digest 结尾）`);
      }
      if (DIGEST_ONLY.test(key) && typeof value === 'string' && !HEX64.test(value)) {
        throw new Error(`${at} 以 Digest 结尾却不是 64 位十六进制摘要：${value}`);
      }
      // 键名可以起错，值不会说谎：任何字段里塞进一把"形状正确的口令"都拦下来，
      // 于是 `name: '口令是 XXXXXXXXXXXXXXXXXXXX'` 这种"就存这一次"也过不去。
      if (typeof value === 'string' && looksLikeCredential(contract, value)) {
        throw new Error(`${at} 的值是一把形状完整的口令（${value.length} 位），拒绝落盘`);
      }
      assertNoPlaintextSecrets(contract, value, at);
    }
  }
}

/// 只认**秘密**那两档长度（配对口令、端点长期口令）。地址码是公开标识，不参与判定。
function looksLikeCredential(contract, text) {
  const normalized = normalize(alphabetFromContract(contract), text);
  if (normalized === null) return false;
  const lengths = ['pairingCode', 'endpointSecret'].map((which) => {
    try {
      return lengthFromContract(contract, which);
    } catch (e) {
      return -1;
    }
  });
  return lengths.includes(normalized.length);
}

function loadTable(filePath, key) {
  const raw = readJsonFile(filePath, null);
  if (!raw || typeof raw !== 'object' || !raw[key] || typeof raw[key] !== 'object') return {};
  return raw[key];
}

/// 写咽喉自己读的这份契约：与调用方传进来的无关，就是为了让"任何一次落盘"都过同一道闸。
let writeContract = null;
function contractForWrite() {
  if (!writeContract) writeContract = assertSupported(loadContract());
  return writeContract;
}

function saveTable(filePath, key, table) {
  assertNoPlaintextSecrets(contractForWrite(), table, key);
  // 写不进去必须抛：静默返回会让调用方以为"设备已登记 / 口令已消耗"，
  // 而对端什么都不知道 —— 宁可 500，也不要一次假装成功的配对。
  if (!writeJsonFile(filePath, { version: TABLE_VERSION, [key]: table }, { mode: FILE_MODE })) {
    throw new Error(`写入 ${filePath} 失败（没落盘就不算成功）`);
  }
  return table;
}

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
  const level = assertLevel(contract, input.level || 'L1');
  const existing = devices[key];
  if (existing && existing.publicKey !== publicKey) {
    // 换公钥 = 换身份：走 T31 的重建 + 重新配对，让所有已配对发送方明确看到，
    // 不是在这里悄悄覆盖（那等于给劫持者一次不留痕迹的换手机会）。
    throw new Error(`地址码 ${key} 已绑定另一把公钥，拒绝静默替换`);
  }
  const record = existing || { createdAt: now, status: 'active', lastSeenAt: null, owner: null };
  record.publicKey = publicKey;
  record.name = typeof input.name === 'string' ? input.name.slice(0, 60) : '';
  record.level = level;
  if (input.owner !== undefined) record.owner = input.owner;
  devices[key] = record;
  saveDevices(devices);
  return record;
}

/// 挂上一枚一次性配对口令：明文只在这一次调用里经过，落盘的只有摘要。
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

/// 端点：长期口令同样只存摘要；"仅允许 POST"的默认值取契约 `transport.postOnlySwitch`。
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
  armPairingCode,
  verifyPairingCode,
  touchDevice,
  isOnline,
  putEndpoint,
  findEndpointBySecret,
};
