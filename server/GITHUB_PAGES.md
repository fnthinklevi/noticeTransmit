# GitHub Pages 部署指南

本文档介绍如何通过 **GitHub Pages** 部署更新服务，作为 Node.js 服务器的轻量替代方案。

## 两种部署模式对比

| | Node.js 服务器 | GitHub Pages |
|---|---|---|
| **运行时** | 需要 Node.js 进程（Node 24） | 纯静态，零运维 |
| **管理后台** | ✅ 可用（`admin.html` + `/api/admin/*`） | ❌ 不可用（页面能打开，接口不存在） |
| **版本管理** | API 侧计算 `hasUpdate`/`forceUpdate` | 客户端读原始 JSON 本地比对 |
| **二步验证** | ✅ 支持（TOTP + 恢复码） | ❌ 不可用 |
| **IP 封锁 / 限流** | ✅ 支持（内置） | ❌ 不可用 |
| **写入 version.json** | ✅ `POST /api/admin/version`（含字段校验） | ❌ 只能改仓库文件后重新部署 |
| **部署成本** | 需服务器 + Nginx + PM2 | 免费零配置 |
| **适用场景** | 正式生产环境 | 个人 / 小规模使用 |

## 客户端兼容机制

客户端 `lib/update_manager.dart` 已内置双模式自动兼容（`_updateServerUrl` 是编译期常量）：

```
1. 先请求 /api/version/check?version=X&build=Y&platform=android   （API 模式）
   ├─ 200 + JSON {code:0, data:{…}}  → 直接用服务端算好的 hasUpdate / forceUpdate
   ├─ 网络异常                        → 退避 2 秒重试一次，仍失败才进入静态模式
   ├─ 被 CDN 拦截（Cloudflare 403 等） → 不回退（静态端点同域同防护，必然同样失败），直接提示
   └─ 其他非 200 / code≠0             → 进入静态模式

2. 回退请求 /api/version.json（无 query 参数）                      （静态模式）
   └─ 200 + 原始 version.json → 客户端本地比对版本号/构建号，并自行算 forceUpdate
```

**无需修改客户端代码**——只要部署的 URL 能返回正确的 JSON，两种模式自动切换。两种模式下客户端都按设备 ABI 从 `downloads` 选包，并用 `sha256` 做安装前的传输层校验（N3），所以静态模式**同样要求 `downloads`/`fileSizes`/`sha256` 三张表填全**。

## 部署工作流实际做了什么

Pages 站由 `.github/workflows/deploy-pages.yml`（workflow 名 `Deploy to GitHub Pages`）发布，**发布的是构建时临时拼出来的 `_pages/` 目录，不是仓库里的任何目录**：

| 环节 | 实现 |
|---|---|
| 触发 | `push` 到 `main` 且改动命中 `server/data/version.json` 或 `server/public/**`；也可手动 **Actions → Deploy to GitHub Pages → Run workflow**（`workflow_dispatch`） |
| 运行器 | `ubuntu-24.04`（7 步；`actions/checkout@v7` + `configure-pages@v5` + `upload-pages-artifact@v3` + `deploy-pages@v4`） |
| 权限 | `contents: read`、`pages: write`、`id-token: write` |
| 并发 | `group: pages`，`cancel-in-progress: true`（后一次推送会取消上一次进行中的部署） |
| 产物组装 | `mkdir -p _pages/api` → `cp -r server/public/* _pages/` → `cp server/data/version.json _pages/api/version.json` → `touch _pages/.nojekyll`（防 Jekyll 破坏 JSON） |
| 上传/发布 | `upload-pages-artifact@v3` 上传 `path: _pages`，`deploy-pages@v4` 发布（`enablement: true`，用 `GITHUB_TOKEN`） |

> ⚠️ 产物里**没有 APK**：`server/public/apks/` 被 `.gitignore` 忽略，CI 检出时该目录是空的。APK 必须放 CDN / GitHub Releases（见下文「注意事项」）。

## 快速部署（3 步）

### 1. 启用 GitHub Pages

1. 进入 GitHub 仓库 → **Settings** → **Pages**
2. **Build and deployment** → Source 选择 **GitHub Actions**
3. **重要**：若页面提示 "Allow GitHub Actions to publish to Pages"，勾选启用
4. 仓库根目录的 `.github/workflows/deploy-pages.yml` 会自动被识别

> ⚠️ **仅需设置一次**。此后每次推送符合条件的文件，GitHub Actions 自动部署，无需再次手动操作。
> 只改 `README`、`docs/` 等文件**不会**触发部署（`paths` 过滤只看 `server/data/version.json` 与 `server/public/**`）。

### 2. 推送触发部署

当 `server/data/version.json` 或 `server/public/` 下的文件发生变更并推送到 `main` 分支时，GitHub Actions 会自动部署。

也可以手动触发：**Actions** → **Deploy to GitHub Pages** → **Run workflow**。

### 3. 获取 URL

部署完成后，GitHub Pages 地址格式为：

```
https://<用户名>.github.io/<仓库名>/
```

例如：`https://fnthinklevi.github.io/noticeTransmit/`

客户端要读静态配置，`_updateServerUrl` 就得指到**含仓库名前缀**的那一层（回退请求是 `$_updateServerUrl/api/version.json`）：`https://fnthinklevi.github.io/noticeTransmit`。

## 静态文件目录结构

工作流组装出的 `_pages/`（即 Pages 站点根）：

```
/
├── index.html              ← 官网首页（复制自 server/public/）
├── admin.html              ← 管理后台页面（静态，API 不存在）
├── admin.js                ← 后台脚本（admin.html 外链，CSP 要求无内联脚本）
├── i18n.js                 ← 官网中/英字典
├── app_icon.png / favicon.ico
├── .nojekyll               ← 禁用 Jekyll 处理
└── api/
    └── version.json        ← 版本配置（复制自 server/data/version.json）
```

> 注意 `api/version.json` 是**人为拼出来的路径**：仓库里它位于 `server/data/version.json`，Pages 上它出现在 `/api/` 前缀下，只为配合客户端的回退请求。`server/public/` 里新增的文件会自动进入产物；`server/data/` 下除 `version.json` 外的文件（`totp.json`、`sessions.json` 等运行期状态）**不会**被发布。

## 发布新版本

### GitHub Pages 模式

1. 修改 `server/data/version.json`：`latestVersion`、`latestBuild`、`changelog`、`minSupportedVersion`、`forceUpdate`（含 `forceUpdateVersion`/`forceUpdateBuild`）、以及四架构的 `downloads` / `fileSizes` / `sha256`
2. 把 APK 上传到 CDN 或 GitHub Releases。App 的下载兜底顺序是 `version.json` 的 `downloads`（CDN 主地址）→ GitHub 加速镜像 → GitHub 直链，后两者按 `releases/download/<版本号>/notice_<arm64|arm32|x86|all>_<版本号>.apk` 拼接：要让兜底生效，**Release tag 必须正好是版本号（不带 `v`），资产必须按该命名上传**。（注意 `.github/workflows/build-apk.yml` 只在 `v*` tag 上建 Release，且资产名是 `notice<版本号>.apk`，与这条兜底命名不一致——别指望 CI 产物自动喂到镜像兜底。）
3. 本地跑一遍闸门：`bash .github/scripts/check_version_consistency.sh`（校验版本号/构建号一致性 + `sha256` 格式与完备性），静态模式下服务端不会替你校验任何字段
4. 提交并推送到 `main` 分支
5. GitHub Actions 自动部署到 Pages；到 `/api/version.json` 确认内容已是新版本

### Node.js 服务器模式

1. 修改 `server/data/version.json`（或直接改仓库那份再上传部署）
2. 通过管理后台 `/admin.html` 提交 `POST /api/admin/version`（保存即生效，无需重启；服务端会做字段校验与白名单投影，并沿用既有 `sha256`）
3. 或直接编辑服务器上的文件——同样是每次请求实时读取，无需重启

## 混合部署（推荐，本项目现状）

- **GitHub Pages** 作为官网静态主站（`fnthinklevi.github.io/noticeTransmit`）
- **Node.js 服务器** 承担 API 与管理后台（`notice.fnthink.top`）
- 客户端 `_updateServerUrl` 指向 Node 服务器：API 正常时用 API，Pages 场景由静态回退兜底

如果 Node 服务器 / CDN 不可用（被墙等），把 `_updateServerUrl` 指向 Pages 地址重新出包即可（这是编译期常量，不能应用内改）。

## 注意事项

1. **GitHub Pages 有 1GB 存储限制和 100GB/月流量限制**，且 Pages 不适合托管大文件——APK 下载地址必须指向 CDN 或 GitHub Releases
2. **JSON 文件更新可能有 1-2 分钟 CDN 缓存延迟**；发版后先直接访问 `https://<站点>/api/version.json` 确认已刷新，再看客户端
3. **管理后台 `admin.html` 在 GitHub Pages 上可以打开，但所有 `/api/admin/*` 请求都会 404**（`admin.js` 用 `window.location.origin` 拼接口地址），登录/改版本/二步验证全部不可用
4. **静态模式没有任何服务端校验**：`version.json` 写错（例如 `latestBuild` 非整数、`sha256` 大写、`downloads` 用了 `http://`）会被客户端按各自容错逻辑解析，问题会直达全部用户——务必先过 `check_version_consistency.sh`
5. **`server/data/` 里的运行期状态不会被发布**，Pages 上也不存在二步验证、会话、IP 封锁、限流这些能力（它们只在 Node.js 服务端里）
