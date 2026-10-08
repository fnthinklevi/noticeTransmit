import 'dart:convert';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:http/http.dart' as http;

/// 端点档的**干跑**那一发（T106 片①b 格2）：`POST <probeUrl>` + `Authorization: Bearer <口令>`。
///
/// 它与签名面那条 `/probe` 的分工由契约说（`endpoint.probe._why`），这里只管客户端这一发：
///  - **口令只进请求头**：不进 URL、不进 query、不进被签的载荷 —— "出示口令"这件事一旦被允许
///    塞进签名载荷，`mayNotCarry` 那条红线就白写了；
///  - 结论键只有 `clientEvents.probe.readyField` 那一枚作者，两张面共用它（各写一个 `ready`
///    的话，改一边不报错，表现是设备永远读到 null 而判成"探针没结论"）。
///
/// 三态口径与内核那条 `probe` 一致（**"没问到"与"问到了坏消息"必须分得开**）：
///  - `ready: true/false` = 服务端答了。红是确凿的；绿的含义是"这条入口现在收得进一条**默认形状**的通知"；
///  - `ready: null` = 没问到：非 200（429 洪水闸／404 路由没挂／反代把这一发拦了）、200 但正文
///    不是 JSON、读不出布尔。⚠ 非 200 **不当红** —— 在这里它没有"路断了"这一种解释，
///    写成红就是拿假警报挡用户，而假警报教会人的是忽略徽标。
///  - 连不上 / 超时**照旧往上抛**：那条路已经有作者了（`probeFnthinkWithRetries` 的 catch），
///    在这里再包一层就等于同一件事有两种记法。
///
/// [client] 只为测试注入；生产每次自己开一条、用完关掉（一轮最多几条，不值得养连接池）。
Future<FnthinkProbeResult> postFnthinkEndpointDryRun({
  required FnthinkContract contract,
  required Uri probeUrl,
  required String secret,
  http.Client? client,
}) async {
  final owned = client == null;
  final c = client ?? http.Client();
  try {
    final res = await c.post(
      probeUrl,
      headers: {
        'authorization': 'Bearer $secret',
        'accept': 'application/json',
      },
    );
    if (res.statusCode != 200) {
      return FnthinkProbeResult(
        status: FnthinkPollStatus.ok,
        reason: 'endpoint-dryrun-http:${res.statusCode}',
      );
    }
    final Object? body;
    try {
      // 显式按 UTF-8 解：`res.body` 跟着响应头的 charset 走，缺省是 latin-1 ——
      // 这一发今天只回 ASCII，但"以后多带一句中文原因"就会在这里变成乱码（T85(a) 同因）。
      body = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      return const FnthinkProbeResult(
        status: FnthinkPollStatus.ok,
        reason: 'endpoint-dryrun-not-json',
      );
    }
    final ready = body is Map<String, Object?>
        ? body[contract.probeReadyField]
        : null;
    if (ready is! bool) {
      return const FnthinkProbeResult(
        status: FnthinkPollStatus.ok,
        reason: 'endpoint-dryrun-no-verdict',
      );
    }
    return FnthinkProbeResult(status: FnthinkPollStatus.ok, ready: ready);
  } finally {
    if (owned) c.close();
  }
}
