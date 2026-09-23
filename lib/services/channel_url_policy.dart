/// 通道 URL 的**唯一**校验规则（第 6 步）。
///
/// 之前这条规则有两份，而且两份不一样：
/// - 原生：[AppChannelTokenHelper.normalizeBase] 与 `ChannelHealthProbe.isProbeableUrl`
///   都接受 `http://` 与 `https://`；
/// - Dart：`backup_service.validatePayload` 只接受 `https://`，注释还写着
///   「与原生保存链路一致」。
///
/// 后果不是报错而是**静默丢配置**：自建 ntfy / Gotify 跑在局域网 http 上很常见，
/// 这类通道在恢复备份时被当成"非法条目"跳过 ⇒ 用户的通道列表少几条，
/// 而备份文件本身看起来是成功的。
///
/// 规则本身保持与原生一致：绝对 URL + http/https 两种 scheme 都算合法。
/// 跨端一致性由 `channel_url_policy_test` 直接解析那两个 Kotlin 函数守着。
abstract final class ChannelUrlPolicy {
  /// 是否为可发送/可探测的绝对 URL（http 或 https）。
  static bool isHttpUrl(String url) {
    final u = url.trim();
    return u.startsWith('http://') || u.startsWith('https://');
  }
}
