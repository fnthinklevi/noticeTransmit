# 证书与签名密钥轮换 Runbook

> 适用范围：
> 1. **SSL 证书固定**（第 1–6 节）；
> 2. **APK 签名密钥轮换**（第 7 节）—— 应用内更新以「本机已安装应用的签名证书」为可信根，
>    更换签名密钥会直接影响更新链路，**换密钥前必须先读第 7 节**。
>
> **证书固定当前状态：默认关闭**（Dart 侧未注入 `CERT_PINS` 即不启用；原生侧 `ENABLE_CERT_PINNING` 默认 false，Debug 构建被 `build.gradle.kts` 强制覆盖为 false），线上依赖 Cloudflare CDN 保护。本文档为启用与轮换时的操作手册，避免轮换不当导致存量客户端无法连接。
>
> 权威总览见 `base.md` §3.5「SSL 证书固定（PinnedHttpClient）」。

## 1. 固定点与配置来源

**两端各一个固定点，两套互不兼容的指纹格式**（这是轮换时最容易踩的地方）：

| 位置 | 说明 |
|------|------|
| `lib/services/pinned_http_client.dart`（仅 `lib/update_manager.dart` 创建并使用 `_updateHttpClient`） | Dart 侧固定，**覆盖范围只有更新链路**（版本检查、`/api/version.json` 静态回退、下载源 HEAD 探测与 APK 下载）；Webhook/邮件推送走原生 `NetworkClient`，不在此列。指纹来自 `--dart-define=CERT_PINS`，格式 `host1=AA:BB:...;host2=CC:DD:...`（分号分隔、`=` 连接 host 与指纹），为空/未注入即不启用。**比对的是「整张叶子证书 DER 的 SHA256」，冒号分隔大写十六进制**（`openssl x509 -fingerprint -sha256` 那种）。实现挂在 `HttpClient.badCertificateCallback` 上：只有标准 TLS 校验**失败**时才会被调用，因此它的语义是「校验失败时，凭指纹放行」——不匹配不会主动断连，防护强度也弱于原生侧 |
| `android/app/src/main/kotlin/com/fnthink/notice/NetworkClient.kt` | **原生侧唯一生效的固定点**（webhook 推送用的 OkHttp 客户端）。`buildCertificatePinner()` 在 `BuildConfig.ENABLE_CERT_PINNING` 为 false 或 `CERT_PINS` 为空时返回 null（不固定）；启用时把 `CERT_PINS`（`sha256/<base64>` 形式的**公钥 SPKI pin**，多个用 `;` 分隔）逐条应用到硬编码的 `notice.fnthink.top` 与 `xget.fnthink.top` 两个 host。**只接受以 `sha256/` 开头的条目**：喂进冒号十六进制会被全部过滤掉 → `pins.isEmpty()` → 静默等于没固定 |
| `MainActivity.kt`（okHttpClient） | 该客户端的 `certificatePinner(...)` 仍是**注释状态**（未生效），且注释里的写法直接把冒号十六进制的 `CERT_PINS` 当 OkHttp pin 用（格式不合法）。要固定原生下载链路，参照 `NetworkClient.kt` 的 `buildCertificatePinner()`，不要照抄这段注释 |
| `android/app/build.gradle.kts` | `CERT_PINS` / `ENABLE_CERT_PINNING` 注入 BuildConfig：取环境变量 `CERT_PINS` / `ENABLE_CERT_PINNING`，或 Gradle 参数 `-PcertPins=...` / `-PenableCertPinning=true`；`buildTypes.debug` 强制 `ENABLE_CERT_PINNING=false` |

**启用开关的作用域不同**：`ENABLE_CERT_PINNING` **只作用于原生侧**（BuildConfig 布尔位）；Dart 侧不读它，只要 `CERT_PINS` 里有 `host=指纹` 就生效。所以「两端同时开启」= 注入两份格式不同的 `CERT_PINS` + 打开原生的 `ENABLE_CERT_PINNING`。

指纹算法：Dart 侧 = 服务器证书 PEM→DER 全量 SHA256（冒号分隔大写十六进制）；原生侧 = 证书公钥（SPKI）DER 的 SHA256，base64 加 `sha256/` 前缀（OkHttp 标准 pin）。

## 2. 获取证书指纹

**Dart 侧（冒号十六进制，叶子证书整体）：**

```bash
openssl s_client -connect notice.fnthink.top:443 -servername notice.fnthink.top \
  </dev/null 2>/dev/null \
  | openssl x509 -noout -fingerprint -sha256 \
  | sed 's/.*=//'
```

**原生侧（`sha256/<base64>` 公钥 pin）：**

```bash
openssl s_client -connect notice.fnthink.top:443 -servername notice.fnthink.top \
  </dev/null 2>/dev/null \
  | openssl x509 -pubkey -noout | openssl pkey -pubin -outform der \
  | openssl dgst -sha256 -binary | openssl base64
# 输出记作 <b64>，写入 CERT_PINS 时拼成 sha256/<b64>
```

两个 host（`notice.fnthink.top`、`xget.fnthink.top`）各自实测：原生侧会把同一批 pin 同时应用到两个 host，Dart 侧按 host 查表、**表里没有的 host 在校验失败时一律拒绝**。

> ⚠️ 直接抓 CDN 边缘得到的指纹会随 Cloudflare 自动轮换而失效。推荐先在 Cloudflare → SSL/TLS → Origin Server 上传自有长期源站证书，固定源站证书（`base.md` §3.5 步骤 1）。

## 3. 启用证书固定（首次）

1. **确认证书策略**：目标域名使用固定证书/CA 稳定（Cloudflare 代理下源站证书在 CDN 边缘终结，需固定**边缘证书**且跟随 Cloudflare 轮换节奏，谨慎评估；推荐固定源站证书）。
2. 本地验证（release 构建必须，原生 Debug 恒关闭）：
   ```bash
   flutter build apk --release \
     --dart-define=CERT_PINS="notice.fnthink.top=AA:BB:...;xget.fnthink.top=DD:EE:..."
   ```
   Dart 侧只需上面这一份（`ENABLE_CERT_PINNING` 对 Dart 无效）。原生侧另注一份 **`sha256/` 格式**的 pin：
   ```bash
   ./gradlew assembleRelease -PcertPins="sha256/AAA...;sha256/BBB..." -PenableCertPinning=true
   ```
   多 pin 用 `;` 分隔，**至少 2 个（当前 + 备用）**。
3. **确认真的生效**（原生侧若不生效是静默的）：把 pin 改成错误值再构建，预期原生日志出现 `Certificate pinning failure`、Dart 侧在标准校验失败的场景下拒绝连接；用正确 pin 时全部恢复。
4. 真机回归：版本检查 / Webhook 推送 / 更新下载三条 HTTPS 链路全部可用。

## 4. 证书轮换流程（已启用时）

轮换原则：**新旧指纹并存过渡，先发客户端，后切服务端**，确保任何时刻存量 App 至少有一个可用 pin。

1. **T0（新证书部署前）**：发布包含「旧 pin + 新 pin」双指纹的客户端版本（Dart 侧 `CERT_PINS="host=旧;host=新"`，原生侧 `CERT_PINS="sha256/旧;sha256/新"`），等待灰度覆盖 ≥ 预期活跃设备（参考 version.json 下载数据）。
2. **T1**：服务端/CDN 切换到新证书。原生 `CertificatePinner` 是**强校验**：新证书上线瞬间，只带旧 pin 的存量版本会立刻断连（推送失败 / 下载失败），未启用固定的旧版本不受影响。这一步必须等 T0 覆盖率达标。
3. **T2**：确认新版本活跃占比达标后，后续版本可移除旧 pin。
4. **验证**：每一步后跑一次真机回归（检查更新、推送、下载）。

## 5. 回滚

- 客户端 pin 错误导致连不上：服务端回退到旧证书（pin 匹配旧证书即可恢复）；无法回退证书时，走紧急发版通道推送去掉 pin 的版本。
- 服务端证书被吊销/泄露等紧急场景：先在 CDN 层更换证书并同步更新客户端双 pin，再按第 4 节流程补发。

## 6. 责任与检查清单

- [ ] 两套格式没有混用：Dart = 冒号十六进制的证书 DER 指纹，原生 = `sha256/<base64>` 公钥 pin（原生侧拿到冒号格式会被静默过滤 = 未固定）
- [ ] 新指纹来自 `openssl` 实测而非证书链中间级（固定的是叶子证书 / 其公钥）
- [ ] 每个 host（`notice.fnthink.top`、`xget.fnthink.top`）都已覆盖，且至少 2 个 pin（当前 + 备用）
- [ ] 双 pin 过渡版本已发布且覆盖达标后才切服务端
- [ ] 已用「错误 pin 应断连」反向验证固定真的生效
- [ ] 原生 Debug 构建不受影响（`build.gradle.kts` 强制 `ENABLE_CERT_PINNING=false`）；Dart 侧 Debug 只要不注入 `CERT_PINS` 即不固定
- [ ] base.md §3.5「SSL 证书固定」小节与本 runbook 同步更新

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

`decide()` 除签名一致性外的判定，换密钥改比对策略时**别误伤**：

1. **回滚防护**：`archiveCode < currentCode` 即拒（与签名无关；`archiveInfo` 解析不到时按 `Long.MIN_VALUE` 处理，等于必拒）；
2. **fail-closed**：读不到当前签名 / 解析不到归档包 / 文件缺失或长度为 0，一律判不通过，绝不降级放行。

调用方校验的是**即将安装的同一份文件**（`MainActivity.verifyApkSignature()` → `ApkSignatureVerifier.verify()`，以及 `installSystemDownload` 里对 `staged` 路径的那次 `verify()`），别在改判定策略时把校验对象换成别的路径，否则留下"校验后被替换"的 TOCTOU 窗口。

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
