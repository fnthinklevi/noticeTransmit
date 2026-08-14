/**
 * 版本检查 / 版本管理 / 健康检查路由
 *
 * 从 server.js 拆分而来，保持原有行为不变：
 * - GET /api/version/check 为公开接口（不受 IP 封锁与认证限制）
 * - GET|POST /api/admin/version 需认证（authMiddleware）
 * - 版本配置保存链路：POST 校验并写入 version.json，GET 读取返回（前后端契约）
 */

const express = require('express');

const store = require('../store');
const { authMiddleware } = require('../middleware');

const router = express.Router();

// 校验请求体为普通 JSON 对象（排除 null、数组、基本类型），防止写入畸形配置
function isPlainObject(value) {
  return (
    typeof value === 'object' &&
    value !== null &&
    !Array.isArray(value)
  );
}

// 字段级校验：版本配置必填字段与类型
// 当前契约：downloads/fileSizes 对象（admin.html saveVersion 提交）；
// 兼容旧契约：downloadUrl/fileSize 单字段（历史客户端）。
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
  // downloads: 必填对象（当前契约），四个平台的下载链接
  if (body.downloads !== undefined) {
    if (!isPlainObject(body.downloads)) {
      errors.push('downloads 必须为 JSON 对象');
    } else {
      for (const k of ['arm64', 'arm32', 'x86_64', 'all']) {
        const v = body.downloads[k];
        if (v === undefined || v === '') continue; // 空串表示该平台未发布，允许
        if (typeof v !== 'string') {
          errors.push(`downloads.${k} 必须为字符串`);
          continue;
        }
        try {
          const url = new URL(v);
          if (url.protocol !== 'https:') {
            errors.push(`downloads.${k} 必须使用 https:// 协议`);
          }
        } catch {
          errors.push(`downloads.${k} 不是合法 URL`);
        }
      }
    }
  }
  // fileSizes: 可选对象，各平台大小为非负整数
  if (body.fileSizes !== undefined) {
    if (!isPlainObject(body.fileSizes)) {
      errors.push('fileSizes 必须为 JSON 对象');
    } else {
      for (const k of ['arm64', 'arm32', 'x86_64', 'all']) {
        const v = body.fileSizes[k];
        if (v === undefined) continue;
        if (typeof v !== 'number' || !Number.isInteger(v) || v < 0) {
          errors.push(`fileSizes.${k} 必须为非负整数`);
        }
      }
    }
  }
  // 兼容旧契约：仅当未提供 downloads 时才校验 downloadUrl/fileSize
  if (body.downloads === undefined) {
    if (body.downloadUrl !== undefined) {
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
    }
    if (body.fileSize !== undefined && (typeof body.fileSize !== 'number' || body.fileSize < 0)) {
      errors.push('fileSize 必须为非负整数');
    }
  }
  // forceUpdate: 可选布尔；为 true 时要求 forceUpdateVersion/Build
  if (body.forceUpdate === true) {
    if (typeof body.forceUpdateVersion !== 'string' || !body.forceUpdateVersion.trim()) {
      errors.push('forceUpdateVersion 必须为非空字符串');
    }
    if (typeof body.forceUpdateBuild !== 'number' || !Number.isInteger(body.forceUpdateBuild) || body.forceUpdateBuild < 0) {
      errors.push('forceUpdateBuild 必须为非负整数');
    }
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

// 公开：版本检查（App 调用）
router.get('/api/version/check', (req, res) => {
  try {
    const { version, build, platform = 'android' } = req.query;
    const versionData = store.readJsonFile(store.VERSION_FILE, {
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

// 管理：读取版本配置（需认证）
router.get('/api/admin/version', authMiddleware, (req, res) => {
  try {
    const data = store.readJsonFile(store.VERSION_FILE, {});
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

// 管理：保存版本配置（需认证）——保存链路核心，校验后原子写入 version.json
router.post('/api/admin/version', authMiddleware, (req, res) => {
  try {
    const body = req.body;
    if (!isPlainObject(body)) {
      return res.status(400).json({ code: -4, message: '请求体必须为 JSON 对象' });
    }
    const errors = validateVersionConfig(body);
    if (errors.length > 0) {
      return res.status(400).json({ code: -4, message: `字段校验失败: ${errors.join('; ')}` });
    }
    const success = store.writeJsonFile(store.VERSION_FILE, body);
    res.json({
      code: success ? 0 : -1,
      message: success ? '保存成功' : '保存失败'
    });
  } catch (e) {
    console.error('Save version error:', e.message);
    res.status(500).json({ code: -5, message: '服务器内部错误' });
  }
});

// 公开：健康检查
router.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

module.exports = router;
