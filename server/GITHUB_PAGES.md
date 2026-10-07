# GitHub Pages 部署指南

这一页讲的是 **GitHub Pages 今天能给你什么、不能给你什么**：它发布的是**官网静态站**（首页 + `/api/version.json`）；
而 **App 的更新通道需要一个能回 `/api/version/check` 的服务** —— 那一条 Pages 给不了（原因见「App 今天到底怎么拿更新」）。

## 两种部署模式对比

| | Node.js 服务器 | GitHub Pages |
|---|---|---|
| **运行时** | 需要 Node.js 进程（Node 24） | 纯静态，零运维 |
| **App 内检查更新** | ✅ `/api/version/check`（App 走的**只有**这一条） | ❌ **走不通**：App 不读静态 `version.json` |
| **官网显示最新版本** | ✅ | ✅（Pages 那份 `/api/version.json` 就是给它读的） |
| **APK 托管** | ✅ `/apks/`（`downloads` 写相对路径也能解析） | ❌ 产物里没有 APK（`server/public/apks/` 被 `.gitignore` 挡着，CI 检出时是空的）⇒ 下载必须指向 CDN 或 Releases |
| **管理后台** | ✅ 可用（`admin.html` + `/api/admin/*`） | ❌ 不可用（页面能打开，接口不存在） |
| **版本管理** | `POST /api/admin/version` 校验后落盘；API 侧算 `hasUpdate` / `forceUpdate` | ❌ 只能改仓库文件后重新部署；没有那个 API，也就没人替你算 `hasUpdate` |
| **二步验证** | ✅ 支持（TOTP + 恢复码） | ❌ 不可用 |
| **IP 封锁 / 限流** | ✅ 支持（内置） | ❌ 不可用 |
| **地理回读**（`/api/version/region`，App 用它挑一档） | ✅ | ❌ 不存在 —— 纯静态跑不了逻辑 |
| **部署成本** | 需服务器 + Nginx + PM2 | 免费零配置 |
| **适用场景** | **要给 App 提供更新，就必须是这一档** | 官网 / 文档的静态镜像；**不是** App 的更新通道 |

## App 今天到底怎么拿更新（2026-10-07 的实际行为）

客户端**只发一发** `GET <所选那一档>/api/version/check?version=…&build=…&platform=android`，四种结局：

```
200 + {code:0, data:{…}}        → 用服务端算好的 hasUpdate / forceUpdate；这一发同时记成那台的健康度
被 CDN 拦截（Cloudflare 403 等） → 直接给可操作提示（同域的别的路径也在同一套防护后面，换路径救不了）
其他非 200 / code≠0             → 就报这一发的结论并收尾
网络异常                         → 退避 2 秒重试一次；两发都没发出去就报"没回话"（与"回了 500"分开）
```

⚠ **原先那条「失败后回退 `/api/version.json`」的静态模式已经整条删除**（提交 `cbec666`）。删它的理由不是"用的人少"，
而是它**从来没通过**：服务端没有那个路由，两个官方域名实测都回 Express 自己那句 `Cannot GET /api/version.json`
（维护者 2026-10-07 确认那是故意没做的）。它唯一的净效果是让用户白等第二个 15 秒超时，然后仍然报同一个错。
⇒ **所以"只部署 Pages"这条路，对 App 的更新流不成立。**

App 拨的是哪一台：`lib/services/update_server_regions.dart` 里的**两档**（大陆 / 海外，除主机名外逐字一致），
用户在「更多 → 更新服务器」里选，两种模式 —— 自动（两台各探一次再挑）与手动（钉住之后谁都不许自动改）。
**已经没有编译期常量 `AppUpdateManager._updateServerUrl` 可改**，这也是本页以前那句
「把 `_updateServerUrl` 指向 Pages 地址重新出包」作废的原因。

安装包那边照旧：客户端按设备 ABI 从服务端下发的 `downloads` 选包，装前用 `sha256` 做传输层校验（N3）；
CDN 主地址失败后再试 GitHub 加速镜像与 Releases 直链 —— 镜像上的资产名**沿用主地址里那一个**（同一个文件、两处归档），
Release 的 tag 段**必须带 `v`**（只有 `v*` 的 tag 才建得出 Release）。

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

例如：`https://your-org.github.io/noticeTransmit/`

Pages 站点根**含仓库名前缀**（`https://your-org.github.io/noticeTransmit`）这一点仍然要记：官网首页里那些相对地址（`api/version.json`、页面内链接）是按"站点根"解析的，前缀少一层就 404。
⚠ 但**读者是官网首页，不是 App 的更新请求** —— App 不读 `/api/version.json`（见上面那节），把 Pages 地址喂给 App 是行不通的。

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

> 注意 `api/version.json` 是**人为拼出来的路径**：仓库里它位于 `server/data/version.json`，Pages 上它出现在 `/api/` 前缀下。
> ⚠ 现在读它的是**官网首页**（站内四级数据源降级的第一级，见 `public/index.html`），**不是 App** —— 它以前配合的是
> 客户端那条静态回退请求，那条已在提交 `cbec666` 删除（服务端没有那个路由）。路径留着是因为官网还在用，别当废话删掉。
> `server/public/` 里新增的文件会自动进入产物；`server/data/` 下除 `version.json` 外的文件（`totp.json`、`sessions.json` 等运行期状态）**不会**被发布。

## 发布新版本

### GitHub Pages 模式

1. 修改 `server/data/version.json`：`latestVersion`、`latestBuild`、`changelog`、`minSupportedVersion`、`forceUpdate`（含 `forceUpdateVersion`/`forceUpdateBuild`）、以及四架构的 `downloads` / `fileSizes` / `sha256`
2. 把 APK 上传到 CDN 或 GitHub Releases。App 的下载顺序是：`downloads` 里那一条（服务端下发的 CDN 主地址）→ GitHub 加速镜像 → Releases 直链。后两条由**客户端自己合成**，形状是 `<镜像基址>/v<版本号>/<主地址里那一份 APK 的文件名>`：
   - tag 段**必须带 `v`**。`.github/workflows/build-apk.yml` 只在 `v*` 的 tag 上建 Release —— 这一页以前写的是"tag 必须正好是版本号（不带 `v`）"，那正是 #234 修掉的缺陷：拼出来的地址必然 404，而它**只在 CDN 主地址挂掉时**才被走到，日常一条用例都摸不到。
   - 文件名**沿用主地址里那一个**（发版脚本一次构建、两处归档 ⇒ 是同一个文件）。所以改 `downloads` 的命名那天，镜像上的那份也得叫那个名字。规则住在 `lib/services/update_download_urls.dart`，别在别处再抄一份。
3. 本地跑一遍闸门：`bash .github/scripts/check_version_consistency.sh`（校验版本号/构建号一致性 + `sha256` 格式与完备性）—— Pages 那份是静态文件，发布之后没有任何服务端会替你校验字段
4. 提交并推送到 `main` 分支
5. GitHub Actions 自动部署到 Pages；到 `/api/version.json` 确认内容已是新版本
6. ⚠ **到这一步 App 看不见新版本**（App 不读静态文件，见上面那节）。要让 App 收到，得改**服务端**那份 `version.json`：管理后台 `POST /api/admin/version`，或直接编辑服务器上的文件（每次请求实时读取，无需重启）

### Node.js 服务器模式

1. 修改 `server/data/version.json`（或直接改仓库那份再上传部署）
2. 通过管理后台 `/admin.html` 提交 `POST /api/admin/version`（保存即生效，无需重启；服务端会做字段校验与白名单投影，并沿用既有 `sha256`）
3. 或直接编辑服务器上的文件——同样是每次请求实时读取，无需重启

## 混合部署（本项目现状）

- **GitHub Pages** = 官网静态镜像（`your-org.github.io/<仓库名>`），读它那份 `/api/version.json` 的是**官网首页**
- **Node.js 服务器** = App 的更新通道与管理后台（示例写作 `notice.example.com` / `notice.example.top`，两档只差主机名）
- App 拨的是**两档里被选中的那一台**（「更多 → 更新服务器」，自动/手动），**永远走 `/api/version/check`**

⚠ 以前这一节写的是「`_updateServerUrl` 指向 Node，Pages 场景由静态回退兜底；Node 或 CDN 不可用（被墙等）时把常量指向 Pages 地址重新出包」。
**这条路今天不存在了**：那个常量已随 T95 片2 删除，静态回退已随 `cbec666` 删除 ⇒ Pages 不能当 App 更新通道的备胎。
App 侧真正生效的"另一台"只有地址表里的**另一档**（那是另一个 Node 实例，不是 Pages）。

## 这一页不涵盖幻念推送，以及为什么

GitHub Pages 是**纯静态**的：它只能发 JSON 文件，不能跑逻辑。而幻念推送的服务端（注册、配对、收件、长连接式轮询、验签、限流、二步验证）**全都是逻辑**。

所以：

| 能力 | GitHub Pages | Node.js 自部署 |
|---|---|---|
| 官网展示最新版本 / 手动下载入口 | ✅ | ✅ |
| **App 内检查更新** | ❌ **走不通**：App 只请求 `/api/version/check`，不读静态 JSON | ✅ |
| 幻念推送（`/api/fnthink/*`） | ❌ **完全不存在** | ✅ 装上契约后可用 |

⚠ **Pages 上既没有"简化版幻念推送"，也没有"降级版更新通道"。** 它只有静态文件 —— `/api/version.json` 那一条是给
官网首页读的（App 不读它，`/health` 也不存在）。想要 App 能收到新版本、或想要推送，都只能跑 Node.js 那一份
（见 README 的「加装幻念推送公网面」与上面的对比表）。

### 边界声明（与 README 那节一致）

- **官方实例**是维护者提供的默认服务地址，按 App 发布同步升级；**自部署实例**是你自己运行的，无可用性承诺、无支持、不代表官方。
- **Pages 站只是一个静态发版渠道**，既不是官方实例，也不是一个"服务实例"——它连 `/health` 都没有。
- 你若把客户端的幻念推送服务地址指向某台第三方实例，**对方能看到消息正文与元数据**（应用内隐私说明里也写着这一点）。

### 版本策略

只保证 **App 与官方实例同步升级**。Pages 站与自部署实例都由你自己跟版；契约与代码不同代时，自部署那份会**直接拒绝**（不做"能解释多少算多少"），用 `npm run fnthink:doctor` 一步确认（详见 README）。

## 注意事项

1. **GitHub Pages 有 1GB 存储限制和 100GB/月流量限制**，且 Pages 不适合托管大文件——APK 下载地址必须指向 CDN 或 GitHub Releases
2. **JSON 文件更新可能有 1-2 分钟 CDN 缓存延迟**；发版后先直接访问 `https://<站点>/api/version.json` 确认已刷新，再**刷新官网页面**看
   （⚠ 看的是官网，不是 App：App 不读这份文件。App 那一路走的是服务端 `/api/version/check`，两台实测都回
   `Cache-Control: no-cache` ⇒ 每次都会回源，不存在"Pages 刷新了 App 就看到了"这回事）
3. **管理后台 `admin.html` 在 GitHub Pages 上可以打开，但所有 `/api/admin/*` 请求都会 404**（`admin.js` 用 `window.location.origin` 拼接口地址），登录/改版本/二步验证全部不可用
4. **Pages 那份静态文件没有任何服务端校验**：`version.json` 写错（例如 `latestBuild` 非整数、`sha256` 大写、`downloads` 用了 `http://`）时，读它的**官网**会按各自的容错逻辑解析 ⇒ 现象是"页面上版本号/大小/链接不对"。
   ⚠ 别把它与"直达全部用户"混为一谈：那一句在今天只对**服务端那一份**成立（App 读的是 `/api/version/check`）。
   但两份是同一个来源 —— 你从仓库 `rsync` 上去的就是服务端那份，所以**发版前一律先过 `check_version_consistency.sh`**（服务端的管理接口 `POST /api/admin/version` 另有字段校验与白名单投影，直接编辑文件那条路径没有）
5. **`server/data/` 里的运行期状态不会被发布**，Pages 上也不存在二步验证、会话、IP 封锁、限流这些能力（它们只在 Node.js 服务端里）
