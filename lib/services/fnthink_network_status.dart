import '../l10n/app_localizations.dart';

/// T215 片3：诊断读数里的 poll 结论翻人话。
///
/// 554/524 是 EdgeOne 的网关超时，不是协议结论；其余 5xx 也只是边缘/源站暂时不可用。
/// 非网关那几档原样返回 —— 本函数只负责"别把网关码糊在用户脸上"，不替内核改判。
String fnthinkPollStatusText(AppLocalizations l10n, String raw) {
  // T228：并发闸的「本轮跳过」是合成状态（零 IO、零 ack），不是一次 HTTP 结论。
  // 它带着 `failed:` 前缀，直接摊在诊断行里会被读成故障；这一档翻人话，且词条里
  // 不许出现 failed／失败。真正的失败（含 signing-unavailable）仍原样返回。
  if (raw == 'failed:round-in-progress' ||
      raw.startsWith('failed:round-in-progress:')) {
    return l10n.fnthinkPollRoundInProgress;
  }
  final code = RegExp(r'(?:http:|gateway-timeout:)(\d+)')
      .firstMatch(raw)
      ?.group(1);
  final numeric = int.tryParse(code ?? '') ?? 0;
  final gateway =
      raw.startsWith('gatewayTimeout:') ||
      raw.startsWith('failed:gateway-timeout:') ||
      (raw.startsWith('failed:http:') && numeric >= 500);
  if (!gateway) return raw;
  if (code == '554' || code == '524') {
    return l10n.fnthinkPollGatewayTimeout;
  }
  return l10n.fnthinkPollGatewayUnavailable(code ?? '5xx');
}

/// 「协议面就绪」只由**最近一次协议结论**回答。
///
/// - `true`：服务端答了（含 429/401/409/410 这类业务结论）；
/// - `false`：网络没通或网关 5xx；
/// - `null`：这一格没有结论（本地签不出来 / 上一轮还在途 / 还没跑过）。
bool? fnthinkPollStatusReachable(String raw) {
  if (raw.isEmpty) return null;
  if (raw == 'ok' || raw.startsWith('ok:')) return true;
  if (raw.startsWith('rateLimited:') ||
      raw.startsWith('rejectedUnsigned:') ||
      raw.startsWith('replayed:') ||
      raw.startsWith('needsCalibration:')) {
    return true;
  }
  if (raw.startsWith('failed:signing-unavailable') ||
      raw.startsWith('failed:round-in-progress')) {
    return null;
  }
  if (raw.startsWith('failed:') ||
      raw.startsWith('transportError:') ||
      raw.startsWith('gatewayTimeout:')) {
    return false;
  }
  return null;
}
