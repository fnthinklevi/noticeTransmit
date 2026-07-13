const express = require('express');
const cors = require('cors');
const path = require('path');
const fs = require('fs');

const app = express();
const PORT = process.env.PORT || 3456;

app.use(cors());
app.use(express.json());
app.use('/public', express.static(path.join(__dirname, 'public')));

const VERSION_FILE = path.join(__dirname, 'data', 'version.json');
const HOTFIX_FILE = path.join(__dirname, 'data', 'hotfix.json');
const DATA_DIR = path.join(__dirname, 'data');

const ADMIN_TOKEN = process.env.ADMIN_TOKEN || 'your-secret-token-change-in-production';

function authMiddleware(req, res, next) {
  const token = req.headers['x-admin-token'];
  if (token !== ADMIN_TOKEN) {
    return res.status(401).json({ code: -1, message: '未授权' });
  }
  next();
}

if (!fs.existsSync(DATA_DIR)) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
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

app.listen(PORT, () => {
  console.log('==============================');
  console.log('  更新服务已启动');
  console.log(`  端口: ${PORT}`);
  console.log(`  时间: ${new Date().toLocaleString()}`);
  console.log('==============================');
  console.log('');
  console.log('API 接口:');
  console.log('  GET  /api/version/check   - 检查版本更新');
  console.log('  GET  /api/hotfix/check    - 检查热更新');
  console.log('  GET  /api/admin/version   - 获取版本配置');
  console.log('  POST /api/admin/version   - 更新版本配置');
  console.log('  GET  /api/admin/hotfix    - 获取热更新配置');
  console.log('  POST /api/admin/hotfix    - 更新热更新配置');
  console.log('  GET  /health              - 健康检查');
  console.log('');
  console.log('静态资源:');
  console.log('  /public/apks/    - APK 文件目录');
  console.log('  /public/hotfix/  - 热更新包目录');
  console.log('');
});
