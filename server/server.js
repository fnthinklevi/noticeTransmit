/**
 * 服务入口：组装 Express 应用并启动，负责进程生命周期（定时持久化 / 优雅关闭）
 *
 * 路由与业务逻辑已拆分至 lib/（store / otp / middleware / routes / app）。
 */

require('dotenv').config();
const app = require('./lib/app');
const store = require('./lib/store');

const PORT = process.env.PORT || 3456;

// 定期清理 + 持久化：保存到文件防止重启丢失
setInterval(() => {
  store.cleanupRateLimitStore();
  store.saveRateLimitStore();
}, store.RATE_LIMIT_WINDOW_MS);

// 定期清理过期会话 + 持久化，避免内存无上限增长
setInterval(store.cleanupSessions, 60 * 60 * 1000);

// 优雅关闭：进程退出前持久化内存状态
function onShutdown(signal) {
  console.log(`\n[${signal}] 正在保存状态...`);
  store.saveRateLimitStore();
  store.saveSessions();
  store.saveFailedAttempts(store.failedAttempts);
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
  const diag = store.getTotpConfig();
  const secretDesc = diag._decryptError
    ? '解密失败(ENCRYPTION_KEY 缺失或不匹配)'
    : diag.secret
      ? `有(${diag.secret.length}字符)`
      : '空';
  console.log(`  二步验证诊断: enabled=${diag.enabled} secret=${secretDesc} 恢复码=${Array.isArray(diag.recoveryCodes) ? diag.recoveryCodes.length : 0} 个 ENCRYPTION_KEY=${process.env.ENCRYPTION_KEY ? '已配置' : '未配置'}`);
  console.log(`  DISABLE_IP_BLOCKING=${store.DISABLE_IP_BLOCKING ? '开启(IP封锁已临时关闭)' : '关闭(IP封锁生效)'}`);
});
