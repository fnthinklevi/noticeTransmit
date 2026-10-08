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
    // 段值用的是 `Uri.pathSegments` 交回来的那一份（Dart 已经按 URL 规则解过**一层**码）：
    // 用户从某些界面复制来的地址可能带一层转义，解这一层拿回真口令是对的。这里**不再解第二层** ——
    // 双重解码等于把用户的转义习惯当成口令的一部分，交出去的就是一串猜出来的东西。
    if (given[i].isEmpty) return null;
    if (seg == ':endpointId') {
      endpointId = given[i];
    } else if (seg == ':secret') {
      secret = given[i];
    } // 契约的模式里只有这两段；多出来的占位段由 validate 那两条形状判据拦在外面。
  }
  if (endpointId == null || secret == null) return null;
  if (secret.length != contract.identityLength('endpointSecret')) return null;

  final probePath = contract.endpointProbePath().replaceAll(
    ':endpointId',
    endpointId,
  );
  return FnthinkEndpointDryRun(
    probeUrl: Uri(
      scheme: 'https',
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: probePath,
    ),
    secret: secret,
    endpointId: endpointId,
  );
}
