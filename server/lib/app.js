/**
 * Express 应用组装：CORS / JSON / 安全头 / 静态资源 / IP 封锁 / 限流 / 路由 / 全局错误
 *
 * 从 server.js 拆分而来，保持原有行为不变；只组装并导出 app，不监听端口
 * （由入口 server.js 启动），便于测试直接 require 后使用 supertest 发起真实 HTTP 请求。
 */

require('dotenv').config();
const express = require('express');
const cors = require('cors');
const path = require('path');

const middleware = require('./middleware');
const authRoutes = require('./routes/auth');
const versionRoutes = require('./routes/version');

const app = express();

// 禁用 X-Powered-By 响应头，避免暴露 Express 指纹
app.disable('x-powered-by');

// 信任反向代理跳数：默认 0（不信任任何代理头，直连部署安全默认值）。
// 反代部署（Nginx/CF）必须显式设置 TRUST_PROXY=1（多级代理按跳数递增），
// 否则 IP 封锁与限流看到的都是代理 IP；而未挂反代时若信任 X-Forwarded-For，
// 攻击者伪造该头即可伪造 IP 绕过封锁/限流（fail-safe 默认）。
app.set('trust proxy', Number(process.env.TRUST_PROXY ?? 0));

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
  }),
);
app.use(express.json({ limit: '1mb' }));

// 安全 HTTP 头（含管理后台 CSP / API 缓存禁用）
app.use(middleware.securityHeaders);

// 静态资源：根路径直接映射到 public 目录
// notice.fnthink.top/            → public/index.html（网站主页）
// notice.fnthink.top/admin.html → public/admin.html（管理后台）
app.use(express.static(path.join(__dirname, '..', 'public')));
// 兼容旧地址：保留 /public 前缀（notice.fnthink.top/public/... 仍可用）
app.use('/public', express.static(path.join(__dirname, '..', 'public')));

// IP 封锁（公开接口豁免）→ 全局限流 → 认证接口限流（顺序与原 server.js 一致）
app.use(middleware.ipBlockMiddleware);
app.use(middleware.generalRateLimiter);
app.use('/api/admin', middleware.authRateLimiter);

// 路由挂载
app.use('/api/admin', authRoutes);
app.use('/', versionRoutes);
// 幻念推送（fnthink-v1）的公网入口。⚠ 这一段必须"坏了也不连累别的端点"：
// 契约文件默认在仓库根的 protocol/，而部署历来只上传 server/ —— 那种情况下 require 链会直接抛
// ENOENT，冒到顶层被拖死的是 /api/version 与管理后台（所有设备的更新检查），
// 而它们和幻念推送一点关系都没有。所以这里接住，降级成"明确 503 + 启动日志说清缺哪份文件"，
// 并让运维在日志第一屏就看到（不是等用户反馈"推送连不上"）。
try {
  const fnthink = require('./fnthink/routes');
  app.use('/api/fnthink', fnthink.router);
} catch (e) {
  console.error('[fnthink] 协议入口没有起来，这段路由已降级为 503：', e.message);
  console.error(
    '[fnthink] 需要把契约文件放到 protocol/fnthink-v1.json，或用 FNTHINK_CONTRACT 指向它',
  );
  app.use('/api/fnthink', (req, res) =>
    res.status(503).json({ error: 'fnthink_protocol_unavailable' }),
  );
}

// 全局错误处理中间件（放在所有路由之后）
app.use(middleware.errorMiddleware);

module.exports = app;
