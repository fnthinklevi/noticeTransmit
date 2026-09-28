# 许可证变更：MIT → Apache License 2.0

英文版本：[LICENSE_CHANGE-en.md](LICENSE_CHANGE-en.md)。

| 项 | 内容 |
|---|---|
| 生效日期 | 2026-09-28（维护者决定） |
| 生效范围 | 自本次提交（含）之后的全部下载与分发；App、`server/`、`packages/fnthink_push/`、`protocol/` 协议文件与向量 |
| 变更文件 | `LICENSE`、`NOTICE`（新增）、`README.md`、`README-en.md`、`CONTRIBUTING.md`、`CONTRIBUTING-en.md`、`server/public/index.html`、`server/public/i18n.js`、`pubspec.yaml`、`packages/fnthink_push/pubspec.yaml`、`server/package.json` |

## 为什么换

Apache-2.0 相对 MIT 只多两件**实质**的东西，本项目的形态让这两件都值钱：

1. **明示专利授权与反向条款**（第 3 条）。幻念推送的设备身份走 AndroidKeyStore 上的 Ed25519，
   30 以下平台引 `net.i2p.crypto:eddsa` 补曲线运算 —— 这类实现处在移动生态专利活动的射程内。
   MIT 完全不含专利条款，Apache-2.0 明确"贡献即授予专利许可，对你发起专利诉讼者许可自动终止"。
2. **NOTICE 链条**（第 4(d) 条）。再分发时必须保留第三方声明，这比 MIT 那句"保留版权声明"更可核查，
   而本产品确实随包分发大量第三方组件（Flutter/BSD、npm/MIT、Kotlin/Apache 等）。

## 必须说清的一点：这次变更**不追及既往**

仓库在此前一直按 MIT 公开（`LICENSE` 的 MIT 正文与 README 的"开源 MIT"表述都在 git 历史里）。
任何人**在此之前**取得的副本，按其取得时的 MIT 条款继续持有，改成 Apache-2.0 不会收回他的这些权利，
也不会阻止他用那份旧副本做闭源分发或商业托管。

⇒ 结论：如果你的目的是"防止别人拿**今天的代码**去做闭源 SaaS"，换证的作用是有限的；
真正的约束点在于"未来版本"。要更强的保护只剩两条路：对 `server/` 单独双许可（AGPL + 商业授权），
或把协议规范（`protocol/`）与实现分开授权。这两条都**没有**在本次做。

## 本次没改的地方（有意为之，不是遗漏）

- **不给每个源文件加许可头**。仓库历史上就没有 SPDX/文件头声明，补一遍会产生数百文件的巨型 diff，
  连带触发 dart format / ktlint / prettier 全量重跑与 golden 复核 —— 那是另一件事，要做就单独排任务。
- **不改 `update.md` 的历史条目**：那是已发布版本的更新说明，把许可证写进历史等于伪造时间线。
  "许可证变更要不要写进下一次发版的更新说明"留给维护者决定。
- **不改第三方组件的许可证**：`package-lock.json` / `pubspec.lock` 里那些 `"license": "MIT"` 是
  **依赖自己的**元数据，与本项目无关，一律不动。
- **`outputs/` 与 `.workbuddy/` 里的历史存档**（含 `outputs/_t22_pre/LICENSE` 这类改动前快照）保持原样：
  它们是取证材料，改了就不是当时那份东西了。

## 兼容性核对（换证时依赖清单必须能进 Apache-2.0）

Apache-2.0 是宽松许可证，吸收 MIT / BSD / ISC / Apache-2.0 依赖没有方向性问题；要单独确认的是 copyleft。
本机实测扫描（**不是**完整审计，只是把方向性问题排掉）：

- Dart/Flutter 侧：逐个读 `pub-cache` 里的 `LICENSE` 首部，得到 MIT / BSD-3-Clause / BSD-2-Clause /
  Apache License，**没有一处出现 Mozilla Public / GNU GPL / LGPL / AGPL / Eclipse Public**；
- npm 侧：`server/package-lock.json` 的全部 `"license"` 字段值里没有任何 GPL/LGPL/AGPL/MPL/SSPL。

⇒ 换成 Apache-2.0 不与现有依赖的条款相冲。

⚠ 两个边界必须写在这里，别把一次抽查读成一次审计：
① 这是工程判断，不是法律意见；正式对外声明合规应当把**完整传递依赖树**（含 Kotlin/Android AAR、
  Flutter plugin 的原生依赖、随包 .so）过一遍并让懂开源合规的人签字 —— 那一步**还没做**。
② 扫描本身会骗人：我第一次用 `grep -i MPL` 得到"几乎所有 Dart 包都是 MPL"的结论，
  其实是 `e**xampl**e` 这个词命中了 `mpl` 三个字母。要按许可证**全称**（"Mozilla Public"等）匹配。
