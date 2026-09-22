/**
 * 认证 / 二步验证路由（挂载于 /api/admin）
 *
 * 从 server.js 拆分而来，保持原有行为不变：
 * - 恢复码走 POST 消费（M-2：GET query 泄露已废弃）
 * - 2FA 失败计数 + IP 封锁（M-8：5 次/10 分钟窗口、公开接口豁免）
 * - 恢复码验证有可见反馈（M-1）
 */

const express = require('express');
const bcrypt = require('bcryptjs');
const QRCode = require('qrcode');

const store = require('../store');
const { verifyOtp, generateSecret, generateURI } = require('../otp');
const { asyncHandler, authMiddleware, verifyToken } = require('../middleware');

const router = express.Router();

// 登录（支持 token + OTP / 恢复码）
router.post(
  '/login',
  asyncHandler(async (req, res) => {
    const ip = store.getClientIp(req);

    if (store.isIpBlocked(ip)) {
      const blockedIPs = store.getBlockedIPs();
      const entry = blockedIPs.find((item) => item.ip === ip);
      const remainingHours = Math.ceil((entry.unblockTime - Date.now()) / (1000 * 60 * 60));
      return res.status(403).json({
        code: -3,
        message: `您的IP已被封锁，剩余 ${remainingHours} 小时后解除`,
        blocked: true,
        remainingHours,
      });
    }

    const { token, otp, recoveryCode } = req.body;

    const isValidToken = await verifyToken(token);
    if (!isValidToken) {
      return res.status(401).json({ code: -1, message: 'Token 错误' });
    }

    const config = store.getTotpConfig();

    if (!config.enabled) {
      const sessionId = store.generateSessionId();
      store.sessions[sessionId] = {
        createdAt: Date.now(),
        authenticated: true,
        twoFAVerified: false,
      };
      store.saveSessions();
      store.clearFailedAttempts(ip);
      return res.json({
        code: 0,
        message: '登录成功',
        sessionId,
        need2FA: false,
        twoFAEnabled: false,
      });
    }

    if (!otp && !recoveryCode) {
      return res.json({
        code: 0,
        message: '请输入二步验证验证码',
        twoFAEnabled: true,
      });
    }

    let isValid = false;
    if (otp) {
      // 服务端密钥配置错误：明确提示且不计入失败次数，避免 3 次误封 IP 240 小时
      if (config._decryptError) {
        console.error(
          '[login:2fa] 服务端 TOTP secret 解密失败（ENCRYPTION_KEY 缺失或不匹配），拒绝验证且不计数',
        );
        return res.status(500).json({
          code: -2,
          message: '服务端二步验证密钥配置错误，请联系管理员检查 ENCRYPTION_KEY',
        });
      }
      // 安全验证 OTP：确保 secret 存在且为字符串，防止 verify 抛出异常
      if (!config.secret || typeof config.secret !== 'string' || !config.secret.trim()) {
        console.error('OTP验证失败：secret 为空或格式错误');
        isValid = false;
      } else {
        isValid = await verifyOtp(config.secret, otp);
      }
    } else if (recoveryCode) {
      // 一次性核销在 store 的认证临界区内完成（锁内重读配置），防并发重放；
      // 明文归一化与 /totp/rebind 保持同口径。
      isValid = await store.consumeRecoveryCode(String(recoveryCode).trim().toUpperCase());
    }

    if (!isValid) {
      // 诊断:输出 2FA 验证失败的详细上下文,便于服务器端排查
      console.error('[login:2fa] 验证失败', {
        hasOtp: !!otp,
        hasRecovery: !!recoveryCode,
        secretEmpty: !config.secret || typeof config.secret !== 'string' || !config.secret.trim(),
        secretLen: config.secret ? config.secret.length : 0,
        encKeyConfigured: !!process.env.ENCRYPTION_KEY,
        recoveryCodeCount: Array.isArray(config.recoveryCodes) ? config.recoveryCodes.length : 0,
      });
      const isBlocked = store.recordFailedAttempt(ip);
      const remainingAttempts = store.getRemainingAttempts(ip);

      if (isBlocked) {
        return res.status(403).json({
          code: -3,
          message: `尝试次数过多，您的IP已被封锁 ${store.BLOCK_DURATION_HOURS} 小时`,
          blocked: true,
          remainingHours: store.BLOCK_DURATION_HOURS,
        });
      }

      return res.status(401).json({
        code: -1,
        message: `验证码错误，还剩 ${remainingAttempts} 次尝试机会`,
        need2FA: true,
        remainingAttempts,
      });
    }

    store.clearFailedAttempts(ip);
    const sessionId = store.generateSessionId();
    store.sessions[sessionId] = {
      createdAt: Date.now(),
      authenticated: true,
      twoFAVerified: true,
    };
    store.saveSessions();

    res.json({
      code: 0,
      message: '登录成功',
      sessionId,
      need2FA: false,
      twoFAEnabled: true,
    });
  }),
);

// 注销：主动吊销当前会话，防止登出后会话 ID 在服务端继续有效
router.post('/logout', authMiddleware, (req, res) => {
  const sessionId = req.headers['x-session-id'];
  if (store.isValidSession(sessionId)) {
    delete store.sessions[sessionId];
    store.saveSessions();
  }
  res.json({ code: 0, message: '已退出登录' });
});

router.get(
  '/totp/setup',
  authMiddleware,
  asyncHandler(async (req, res) => {
    const config = store.getTotpConfig();
    const { recoveryCode } = req.query;

    // 恢复码经 GET query 传输会留在访问日志/浏览器历史，且该端点不消费恢复码。
    // 重新绑定一律走 POST /api/admin/totp/rebind。
    if (recoveryCode) {
      return res
        .status(400)
        .json({ code: -1, message: '请改用 POST /api/admin/totp/rebind 提交恢复码' });
    }

    // 已启用：仅返回状态（不生成新 secret，避免破坏已绑定的认证器）
    if (config.enabled) {
      return res.json({
        code: 0,
        message: 'success',
        data: {
          enabled: true,
          hasSecret: !!config.secret,
          rebindable: Array.isArray(config.recoveryCodes) && config.recoveryCodes.length > 0,
        },
      });
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
        rebind: false,
        secret,
        qrCodeUrl,
        otpauth,
        manualCode: secret,
      },
    });
  }),
);

// 重新绑定二步验证：POST 提交恢复码（避免 GET query 泄露），校验成功后消费（一次性）
router.post(
  '/totp/rebind',
  authMiddleware,
  asyncHandler(async (req, res) => {
    const ip = store.getClientIp(req);
    const config = store.getTotpConfig();
    const { recoveryCode } = req.body || {};

    if (!config.enabled) {
      return res.status(400).json({ code: -1, message: '二步验证未启用，无需重新绑定' });
    }
    if (typeof recoveryCode !== 'string' || !recoveryCode.trim()) {
      return res.status(400).json({ code: -1, message: '恢复码不能为空' });
    }

    const normalized = recoveryCode.trim().toUpperCase();
    // 一次性核销走 store 的认证临界区（锁内重读配置），与 /login 同规，防并发重放。
    const consumed = await store.consumeRecoveryCode(normalized);

    if (!consumed) {
      // 校验失败计入失败次数，受 IP 封锁保护（与登录路径语义一致）
      console.error('[rebind] 恢复码验证失败，IP:', ip);
      const isBlocked = store.recordFailedAttempt(ip);
      if (isBlocked) {
        return res.status(403).json({
          code: -3,
          message: `尝试次数过多，您的IP已被封锁 ${store.BLOCK_DURATION_HOURS} 小时`,
          blocked: true,
        });
      }
      const remaining = store.getRemainingAttempts(ip);
      return res
        .status(400)
        .json({ code: -1, message: `恢复码错误，还剩 ${remaining} 次尝试机会` });
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
        rebind: true,
        secret,
        qrCodeUrl,
        otpauth,
        manualCode: secret,
      },
    });
  }),
);

router.post(
  '/totp/enable',
  authMiddleware,
  asyncHandler(async (req, res) => {
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

    const { plain: recoveryCodes, hashed: hashedCodes } = await store.generateRecoveryCodes();
    const config = {
      enabled: true,
      secret,
      recoveryCodes: hashedCodes,
    };

    store.saveTotpConfig(config);
    // 凭据态势已变更：吊销全部会话，强制以「Token + OTP」重新登录。authMiddleware 也会
    // 拒绝开启前铸造的 token-only 会话，这里把内存与落盘会话一并清掉。
    store.revokeAllSessions('二步验证已启用');

    res.json({
      code: 0,
      message: '二步验证已启用',
      data: {
        enabled: true,
        recoveryCodes,
      },
    });
  }),
);

router.post(
  '/totp/disable',
  authMiddleware,
  asyncHandler(async (req, res) => {
    const { otp, recoveryCode } = req.body;
    const config = store.getTotpConfig();

    if (!config.enabled) {
      return res.status(400).json({ code: -1, message: '二步验证未启用' });
    }

    let isValid = false;
    if (otp) {
      if (config._decryptError) {
        return res.status(500).json({
          code: -2,
          message: '服务端二步验证密钥配置错误，请联系管理员检查 ENCRYPTION_KEY',
        });
      }
      try {
        isValid = await verifyOtp(config.secret, otp);
      } catch (e) {
        console.error('TOTP disable verify error:', e.message);
        isValid = false;
      }
    } else if (recoveryCode) {
      // 恢复码在这里也必须**核销**：旧实现只比对不落盘，一条码只要没被 /login 消费过，
      // 就能反复用来关闭 2FA（等于把二步验证长期降级为「仅 token」）；而且裸 bcrypt.compare
      // 会 await 让出事件循环，并发下同一码可通过多次。统一走 store 的认证临界区。
      isValid = await store.consumeRecoveryCode(String(recoveryCode).trim().toUpperCase());
    }

    if (!isValid) {
      return res.status(400).json({ code: -1, message: '验证码错误' });
    }

    // consumeRecoveryCode 已在锁内落盘，这里必须重读：拿上面的旧快照写回会把刚核销的码复活
    const disabled = store.getTotpConfig();
    disabled.enabled = false;
    store.saveTotpConfig(disabled);

    res.json({
      code: 0,
      message: '二步验证已禁用',
    });
  }),
);

router.get('/totp/status', authMiddleware, (req, res) => {
  try {
    const config = store.getTotpConfig();
    res.json({
      code: 0,
      message: 'success',
      data: {
        enabled: config.enabled,
        hasRecoveryCodes: config.recoveryCodes && config.recoveryCodes.length > 0,
      },
    });
  } catch (e) {
    console.error('TOTP status error:', e.message);
    res.status(500).json({ code: -5, message: '服务器内部错误' });
  }
});

router.post(
  '/totp/regenerate-recovery',
  authMiddleware,
  asyncHandler(async (req, res) => {
    const { otp, recoveryCode } = req.body;
    const config = store.getTotpConfig();

    if (!config.enabled) {
      return res.status(400).json({ code: -1, message: '二步验证未启用' });
    }

    let isValid = false;
    if (otp) {
      if (config._decryptError) {
        return res.status(500).json({
          code: -2,
          message: '服务端二步验证密钥配置错误，请联系管理员检查 ENCRYPTION_KEY',
        });
      }
      try {
        isValid = await verifyOtp(config.secret, otp);
      } catch (e) {
        console.error('TOTP regenerate verify error:', e.message);
        isValid = false;
      }
    } else if (recoveryCode) {
      // 与 /login、/totp/rebind 同一条临界区：旧实现裸比对 + splice + 写盘，并发下同一恢复码
      // 可被两个请求同时通过（各自基于同一快照改数组，后写者覆盖前者）。
      isValid = await store.consumeRecoveryCode(String(recoveryCode).trim().toUpperCase());
    }

    if (!isValid) {
      return res.status(400).json({ code: -1, message: '验证码错误' });
    }

    // 核销已在锁内落盘 → 重读后再换发新批次，避免用旧快照复活刚核销的那条
    const fresh = store.getTotpConfig();
    const { plain: recoveryCodes, hashed: hashedCodes } = await store.generateRecoveryCodes();
    fresh.recoveryCodes = hashedCodes;
    store.saveTotpConfig(fresh);

    res.json({
      code: 0,
      message: '恢复码已重新生成',
      data: {
        recoveryCodes,
      },
    });
  }),
);

module.exports = router;
