import 'contract.dart';

/// 一条**幻念端点的推送地址**（T106 片①b 格2）。
///
/// 它不是通用的"URL 解析结果"：里面只装这一发干跑要用的三件东西，而这三件都必须由契约算出来 ——
/// 路径住在契约 `endpoint.ingress.pathPattern` 与 `endpoint.probe.bearerPath`，
/// 口令住在用户从端点页复制下来的那一条地址里。
class FnthinkEndpointDryRun {
  const FnthinkEndpointDryRun({
    required this.probeUrl,
    required this.secret,
    required this.endpointId,
  });

  /// 干跑要 POST 的那一条。⚠ 口令**不在**里面（见 [secret]）：契约 `secretPlacement`
  /// 在这一发上说的是 bearer-header。
  final Uri probeUrl;

  /// 长期口令。只进请求头，不许进 URL、query，也不许进被签的载荷（那正是每一条
  /// clientEvents 的 `mayNotCarry` 明令禁的那件事）。
  final String secret;

  final String endpointId;
}

/// 契约那条**模式**拆成段（丢掉开头斜杠造成的空段）。
List<String> _patternSegments(String pattern) =>
    pattern.split('/').where((s) => s.isNotEmpty).toList(growable: false);

/// 认 [target] 是不是「我们这套端点收单的路径形态」，是就折算出干跑要用的那一发。
///
/// 返回 null = **这一条没有干跑那条路**，调用方必须据此跳过（而不是把它当一次红来写）。
/// 每个 null 分支各防一种会静默变坏的事：
///  - 第三方 webhook（NAS 自己的口、Slack 那种）：协议里没有"问它收不收得进"这一发，
///    硬探就等于真推一条 —— 而"测一次别打扰对面"正是整件事的前提；
///  - host 不是这台设备正在用的那一台：`Authorization` 头会把长期口令送给链路上那个人。
///    ⚠ 只放行"当前那一台"、不放行"契约声明的两台"：端点记录住在它被创建的那台上，
///    往另一台问一个不存在的人只会得到**假红**，而这一族的红灯承诺过是确凿的；
///  - POST + Bearer 形态（`/p/<id>`，口令不在地址里）：通道行里本来就没存口令 ⇒ 不猜、不试空口令；
///  - 带 query 或 fragment：契约 `transport.secretPlacement` 禁的就是那个形状；
///  - 口令位数不对：那是用户手敲错的地址，拿它去探得到的又是一次**假红**。
///
/// ⚠ 路径形状**只从契约读**（这里不重打 `/api/fnthink/p/…`）：服务器上换前缀时，
///   重打的那一份会变成"看着对、永远 404"的第二条路径。
FnthinkEndpointDryRun? fnthinkEndpointDryRunFor({
  required FnthinkContract contract,
  required String target,
  required String allowedHost,
}) {
  // ⚠ 校验与解析走 [_parseEndpointTarget]（与"发一条消息"那一发**共用同一份**）：
  //   两边各写一份的话，表现会是"干跑说这条通道通、真发一条时报口令不对"。
  final parsed = _parseEndpointTarget(
    contract: contract,
    target: target,
    allowedHost: allowedHost,
  );
  if (parsed == null) return null;
  final probePath = contract.endpointProbePath().replaceAll(
    ':endpointId',
    parsed.endpointId,
  );
  return FnthinkEndpointDryRun(
    probeUrl: Uri(
      scheme: 'https',
      host: parsed.uri.host,
      port: parsed.uri.hasPort ? parsed.uri.port : null,
      path: probePath,
    ),
    secret: parsed.secret,
    endpointId: parsed.endpointId,
  );
}

/// 一条**发给某个端点的消息**（T122）该打哪一条 URL。
///
/// 与 [FnthinkEndpointDryRun] 同一处作者、同一份校验，差别只在"打哪条路径"：
/// 干跑打契约声明的 `endpoint.probe.bearerPath`，消息打**POST + Bearer 形态**的收单路径
/// （`endpoint.ingress.postBearerPath`）—— 口令只进请求头，**不进 URL**。
/// ⚠ 为什么不直接用用户存在通道里的那条"推送地址"（口令在路径段里）：
///   那一条是给第三方脚本抄的形态；本机自己能放请求头时没理由再把口令写进 URL
///   （URL 会被 access log、浏览器历史与中间代理各留一份副本）。
class FnthinkEndpointMessage {
  const FnthinkEndpointMessage({
    required this.messageUrl,
    required this.secret,
    required this.endpointId,
  });

  final Uri messageUrl;

  /// 长期口令。只进请求头（同 [FnthinkEndpointDryRun.secret] 那条规矩）。
  final String secret;

  final String endpointId;
}

/// [fnthinkEndpointMessageFor] 与 [fnthinkEndpointDryRunFor] 共用的那一段解析。
///
/// 返回 null 的每一条理由都与干跑那份逐条相同，见 [fnthinkEndpointDryRunFor] 的文档 ——
/// 两边**必须**用同一份判据：各写一份的话，表现会是"干跑说这条通道通、发消息时报口令不对"。
({Uri uri, String endpointId, String secret})? _parseEndpointTarget({
  required FnthinkContract contract,
  required String target,
  required String allowedHost,
}) {
  final Uri uri;
  try {
    uri = Uri.parse(target);
  } on FormatException {
    return null;
  }
  if (uri.scheme != 'https') return null;
  if (allowedHost.isEmpty || uri.host != allowedHost) return null;
  if (uri.query.isNotEmpty || uri.hasFragment) return null;

  final pattern = _patternSegments(contract.endpointIngressPath('pathPattern'));
  final given = uri.pathSegments;
  if (given.length != pattern.length) return null;
  String? endpointId;
  String? secret;
  for (var i = 0; i < pattern.length; i++) {
    final seg = pattern[i];
    if (!seg.startsWith(':')) {
      if (seg != given[i]) return null;
      continue;
    }
    if (given[i].isEmpty) return null;
    if (seg == ':endpointId') {
      endpointId = given[i];
    } else if (seg == ':secret') {
      secret = given[i];
    }
  }
  if (endpointId == null || secret == null) return null;
  if (secret.length != contract.identityLength('endpointSecret')) return null;
  return (uri: uri, endpointId: endpointId, secret: secret);
}

/// 认 [target] 是一条幻念端点的推送地址（同 [fnthinkEndpointDryRunFor] 的判据），
/// 是就折算出"发一条消息"要打的那一发。null = 这一条不是我们的端点（调用方据此跳过或报错）。
FnthinkEndpointMessage? fnthinkEndpointMessageFor({
  required FnthinkContract contract,
  required String target,
  required String allowedHost,
}) {
  final parsed = _parseEndpointTarget(
    contract: contract,
    target: target,
    allowedHost: allowedHost,
  );
  if (parsed == null) return null;
  final pushPath = contract
      .endpointIngressPath('postBearerPath')
      .replaceAll(':endpointId', parsed.endpointId);
  return FnthinkEndpointMessage(
    messageUrl: Uri(
      scheme: 'https',
      host: parsed.uri.host,
      port: parsed.uri.hasPort ? parsed.uri.port : null,
      path: pushPath,
    ),
    secret: parsed.secret,
    endpointId: parsed.endpointId,
  );
}
