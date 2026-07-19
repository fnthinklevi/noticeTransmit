# GitHub Pages 部署指南

本文档介绍如何通过 **GitHub Pages** 部署更新服务，作为 Node.js 服务器的轻量替代方案。

## 两种部署模式对比

| | Node.js 服务器 | GitHub Pages |
|---|---|---|
| **运行时** | 需要 Node.js 进程 | 纯静态，零运维 |
| **管理后台** | ✅ 支持（admin.html + API） | ❌ 不可用 |
| **版本管理** | API 动态对比版本号 | 客户端静态对比 |
| **二步验证** | ✅ 支持 | ❌ 不可用 |
| **IP 封锁** | ✅ 支持 | ❌ 不可用 |
| **部署成本** | 需服务器 + Nginx + PM2 | 免费零配置 |
| **适用场景** | 正式生产环境 | 个人 / 小规模使用 |

## 客户端兼容机制

客户端 `update_manager.dart` 已内置双模式自动兼容：

```
1. 先请求 /api/version/check?version=X&build=Y  （API 模式）
   ├─ 200 + JSON {code:0, data:{...}}  → 使用服务端对比结果
   └─ 404 / 超时 / 连接失败            → 进入静态模式

2. 回退请求 /api/version.json              （静态模式）
   └─ 200 + 原始 version.json            → 客户端本地对比版本号
```

热更新同理：`/api/hotfix/check` → `/api/hotfix.json`。

**无需修改客户端代码**——只要部署的 URL 能返回正确的 JSON，两种模式自动切换。

## 快速部署（3 步）

### 1. 启用 GitHub Pages

1. 进入 GitHub 仓库 → **Settings** → **Pages**
2. **Source** 选择 **GitHub Actions**
3. 仓库根目录的 `.github/workflows/deploy-pages.yml` 会自动被识别

### 2. 推送触发部署

当 `server/data/version.json`、`server/data/hotfix.json` 或 `server/public/` 下的文件发生变更并推送到 `main` 分支时，GitHub Actions 会自动部署。

也可以手动触发：**Actions** → **Deploy to GitHub Pages** → **Run workflow**。

### 3. 获取 URL

部署完成后，GitHub Pages 地址格式为：

```
https://<用户名>.github.io/<仓库名>/
```

例如：`https://fnthinklevi.github.io/noticeTransmit/`

## 静态文件目录结构

GitHub Pages 部署后的文件结构：

```
/
├── index.html              ← 官网首页（复制自 server/public/）
├── admin.html              ← 管理后台页面（静态，API 不可用）
├── .nojekyll               ← 禁用 Jekyll 处理
└── api/
    ├── version.json        ← 版本配置（复制自 server/data/）
    └── hotfix.json         ← 热更新配置（复制自 server/data/）
```

## 发布新版本

### GitHub Pages 模式

1. 修改 `server/data/version.json`（版本号、changelog、downloadUrl、fileSize）
2. 将 APK 上传到 CDN 或 GitHub Releases
3. 提交并推送到 `main` 分支
4. GitHub Actions 自动部署到 Pages

### Node.js 服务器模式

1. 修改 `server/data/version.json`
2. 通过管理后台 API 更新（支持热修改，无需重启）
3. 或直接编辑文件后重启服务

## 混合部署（推荐）

可以同时使用两种模式：

- **GitHub Pages** 作为主站（`your-name.github.io/repo`）
- **Node.js 服务器** 作为管理后台和 API（`notice.fnthink.top`）
- 客户端 `_updateServerUrl` 指向其中一个

如果 GitHub Pages 不可用（被墙等），切换到 Node.js 服务器即可。

## 注意事项

1. **GitHub Pages 有 1GB 存储限制和 100GB/月流量限制**
2. **JSON 文件更新可能有 1-2 分钟 CDN 缓存延迟**
3. **管理后台 `admin.html` 在 GitHub Pages 上可以打开但 API 调用会失败**
4. **APK 下载地址仍需指向 CDN 或 GitHub Releases**（GitHub Pages 不适合托管大文件）
