/**
 * 中间件层：安全头、限流、IP 封锁、认证、async 包装、全局错误处理
 *
 * 从 server.js 拆分而来，保持原有行为不变：
 * - 限流阈值来自 store（RATE_LIMIT_GENERAL_MAX / RATE_LIMIT_AUTH_MAX）
 * - IP 封锁策略（5 次失败触发 / 封锁 1 小时）与公开接口豁免均保留
 */

const bcrypt = require('bcryptjs');

const store = require('./store');

// ========== 安全 HTTP 头 ==========

function securityHeaders(req, res, next) {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('X-XSS-Protection', '0'); // 现代浏览器已废弃此头，设为 0 禁用旧版非标准行为
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  res.setHeader('X-DNS-Prefetch-Control', 'off');
  res.setHeader('X-Permitted-Cross-Domain-Policies', 'none');
  // HSTS：仅在浏览器通过 HTTPS 访问时记录，纯 HTTP 部署无副作用
  res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
  // CSP：仅对管理后台启用严格策略（admin.js 已外置、无内联脚本/onclick）
  // 二维码为 data: URI、多处使用内联 style 属性，故 img-src data: 与 style-src 'unsafe-inline' 需保留
  if (req.path === '/admin.html' || req.path.endsWith('/admin.html')) {
    res.setHeader(
      'Content-Security-Policy',
      "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; font-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'"
    );
  }
  if (req.path.startsWith('/api/admin')) {
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, private');
  }
  next();
}

// ========== 限流 ==========

function createRateLimitMiddleware(maxRequests, windowMs, message) {
  return (req, res, next) => {
    const ip = store.getClientIp(req);
    const key = `${ip}:${req.path}`;
    const now = Date.now();

    if (!store.rateLimitStore[key]) {
      store.rateLimitStore[key] = { count: 0, windowStart: now };
    }

    const entry = store.rateLimitStore[key];

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
  store.RATE_LIMIT_GENERAL_MAX,
  store.RATE_LIMIT_WINDOW_MS,
  '请求过于频繁，请稍后再试'
);

const authRateLimiter = createRateLimitMiddleware(
  store.RATE_LIMIT_AUTH_MAX,
  store.RATE_LIMIT_WINDOW_MS,
  '认证请求过于频繁，请稍后再试'
);

// ========== IP 封锁 ==========

function ipBlockMiddleware(req, res, next) {
  // 公开接口（健康检查/版本检查）不受 IP 封锁影响：
  // 封锁按 IP 维度生效，NAT 共享出口下误封会殃及所有 App 设备的版本更新检查
  if (req.path === '/health' || req.path.startsWith('/api/version')) {
    return next();
  }

  const ip = store.getClientIp(req);

  if (store.isIpBlocked(ip)) {
    const blockedIPs = store.getBlockedIPs();
    const entry = blockedIPs.find((item) => item.ip === ip);
    const remainingHours = Math.ceil((entry.unblockTime - Date.now()) / (1000 * 60 * 60));
    return res.status(403).json({
      code: -3,
      message: `您的IP已被封锁，剩余 ${remainingHours} 小时后解除`,
      blocked: true,
      remainingHours
    });
  }

  next();
}

// ========== Token 验证 ==========

async function verifyToken(token) {
  try {
    return await bcrypt.compare(token, store.ADMIN_TOKEN_HASH);
  } catch (e) {
    console.error('Token验证失败:', e.message);
    return false;
  }
}

// ========== async 包装 ==========

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

// ========== 认证中间件 ==========

async function authMiddleware(req, res, next) {
  try {
    const token = req.headers['x-admin-token'];
    const sessionId = req.headers['x-session-id'];

    if (sessionId && store.sessions[sessionId]) {
      if (Date.now() - store.sessions[sessionId].createdAt > store.SESSION_TTL_MS) {
        delete store.sessions[sessionId];
        return res.status(401).json({ code: -1, message: '会话已过期，请重新登录' });
      }
      // 注意：不重置 createdAt —— 会话为固定 24h TTL，持续使用不会无限续期
      req.session = store.sessions[sessionId];
      return next();
    }

    const isValid = await verifyToken(token);
    if (!isValid) {
      return res.status(401).json({ code: -1, message: '未授权' });
    }

    const config = store.getTotpConfig();
    if (config.enabled) {
      return res.status(401).json({ code: -2, message: '需要二步验证', require2FA: true });
    }

    const newSessionId = store.generateSessionId();
    store.sessions[newSessionId] = {
      createdAt: Date.now(),
      authenticated: true,
      twoFAVerified: false
    };
    store.saveSessions();
    req.session = store.sessions[newSessionId];
    res.setHeader('x-session-id', newSessionId);
    next();
  } catch (err) {
    console.error('authMiddleware error:', err.message);
    return res.status(500).json({ code: -5, message: '服务器内部错误' });
  }
}

// ========== 全局错误处理 ==========

function errorMiddleware(err, req, res, next) {
  console.error('Unhandled error:', err.message, err.stack);
  res.status(500).json({
    code: -5,
    message: 'Internal server error',
    error: process.env.NODE_ENV === 'development' ? err.message : undefined
  });
}

module.exports = {
  securityHeaders,
  createRateLimitMiddleware,
  generalRateLimiter,
  authRateLimiter,
  ipBlockMiddleware,
  verifyToken,
  asyncHandler,
  authMiddleware,
  errorMiddleware,
};
