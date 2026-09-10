# 证书与签名密钥轮换 Runbook

> 适用范围：
> 1. **SSL 证书固定**（第 1–6 节）；
> 2. **APK 签名密钥轮换**（第 7 节）—— 应用内更新以「本机已安装应用的签名证书」为可信根，
>    更换签名密钥会直接影响更新链路，**换密钥前必须先读第 7 节**。
>
> **证书固定当前状态：默认关闭**（未注入 `CERT_PINS` 时仅做标准 TLS 验证），线上依赖 Cloudflare CDN 保护。本文档为启用与轮换时的操作手册，避免轮换不当导致存量客户端无法连接。

## 1. 固定点与配置来源

| 位置 | 说明 |
|------|------|
| `lib/services/pinned_http_client.dart` | Dart 侧 HTTP 客户端固定。指纹来自 `--dart-define=CERT_PINS`，格式 `host1=AA:BB:...;host2=CC:DD:...`，为空则不启用 |
| `MainActivity.kt`（okHttpClient） | 原生侧 OkHttp 固定点，`certificatePinner` 代码已就位（注释状态），pin 值来自 BuildConfig |
| `android/app/build.gradle.kts` | `CERT_PINS` / `ENABLE_CERT_PINNING` 经环境变量或 `-PcertPins` `-PenableCertPinning` 注入 BuildConfig；Debug 构建强制关闭 |

指纹算法：对服务器证书 PEM 中 DER 部分计算 SHA256，冒号分隔大写十六进制（如 `AA:BB:CC:...`）。

## 2. 获取证书指纹

```bash
openssl s_client -connect notice.fnthink.top:443 -servername notice.fnthink.top \
  </dev/null 2>/dev/null \
  | openssl x509 -noout -fingerprint -sha256 \
  | sed 's/.*=//'
```

## 3. 启用证书固定（首次）

1. **确认证书策略**：确认目标域名使用固定证书/CA 稳定（Cloudflare 代理下源站证书在 CDN 边缘终结，需固定**边缘证书**且跟随 Cloudflare 轮换节奏，谨慎评估）。
2. 本地验证（release 构建必须，Debug 恒关闭）：
   ```bash
   flutter build apk --release \
     --dart-define=CERT_PINS="notice.fnthink.top=AA:BB:..." \
     --dart-define=ENABLE_CERT_PINNING=true
   ```
   同时原生侧构建注入 `-PcertPins=...` `-PenableCertPinning=true`。
3. 真机回归：版本检查 / Webhook 推送 / 更新下载三条 HTTPS 链路全部可用。

## 4. 证书轮换流程（已启用时）

轮换原则：**新旧指纹并存过渡，先发客户端，后切服务端**，确保任何时刻存量 App 至少有一个可用 pin。

1. **T0（新证书部署前）**：发布包含「旧 pin + 新 pin」双指纹的客户端版本（`CERT_PINS="host=旧;host=新"`），等待灰度覆盖 ≥ 预期活跃设备（参考 version.json 下载数据）。
2. **T1**：服务端/CDN 切换到新证书。旧版本客户端仍靠旧 pin 失效前的标准 TLS + CDN 保护（未启用固定的旧版本不受影响）。
3. **T2**：确认新版本活跃占比达标后，后续版本可移除旧 pin。
4. **验证**：每一步后跑一次真机回归（检查更新、推送、下载）。

## 5. 回滚

- 客户端 pin 错误导致连不上：服务端回退到旧证书（pin 匹配旧证书即可恢复）；无法回退证书时，走紧急发版通道推送去掉 pin 的版本。
- 服务端证书被吊销/泄露等紧急场景：先在 CDN 层更换证书并同步更新客户端双 pin，再按第 4 节流程补发。

## 6. 责任与检查清单

- [ ] 新指纹来自 `openssl` 实测而非证书链中间级（固定的是叶子证书）
- [ ] 双 pin 过渡版本已发布且覆盖达标后才切服务端
- [ ] Debug 构建不受影响（恒关闭）
- [ ] base.md「证书固定」小节与本 runbook 同步更新

## 7. APK 签名密钥轮换（应用内更新的可信根）

> **背景**：应用内更新（`lib/update_manager.dart` +
> `android/app/src/main/kotlin/com/fnthink/notice/ApkSignatureVerifier.kt`）
> 以下载包的**签名证书**是否与当前已安装应用一致作为可信根。该可信根独立于分发服务器，
> 可抵御服务器被入侵、镜像被投毒、CDN 被劫持（sha256 写入 version.json 无法防御这些场景 ——
> 攻击者可同时篡改 hash 与 APK）。

### 7.1 ⚠️ 运维地雷：换密钥 = 存量用户无法再应用内更新

因为可信根是"本机签名"，**更换签名密钥后，新包的签名必然与存量用户已安装的版本不匹配**，
`ApkSignatureVerifier.verify()` 会判定失败并阻止安装。后果：

- 所有存量用户**永远无法通过应用内更新升级**，只能卸载重装（丢失本地配置与推送历史）；
- 用户只会看到"安装包校验未通过"之类的提示，不会意识到需要重装。

### 7.2 轮换前必须三选一

| 方案 | 做法 | 适用场景 |
|------|------|----------|
| **A. 多签名过渡（推荐）** | 用 v1/v2/v3 多签名同时签上旧密钥与新密钥，使过渡期新包同时持有两个签名证书 | 常规轮换 |
| **B. 校验侧放宽过渡** | 临时改为"新旧签名任一匹配即通过"，发布过渡版本后再收紧为严格一致 | A 不可行时 |
| **C. 接受断更** | 明确告知用户需手动卸载重装，并在更新接口返回提示 | 密钥已泄露等紧急场景 |

采用 A / B 时必须同步调整 `ApkSignatureVerifier.decide()` 的比对策略 ——
**当前实现为签名集合严格相等**（`current != archive` 即拒绝），
多签名过渡期需改为交集判定或维护"受信任签名指纹白名单"。

### 7.3 推荐流程（方案 A）

1. **T0**：新版本 APK 用**旧密钥 + 新密钥**多签名后发布（签名集合同时包含两者）。
2. **T1**：确认灰度覆盖达标后，后续版本改用**仅新密钥**签名；前提是存量用户已升级到 T0 版本
   （其签名集合已含新密钥），否则会命中 7.1 的锁定问题。
3. **验证**：每个阶段用真机跑一次完整应用内更新（检查更新 → 下载 → **安装未被拦截**）。

### 7.4 检查清单

- [ ] 已确认是否走多签名过渡（换密钥前的必答题）
- [ ] `ApkSignatureVerifier.decide()` 的比对策略已与签名方案匹配
- [ ] 真机回归：应用内更新能正常完成安装（不被"签名不一致"拦截）
- [ ] 若走方案 C：已在 SECURITY.md 与发布说明中告知用户需卸载重装
- [ ] `ApkSignatureVerifierTest`（JVM）与 `ApkSignatureVerifierInstrumentedTest`（真机）全部通过
