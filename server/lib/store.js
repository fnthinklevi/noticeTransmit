/**
 * 存储层：文件路径、持久化 JSON 读写、运行时状态（限流/会话/IP 封锁/失败次数/TOTP 配置）
 *
 * 从 server.js 拆分而来，保持原有行为不变：
 * - 数据目录可用 DATA_DIR 环境变量覆盖（默认 <server>/data），便于测试隔离
 * - 限流阈值可用 RATE_LIMIT_GENERAL_MAX / RATE_LIMIT_AUTH_MAX 覆盖（默认 60 / 5）
 */

const path = require('path');
const fs = require('fs');
const crypto = require('crypto');
const bcrypt = require('bcryptjs');

const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, '..', 'data');
const VERSION_FILE = path.join(DATA_DIR, 'version.json');
const TOTP_FILE = path.join(DATA_DIR, 'totp.json');
const BLOCK_FILE = path.join(DATA_DIR, 'blocked_ips.json');
const FAILED_ATTEMPTS_FILE = path.join(DATA_DIR, 'failed_attempts.json');
const SESSIONS_FILE = path.join(DATA_DIR, 'sessions.json');
const RATE_LIMIT_FILE = path.join(DATA_DIR, 'rate_limit.json');

const RATE_LIMIT_WINDOW_MS = 60 * 1000;
const RATE_LIMIT_GENERAL_MAX = Number(process.env.RATE_LIMIT_GENERAL_MAX || 60);
const RATE_LIMIT_AUTH_MAX = Number(process.env.RATE_LIMIT_AUTH_MAX || 5);

const SESSION_TTL_MS = 24 * 60 * 60 * 1000;

// 封锁策略：5 次失败触发，封锁 1 小时（原为 3 次/240 小时，罚不当罪；
// NAT 共享出口或运维误操作下 3 次即被长封 10 天，严重影响可用性）
const MAX_FAILED_ATTEMPTS = 5;
const FAILURE_WINDOW_MINUTES = 10;
const BLOCK_DURATION_HOURS = 1;

// IP 封锁开关：设置 DISABLE_IP_BLOCKING=1 可临时关闭 IP 封锁（仍记录失败次数，但不执行封锁/拦截）
const DISABLE_IP_BLOCKING = ['1', 'true', 'yes'].includes(
  (process.env.DISABLE_IP_BLOCKING || '').toLowerCase(),
);

const ADMIN_TOKEN_HASH = process.env.ADMIN_TOKEN_HASH;

// ENCRYPTION_KEY 必须为 64 位十六进制（AES-256-GCM 需要 32 字节）。格式不合法则视为未配置，
// 避免 Buffer.from(...,'hex') 产生错误长度密钥导致加解密崩溃。
let ENCRYPTION_KEY = process.env.ENCRYPTION_KEY;
if (ENCRYPTION_KEY && !/^[0-9a-fA-F]{64}$/.test(ENCRYPTION_KEY)) {
  console.warn(
    'ENCRYPTION_KEY 格式不合法（应为 64 位十六进制字符），已忽略，TOTP secret 将以明文存储',
  );
  ENCRYPTION_KEY = undefined;
}

if (!ADMIN_TOKEN_HASH) {
  console.error('错误：未配置 ADMIN_TOKEN_HASH 环境变量，服务无法启动');
  console.error(
    "请运行: ADMIN_TOKEN_HASH=$(node -e \"const bcrypt=require('bcryptjs');bcrypt.hash('your-token',10).then(h=>console.log(h))\")",
  );
  process.exit(1);
}

function readJsonFile(filePath, defaultValue) {
  try {
    if (fs.existsSync(filePath)) {
      const content = fs.readFileSync(filePath, 'utf8');
      return JSON.parse(content);
    }
  } catch (e) {
    console.error('读取文件失败:', filePath, e.message);
  }
  return defaultValue;
}

function writeJsonFile(filePath, data) {
  try {
    const dir = path.dirname(filePath);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
    // 原子写入：先写 .tmp 再 rename，防止崩溃产生截断文件
    const tmp = filePath + '.tmp';
    fs.writeFileSync(tmp, JSON.stringify(data, null, 2), 'utf8');
    fs.renameSync(tmp, filePath);
    return true;
  } catch (e) {
    console.error('写入文件失败:', filePath, e.message);
    return false;
  }
}

if (!fs.existsSync(DATA_DIR)) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

// ========== 限流（内存 + 定期持久化） ==========

const rateLimitStore = {};

function saveRateLimitStore() {
  // 仅保存当前窗口内的记录，减少文件体积
  const now = Date.now();
  const slim = {};
  for (const [key, entry] of Object.entries(rateLimitStore)) {
    if (now - entry.windowStart <= RATE_LIMIT_WINDOW_MS) {
      slim[key] = entry;
    }
  }
  if (Object.keys(slim).length > 0) {
    writeJsonFile(RATE_LIMIT_FILE, slim);
  } else {
    // 全部过期就删文件
    try {
      if (fs.existsSync(RATE_LIMIT_FILE)) fs.unlinkSync(RATE_LIMIT_FILE);
    } catch (_) {}
  }
}

// 启动时加载上次持久化的限流记录
(function loadRateLimitStore() {
  const saved = readJsonFile(RATE_LIMIT_FILE, {});
  const now = Date.now();
  for (const [key, entry] of Object.entries(saved)) {
    if (now - entry.windowStart <= RATE_LIMIT_WINDOW_MS) {
      rateLimitStore[key] = entry;
    }
  }
  if (Object.keys(rateLimitStore).length > 0) {
    console.log(`[persist] 恢复限流记录 ${Object.keys(rateLimitStore).length} 条`);
  }
})();

function cleanupRateLimitStore() {
  const now = Date.now();
  for (const [key, entry] of Object.entries(rateLimitStore)) {
    if (now - entry.windowStart > RATE_LIMIT_WINDOW_MS * 2) {
      delete rateLimitStore[key];
    }
  }
}

function getClientIp(req) {
  return req.ip || 'unknown';
}

/**
 * 限流键的路由桶：把请求者可控的任意路径收敛为固定少数几类，
 * 否则每个探测路径都会新建一条记录并整体落盘（内存/文件无上限增长）。
 */
function rateLimitBucket(path) {
  const p = String(path || '');
  if (p.startsWith('/api/admin')) return 'api-admin';
  if (p.startsWith('/api/')) return 'api';
  return 'static';
}

// ========== 会话 ==========

// 必须用 null 原型：`{}` 会经原型链命中，`sessions['__proto__']` / `sessions['constructor']`
// 返回真值对象，使「请求头带的会话键恰为原型属性名」被误判为有效会话 → 无凭据通过认证。
const sessions = Object.create(null);

/**
 * 会话是否有效。三重判定：键为自有属性（排除原型链命中）+ 记录存在 + 确实已认证。
 * 攻击者可控的 x-session-id 只能走到这里，不再能借原型链绕过。
 */
function isValidSession(sessionId) {
  if (typeof sessionId !== 'string' || sessionId === '') return false;
  if (!Object.prototype.hasOwnProperty.call(sessions, sessionId)) return false;
  const s = sessions[sessionId];
  return !!s && s.authenticated === true;
}

/** 吊销全部会话（二步验证开关等凭据状态变更后必须重新登录） */
function revokeAllSessions(reason) {
  const ids = Object.keys(sessions);
  for (const id of ids) delete sessions[id];
  saveSessions();
  console.log(`[auth] 已吊销全部会话（${ids.length} 条）：${reason || '未说明'}`);
}

function saveSessions() {
  writeJsonFile(SESSIONS_FILE, sessions);
}

// 启动时加载上次的会话
(function loadSessions() {
  const saved = readJsonFile(SESSIONS_FILE, {});
  const now = Date.now();
  for (const [id, session] of Object.entries(saved)) {
    if (now - session.createdAt <= SESSION_TTL_MS) {
      sessions[id] = session;
    }
  }
  if (Object.keys(sessions).length > 0) {
    console.log(`[persist] 恢复会话 ${Object.keys(sessions).length} 条`);
  }
})();

// 定期清理过期会话 + 持久化，避免内存无上限增长
function cleanupSessions() {
  const now = Date.now();
  for (const [id, session] of Object.entries(sessions)) {
    if (now - session.createdAt > SESSION_TTL_MS) {
      delete sessions[id];
    }
  }
  saveSessions();
}

function generateSessionId() {
  return crypto.randomUUID();
}

// ========== IP 封锁 ==========

// 内存为准 + 变更落盘。原实现每个非公开请求都 existsSync + readFileSync + JSON.parse
// 一个文件（`isIpBlocked` 在中间件里逐请求调用），同步 IO 压在事件循环上，负载下
// 等于自我 DoS。启动后首次访问读入，此后读写走内存。
let blockedIPsCache = null;

function getBlockedIPs() {
  if (blockedIPsCache === null) {
    const saved = readJsonFile(BLOCK_FILE, []);
    const now = Date.now();
    // 读入即剔除已过期封锁，行为与原来的惰性剔除一致但只做一次
    blockedIPsCache = Array.isArray(saved)
      ? saved.filter((item) => item && item.unblockTime > now)
      : [];
    if (Array.isArray(saved) && blockedIPsCache.length !== saved.length) {
      writeJsonFile(BLOCK_FILE, blockedIPsCache);
    }
  }
  return blockedIPsCache;
}

function saveBlockedIPs(ips) {
  blockedIPsCache = Array.isArray(ips) ? ips : [];
  return writeJsonFile(BLOCK_FILE, blockedIPsCache);
}

function isIpBlocked(ip) {
  if (DISABLE_IP_BLOCKING) return false;
  const blockedIPs = getBlockedIPs();
  const entry = blockedIPs.find((item) => item.ip === ip);
  if (!entry) return false;
  if (Date.now() > entry.unblockTime) {
    const filtered = blockedIPs.filter((item) => item.ip !== ip);
    saveBlockedIPs(filtered);
    return false;
  }
  return true;
}

function blockIp(ip) {
  const blockedIPs = getBlockedIPs();
  const existing = blockedIPs.find((item) => item.ip === ip);
  if (existing) {
    existing.unblockTime = Date.now() + BLOCK_DURATION_HOURS * 60 * 60 * 1000;
  } else {
    blockedIPs.push({
      ip,
      blockTime: Date.now(),
      unblockTime: Date.now() + BLOCK_DURATION_HOURS * 60 * 60 * 1000,
    });
  }
  saveBlockedIPs(blockedIPs);
  console.log(
    `IP ${ip} has been blocked for ${BLOCK_DURATION_HOURS} hours due to too many failed 2FA attempts`,
  );
}

// ========== 失败次数（2FA） ==========

let failedAttempts = loadFailedAttempts();

function loadFailedAttempts() {
  const data = readJsonFile(FAILED_ATTEMPTS_FILE, {});
  const cutoff = Date.now() - FAILURE_WINDOW_MINUTES * 60 * 1000;
  const cleaned = {};
  for (const [ip, record] of Object.entries(data)) {
    if (record.lastAttempt > cutoff) {
      cleaned[ip] = record;
    }
  }
  if (Object.keys(cleaned).length !== Object.keys(data).length) {
    saveFailedAttempts(cleaned);
  }
  return cleaned;
}

function saveFailedAttempts(data) {
  const cutoff = Date.now() - FAILURE_WINDOW_MINUTES * 60 * 1000;
  const cleaned = {};
  for (const [ip, record] of Object.entries(data)) {
    if (record.lastAttempt > cutoff) {
      cleaned[ip] = record;
    }
  }
  writeJsonFile(FAILED_ATTEMPTS_FILE, cleaned);
}

function recordFailedAttempt(ip) {
  if (!failedAttempts[ip]) {
    failedAttempts[ip] = {
      count: 0,
      firstAttempt: Date.now(),
      lastAttempt: Date.now(),
    };
  }

  failedAttempts[ip].count++;
  failedAttempts[ip].lastAttempt = Date.now();

  const windowStart = failedAttempts[ip].firstAttempt;
  const windowEnd = windowStart + FAILURE_WINDOW_MINUTES * 60 * 1000;

  if (Date.now() > windowEnd) {
    failedAttempts[ip] = {
      count: 1,
      firstAttempt: Date.now(),
      lastAttempt: Date.now(),
    };
  }

  if (failedAttempts[ip].count >= MAX_FAILED_ATTEMPTS) {
    if (!DISABLE_IP_BLOCKING) {
      blockIp(ip);
    }
    delete failedAttempts[ip];
    saveFailedAttempts(failedAttempts);
    return !DISABLE_IP_BLOCKING;
  }

  saveFailedAttempts(failedAttempts);
  return false;
}

function clearFailedAttempts(ip) {
  delete failedAttempts[ip];
  saveFailedAttempts(failedAttempts);
}

function getRemainingAttempts(ip) {
  if (!failedAttempts[ip]) return MAX_FAILED_ATTEMPTS;
  const windowEnd = failedAttempts[ip].firstAttempt + FAILURE_WINDOW_MINUTES * 60 * 1000;
  if (Date.now() > windowEnd) return MAX_FAILED_ATTEMPTS;
  return MAX_FAILED_ATTEMPTS - failedAttempts[ip].count;
}

// ========== TOTP 配置 + 加解密 ==========

function encryptSecret(secret) {
  if (!ENCRYPTION_KEY) {
    console.warn('未配置 ENCRYPTION_KEY，TOTP secret 将以明文存储');
    return { plain: secret };
  }
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv('aes-256-gcm', Buffer.from(ENCRYPTION_KEY, 'hex'), iv);
  const encrypted = Buffer.concat([cipher.update(secret, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return {
    iv: iv.toString('hex'),
    data: encrypted.toString('hex'),
    tag: tag.toString('hex'),
  };
}

// 解密 TOTP secret。返回 { ok, value }：
//   ok=false 表示 ENCRYPTION_KEY 缺失/不匹配（解密失败），调用方应明确报错，
//   而不是静默当作空 secret —— 否则 OTP 永远验证失败且被误计为登录尝试。
function decryptSecret(encryptedData) {
  if (!encryptedData) {
    return { ok: true, value: '' };
  }
  // 明文存储（未配置 ENCRYPTION_KEY 时代写入）
  if (encryptedData.plain !== undefined) {
    return { ok: true, value: encryptedData.plain };
  }
  if (!ENCRYPTION_KEY) {
    console.error('TOTP secret 已加密但未配置 ENCRYPTION_KEY，无法解密');
    return { ok: false, value: '' };
  }
  try {
    const iv = Buffer.from(encryptedData.iv, 'hex');
    const data = Buffer.from(encryptedData.data, 'hex');
    const tag = Buffer.from(encryptedData.tag, 'hex');
    const decipher = crypto.createDecipheriv('aes-256-gcm', Buffer.from(ENCRYPTION_KEY, 'hex'), iv);
    decipher.setAuthTag(tag);
    return { ok: true, value: decipher.update(data) + decipher.final('utf8') };
  } catch (e) {
    console.error('TOTP secret 解密失败:', e.message);
    return { ok: false, value: '' };
  }
}

function getTotpConfig() {
  let decryptError = false;
  try {
    const config = readJsonFile(TOTP_FILE, { enabled: false, secret: '', recoveryCodes: [] });
    if (config.secret && typeof config.secret !== 'string') {
      const decrypted = decryptSecret(config.secret);
      if (!decrypted.ok) {
        decryptError = true;
        console.error('[totp] secret 解密失败，请检查 ENCRYPTION_KEY 是否与启用二步验证时一致');
      }
      config.secret = decrypted.value || '';
    }
    // 确保 secret 是字符串，防止 verify 抛出异常
    if (typeof config.secret !== 'string') {
      config.secret = '';
    }
    // 内部标志：仅用于区分"密钥配置错误"与"未启用 2FA"，不会写入文件
    if (decryptError) {
      config._decryptError = true;
    }
    return config;
  } catch (e) {
    console.error('读取 TOTP 配置失败:', e.message);
    return { enabled: false, secret: '', recoveryCodes: [] };
  }
}

function saveTotpConfig(config) {
  const saveConfig = { ...config };
  // _decryptError 是内存诊断标志，禁止写入 totp.json
  delete saveConfig._decryptError;
  if (saveConfig.secret) {
    saveConfig.secret = encryptSecret(saveConfig.secret);
  }
  return writeJsonFile(TOTP_FILE, saveConfig);
}

// ========== 恢复码原子消费 ==========

// 同进程认证临界区（串行队列）。恢复码的「读配置 → bcrypt 校验 → 核销 → 落盘」中间有
// await（bcrypt.compare 会让出事件循环），并发请求各自读到同一份 recoveryCodes 数组，
// 最后一个写盘者覆盖前一个 → 同一个「一次性」恢复码可被重复使用，等于绕过二步验证。
let authChain = Promise.resolve();

function withAuthLock(task) {
  const result = authChain.then(() => task());
  // 队列必须与前序结果解耦：前一个请求抛错不得卡死后续认证
  authChain = result.then(
    () => undefined,
    () => undefined,
  );
  return result;
}

/**
 * 原子核销一个恢复码。锁内**重新读取**配置，因此并发重放的第二个请求看到的是
 * 已被前序请求移除后的集合。
 * @param {string} plainCode 用户提交的明文恢复码
 * @returns {Promise<boolean>} true = 本次核销成功（该码此前未被使用）
 */
function consumeRecoveryCode(plainCode) {
  return withAuthLock(async () => {
    const config = getTotpConfig();
    if (!config || !Array.isArray(config.recoveryCodes) || !plainCode) return false;
    for (let i = 0; i < config.recoveryCodes.length; i++) {
      let matched = false;
      try {
        matched = await bcrypt.compare(plainCode, config.recoveryCodes[i]);
      } catch (e) {
        console.error('恢复码校验异常:', e.message);
        matched = false;
      }
      if (matched) {
        config.recoveryCodes.splice(i, 1);
        saveTotpConfig(config);
        return true;
      }
    }
    return false;
  });
}

async function generateRecoveryCodes() {
  const codes = [];
  const hashedCodes = [];
  for (let i = 0; i < 8; i++) {
    const code = crypto.randomBytes(4).toString('hex').toUpperCase();
    codes.push(code);
    hashedCodes.push(await bcrypt.hash(code, 10));
  }
  return { plain: codes, hashed: hashedCodes };
}

module.exports = {
  DATA_DIR,
  VERSION_FILE,
  TOTP_FILE,
  BLOCK_FILE,
  FAILED_ATTEMPTS_FILE,
  SESSIONS_FILE,
  RATE_LIMIT_FILE,
  RATE_LIMIT_WINDOW_MS,
  RATE_LIMIT_GENERAL_MAX,
  RATE_LIMIT_AUTH_MAX,
  SESSION_TTL_MS,
  MAX_FAILED_ATTEMPTS,
  FAILURE_WINDOW_MINUTES,
  BLOCK_DURATION_HOURS,
  DISABLE_IP_BLOCKING,
  ADMIN_TOKEN_HASH,
  readJsonFile,
  writeJsonFile,
  rateLimitStore,
  saveRateLimitStore,
  cleanupRateLimitStore,
  getClientIp,
  sessions,
  isValidSession,
  revokeAllSessions,
  saveSessions,
  cleanupSessions,
  generateSessionId,
  getBlockedIPs,
  rateLimitBucket,
  saveBlockedIPs,
  isIpBlocked,
  blockIp,
  failedAttempts,
  saveFailedAttempts,
  recordFailedAttempt,
  clearFailedAttempts,
  getRemainingAttempts,
  getTotpConfig,
  saveTotpConfig,
  consumeRecoveryCode,
  generateRecoveryCodes,
};
