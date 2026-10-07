/**
 * 版本检查 / 版本管理 / 健康检查路由
 *
 * 从 server.js 拆分而来，保持原有行为不变：
 * - GET /api/version/check 为公开接口（不受 IP 封锁与认证限制）
 * - GET /api/version/region 同样公开：只回边缘看到的国家码，裁决在客户端（T96）
 * - GET|POST /api/admin/version 需认证（authMiddleware）
 * - 版本配置保存链路：POST 校验并写入 version.json，GET 读取返回（前后端契约）
 */

const express = require('express');

const store = require('../store');
const { authMiddleware } = require('../middleware');
// T75 ④：`/health` 要报契约版本，取值与版本闸门只认 `fnthink/contract` 这一份 ——
// 自己另抄一份 SUPPORTED_MAJOR 就是第二份真值，而它错配时不会报错，只会让自部署者
// 看到「版本号对但连不上」这类查不出来的现象。
const contractModule = require('../fnthink/contract');

const router = express.Router();

// 校验请求体为普通 JSON 对象（排除 null、数组、基本类型），防止写入畸形配置
function isPlainObject(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

// 字段级校验：版本配置必填字段与类型
// 当前契约：downloads/fileSizes 对象（admin.html saveVersion 提交）；
// 兼容旧契约：downloadUrl/fileSize 单字段（历史客户端）。
/// version.json 的合法字段（保存接口只接受这些键，其余忽略不落盘）。
/// 前 10 项为当前契约；`downloadUrl` / `fileSize` 是旧版客户端仍读的兼容字段。
const VERSION_CONFIG_FIELDS = [
  'latestVersion',
  'latestBuild',
  'forceUpdate',
  'forceUpdateVersion',
  'forceUpdateBuild',
  'changelog',
  // T61 更新流双语：**新增**英文那一份，`changelog` 保持中文串不动 ——
  // 老包读的是 `changelog`，改成对象的话它们 `toString()` 会显示 `{zh=…}`。
  // 这一行必须在白名单里：保存接口只接受列出来的键，漏了它就是"管理面填了、
  // 落盘时静默丢掉"，而报告里看不出任何东西。
  'changelogEn',
  'downloads',
  'fileSizes',
  'sha256',
  'minSupportedVersion',
  'downloadUrl',
  'fileSize',
];

function validateVersionConfig(body) {
  const errors = [];
  // latestVersion: 必填、非空字符串
  if (typeof body.latestVersion !== 'string' || !body.latestVersion.trim()) {
    errors.push('latestVersion 必须为非空字符串');
  }
  // latestBuild: 必填、正整数
  if (
    typeof body.latestBuild !== 'number' ||
    !Number.isInteger(body.latestBuild) ||
    body.latestBuild <= 0
  ) {
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
  // sha256: 可选对象（N3 传输层校验），各平台 64 位十六进制（空串 = 跳过该校验）
  if (body.sha256 !== undefined) {
    if (!isPlainObject(body.sha256)) {
      errors.push('sha256 必须为 JSON 对象');
    } else {
      const hex64 = /^[0-9a-f]{64}$/;
      for (const k of ['arm64', 'arm32', 'x86_64', 'all']) {
        const v = body.sha256[k];
        if (v === undefined || v === '') continue; // 空串/缺失表示该平台不校验
        if (typeof v !== 'string' || !hex64.test(v)) {
          errors.push(`sha256.${k} 必须为 64 位小写十六进制`);
        }
      }
    }
  }
  // T61：`changelog` / `changelogEn` 都是可选字符串。
  // ⚠ 这里**不要求英文那一份非空**：老版本还没有它（`changelogEn` 缺失是常态，
  //   不是缺陷），强制必填会让每一次升级保存都红，而客户端本来就按"取不到回退中文"处理。
  //   要非空的话得由发版闸门去核（那是"这一版该有"的判断，不是"这个键合法"的判断）。
  for (const k of ['changelog', 'changelogEn']) {
    const v = body[k];
    if (v === undefined) continue;
    if (typeof v !== 'string') {
      errors.push(`${k} 必须为字符串`);
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
    if (
      typeof body.forceUpdateBuild !== 'number' ||
      !Number.isInteger(body.forceUpdateBuild) ||
      body.forceUpdateBuild < 0
    ) {
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
      // T61：英文那一份同样给空串默认值，缺它时客户端按"取不到回退中文"处理。
      changelogEn: '',
      downloads: {},
      fileSizes: {},
      minSupportedVersion: '1.0.0',
    });

    const hasUpdate =
      compareVersions(versionData.latestVersion, version) > 0 ||
      versionData.latestBuild > Number(build || 0);

    const needForce =
      versionData.forceUpdate &&
      (compareVersions(versionData.forceUpdateVersion || versionData.latestVersion, version) > 0 ||
        versionData.forceUpdateBuild > Number(build || 0));

    const downloads = versionData.downloads || {};
    const fileSizes = versionData.fileSizes || {};
    const sha256 = versionData.sha256 || {};
    // 根据平台参数解析对应的单架构下载链接和大小（默认 arm64）
    const platformKey =
      platform === 'x86_64' ? 'x86_64' : platform === 'armeabi-v7a' ? 'arm32' : 'arm64';
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
        // T61：两串都发下去，**由客户端按软件语言只显示一种**（取不到回退中文）。
        // ⚠ 服务端不在这里替客户端选：它不知道这台机器的软件语言，而问一次要多一个参数
        // 与一条代理链路；两串一起发是唯一不把语言判断塞进两处的做法。
        changelogEn: versionData.changelogEn || '',
        downloadUrl,
        fileSize,
        downloads,
        fileSizes,
        sha256,
        minSupportedVersion: versionData.minSupportedVersion,
      },
    });
  } catch (e) {
    console.error('Version check error:', e.message);
    res.status(500).json({ code: -5, message: '服务器内部错误' });
  }
});

// ────────────────────────────── T96 地理回读 ──────────────────────────────
//
// 公开：GET /api/version/region —— 把**边缘**看到的国家码原样报给客户端。
// 客户端拿它做首启的"该连哪一台"裁决（大陆档 / 国际档）。
//
// ⚠ 这一条**只报事实、不做裁决**：回的三样是 country / source / edge。
//   "哪些国家码算大陆"住在客户端的纯函数里。裁决若搬进服务端，两个域名的两份
//   部署就必须永远一致（多一个真值出处），而改判据要从"改客户端"变成"重新部署"。
//
// ⚠ 为什么**不**用 `req.ip` 去查 GeoIP：本机 `trust proxy = 0`（见 lib/app.js 那条
//   注释），源站看到的 `req.ip` 是 **CDN 回源 IP** —— 拿它算地理会把 Cloudflare 的
//   机房当成用户（#140 量的正是同一件事，只是那里伤的是限流）。而 `cf-ipcountry`
//   是 CF 边缘按**真实客户端 IP** 判好之后随请求带进来的，与 trust proxy 无关。
//   ⇒ 今天这个端点不需要先动反代配置就能在那一台上用。
// ⚠ `.com` 那台走腾讯 EdgeOne：它是否在回源请求里带地理头**未经实测**，所以这里
//   不猜头名（猜错的话永远回 source:'none'，而那看起来像"部署没生效"）。头名由
//   `FNTHINK_GEO_HEADER` 配置；`FNTHINK_GEO_ECHO=1` 时额外把请求头的**名字**列出来
//   （只有名字、不含值）用于部署后跑一次 curl 就测出 EdgeOne 到底带了什么，测完关掉。
// ⚠ 缓存口径与 /api/version/check **相反**：那份是全体一致的版本配置，这一份是每个
//   用户不一样的地理结论。必须 `no-store`（`no-cache` 仍允许存储 + 回源校验，
//   于是第一个用户的国家码可能被发给后面的人），并按地理头写 `Vary`。
// ⚠ 不落日志：这里既不写 IP 也不写国家码。一条"问一次地理"的接口不该顺手变成
//   访问日志里的地理记录 —— 那是隐私政策要另算的一件事。

const CF_COUNTRY_HEADER = 'cf-ipcountry';
// EdgeOne 那台将来实测到的头名由这里配（小写，Node 的 req.get 不区分大小写）
const GEO_COUNTRY_HEADER_ENV = 'FNTHINK_GEO_HEADER';
// 边缘标识在 cf-* 之外没法从请求头自证，允许部署方显式标注（如 edgeone）
const GEO_EDGE_LABEL_ENV = 'FNTHINK_EDGE';
const GEO_ECHO_ENV = 'FNTHINK_GEO_ECHO';

// 国家码只认 ISO 3166-1 alpha-2 的**形状**（两个 ASCII 字母）。
// ⚠ 另外单列 CF 的两个**保留值**（不属于 alpha-2，但确实是边缘给的一种事实）：
//   · `XX` —— 边缘判不出来；
//   · `T1` —— 匿名代理（iCloud Private Relay 那一类）。
// 折叠成 null 的话，"它说不知道"与"根本没给地理头"就同一形状，而这两种在客户端
// 是不同分支（前者该按国家码之外再回落，后者该只用时延）。
// ⚠ 这两个值**不是**结论：客户端不许把它们放进任何一档的判据里。裁决仍然在客户端，
//   这里只保证它们不会被当成畸形丢掉。
function parseGeoCountry(raw) {
  if (typeof raw !== 'string') return null;
  const s = raw.trim().toUpperCase();
  return /^[A-Z]{2}$/.test(s) || s === 'XX' || s === 'T1' ? s : null;
}

// 配置里的自定义地理头名；不合法（空、含空格/冒号/换行）一律当作没配。
function geoHeaderName() {
  const raw = String(process.env[GEO_COUNTRY_HEADER_ENV] || '')
    .trim()
    .toLowerCase();
  return /^[a-z0-9-]{1,64}$/.test(raw) ? raw : null;
}

// 边缘标识：cf-* 在场就是 cloudflare（这是能从请求头上自证的唯一一种）；
// 否则用部署方标注的值，否则 unknown —— **不猜**"另一个域名前面一定是 EdgeOne"，
// 那正是本端点要测的东西，写死了就再也测不出来。
function edgeLabelOf(req) {
  if (req.get('cf-ray') || req.get(CF_COUNTRY_HEADER) || req.get('cf-visitor')) {
    return 'cloudflare';
  }
  const configured = String(process.env[GEO_EDGE_LABEL_ENV] || '')
    .trim()
    .toLowerCase();
  return /^[a-z0-9-]{1,32}$/.test(configured) ? configured : 'unknown';
}

router.get('/api/version/region', (req, res) => {
  const configuredHeader = geoHeaderName();
  const cfRaw = req.get(CF_COUNTRY_HEADER);
  const customRaw = configuredHeader ? req.get(configuredHeader) : undefined;
  const cfCountry = parseGeoCountry(cfRaw);
  const customCountry = parseGeoCountry(customRaw);

  let country = null;
  let source = 'none';
  if (cfCountry) {
    country = cfCountry;
    source = 'cf-ipcountry';
  } else if (customCountry) {
    country = customCountry;
    source = 'geo-header';
  }
  // 头到了、值不成形状：与"根本没有头"是两件事（前者像中间层改写，后者像没接上），
  // 用一个布尔区分，country/source 那一对的不变量保持干净。
  const rawUnusable =
    (!!cfRaw && !cfCountry) || (!!configuredHeader && !!customRaw && !customCountry);

  res.set('Cache-Control', 'no-store');
  // 无论这次有没有读到，响应都按这两个头变（读到的是 cf，配的是自定义那一个）
  res.set('Vary', [CF_COUNTRY_HEADER, configuredHeader].filter(Boolean).join(', '));

  res.json({
    code: 0,
    message: 'success',
    data: {
      country,
      source,
      edge: edgeLabelOf(req),
      ...(rawUnusable ? { rawUnusable: true } : {}),
      // 只在配了自定义头时出现：让"我要的是哪个头、它到没到"部署后一眼读得出来
      ...(configuredHeader
        ? {
            geoHeader: configuredHeader,
            ...(customRaw ? {} : { geoHeaderMissing: true }),
          }
        : {}),
      ...(process.env[GEO_ECHO_ENV] === '1'
        ? { headerNames: Object.keys(req.headers).sort() }
        : {}),
    },
  });
});

// 管理：读取版本配置（需认证）
router.get('/api/admin/version', authMiddleware, (req, res) => {
  try {
    const data = store.readJsonFile(store.VERSION_FILE, {});
    res.json({
      code: 0,
      message: 'success',
      data,
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
    // 白名单投影后再落盘：`writeJsonFile(body)` 原样入库会把请求体的任意字段写进
    // version.json，而该文件经公开接口 /api/admin/version 完整回显 —— 等于让管理员
    // 会话把服务器变成任意键值的存储（mass assignment + 公开回显）。
    const safe = {};
    for (const key of VERSION_CONFIG_FIELDS) {
      if (body[key] !== undefined) safe[key] = body[key];
    }
    const ignored = Object.keys(body).filter((k) => !VERSION_CONFIG_FIELDS.includes(k));
    if (ignored.length > 0) {
      console.warn(`[version] 已忽略未知字段（不落盘）：${ignored.join(', ')}`);
    }
    // N3：admin.html 的 saveVersion 不含 sha256 字段——直接覆盖会丢掉发版时写入的
    // 传输层校验值。body 未提供 sha256 时沿用既有配置（显式提交的 sha256 仍可覆盖）。
    if (safe.sha256 === undefined) {
      const existing = store.readJsonFile(store.VERSION_FILE, {});
      if (isPlainObject(existing) && existing.sha256 !== undefined) {
        safe.sha256 = existing.sha256;
      }
    }
    const success = store.writeJsonFile(store.VERSION_FILE, safe);
    res.json({
      code: success ? 0 : -1,
      message: success ? '保存成功' : '保存失败',
    });
  } catch (e) {
    console.error('Save version error:', e.message);
    res.status(500).json({ code: -5, message: '服务器内部错误' });
  }
});

// 公开：健康检查。
// ⚠ T75 ④：这里**必须报契约版本**（`protocolVersion` / `contractVersion`）——
//   自部署者遇到「我这边连不上」时，第一件要确认的就是「我这份 server/ 与那份契约
//   是不是同一代」。只回 `{status:'ok'}` 的话，一个版本错配的实例和健康的实例长得
//   一模一样，于是每次都得开一条 issue 才问得出来。
//   ⚠ 契约读不到时**照旧回 200**，只把两个字段置成 null 并带上原因 ——
//     `/health` 是整台风服务的心跳（连它都与幻念推送毫无关系），让契约缺失把它带走
//     就是把「协议面降级」升级成「整机不可用」，与 A1 定的那条部署口径相反。
router.get('/health', (req, res) => {
  let contractVersion = null;
  let protocolVersion = null;
  let contractError = null;
  try {
    const contract = contractModule.assertSupported(contractModule.loadContract());
    contractVersion = contract.contractVersion;
    protocolVersion = contract.protocol;
  } catch (e) {
    contractError = e && e.code ? e.code : 'CONTRACT_UNREADABLE';
  }
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    // 本实现支持到的主版本（常量恒在，报出来是为了让自部署者一眼看出「落后了几代」）
    supportedMajor: contractModule.SUPPORTED_MAJOR,
    contractVersion,
    protocolVersion,
    ...(contractError ? { contractError } : {}),
  });
});

module.exports = router;
