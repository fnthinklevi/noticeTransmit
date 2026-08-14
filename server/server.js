require('dotenv').config();
const express = require('express');
const cors = require('cors');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const { generateSecret, generateURI, verify, createGuardrails, NobleCryptoPlugin, ScureBase32Plugin } = require('otplib');
// otplib v13：需显式提供 crypto / base32 插件
const otpCrypto = new NobleCryptoPlugin();
const otpBase32 = new ScureBase32Plugin();
// v13 默认要求 secret 至少 16 字节(128bit)。旧版本生成的 16 字符 base32 secret 仅 10 字节，
// 验证时需放宽 MIN_SECRET_BYTES guardrail，否则会抛 SecretTooShortError。
function buildOtpVerifyOptions(secret) {
  const decodedBytes = Math.floor(String(secret).replace(/=+$/, '').length * 5 / 8);
  const opts = { secret, crypto: otpCrypto, base32: otpBase32, epochTolerance: 30 };
  if (decodedBytes < 16) {
    opts.guardrails = createGuardrails({ MIN_SECRET_BYTES: decodedBytes });
  }
  return opts;
}
// v13 的 verify 返回 Promise<{ valid, delta, ... }>，统一封装为 boolean
async function verifyOtp(secret, token) {
  try {
    const result = await verify({ ...buildOtpVerifyOptions(secret), token });
    return !!result.valid;
  } catch (e) {
    console.error('OTP 验证异常:', e.message);
    return false;
  }
}
const QRCode = require('qrcode');

const app = express();
const PORT = process.env.PORT || 3456;

// 信任反向代理跳数：默认 1（Nginx），可用 TRUST_PROXY 覆盖（0 表示不信任任何代理头）
app.set('trust proxy', Number(process.env.TRUST_PROXY ?? 1));

// CORS 白名单：默认仅允许无 Origin 的请求（App 原生 http / curl 等）与 ALLOWED_ORIGINS 中列出的来源。
// 设置 ALLOWED_ORIGINS='*' 可恢复放行所有来源。多个来源用逗号分隔。
const ALLOWED_ORIGINS = (process.env.ALLOWED_ORIGINS || '')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);
app.use(
  cors({
    origin(origin, callback) {
      // 无 Origin（原生 App、服务端调用、同源）直接放行
      if (!origin) return callback(null, true);
      if (ALLOWED_ORIGINS.includes('*') || ALLOWED_ORIGINS.includes(origin)) {
        return callback(null, true);
      }
      return callback(null, false);
    },
  })
);
app.use(express.json({ limit: '1mb' }));

// 安全 HTTP 头
app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('X-XSS-Protection', '0'); // 现代浏览器已废弃此头，设为 0 禁用旧版非标准行为
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  res.setHeader('X-DNS-Prefetch-Control', 'off');
  res.setHeader('X-Permitted-Cross-Domain-Policies', 'none');
  if (req.path.startsWith('/api/admin')) {
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, private');
  }
  next();
});
// 静态资源：根路径直接映射到 public 目录
// notice.fnthink.top/            → public/index.html（网站主页）
// notice.fnthink.top/admin.html → public/admin.html（管理后台）
app.use(express.static(path.join(__dirname, 'public')));
// 兼容旧地址：保留 /public 前缀（notice.fnthink.top/public/... 仍可用）
app.use('/public', express.static(path.join(__dirname, 'public')));

const DATA_DIR = path.join(__dirname, 'data');

const rateLimitStore = {};

// 定期清理 + 持久化：保存到文件防止重启丢失
const RATE_LIMIT_FILE = path.join(DATA_DIR, 'rate_limit.json');
const RATE_LIMIT_WINDOW_MS = 60 * 1000;
const RATE_LIMIT_GENERAL_MAX = 60;
const RATE_LIMIT_AUTH_MAX = 5;

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
    try { if (fs.existsSync(RATE_LIMIT_FILE)) fs.unlinkSync(RATE_LIMIT_FILE); } catch (_) {}
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

function createRateLimitMiddleware(maxRequests, windowMs, message) {
  return (req, res, next) => {
    const ip = getClientIp(req);
    const key = `${ip}:${req.path}`;
    const now = Date.now();

    if (!rateLimitStore[key]) {
      rateLimitStore[key] = { count: 0, windowStart: now };
    }

    const entry = rateLimitStore[key];

    if (now - entry.windowStart > windowMs) {
      entry.count = 0;
      entry.windowStart = now;
    }

    entry.count++;

    if (entry.count > maxRequests) {
      const remainingMs = windowMs - (now - entry.windowStart);
      const remainingSeconds = Math.ceil(remainingMs / 1000);
      return res.status(429).json({
        code: -4,
        message: message,
        retryAfter: remainingSeconds
      });
    }

    next();
  };
}

const generalRateLimiter = createRateLimitMiddleware(
  RATE_LIMIT_GENERAL_MAX,
  RATE_LIMIT_WINDOW_MS,
  '请求过于频繁，请稍后再试'
);

const authRateLimiter = createRateLimitMiddleware(
  RATE_LIMIT_AUTH_MAX,
  RATE_LIMIT_WINDOW_MS,
  '认证请求过于频繁，请稍后再试'
);

function getClientIp(req) {
  return req.ip || 'unknown';
}

function cleanupRateLimitStore() {
  const now = Date.now();
  for (const [key, entry] of Object.entries(rateLimitStore)) {
    if (now - entry.windowStart > RATE_LIMIT_WINDOW_MS * 2) {
      delete rateLimitStore[key];
    }
  }
}

setInterval(() => {
  cleanupRateLimitStore();
  saveRateLimitStore();
}, RATE_LIMIT_WINDOW_MS);

app.use((req, res, next) => {
  const ip = getClientIp(req);
  
  if (isIpBlocked(ip)) {
    const blockedIPs = getBlockedIPs();
    const entry = blockedIPs.find(item => item.ip === ip);
    const remainingHours = Math.ceil((entry.unblockTime - Date.now()) / (1000 * 60 * 60));
    return res.status(403).json({
      code: -3,
      message: `您的IP已被封锁，剩余 ${remainingHours} 小时后解除`,
      blocked: true,
      remainingHours
    });
  }
  
  next();
});

app.use(generalRateLimiter);
app.use('/api/admin', authRateLimiter);

const VERSION_FILE = path.join(__dirname, 'data', 'version.json');
const TOTP_FILE = path.join(__dirname, 'data', 'totp.json');
const BLOCK_FILE = path.join(__dirname, 'data', 'blocked_ips.json');

// IP 封锁开关：设置 DISABLE_IP_BLOCKING=1 可临时关闭 IP 封锁（仍记录失败次数，但不执行封锁/拦截）
const DISABLE_IP_BLOCKING = ['1', 'true', 'yes'].includes((process.env.DISABLE_IP_BLOCKING || '').toLowerCase());

const ADMIN_TOKEN_HASH = process.env.ADMIN_TOKEN_HASH;
// ENCRYPTION_KEY 必须为 64 位十六进制（AES-256-GCM 需要 32 字节）。格式不合法则视为未配置，
// 避免 Buffer.from(...,'hex') 产生错误长度密钥导致加解密崩溃。
let ENCRYPTION_KEY = process.env.ENCRYPTION_KEY;
if (ENCRYPTION_KEY && !/^[0-9a-fA-F]{64}$/.test(ENCRYPTION_KEY)) {
  console.warn(
    'ENCRYPTION_KEY 格式不合法（应为 64 位十六进制字符），已忽略，TOTP secret 将以明文存储'
  );
  ENCRYPTION_KEY = undefined;
}

if (!ADMIN_TOKEN_HASH) {
  console.error('错误：未配置 ADMIN_TOKEN_HASH 环境变量，服务无法启动');
  console.error('请运行: ADMIN_TOKEN_HASH=$(node -e "const bcrypt=require(\'bcrypt\');bcrypt.hash(\'your-token\',10).then(h=>console.log(h))")');
  process.exit(1);
}

const MAX_FAILED_ATTEMPTS = 3;
const FAILURE_WINDOW_MINUTES = 10;
const BLOCK_DURATION_HOURS = 240;

const FAILED_ATTEMPTS_FILE = path.join(DATA_DIR, 'failed_attempts.json');

const SESSION_TTL_MS = 24 * 60 * 60 * 1000;
const SESSIONS_FILE = path.join(DATA_DIR, 'sessions.json');

const sessions = {};

// 持久化会话到文件
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

setInterval(cleanupSessions, 60 * 60 * 1000);

let failedAttempts = loadFailedAttempts();

function getBlockedIPs() {
  return readJsonFile(BLOCK_FILE, []);
}

function saveBlockedIPs(ips) {
  return writeJsonFile(BLOCK_FILE, ips);
}

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

function isIpBlocked(ip) {
  if (DISABLE_IP_BLOCKING) return false;
  const blockedIPs = getBlockedIPs();
  const entry = blockedIPs.find(item => item.ip === ip);
  if (!entry) return false;
  if (Date.now() > entry.unblockTime) {
    const filtered = blockedIPs.filter(item => item.ip !== ip);
    saveBlockedIPs(filtered);
    return false;
  }
  return true;
}

function blockIp(ip) {
  const blockedIPs = getBlockedIPs();
  const existing = blockedIPs.find(item => item.ip === ip);
  if (existing) {
    existing.unblockTime = Date.now() + BLOCK_DURATION_HOURS * 60 * 60 * 1000;
  } else {
    blockedIPs.push({
      ip,
      blockTime: Date.now(),
      unblockTime: Date.now() + BLOCK_DURATION_HOURS * 60 * 60 * 1000
    });
  }
  saveBlockedIPs(blockedIPs);
  console.log(`IP ${ip} has been blocked for ${BLOCK_DURATION_HOURS} hours due to too many failed 2FA attempts`);
}

function recordFailedAttempt(ip) {
  if (!failedAttempts[ip]) {
    failedAttempts[ip] = {
      count: 0,
      firstAttempt: Date.now(),
      lastAttempt: Date.now()
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
      lastAttempt: Date.now()
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

function generateSessionId() {
  return crypto.randomUUID();
}

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
    tag: tag.toString('hex')
  };
}

function decryptSecret(encryptedData) {
  if (!ENCRYPTION_KEY || encryptedData.plain) {
    return encryptedData.plain || '';
  }
  try {
    const iv = Buffer.from(encryptedData.iv, 'hex');
    const data = Buffer.from(encryptedData.data, 'hex');
    const tag = Buffer.from(encryptedData.tag, 'hex');
    const decipher = crypto.createDecipheriv('aes-256-gcm', Buffer.from(ENCRYPTION_KEY, 'hex'), iv);
    decipher.setAuthTag(tag);
    return decipher.update(data) + decipher.final('utf8');
  } catch (e) {
    console.error('解密失败:', e.message);
    return '';
  }
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

const totpConfig = readJsonFile(TOTP_FILE, {
  enabled: false,
  secret: '',
  recoveryCodes: []
});

function getTotpConfig() {
  try {
    const config = readJsonFile(TOTP_FILE, { enabled: false, secret: '', recoveryCodes: [] });
    if (config.secret && typeof config.secret !== 'string') {
      const decrypted = decryptSecret(config.secret);
      if (!decrypted) {
        console.error('[totp] secret 解密失败，请检查 ENCRYPTION_KEY 是否与启用二步验证时一致');
      }
      config.secret = decrypted || '';
    }
    // 确保 secret 是字符串，防止 verify 抛出异常
    if (typeof config.secret !== 'string') {
      config.secret = '';
    }
    return config;
  } catch (e) {
    console.error('读取 TOTP 配置失败:', e.message);
    return { enabled: false, secret: '', recoveryCodes: [] };
  }
}

function saveTotpConfig(config) {
  const saveConfig = { ...config };
  if (saveConfig.secret) {
    saveConfig.secret = encryptSecret(saveConfig.secret);
  }
  return writeJsonFile(TOTP_FILE, saveConfig);
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

// 校验请求体为普通 JSON 对象（排除 null、数组、基本类型），防止写入畸形配置
function isPlainObject(value) {
  return (
    typeof value === 'object' &&
    value !== null &&
    !Array.isArray(value)
  );
}

// 字段级校验：版本配置必填字段与类型
function validateVersionConfig(body) {
  const errors = [];
  // latestVersion: 必填、非空字符串
  if (typeof body.latestVersion !== 'string' || !body.latestVersion.trim()) {
    errors.push('latestVersion 必须为非空字符串');
  }
  // latestBuild: 必填、正整数
  if (typeof body.latestBuild !== 'number' || !Number.isInteger(body.latestBuild) || body.latestBuild <= 0) {
    errors.push('latestBuild 必须为正整数');
  }
  // downloadUrl: 必填、以 https:// 开头的合法 URL
  if (typeof body.downloadUrl !== 'string' || !body.downloadUrl.trim()) {
    errors.push('downloadUrl 必须为非空字符串');
  } else {
    try {
      const url = new URL(body.downloadUrl);
      if (url.protocol !== 'https:') {
        errors.push('downloadUrl 必须使用 https:// 协议');
      }
    } catch {
      errors.push('downloadUrl 不是合法 URL');
    }
  }
  // fileSize: 必填、正整数（可选，如提供则校验）
  if (body.fileSize !== undefined && (typeof body.fileSize !== 'number' || body.fileSize < 0)) {
    errors.push('fileSize 必须为非负整数');
  }
  return errors;
}

function compareVersions(v1, v2) {
  // 容错：undefined/null/非字符串一律按 '0'，非数字段（如 1.5.0-beta）取前导整数，缺失补 0
  const toParts = (v) =>
    String(v == null ? '0' : v)
      .split('.')
      .map((s) => {
        const n = parseInt(s, 10);
        return Number.isNaN(n) ? 0 : n;
      });
  const parts1 = toParts(v1);
  const parts2 = toParts(v2);
  for (let i = 0; i < Math.max(parts1.length, parts2.length); i++) {
    const p1 = parts1[i] || 0;
    const p2 = parts2[i] || 0;
    if (p1 > p2) return 1;
    if (p1 < p2) return -1;
  }
  return 0;
}

async function verifyToken(token) {
  try {
    return await bcrypt.compare(token, ADMIN_TOKEN_HASH);
  } catch (e) {
    console.error('Token验证失败:', e.message);
    return false;
  }
}

/**
 * 安全包装 async 路由处理函数，捕获所有异常并返回 500，
 * 防止 Express 4 中 async 函数异常导致请求挂起（504 网关超时）。
 */
function asyncHandler(fn) {
  return (req, res, next) => {
    Promise.resolve(fn(req, res, next)).catch((err) => {
      console.error('Async route error:', err.message, err.stack);
      res.status(500).json({
        code: -5,
        message: '服务器内部错误',
        error: process.env.NODE_ENV === 'development' ? err.message : undefined
      });
    });
  };
}

async function authMiddleware(req, res, next) {
  try {
    const token = req.headers['x-admin-token'];
    const sessionId = req.headers['x-session-id'];

    if (sessionId && sessions[sessionId]) {
      if (Date.now() - sessions[sessionId].createdAt > 24 * 60 * 60 * 1000) {
        delete sessions[sessionId];
        return res.status(401).json({ code: -1, message: '会话已过期，请重新登录' });
      }
      sessions[sessionId].createdAt = Date.now();
      req.session = sessions[sessionId];
      return next();
    }

    const isValid = await verifyToken(token);
    if (!isValid) {
      return res.status(401).json({ code: -1, message: '未授权' });
    }

    const config = getTotpConfig();
    if (config.enabled) {
      return res.status(401).json({ code: -2, message: '需要二步验证', require2FA: true });
    }

    const newSessionId = generateSessionId();
    sessions[newSessionId] = {
      createdAt: Date.now(),
      authenticated: true,
      twoFAVerified: false
    };
    saveSessions();
    req.session = sessions[newSessionId];
    res.setHeader('x-session-id', newSessionId);
    next();
  } catch (err) {
    console.error('authMiddleware error:', err.message);
    return res.status(500).json({ code: -5, message: '服务器内部错误' });
  }
}

app.post('/api/admin/login', asyncHandler(async (req, res) => {
  const ip = getClientIp(req);
  
  if (isIpBlocked(ip)) {
    const blockedIPs = getBlockedIPs();
    const entry = blockedIPs.find(item => item.ip === ip);
    const remainingHours = Math.ceil((entry.unblockTime - Date.now()) / (1000 * 60 * 60));
    return res.status(403).json({ 
      code: -3, 
      message: `您的IP已被封锁，剩余 ${remainingHours} 小时后解除`,
      blocked: true,
      remainingHours 
    });
  }

  const { token, otp, recoveryCode } = req.body;

  const isValidToken = await verifyToken(token);
  if (!isValidToken) {
    return res.status(401).json({ code: -1, message: 'Token 错误' });
  }

  const config = getTotpConfig();

  if (!config.enabled) {
    const sessionId = generateSessionId();
    sessions[sessionId] = {
      createdAt: Date.now(),
      authenticated: true,
      twoFAVerified: false
    };
    saveSessions();
    clearFailedAttempts(ip);
    return res.json({
      code: 0,
      message: '登录成功',
      sessionId,
      need2FA: false,
      twoFAEnabled: false
    });
  }

  if (!otp && !recoveryCode) {
    return res.json({
      code: 0,
      message: '请输入二步验证验证码',
      twoFAEnabled: true
    });
  }

  let isValid = false;
  if (otp) {
    // 安全验证 OTP：确保 secret 存在且为字符串，防止 verify 抛出异常
    if (!config.secret || typeof config.secret !== 'string' || !config.secret.trim()) {
      console.error('OTP验证失败：secret 为空或格式错误');
      isValid = false;
    } else {
      isValid = await verifyOtp(config.secret, otp);
    }
  } else if (recoveryCode && config.recoveryCodes && Array.isArray(config.recoveryCodes)) {
    for (let i = 0; i < config.recoveryCodes.length; i++) {
      const hashedCode = config.recoveryCodes[i];
      try {
        if (await bcrypt.compare(recoveryCode, hashedCode)) {
          isValid = true;
          config.recoveryCodes.splice(i, 1);
          saveTotpConfig(config);
          break;
        }
      } catch (e) {
        console.error('恢复码验证异常:', e.message);
      }
    }
  }

  if (!isValid) {
    // 诊断:输出 2FA 验证失败的详细上下文,便于服务器端排查
    console.error('[login:2fa] 验证失败', {
      hasOtp: !!otp,
      hasRecovery: !!recoveryCode,
      secretEmpty: !config.secret || typeof config.secret !== 'string' || !config.secret.trim(),
      secretLen: config.secret ? config.secret.length : 0,
      encKeyConfigured: !!process.env.ENCRYPTION_KEY,
      recoveryCodeCount: Array.isArray(config.recoveryCodes) ? config.recoveryCodes.length : 0
    });
    const isBlocked = recordFailedAttempt(ip);
    const remainingAttempts = getRemainingAttempts(ip);
    
    if (isBlocked) {
      return res.status(403).json({ 
        code: -3, 
        message: `尝试次数过多，您的IP已被封锁 ${BLOCK_DURATION_HOURS} 小时`,
        blocked: true,
        remainingHours: BLOCK_DURATION_HOURS
      });
    }
    
    return res.status(401).json({ 
      code: -1, 
      message: `验证码错误，还剩 ${remainingAttempts} 次尝试机会`, 
      need2FA: true,
      remainingAttempts 
    });
  }

  clearFailedAttempts(ip);
  const sessionId = generateSessionId();
  sessions[sessionId] = {
    createdAt: Date.now(),
    authenticated: true,
    twoFAVerified: true
  };
  saveSessions();

  res.json({
    code: 0,
    message: '登录成功',
    sessionId,
    need2FA: false,
    twoFAEnabled: true
  });
}));

app.get('/api/admin/totp/setup', authMiddleware, asyncHandler(async (req, res) => {
  const config = getTotpConfig();
  const { recoveryCode } = req.query;
  const rebind = config.enabled && !!recoveryCode;

  // 已启用且未提供恢复码：仅返回状态（不生成新 secret，避免破坏已绑定的认证器）
  if (config.enabled && !rebind) {
    return res.json({
      code: 0,
      message: 'success',
      data: {
        enabled: true,
        hasSecret: !!config.secret,
        rebindable: Array.isArray(config.recoveryCodes) && config.recoveryCodes.length > 0
      }
    });
  }

  // 重新绑定：需先通过恢复码验证
  if (rebind) {
    let valid = false;
    if (Array.isArray(config.recoveryCodes)) {
      for (let i = 0; i < config.recoveryCodes.length; i++) {
        try {
          if (await bcrypt.compare(recoveryCode, config.recoveryCodes[i])) {
            valid = true;
            break;
          }
        } catch (e) {
          console.error('恢复码验证异常:', e.message);
        }
      }
    }
    if (!valid) {
      return res.status(400).json({ code: -1, message: '恢复码错误' });
    }
  }

  const secret = generateSecret(32);
  const service = '通知推送助手管理后台';
  const account = 'admin';
  const otpauth = generateURI({ label: account, issuer: service, secret });

  let qrCodeUrl = '';
  try {
    qrCodeUrl = await QRCode.toDataURL(otpauth);
  } catch (e) {
    console.error('生成二维码失败:', e.message);
    return res.status(500).json({ code: -1, message: '生成二维码失败' });
  }

  res.json({
    code: 0,
    message: 'success',
    data: {
      enabled: false,
      rebind: !!rebind,
      secret,
      qrCodeUrl,
      otpauth,
      manualCode: secret
    }
  });
}));

app.post('/api/admin/totp/enable', authMiddleware, asyncHandler(async (req, res) => {
  const { secret, otp } = req.body;

  if (!secret || !otp) {
    return res.status(400).json({ code: -1, message: '参数缺失' });
  }

  let isValid = false;
  try {
    isValid = await verifyOtp(secret, otp);
  } catch (e) {
    console.error('TOTP enable verify error:', e.message);
    isValid = false;
  }

  if (!isValid) {
    return res.status(400).json({ code: -1, message: '验证码错误' });
  }

  const { plain: recoveryCodes, hashed: hashedCodes } = await generateRecoveryCodes();
  const config = {
    enabled: true,
    secret,
    recoveryCodes: hashedCodes
  };

  saveTotpConfig(config);

  res.json({
    code: 0,
    message: '二步验证已启用',
    data: {
      enabled: true,
      recoveryCodes
    }
  });
}));

app.post('/api/admin/totp/disable', authMiddleware, asyncHandler(async (req, res) => {
  const { otp, recoveryCode } = req.body;
  const config = getTotpConfig();

  if (!config.enabled) {
    return res.status(400).json({ code: -1, message: '二步验证未启用' });
  }

  let isValid = false;
  if (otp) {
    try {
      isValid = await verifyOtp(config.secret, otp);
    } catch (e) {
      console.error('TOTP disable verify error:', e.message);
      isValid = false;
    }
  } else if (recoveryCode && config.recoveryCodes && Array.isArray(config.recoveryCodes)) {
    for (const hashedCode of config.recoveryCodes) {
      try {
        if (await bcrypt.compare(recoveryCode, hashedCode)) {
          isValid = true;
          break;
        }
      } catch (e) {
        console.error('恢复码验证异常:', e.message);
      }
    }
  }

  if (!isValid) {
    return res.status(400).json({ code: -1, message: '验证码错误' });
  }

  config.enabled = false;
  saveTotpConfig(config);

  res.json({
    code: 0,
    message: '二步验证已禁用'
  });
}));

app.get('/api/admin/totp/status', authMiddleware, (req, res) => {
  try {
    const config = getTotpConfig();
    res.json({
      code: 0,
      message: 'success',
      data: {
        enabled: config.enabled,
        hasRecoveryCodes: config.recoveryCodes && config.recoveryCodes.length > 0
      }
    });
  } catch (e) {
    console.error('TOTP status error:', e.message);
    res.status(500).json({ code: -5, message: '服务器内部错误' });
  }
});

app.post('/api/admin/totp/regenerate-recovery', authMiddleware, asyncHandler(async (req, res) => {
  const { otp, recoveryCode } = req.body;
  const config = getTotpConfig();

  if (!config.enabled) {
    return res.status(400).json({ code: -1, message: '二步验证未启用' });
  }

  let isValid = false;
  if (otp) {
    try {
      isValid = await verifyOtp(config.secret, otp);
    } catch (e) {
      console.error('TOTP regenerate verify error:', e.message);
      isValid = false;
    }
  } else if (recoveryCode && Array.isArray(config.recoveryCodes)) {
    for (let i = 0; i < config.recoveryCodes.length; i++) {
      try {
        if (await bcrypt.compare(recoveryCode, config.recoveryCodes[i])) {
          isValid = true;
          config.recoveryCodes.splice(i, 1);
          saveTotpConfig(config);
          break;
        }
      } catch (e) {
        console.error('恢复码验证异常:', e.message);
      }
    }
  }

  if (!isValid) {
    return res.status(400).json({ code: -1, message: '验证码错误' });
  }

  const { plain: recoveryCodes, hashed: hashedCodes } = await generateRecoveryCodes();
  config.recoveryCodes = hashedCodes;
  saveTotpConfig(config);

  res.json({
    code: 0,
    message: '恢复码已重新生成',
    data: {
      recoveryCodes
    }
  });
}));

app.get('/api/version/check', (req, res) => {
  try {
    const { version, build, platform = 'android' } = req.query;
    const versionData = readJsonFile(VERSION_FILE, {
      latestVersion: '1.0.0',
      latestBuild: 1,
      forceUpdate: false,
      forceUpdateBuild: 0,
      changelog: '',
      downloads: {},
      fileSizes: {},
      minSupportedVersion: '1.0.0'
    });

    const hasUpdate = compareVersions(versionData.latestVersion, version) > 0 ||
      versionData.latestBuild > Number(build || 0);

    const needForce = versionData.forceUpdate &&
      (compareVersions(versionData.forceUpdateVersion || versionData.latestVersion, version) > 0 ||
       versionData.forceUpdateBuild > Number(build || 0));

    const downloads = versionData.downloads || {};
    const fileSizes = versionData.fileSizes || {};
    // 根据平台参数解析对应的单架构下载链接和大小（默认 arm64）
    const platformKey = platform === 'x86_64' ? 'x86_64' : (platform === 'armeabi-v7a' ? 'arm32' : 'arm64');
    const downloadUrl = downloads[platformKey] || downloads['all'] || '';
    const fileSize = fileSizes[platformKey] || fileSizes['all'] || 0;

    res.json({
      code: 0,
      message: 'success',
      data: {
        hasUpdate,
        latestVersion: versionData.latestVersion,
        latestBuild: versionData.latestBuild,
        forceUpdate: needForce,
        changelog: versionData.changelog,
        downloadUrl,
        fileSize,
        downloads,
        fileSizes,
        minSupportedVersion: versionData.minSupportedVersion
      }
    });
  } catch (e) {
    console.error('Version check error:', e.message);
    res.status(500).json({ code: -5, message: '服务器内部错误' });
  }
});

app.get('/api/admin/version', authMiddleware, (req, res) => {
  try {
    const data = readJsonFile(VERSION_FILE, {});
    res.json({
      code: 0,
      message: 'success',
      data
    });
  } catch (e) {
    console.error('Get version error:', e.message);
    res.status(500).json({ code: -5, message: '服务器内部错误' });
  }
});

app.post('/api/admin/version', authMiddleware, (req, res) => {
  try {
    const body = req.body;
    if (!isPlainObject(body)) {
      return res.status(400).json({ code: -4, message: '请求体必须为 JSON 对象' });
    }
    const errors = validateVersionConfig(body);
    if (errors.length > 0) {
      return res.status(400).json({ code: -4, message: `字段校验失败: ${errors.join('; ')}` });
    }
    const success = writeJsonFile(VERSION_FILE, body);
    res.json({
      code: success ? 0 : -1,
      message: success ? '保存成功' : '保存失败'
    });
  } catch (e) {
    console.error('Save version error:', e.message);
    res.status(500).json({ code: -5, message: '服务器内部错误' });
  }
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// 全局错误处理中间件
app.use((err, req, res, next) => {
  console.error('Unhandled error:', err.message, err.stack);
  res.status(500).json({
    code: -5,
    message: 'Internal server error',
    error: process.env.NODE_ENV === 'development' ? err.message : undefined
  });
});

// 优雅关闭：进程退出前持久化内存状态
function onShutdown(signal) {
  console.log(`\n[${signal}] 正在保存状态...`);
  saveRateLimitStore();
  saveSessions();
  saveFailedAttempts(failedAttempts);
  console.log(`[${signal}] 状态已保存，安全退出`);
  process.exit(0);
}
process.on('SIGTERM', () => onShutdown('SIGTERM'));
process.on('SIGINT', () => onShutdown('SIGINT'));
process.on('SIGHUP', () => onShutdown('SIGHUP'));

// 捕获未处理的 Promise rejection，防止进程崩溃
process.on('unhandledRejection', (reason, promise) => {
  console.error('Unhandled Rejection at:', promise, 'reason:', reason);
});

app.listen(PORT, () => {
  console.log('==============================');
  console.log('  更新服务已启动');
  console.log(`  端口: ${PORT}`);
  console.log(`  时间: ${new Date().toLocaleString()}`);
  console.log('==============================');
  console.log('');
  console.log('API 接口:');
  console.log('  GET  /api/version/check           - 检查版本更新');
  console.log('  POST /api/admin/login             - 管理员登录');
  console.log('  GET  /api/admin/totp/setup        - 获取二步验证设置');
  console.log('  POST /api/admin/totp/enable       - 启用二步验证');
  console.log('  POST /api/admin/totp/disable      - 禁用二步验证');
  console.log('  GET  /api/admin/totp/status       - 获取二步验证状态');
  console.log('  POST /api/admin/totp/regenerate-recovery - 重新生成恢复码');
  console.log('  GET  /api/admin/version           - 获取版本配置');
  console.log('  POST /api/admin/version           - 更新版本配置');
  console.log('  GET  /health                      - 健康检查');
  console.log('');
  console.log('静态资源:');
  console.log('  /                - 网站主页 (public/index.html)');
  console.log('  /admin.html      - 管理后台页面');
  console.log('  /apks/          - APK 文件目录');
  console.log('  (兼容) /public/... - 旧地址仍可用');
  console.log('');
  // 启动时输出 2FA 配置诊断,便于排查验证失败问题
  const diag = getTotpConfig();
  console.log(`  二步验证诊断: enabled=${diag.enabled} secret=${diag.secret ? `有(${diag.secret.length}字符)` : '空'} 恢复码=${Array.isArray(diag.recoveryCodes) ? diag.recoveryCodes.length : 0} 个 ENCRYPTION_KEY=${process.env.ENCRYPTION_KEY ? '已配置' : '未配置'}`);
  console.log(`  DISABLE_IP_BLOCKING=${DISABLE_IP_BLOCKING ? '开启(IP封锁已临时关闭)' : '关闭(IP封锁生效)'}`);
});
