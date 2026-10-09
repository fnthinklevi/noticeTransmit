import 'dart:convert';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:http/http.dart' as http;

/// 往一条**幻念端点**发一条消息（T122）：`POST <postBearerPath 形态>` + `Authorization: Bearer <口令>`，
/// 正文 `{"title": …, "body": …}`。
///
/// 与两条邻路的分工：端点页那条**干跑**一个字段都不读、一条都不投；签名面那条 `sendNotice`
/// （设备→设备）走 Ed25519 与能力裁决；这一条走的是**长期口令**那条面（T39/T41），端点只能产 L1
/// —— `type` 一带都不带（T120 的折价正是为这种载荷准备的）。
///
/// 结论词表与 `fnthinkSendResultText` 那套对齐（**不新造档位**）：202⇒accepted（读不出 messageId
/// 就是 unparseable，不猜）；400⇒badInput；403⇒rejectedCapability；429⇒rateLimited（带 Retry-After）；
/// 其余码（401 口令不对／404 路由没挂／405 只收 POST）⇒ preconditionFailed + `endpoint-http:<码>`
/// —— **不折成"发送失败"**：那三种的下一步动作不一样；连不上／超时 ⇒ transportError。
Future<FnthinkSendResult> postFnthinkEndpointMessage({
  required Uri messageUrl,
  required String secret,
  required String title,
  required String body,
  http.Client? client,
}) async {
  final owned = client == null;
  final c = client ?? http.Client();
  try {
    final res = await c.post(
      messageUrl,
      headers: {
        'authorization': 'Bearer $secret',
        'content-type': 'application/json; charset=utf-8',
        'accept': 'application/json',
      },
      body: jsonEncode({'title': title, 'body': body}),
    );
    final code = res.statusCode;
    if (code == 202) {
      final Object? decoded;
      try {
        decoded = jsonDecode(utf8.decode(res.bodyBytes));
      } on FormatException {
        return const FnthinkSendResult(status: FnthinkSendStatus.unparseable);
      }
      final id = decoded is Map<String, Object?> ? decoded['messageId'] : null;
      if (id is! String || id.isEmpty) {
        // 没有 id 的"收下"不算收下（与发送内核同一条）。
        return const FnthinkSendResult(status: FnthinkSendStatus.unparseable);
      }
      return FnthinkSendResult(
        status: FnthinkSendStatus.accepted,
        messageId: id,
        action: decoded is Map<String, Object?> ? '${decoded['action']}' : null,
      );
    }
    if (code == 400) {
      return const FnthinkSendResult(status: FnthinkSendStatus.badInput);
    }
    if (code == 403) {
      return FnthinkSendResult(
        status: FnthinkSendStatus.rejectedCapability,
        receipt: _receiptOf(res),
      );
    }
    if (code == 429) {
      return FnthinkSendResult(
        status: FnthinkSendStatus.rateLimited,
        retryAfterSeconds: int.tryParse(res.headers['retry-after'] ?? ''),
      );
    }
    return FnthinkSendResult(
      status: FnthinkSendStatus.preconditionFailed,
      reason: 'endpoint-http:$code',
    );
  } catch (_) {
    return const FnthinkSendResult(status: FnthinkSendStatus.transportError);
  } finally {
    if (owned) c.close();
  }
}

/// 403 那枚回执词（读不出来就不带 —— 不编一个）。
String? _receiptOf(http.Response res) {
  try {
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final receipt = decoded is Map<String, Object?> ? decoded['receipt'] : null;
    return receipt is String && receipt.isNotEmpty ? receipt : null;
  } on FormatException {
    return null;
  }
}
