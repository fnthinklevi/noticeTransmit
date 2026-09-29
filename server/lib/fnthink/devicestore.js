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
// 只要"契约内容缺这台实现要读的数"就必须打这个标记（#130-A4 那条）：让它冒成普通 Error 的话，
// 挂载方分不清这是部署问题还是代码 bug，而错的修法是把 catch 放宽。
const { shapeError } = require('./contract');
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

/// 设备表到上限时抛的那枚 code：路由靠它决定"回 429（实例满了）"还是"往上抛（代码坏了）"。
/// 与 contract.js 那三类契约错误同一套理由 —— 按种类判，不比对错误文案。
const DEVICE_CAP_CODE = 'FNTHINK_DEVICE_CAP';
/// 端点数量到上限（每台 / 全局）。与设备上限同一个处理方向：只拒新的，绝不挤掉已有端点。
const ENDPOINT_CAP_CODE = 'FNTHINK_ENDPOINT_CAP'; /// 登记这一步的两种**业务拒绝**（换公钥 / 顺手改授权）也各自带 code：
/// 它们的消息文本里有地址码，是给运维日志看的；一路冒到 errorMiddleware 就会变成
/// 一次 500 + "这个地址码已经绑过另一把钥匙"，而 /register 是公网面 —— 那就是枚举器。
const DEVICE_KEY_SWAP_CODE = 'FNTHINK_DEVICE_KEY_SWAP';

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
///
/// ⚠ 登记**不产生任何授权**（#131 第三片改的就是这一件）：旧版在这里往发送方自己那一行写
///   `grant`，而收单读的就是那份 —— 效果是"谁登记过就能给任何人投"。授权的内容是
///   「A 允许 B 投给我」，做决定的是被投的那台，所以它存在 A 的 `grantsBy` 里（契约
///   `pairing.relationshipStoredOn`），由 A 自己的 pairConfirm 签名带进来。
///   这里顺手把老行里那份 `grant` 清掉：留着它不会放行任何东西，但它会一直骗读代码的人
///   —— "看着权威、其实没人读"的字段比缺字段更贵。
function registerDevice(contract, devices, input, now) {
  if (!isValidAddressCode(contract, input.addressCode)) {
    throw new Error(`不是合法的地址码（应为 ${lengthFromContract(contract, 'addressCode')} 位）`);
  }
  const key = keyOf(contract, input.addressCode);
  const publicKey = assertPublicKey(input.publicKey);
  const existing = devices[key];
  // 设备表上限（契约 limits.devicesMax）。/register 是全协议唯一一类「提交者还没有身份」的
  // 写入面：攻击者做一次的成本是生成一把 Ed25519 密钥，服务端做一次的成本是一行记录加一次磁盘写。
  // 到上限一律**拒绝新的**，绝不覆盖任何已有记录（覆盖一次就是一次静默换身份）。
  // 已存在的设备再登记一次不受这条影响 —— 否则表一满，现网设备连"刷新名字"都做不了。
  const cap = Number((contract.limits || {}).devicesMax);
  if (!Number.isInteger(cap) || cap <= 0) {
    throw new Error(
      '契约缺 limits.devicesMax（不补默认上限：没有上限就是给未认证流量送一台无限增长的存储）',
    );
  }
  if (!existing && Object.keys(devices).length >= cap) {
    // 带 code 抛，让调用方能把它与"代码 bug"分辨开（与 contract.js 那三类同一套路）：
    // 路由要靠它决定"回 429"还是"往上抛"，靠比对错误文案一旦改文案就瞎了。
    const err = new Error(`设备表已到上限 ${cap} 台，新登记暂缓（不覆盖任何已有记录）`);
    err.code = DEVICE_CAP_CODE;
    throw err;
  }
  if (existing && existing.publicKey !== publicKey) {
    // 换公钥 = 换身份：走 T31 的重建 + 重新配对，让所有已配对发送方明确看到，
    // 不是在这里悄悄覆盖（那等于给劫持者一次不留痕迹的换手机会）。
    // ⚠ 带 code 抛，而且文案里的地址码是给运维看的、**不是给响应体看的**：
    //   这条走法若冒到 HTTP 层，回出去的 500 就把"这个地址码已经绑过另一把钥匙"说出去了 ——
    //   那正是 T27 立"同形"那条时要防的枚举器。路由按 code 把它咽成与其它身份失败同一句话。
    const err = new Error(`地址码 ${key} 已绑定另一把公钥，拒绝静默替换`);
    err.code = DEVICE_KEY_SWAP_CODE;
    throw err;
  }
  const record = existing || {
    createdAt: now,
    // 新登记的记录落在"允许投递"那一档，与解冻是同一个来源（以前这里写死一个字符串，
    // 那是第四处第二份真值：契约改档位名时它不会报错，只会让新设备一登记就没人认得它的状态）。
    status: resumableStatus(contract),
    lastSeenAt: null,
    owner: null,
  };
  // 关系那一列**只由契约命名**（下面那一段），这里不许写一遍列名当种子：
  // 写了就是第二份真值，列名换了会多出一个谁都不读的空调用，而正确的那一列照样能建起来 —— 没人报错。
  record.publicKey = publicKey;
  record.name = typeof input.name === 'string' ? input.name.slice(0, 60) : '';
  if (
    !record[relationshipField(contract)] ||
    typeof record[relationshipField(contract)] !== 'object'
  ) {
    record[relationshipField(contract)] = {};
  }
  delete record.grant; // 见函数头：那份授权已经换地方了，留着一份没人读的 grant 比缺一份更贵
  if (input.owner !== undefined) record.owner = input.owner;
  devices[key] = record;
  saveDevices(devices);
  return record;
}

/// 契约里那一列叫什么。**不在代码里写死**：列名换了而代码不动，表现是关系读不到 ⇒
/// 所有已配对发送方一夜之间全被拒（而每条拒收日志都写着"没配对"，看着像数据被人清了）。
function relationshipField(contract) {
  const field = (contract.pairing || {}).relationshipField;
  if (typeof field !== 'string' || field === '') {
    throw new Error(
      '契约缺 pairing.relationshipField（不补默认列名：补了就是在代码里发明一份表结构）',
    );
  }
  return field;
}

/// 读「A 允许 B 投到哪一档」这一条关系。**读不到就返回 null** —— 由调用方按
/// `pairing.relationshipRequiredForIntake` 决定"拒"，这里不回落成缺省档：
/// 缺省档防的是"有授权记录但字段缺"，把它当成"谁都没配过对"的默认放行方向就是 fail-open。
function peerGrant(contract, record, peerCode) {
  const by = record ? record[relationshipField(contract)] : null;
  if (!by || typeof by !== 'object' || Array.isArray(by)) return null;
  const peerKey = keyOf(contract, peerCode);
  if (peerKey === null) return null;
  // 用 hasOwnProperty：普通对象上 `by['constructor']` 会取到 Object.prototype 那个真值，
  // 于是"任何一个能 normalize 成合法地址码的输入"之外又多了一条不走的路（本仓在会话表上栽过）。
  const entry = Object.prototype.hasOwnProperty.call(by, peerKey) ? by[peerKey] : null;
  if (!entry || typeof entry !== 'object' || Array.isArray(entry)) return null;
  return entry;
}

/// A 确认把 B 写进自己的白名单 —— 授权写入的**唯一咽喉**，别处不许再写 `grantsBy[...]`。
/// 只有 A 自己的签名能走到这里（routes 的 /pair-confirm 先过 authorizePairConfirm）。
/// ⚠ 每次确认都把 `items` 重置成空清单：重新配对不继承旧的逐条勾选 —— L2/L3 那些
///   "每一次都要人看一眼"的条目，不该因为重新扫一次码就自动回来（契约 itemRequiredFromLevel 的方向）。
function approvePeer(contract, devices, addressCode, peerCode, level, now) {
  const record = devices[keyOf(contract, addressCode)];
  if (!record) throw new Error('设备未登记（授权不能挂在没有记录的设备上）');
  const peerKey = keyOf(contract, peerCode);
  if (peerKey === null || !isValidAddressCode(contract, peerKey)) {
    throw new Error('对方地址码不合法（授权不能写给一个不像地址码的东西）');
  }
  assertLevel(contract, level);
  const field = relationshipField(contract);
  if (!record[field] || typeof record[field] !== 'object' || Array.isArray(record[field])) {
    record[field] = {};
  }
  const prev = Object.prototype.hasOwnProperty.call(record[field], peerKey)
    ? record[field][peerKey]
    : null;
  record[field][peerKey] = {
    maxLevel: level,
    items: [],
    revision: (Number(prev && prev.revision) || 0) + 1,
    grantedAt: now,
  };
  saveDevices(devices);
  return record[field][peerKey];
}

/// A 撤销对 B 的授权 —— **全服务端唯一一处**从 `grantsBy` 里删条目的地方（与 `approvePeer` 对称：
/// 那边是唯一写入者，这边是唯一删除者；别处再写一次 `delete by[...]` 就等于多一本账）。
///
/// ⚠ 三条：
///  ① 只删 A 自己那一份关系。设备表里不存"B 允许 A"——`pairing.relationshipStoredOn` 说的是
///    授权存在**被投那台**的记录上，所以双向配对里"我撤了我的"从来不等于"对面撤了对面的"；
///  ② 撤一条本来就不存在的关系：**不改表、不抛、回 `removed:false`**。撤销是幂等的 —— 目标状态是
///    「这个 peer 不在我的名单里」，已经不在就是已达成；抛错或回 404 只会让客户端把"本来没有"
///    当成一次失败，从而留着本机那一行不再删（两边从此各说一段）；
///  ③ 这里**不留墓碑字段**（`grantsBy[peer]` 直接删）。留一条 `revoked:true` 的记录就得让入站
///    判定多读一个分支，而忘了读那一支就是 fail-open：撤过的对面还能推进来。
///    "曾经给过谁、什么时候撤的"要看得见，靠的是留痕与备份里的那份表，不是靠在这一行留个记号。
function revokePeer(contract, devices, addressCode, peerCode, now) {
  const record = devices[keyOf(contract, addressCode)];
  if (!record) throw new Error('设备未登记（撤销不能挂在没有记录的设备上）');
  const peerKey = keyOf(contract, peerCode);
  if (peerKey === null || !isValidAddressCode(contract, peerKey)) {
    throw new Error('对方地址码不合法（撤销不能指向一个不像地址码的东西）');
  }
  const field = relationshipField(contract);
  const by = record[field];
  const had =
    !!by &&
    typeof by === 'object' &&
    !Array.isArray(by) &&
    Object.prototype.hasOwnProperty.call(by, peerKey);
  if (!had) return { removed: false, at: now };
  delete by[peerKey];
  saveDevices(devices);
  return { removed: true, at: now };
}

/// 本机身份重建后：所有在册发送方都要重新配对 —— 实现在下面那一节的
/// `invalidatePeersAfterRebuild`（T31② 落的，调用方是 ops.js 的 `POST /fnthink/devices/rebuild-invalidation`）。
/// ⚠ 它改的是**在册设备自己的状态**（active → 重建后那一档），既不删记录也不动任何人的 `grantsBy`。
///   而"A 单条划掉 B"那一发至今**没有入口**：设备面没有对应的签名事件，管理面也只有按台的 revoke
///   与一键冻结。所以幻念推送页的名单今日是只读的 —— 那半边理由写在
///   `lib/services/fnthink_peer_service.dart`（本机删行 ≠ 对面推不进来）。

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

/// 状态名一律从契约的词汇表读（#130-A5）。以前这里是三处写死的字符串
/// （吊销那一档、允许投递那一档、待重建那一档），那是典型的第二份真值：契约哪天加一档而
/// 代码里那串没跟上，表现不是报错，而是"这台设备的状态看着正常，但没有任何代码认得它"。
function statusNameOf(contract, key) {
  const revocation = (contract || {}).revocation || {};
  const table = revocation.deviceStatuses || {};
  const value = revocation[key];
  if (typeof value !== 'string' || !value) {
    throw shapeError(
      `revocation.${key} 缺失或非字符串：状态名只能从契约读，实现里不许留一份"看不见的缺省"`,
    );
  }
  // 这里**不调 assertDeviceStatus**：那个函数管的是"外部（运维）给了一个不认识的档位"，
  // 那是用户输入错误（该 400）；而这里错的是契约文件本身 —— 它是"内容缺这台实现要读的数"那一类，
  // 必须打成可降级的 SHAPE，让启动横幅说破原因，而不是在某个请求里冒成一次输入错误。
  if (!Object.prototype.hasOwnProperty.call(table, value)) {
    throw shapeError(
      `revocation.${key} 指向状态表外的一档（实际 ${value}，可取：${Object.keys(table).join(' / ')}）：` +
        '名字漂在表外不会报错，只会让这台设备的状态没有任何代码认得',
    );
  }
  return value;
}

const revokedStatus = (contract) => statusNameOf(contract, 'revokedStatus');
const frozenStatus = (contract) => statusNameOf(contract, 'frozenStatus');
const resumableStatus = (contract) => statusNameOf(contract, 'resumableStatus');
const afterRebuildStatus = (contract) => statusNameOf(contract, 'afterRebuildStatus');

/// 运维入口的口径（同样只从契约读）：列状态的上限与"哪些动作要先确认"。
function opsConfigFromContract(contract) {
  const src = (contract || {}).ops;
  if (!src || typeof src !== 'object') {
    throw shapeError('契约缺 ops 段：运维入口的确认名单与列表上限没有第二个来源');
  }
  const listMaxRows = Number(src.listMaxRows);
  if (!Number.isInteger(listMaxRows) || listMaxRows <= 0) {
    throw shapeError(
      `ops.listMaxRows 必须是正整数（实际 ${src.listMaxRows}）：列状态没有上限，` +
        '就是把管理面做成一台一次拉走整张设备表的机器',
    );
  }
  const list = Array.isArray(src.confirmationRequiredFor)
    ? src.confirmationRequiredFor.map(String)
    : null;
  if (!list || !list.length) {
    throw shapeError(
      'ops.confirmationRequiredFor 必须是非空数组：一个都不要求确认，等于把"回不去的那类动作"' +
        '（吊销要重配、一键全部失效要整片重配）挂在一次误点上',
    );
  }
  return { listMaxRows, confirmationRequired: new Set(list) };
}

function setDeviceStatus(contract, devices, addressCode, status, now) {
  assertDeviceStatus(contract, status);
  const key = keyOf(contract, addressCode);
  const record = devices[key];
  if (!record) throw new Error('设备未登记（状态不能挂在没有记录的设备上）');
  record.status = status;
  record.statusChangedAt = now;
  if (status === revokedStatus(contract)) record.revokedAt = now;
  saveDevices(devices);
  return record;
}

function revokeDevice(contract, devices, addressCode, now) {
  return setDeviceStatus(contract, devices, addressCode, revokedStatus(contract), now);
}

function freezeDevice(contract, devices, addressCode, now) {
  return setDeviceStatus(contract, devices, addressCode, frozenStatus(contract), now);
}

/// 解冻：去处是契约里"允许投递"的那一档（resumableStatus），不是在代码里写回某个状态字符串。
function resumeDevice(contract, devices, addressCode, now) {
  return setDeviceStatus(contract, devices, addressCode, resumableStatus(contract), now);
}

/// 一键全部失效。返回**被改动的台数**：按这个钮的人要能回答"它到底影响了谁"，
/// 而"0 台"与"没这个钮"在现场看起来是一样的。
function revokeAllDevices(contract, devices, now) {
  const revoked = revokedStatus(contract);
  const keys = Object.keys(devices).filter((k) => devices[k].status !== revoked);
  for (const k of keys) {
    devices[k].status = revoked;
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
  const active = resumableStatus(contract);
  const next = afterRebuildStatus(contract);
  const changed = Object.keys(devices).filter((k) => devices[k].status === active);
  for (const k of changed) {
    devices[k].status = next;
    devices[k].statusChangedAt = now;
  }
  if (changed.length) saveDevices(devices);
  return changed.length;
}

/// 按状态挑设备（运维列状态用）。返回**表里的原对象**，端出去之前必须过 ops.js 的白名单取字段。
function devicesInStatus(devices, status) {
  return Object.keys(devices)
    .filter((k) => devices[k].status === status)
    .map((k) => ({ addressCode: k, ...devices[k] }));
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

/// 端点段（T38）：数字与语义一律从契约读，取不到就抛可降级的 SHAPE。
function endpointConfigFromContract(contract) {
  const src = (contract || {}).endpoint;
  if (!src || typeof src !== 'object') {
    throw shapeError('契约缺 endpoint 段：端点的上限、轮换宽限与调用日志形状没有第二个来源');
  }
  const intOf = (value, name, max) => {
    const n = Number(value);
    if (!Number.isInteger(n) || n <= 0 || (max !== undefined && n > max)) {
      throw shapeError(
        `endpoint.${name} 必须是正整数${max !== undefined ? `且 ≤ ${max}` : ''}（实际 ${value}）`,
      );
    }
    return n;
  };
  const statuses = Array.isArray(src.statuses) ? src.statuses.map(String) : [];
  if (
    statuses.length !== 2 ||
    !statuses.includes(String(src.usableStatus)) ||
    !statuses.includes(String(src.revokedStatus)) ||
    String(src.usableStatus) === String(src.revokedStatus)
  ) {
    throw shapeError(
      `endpoint.statuses / usableStatus / revokedStatus 不自洽（${statuses.join(', ')} | ` +
        `${src.usableStatus} | ${src.revokedStatus}）：判定"还能不能用"必须是白名单式`,
    );
  }
  if (src.ipAllowlistEmptyMeans !== 'any') {
    throw shapeError(
      'endpoint.ipAllowlistEmptyMeans 只能是 any：空名单若谁都拒，表现是"口令对却全 401"，' +
        '看起来像服务端坏了；配置项的缺省必须是"没配也能跑"那个方向',
    );
  }
  if (src.ipMismatchOutcome !== 'same-as-bad-secret') {
    throw shapeError(
      'endpoint.ipMismatchOutcome 必须是 same-as-bad-secret：给出不同结论的入口就是一台' +
        '"哪个来源 IP 被哪个端点允许"的探针',
    );
  }
  const methodStatus = Number(src.postOnlyMethodStatus);
  if (!(methodStatus >= 400 && methodStatus < 500)) {
    throw shapeError(
      `endpoint.postOnlyMethodStatus 必须是 4xx（实际 ${src.postOnlyMethodStatus}）`,
    );
  }
  const log = src.callLog || {};
  const fields = Array.isArray(log.fields) ? log.fields.map(String) : [];
  const forbidden = ['body', 'title', 'secret', 'path', 'url', 'signature', 'pairingCode'];
  const dirty = fields.filter((f) => forbidden.includes(f));
  if (!fields.length || dirty.length) {
    throw shapeError(
      `endpoint.callLog.fields 只能存元数据（时间/来源/结论）：${
        dirty.length ? `出现了 ${dirty.join(', ')}` : '名单为空'
      } —— 正文一旦进日志，auditStoresMetadataOnly 就是空话`,
    );
  }
  return {
    usableStatus: String(src.usableStatus),
    revokedStatus: String(src.revokedStatus),
    perDeviceMax: intOf(src.perDeviceMax, 'perDeviceMax'),
    globalMax: intOf(src.globalMax, 'globalMax'),
    graceSeconds: intOf((src.rotation || {}).graceSeconds, 'rotation.graceSeconds', 86400),
    methodStatus,
    callLogMax: intOf(log.maxPerEndpoint, 'callLog.maxPerEndpoint', 1000),
    callLogFields: fields,
  };
}

/// 生成一把端点口令：字母表与位数都取契约 identity.endpointSecret。
/// ⚠ 用 crypto.randomInt 而不是"取模随机字节"：Crockford 字母表长 31，不整除 256，
///   取模会让某些字符更常见 —— 口令分布的偏置正是这类"看起来是随机"的实现最容易漏掉的。
function newEndpointSecret(contract) {
  const alphabet = alphabetFromContract(contract);
  const length = lengthFromContract(contract, 'endpointSecret');
  let out = '';
  for (let i = 0; i < length; i += 1) out += alphabet[crypto.randomInt(alphabet.length)];
  return out;
}

/// 端点的对外形状。**secretDigest 一律不带**：摘要是"可离线爆破的靶子"，
/// 而口令本身服务端从头到尾没存过 —— 把靶子端出去，等于把一次泄露的代价从"要猜"降成"能验"。
function publicEndpoint(id, record) {
  return {
    id,
    name: record.name || '',
    owner: record.owner || null,
    status: record.status,
    postOnly: record.postOnly === true,
    ipAllowlist: Array.isArray(record.ipAllowlist) ? [...record.ipAllowlist] : [],
    createdAt: record.createdAt === undefined ? null : record.createdAt,
    lastUsedAt: record.lastUsedAt === undefined ? null : record.lastUsedAt,
    revokedAt: record.revokedAt === undefined ? null : record.revokedAt,
    // 只报"旧口令还能用到什么时候"，不报旧摘要本身。
    rotatingUntil: record.rotatedFrom ? record.rotatedFrom.validUntil : null,
    calls: Array.isArray(record.calls) ? record.calls.map((entry) => ({ ...entry })) : [],
  };
}

/// 创建一个端点。⚠ 明文口令只在这一次返回（调用方必须当场转交，不留副本）。
function createEndpoint(contract, endpoints, input = {}, now, cfg) {
  const epc = cfg || endpointConfigFromContract(contract);
  const usable = (record) => !!record && record.status === epc.usableStatus;
  const owner = typeof input.owner === 'string' && input.owner ? input.owner : null;
  // 到上限**只拒新的**：挤掉一个已有端点等于让某台 NAS 的定时任务从此静默失效，
  // 而那正是"设备表到上限也不覆盖已有记录"同一条红线。
  if (
    Object.values(endpoints).filter((r) => usable(r) && (r.owner || null) === owner).length >=
    epc.perDeviceMax
  ) {
    const err = new Error(`这台设备的可用端点已达上限 ${epc.perDeviceMax}`);
    err.code = ENDPOINT_CAP_CODE;
    throw err;
  }
  if (Object.values(endpoints).filter(usable).length >= epc.globalMax) {
    const err = new Error(`端点总数已达全局上限 ${epc.globalMax}`);
    err.code = ENDPOINT_CAP_CODE;
    throw err;
  }
  const alphabet = alphabetFromContract(contract);
  const length = lengthFromContract(contract, 'endpointSecret');
  let secret;
  if (typeof input.secret === 'string' && input.secret) {
    secret = normalize(alphabet, input.secret);
    if (secret === null || secret.length !== length) {
      throw new Error('端点口令形状不符（按契约 identity.endpointSecret 的字母表与位数）');
    }
  } else {
    secret = newEndpointSecret(contract);
  }
  const id = newEndpointId();
  const defaultPostOnly = !contract.transport || contract.transport.postOnlySwitch !== false;
  const record = {
    name: typeof input.name === 'string' ? input.name.slice(0, 60) : '',
    owner,
    status: epc.usableStatus,
    postOnly: input.postOnly === undefined ? defaultPostOnly : !!input.postOnly,
    ipAllowlist: Array.isArray(input.ipAllowlist) ? input.ipAllowlist.map(String) : [],
    secretDigest: credentialDigest(contract, 'endpointSecret', secret),
    rotatedFrom: null,
    createdAt: now,
    lastUsedAt: null,
    revokedAt: null,
    calls: [],
  };
  endpoints[id] = record;
  saveEndpoints(endpoints);
  return { id, secret, endpoint: publicEndpoint(id, record) };
}

/// 轮换：新口令立刻生效，旧口令在 graceSeconds 内仍可验证。
/// 没有宽限期的后果不是不便，是"从此没人换口令" —— 第三方平台里的口令是抄进去的，
/// 换一次要人挨个改，而改不动的那一处就成了永远不换的长期凭证。
function rotateEndpoint(contract, endpoints, id, now, cfg) {
  const epc = cfg || endpointConfigFromContract(contract);
  const record = endpoints[id];
  if (!record || record.status !== epc.usableStatus) {
    throw new Error('端点不存在或已吊销（轮换不许让一个已吊销的端点复活）');
  }
  const secret = newEndpointSecret(contract);
  record.rotatedFrom = {
    secretDigest: record.secretDigest,
    rotatedAt: now,
    validUntil: now + epc.graceSeconds * 1000,
  };
  record.secretDigest = credentialDigest(contract, 'endpointSecret', secret);
  saveEndpoints(endpoints);
  return { id, secret, endpoint: publicEndpoint(id, record) };
}

function revokeEndpoint(contract, endpoints, id, now, cfg) {
  const epc = cfg || endpointConfigFromContract(contract);
  const record = endpoints[id];
  if (!record) return null;
  const wasUsable = record.status === epc.usableStatus;
  if (wasUsable) {
    record.status = epc.revokedStatus;
    record.revokedAt = now;
    // 宽限期里的旧摘要一起清掉：留着它，"已吊销"就仍然可能被验过 —— 这正是黑名单式判定的漏法。
    record.rotatedFrom = null;
    saveEndpoints(endpoints);
  }
  return { revoked: wasUsable, endpoint: publicEndpoint(id, record) };
}

/// 接收端的自管设置：命名、IP 白名单、仅允许 POST。口令本身不在这里动（那是 rotate 的事）。
function setEndpointPolicy(contract, endpoints, id, patch = {}, cfg) {
  const epc = cfg || endpointConfigFromContract(contract);
  const record = endpoints[id];
  if (!record || record.status !== epc.usableStatus) {
    throw new Error('端点不存在或已吊销（设置不能挂在一个已经不存在的入口上）');
  }
  if (typeof patch.name === 'string') record.name = patch.name.slice(0, 60);
  if (patch.postOnly !== undefined) record.postOnly = !!patch.postOnly;
  if (Array.isArray(patch.ipAllowlist)) record.ipAllowlist = patch.ipAllowlist.map(String);
  saveEndpoints(endpoints);
  return publicEndpoint(id, record);
}

/// 空名单 = 不限来源（契约 ipAllowlistEmptyMeans=any）。CIDR 不在这一片，留 T40 与配额同批。
function endpointIpAllowed(record, ip) {
  const list = Array.isArray(record && record.ipAllowlist) ? record.ipAllowlist : [];
  if (!list.length) return true;
  return list.map(String).includes(String(ip));
}

/// 按口令找端点：当前摘要或**宽限期内的旧摘要**都算命中。
/// 返回 usedRotated 给上层留痕（"还在用旧口令"这件事运维应当看得见，但它不改变对外结论）。
function findEndpointBySecret(contract, endpoints, secret, now, cfg) {
  const epc = cfg || endpointConfigFromContract(contract);
  let digest;
  try {
    digest = credentialDigest(contract, 'endpointSecret', secret);
  } catch (e) {
    return null;
  }
  const when = now === undefined ? Date.now() : now;
  for (const [id, record] of Object.entries(endpoints)) {
    if (!record || record.status !== epc.usableStatus) continue;
    if (record.secretDigest === digest) {
      return Object.assign({ id, usedRotated: false }, record);
    }
    const rotated = record.rotatedFrom;
    if (rotated && rotated.secretDigest === digest && Number(rotated.validUntil) > when) {
      return Object.assign({ id, usedRotated: true }, record);
    }
  }
  return null;
}

/// 最近调用日志：只按契约白名单挑字段（多余的键一概不记也不回显），并按上限保新截尾。
/// 没有上限的那份"最近调用"就是攻击者驱动的存储 —— 而它是洪水最容易打到的那一项。
function recordEndpointCall(contract, endpoints, id, entry = {}, now, cfg) {
  const epc = cfg || endpointConfigFromContract(contract);
  const record = endpoints[id];
  if (!record) return null;
  const at = entry.at === undefined ? now : entry.at;
  const logged = { at };
  for (const field of epc.callLogFields) {
    if (field === 'at') continue;
    logged[field] = entry[field] === undefined ? null : entry[field];
  }
  record.calls = [...(Array.isArray(record.calls) ? record.calls : []), logged].slice(
    -epc.callLogMax,
  );
  record.lastUsedAt = at;
  saveEndpoints(endpoints);
  return record.calls.length;
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
  DEVICE_CAP_CODE,
  DEVICE_KEY_SWAP_CODE,
  approvePeer,
  revokePeer,
  peerGrant,
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
  relationshipField,
  assertDeviceStatus,
  revokedStatus,
  frozenStatus,
  resumableStatus,
  afterRebuildStatus,
  opsConfigFromContract,
  devicesInStatus,
  freezeDevice,
  resumeDevice,
  invalidatePeersAfterRebuild,
  revokeAllDevices,
  revokeDevice,
  setDeviceStatus,
  armPairingCode,
  verifyPairingCode,
  touchDevice,
  isOnline,
  devicePresence,
  endpointConfigFromContract,
  newEndpointSecret,
  publicEndpoint,
  createEndpoint,
  rotateEndpoint,
  revokeEndpoint,
  setEndpointPolicy,
  endpointIpAllowed,
  recordEndpointCall,
  ENDPOINT_CAP_CODE,
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
