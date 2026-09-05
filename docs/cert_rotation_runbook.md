# SSL 证书固定轮换 Runbook

> 适用范围：NoticeTransmit 客户端证书固定机制。
> **当前状态：证书固定默认关闭**（未注入 `CERT_PINS` 时仅做标准 TLS 验证），线上依赖 Cloudflare CDN 保护。本文档为启用与轮换时的操作手册，避免轮换不当导致存量客户端无法连接。

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
