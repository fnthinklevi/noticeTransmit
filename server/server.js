require('dotenv').config();
const express = require('express');
const cors = require('cors');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const { authenticator, totp } = require('otplib');
const QRCode = require('qrcode');

const app = express();
const PORT = process.env.PORT || 3456;

app.set('trust proxy', 1);

app.use(cors());
app.use(express.json({ limit: '1mb' }));
app.use('/public', express.static(path.join(__dirname, 'public')));

const rateLimitStore = {};
const RATE_LIMIT_WINDOW_MS = 60 * 1000;
const RATE_LIMIT_GENERAL_MAX = 60;
const RATE_LIMIT_AUTH_MAX = 5;

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

setInterval(cleanupRateLimitStore, RATE_LIMIT_WINDOW_MS);

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
const HOTFIX_FILE = path.join(__dirname, 'data', 'hotfix.json');
const TOTP_FILE = path.join(__dirname, 'data', 'totp.json');
const BLOCK_FILE = path.join(__dirname, 'data', 'blocked_ips.json');
const DATA_DIR = path.join(__dirname, 'data');

const ADMIN_TOKEN_HASH = process.env.ADMIN_TOKEN_HASH;
const ENCRYPTION_KEY = process.env.ENCRYPTION_KEY;

if (!ADMIN_TOKEN_HASH) {
  console.error('错误：未配置 ADMIN_TOKEN_HASH 环境变量，服务无法启动');
  console.error('请运行: ADMIN_TOKEN_HASH=$(node -e "const bcrypt=require(\'bcrypt\');bcrypt.hash(\'your-token\',10).then(h=>console.log(h))")');
  process.exit(1);
}

const MAX_FAILED_ATTEMPTS = 3;
const FAILURE_WINDOW_MINUTES = 10;
const BLOCK_DURATION_HOURS = 240;

const FAILED_ATTEMPTS_FILE = path.join(DATA_DIR, 'failed_attempts.json');

const sessions = {};
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
    blockIp(ip);
    delete failedAttempts[ip];
    saveFailedAttempts(failedAttempts);
    return true;
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
      const content = fs.readFileSync(filePath, 'utf-8');
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
    fs.writeFileSync(filePath, JSON.stringify(data, null, 2), 'utf-8');
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
  const config = readJsonFile(TOTP_FILE, { enabled: false, secret: '', recoveryCodes: [] });
  if (config.secret && typeof config.secret !== 'string') {
    config.secret = decryptSecret(config.secret);
  }
  return config;
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

function compareVersions(v1, v2) {
  const parts1 = v1.split('.').map(Number);
  const parts2 = v2.split('.').map(Number);
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

async function authMiddleware(req, res, next) {
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
  req.session = sessions[newSessionId];
  res.setHeader('x-session-id', newSessionId);
  next();
}

app.post('/api/admin/login', async (req, res) => {
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
    isValid = authenticator.verify({ token: otp, secret: config.secret });
  } else if (recoveryCode && config.recoveryCodes) {
    for (let i = 0; i < config.recoveryCodes.length; i++) {
      const hashedCode = config.recoveryCodes[i];
      if (await bcrypt.compare(recoveryCode, hashedCode)) {
        isValid = true;
        config.recoveryCodes.splice(i, 1);
        saveTotpConfig(config);
        break;
      }
    }
  }

  if (!isValid) {
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

  res.json({
    code: 0,
    message: '登录成功',
    sessionId,
    need2FA: false,
    twoFAEnabled: true
  });
});

app.get('/api/admin/totp/setup', authMiddleware, (req, res) => {
  const config = getTotpConfig();
  
  if (config.enabled) {
    return res.json({
      code: 0,
      message: 'success',
      data: {
        enabled: true,
        hasSecret: !!config.secret
      }
    });
  }

  const secret = authenticator.generateSecret();
  const service = '通知推送助手管理后台';
  const account = 'admin';
  const otpauth = authenticator.keyuri(account, service, secret);

  QRCode.toDataURL(otpauth, (err, qrCodeUrl) => {
    if (err) {
      return res.status(500).json({ code: -1, message: '生成二维码失败' });
    }

    res.json({
      code: 0,
      message: 'success',
      data: {
        enabled: false,
        secret,
        qrCodeUrl,
        otpauth,
        manualCode: secret
      }
    });
  });
});

app.post('/api/admin/totp/enable', authMiddleware, async (req, res) => {
  const { secret, otp } = req.body;

  if (!secret || !otp) {
    return res.status(400).json({ code: -1, message: '参数缺失' });
  }

  const isValid = authenticator.verify({ token: otp, secret });
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
});

app.post('/api/admin/totp/disable', authMiddleware, async (req, res) => {
  const { otp, recoveryCode } = req.body;
  const config = getTotpConfig();

  if (!config.enabled) {
    return res.status(400).json({ code: -1, message: '二步验证未启用' });
  }

  let isValid = false;
  if (otp) {
    isValid = authenticator.verify({ token: otp, secret: config.secret });
  } else if (recoveryCode && config.recoveryCodes) {
    for (const hashedCode of config.recoveryCodes) {
      if (await bcrypt.compare(recoveryCode, hashedCode)) {
        isValid = true;
        break;
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
});

app.get('/api/admin/totp/status', authMiddleware, (req, res) => {
  const config = getTotpConfig();
  res.json({
    code: 0,
    message: 'success',
    data: {
      enabled: config.enabled,
      hasRecoveryCodes: config.recoveryCodes && config.recoveryCodes.length > 0
    }
  });
});

app.post('/api/admin/totp/regenerate-recovery', authMiddleware, async (req, res) => {
  const { otp } = req.body;
  const config = getTotpConfig();

  if (!config.enabled) {
    return res.status(400).json({ code: -1, message: '二步验证未启用' });
  }

  if (!otp || !authenticator.verify({ token: otp, secret: config.secret })) {
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
});

app.get('/api/version/check', (req, res) => {
  const { version, build, platform = 'android' } = req.query;
  const versionData = readJsonFile(VERSION_FILE, {
    latestVersion: '1.0.0',
    latestBuild: 1,
    forceUpdate: false,
    forceUpdateBuild: 0,
    changelog: '',
    downloadUrl: '',
    fileSize: 0,
    platform: 'android',
    minSupportedVersion: '1.0.0'
  });

  const hasUpdate = compareVersions(versionData.latestVersion, version) > 0 ||
    versionData.latestBuild > Number(build || 0);

  const needForce = versionData.forceUpdate &&
    (compareVersions(versionData.forceUpdateVersion || versionData.latestVersion, version) > 0 ||
     versionData.forceUpdateBuild > Number(build || 0));

  res.json({
    code: 0,
    message: 'success',
    data: {
      hasUpdate,
      appName: versionData.appName || ('notice' + versionData.latestVersion),
      latestVersion: versionData.latestVersion,
      latestBuild: versionData.latestBuild,
      forceUpdate: needForce,
      changelog: versionData.changelog,
      downloadUrl: versionData.downloadUrl,
      fileSize: versionData.fileSize,
      platform: versionData.platform,
      minSupportedVersion: versionData.minSupportedVersion
    }
  });
});

app.get('/api/hotfix/check', (req, res) => {
  const { contentVersion, platform = 'android' } = req.query;
  const hotfixData = readJsonFile(HOTFIX_FILE, {
    latestContentVersion: 0,
    version: '1.0.0',
    forceUpdate: false,
    forceContentVersion: 0,
    changelog: '',
    downloadUrl: '',
    fileSize: 0,
    platform: 'android',
    minAppVersion: '1.0.0'
  });

  const currentContentVer = Number(contentVersion || 0);
  const hasUpdate = hotfixData.latestContentVersion > currentContentVer;
  const needForce = hotfixData.forceUpdate &&
    hotfixData.forceContentVersion > currentContentVer;

  res.json({
    code: 0,
    message: 'success',
    data: {
      hasUpdate,
      latestContentVersion: hotfixData.latestContentVersion,
      version: hotfixData.version,
      forceUpdate: needForce,
      changelog: hotfixData.changelog,
      downloadUrl: hotfixData.downloadUrl,
      fileSize: hotfixData.fileSize,
      platform: hotfixData.platform,
      minAppVersion: hotfixData.minAppVersion
    }
  });
});

app.get('/api/admin/version', authMiddleware, (req, res) => {
  const data = readJsonFile(VERSION_FILE, {});
  res.json({
    code: 0,
    message: 'success',
    data
  });
});

app.post('/api/admin/version', authMiddleware, (req, res) => {
  const body = req.body;
  const success = writeJsonFile(VERSION_FILE, body);
  res.json({
    code: success ? 0 : -1,
    message: success ? '保存成功' : '保存失败'
  });
});

app.get('/api/admin/hotfix', authMiddleware, (req, res) => {
  const data = readJsonFile(HOTFIX_FILE, {});
  res.json({
    code: 0,
    message: 'success',
    data
  });
});

app.post('/api/admin/hotfix', authMiddleware, (req, res) => {
  const body = req.body;
  const success = writeJsonFile(HOTFIX_FILE, body);
  res.json({
    code: success ? 0 : -1,
    message: success ? '保存成功' : '保存失败'
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({
    code: -5,
    message: 'Internal server error',
    error: process.env.NODE_ENV === 'development' ? err.message : undefined
  });
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
  console.log('  GET  /api/hotfix/check            - 检查热更新');
  console.log('  POST /api/admin/login             - 管理员登录');
  console.log('  GET  /api/admin/totp/setup        - 获取二步验证设置');
  console.log('  POST /api/admin/totp/enable       - 启用二步验证');
  console.log('  POST /api/admin/totp/disable      - 禁用二步验证');
  console.log('  GET  /api/admin/totp/status       - 获取二步验证状态');
  console.log('  POST /api/admin/totp/regenerate-recovery - 重新生成恢复码');
  console.log('  GET  /api/admin/version           - 获取版本配置');
  console.log('  POST /api/admin/version           - 更新版本配置');
  console.log('  GET  /api/admin/hotfix            - 获取热更新配置');
  console.log('  POST /api/admin/hotfix            - 更新热更新配置');
  console.log('  GET  /health                      - 健康检查');
  console.log('');
  console.log('静态资源:');
  console.log('  /public/apks/      - APK 文件目录');
  console.log('  /public/hotfix/    - 热更新包目录');
  console.log('  /public/admin.html - 管理后台页面');
  console.log('');
  console.log('二步验证状态:', getTotpConfig().enabled ? '✅ 已启用' : '❌ 未启用');
  console.log('Token验证方式:', ADMIN_TOKEN_HASH ? '✅ bcrypt哈希' : '❌ 未配置（使用明文）');
});