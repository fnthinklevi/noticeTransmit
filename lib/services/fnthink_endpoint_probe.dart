import 'dart:async';

import 'dart:convert';

import 'package:http/http.dart' as http;

/// T76 ⓑ：按**实测往返时延**在契约声明的那两台里就近选（维护者 2026-10-05 拍板走方案①）。
///
/// 三条不采用别的判据的理由都在 T76 §6，这里只留它们各自踩坏过什么：
///  - **禁 ping 域名**：CDN 之后 ICMP 只到边缘节点，测出来的不是源站距离，
///    而我们要的是"这台设备到这两个入口各有多快"。所以这里走一次真的 HTTPS GET。
///  - **不用 GeoIP**：客户端判不出"中国大陆"——港澳台、海外华人、出差一律选错，
///    等于把地域当身份。
///  - **不用 `/health` 回一个 `edgeRegion` 键**：那要新增契约键，而两台服务端得同时上
///    同一版才答得出；`.com` 还没部署好 ⇒ 长期"只有半边答得出"。
///    本仓的规矩是**新增键必须本片就有读者**，而这个读者会半哑。
///
/// 探的是 `/health` 而不是业务端点：它是整台风服务的心跳（T75 落的），且在
/// `IP_BLOCK_EXEMPT_PREFIXES` 里 —— NAT 出口被误封时它不该跟着一起倒。
///
/// ⚠ **"答了"就算可达，不看状态码**：403/404 同样证明服务器在、答了，
/// 而把非 2xx 当不可达会让"服务在但这一档被拒"被读成"这一台不通"。
typedef EndpointLatencyProbe =
    Future<Map<String, Duration>> Function(List<String> hosts);

/// 给 [hosts] 各测一次往返时延。**测不到的（超时/连接失败/DNS 失败）不进表**。
///
/// [timeout] 是单台的预算，不是总和：两台并发发，总预算仍是一份 [timeout]。
Future<Map<String, Duration>> measureEndpointLatency(
  List<String> hosts, {
  http.Client? client,
  Duration timeout = const Duration(seconds: 3),
  void Function(String host, Map<String, Object?> body)? onHealthBody,
}) async {
  final owned = client == null;
  final c = client ?? http.Client();
  try {
    final results = await Future.wait(
      hosts.map((host) async {
        final sw = Stopwatch()..start();
        try {
          final response = await c
              .get(Uri.https(host, '/health'))
              .timeout(timeout);
          sw.stop();
          // T155：`/health` 的正文里带着「客户端契约版本」那一格（见 [readClientContractVerdict]）。
          // ⚠ **解析失败不许影响"可达"那个主判据**：反代给 HTML 错误页时正文读不出来，
          //   而服务器是在、答了的 —— 让它把一次可达探成不可达，比不报更坏。
          if (onHealthBody != null) {
            try {
              final decoded = jsonDecode(
                utf8.decode(response.bodyBytes, allowMalformed: false),
              );
              if (decoded is Map<String, Object?>) onHealthBody(host, decoded);
            } catch (_) {
              // 读不出正文 = 这一格没有读数，不是"读出来是不一致"。
            }
          }
          return MapEntry(host, sw.elapsed);
        } catch (_) {
          // 超时 / 连接被拒 / DNS 不对：一律读成"这台测不到"，不进表。
          // ⚠ 这里**不区分**"连不上"与"连上了但没在预算内答完" ——
          //   对"就近选"这个用途来说，两者的处置完全一样（不参与竞选）。
          return MapEntry(host, const Duration(days: 1));
        }
      }),
    );
    return {
      for (final e in results)
        if (e.value < const Duration(days: 1)) e.key: e.value,
    };
  } finally {
    if (owned) c.close();
  }
}

/// T155：从 `/health` 的正文里取**客户端契约版本那一格**的结论。
///
/// ⚠ 三档原样带回，**不折成布尔**：`null`（还没收到过带版本的请求）／
///   `'mismatch'`（有一台带着旧版来过）／`'unreadable'`（带了但不是可比的形状）。
///   折成布尔就与「还没见过」同形 —— 而这三件事用户该看到的说法完全不同
///   （第 8.194 版那条「没读到／还没看／真的没有要分开」的同一族）。
/// ⚠ 正文不是 JSON（反代给了 HTML 错误页）时回 `null`，**不抛**：
///   这一格是"顺便看一眼"，不该把"服务器可达"那个主判据带崩。
///
/// [healthKey] 是**必填**的，而且**故意不给默认值** ——
/// 第一版给了一个可选参数，默认走 `FnthinkContract.readFile()`，被
/// `fnthink_contract_loader_test.dart`「lib/ 里除了这个文件没人自己读契约」当场喊红。
/// 那条守卫是对的：`readFile` 按"从 cwd 逐级向上找仓库根"定位，**设备沙箱里没有仓库根** ⇒
/// 真机上那一格会抛，而不是回个值。
/// 所以键名由**手上已经握着契约的那个调用方**交进来（本仓是页面从 `_settings.contract` 拿）——
/// 这同时把依赖变成显式的：探针不需要知道契约从哪来，也不该自己找一份。
Object? readClientContractVerdict(Map<String, Object?> body, String healthKey) {
  if (healthKey.isEmpty) return null;
  final value = body[healthKey];
  if (value == null) return null;
  if (value is String) return value;
  // 服务端回的是字符串；回成别的类型 ⇒ 形状变了，如实带回去（界面会说"读不出来"）。
  return 'unreadable';
}

/// 就近选：**纯函数**，只认"测到的那些里最快的那个"。
///
/// [preferredOrder] 决定**并列时**归谁（契约声明顺序：international 在前）。
/// 为什么要它：两台都测不到、或两边一模一样快时，结果必须是**确定的** ——
/// 否则同一台设备两次冷启动可能连到不同的服务器，而用户什么都没按。
String? nearestHost(
  Map<String, Duration> latencies, {
  required List<String> preferredOrder,
}) {
  if (latencies.isEmpty) return null;
  String? best;
  var bestMs = 1 << 62;
  for (final host in preferredOrder) {
    final d = latencies[host];
    if (d == null) continue;
    if (d.inMilliseconds < bestMs) {
      best = host;
      bestMs = d.inMilliseconds;
    }
  }
  return best ?? latencies.keys.first;
}
