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

const store = require('./store');
const { isContractAvailabilityError } = require('./fnthink/contract');
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
// 公网面（fnthink）的请求体上限**必须挂在这把管理面的 1 MB 之前**：body-parser 见到已解析的
// `req._body` 就跳过，所以谁先注册谁说了算 —— 顺序错了不报错，只是公网面静默地继续吃 1 MB。
// 两把尺子量的是方向不同的东西：公网面 1 MB 松了 16 倍，而管理面（备份导入）就是要 1 MB 以上。
try {
  const { createFnthinkBodyLimit } = require('./fnthink/bodylimit');
  const fnthinkBody = createFnthinkBodyLimit();
  app.set('fnthinkBodyMaxBytes', fnthinkBody.max);
  app.use('/api/fnthink', fnthinkBody.middlewares);
} catch (e) {
  // 契约读不到 ⇒ 这一档挂不上。不静默：下面那把 1 MB 会接管公网面，而路由本身也会降级 503，
  // 但日志必须说破"体积闸没挂上"，否则运维以为公网面已经有上限了。
  console.error('[fnthink] 请求体上限没挂上，公网面暂时吃管理面的 1 MB：', e.message);
}
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
  // 限流器挂在路由之前：协议面上的洪水应该先被闸门挡住，再谈验签（验签比计数贵得多）。
  const { createFnthinkRateLimiter } = require('./fnthink/ratelimit');
  const fnthinkLimiter = createFnthinkRateLimiter(store.RATE_LIMIT_FNTHINK_MAX);
  app.use('/api/fnthink', fnthinkLimiter);
  const fnthink = require('./fnthink/routes');
  app.use('/api/fnthink', fnthink.router);
  // 启动日志要报"公网面上到底开了哪几条"。这份清单**从路由本身取**，不在 server.js 里再抄一串：
  // 抄的那份早晚少一个，而少的表现是"运维以为没开，其实开着"（或反过来，去加固错的那一侧）。
  app.set(
    'fnthinkEndpoints',
    fnthink.router.stack
      .filter((layer) => layer.route)
      .map(
        (layer) =>
          `${Object.keys(layer.route.methods)
            .sort()
            .join(',')
            .toUpperCase()} /api/fnthink${layer.route.path}`,
      ),
  );
} catch (e) {
  // ⚠ 只咽"契约这一层真的不可用"：文件不在 / 不是合法 JSON / 协议主版本不认识。
  //   其它异常一律往上抛 —— 本片实测踩过：这里漏了 `require('./store')`，抛的是
  //   ReferenceError，被这道 catch 吞成 503，日志变成"请把契约文件放到 protocol/"，
  //   于是一个代码 bug 伪装成了部署问题（而且测试里只看到一串 503）。
  if (!isContractAvailabilityError(e)) throw e;
  app.set('fnthinkEndpoints', []);
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
