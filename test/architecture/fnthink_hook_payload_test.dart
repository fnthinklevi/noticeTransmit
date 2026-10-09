import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T112 ②：幻念通道的 webhook 目标发的是 **JSON**，与通用 webhook 同一位载荷作者。
///
/// 缺陷的形状值得记下来：`dispatchFnthinkHook` 原先把 `buildTextBody(...)` 的**纯文本多行正文**
/// 交给 `NetworkClient.sendWithRetry`，而它的 `contentType` 默认就是
/// `application/json; charset=utf-8` ⇒ 服务端 `express.json` 抛 `entity.parse.failed`，
/// 被 bodylimit 按契约回 400 + 空 body `{}`（那一带故意不区分"哪个字段读不出来"），
/// 界面只能说「HTTP 400：{}」。
/// ⚠ 正解不是把 content-type 改成 text/plain：端点只解析 JSON 与 query，那样**一条都进不去**。
void main() {
  final root = projectRoot();

  String read(String rel) =>
      stripComments(File('$root/$rel').readAsStringSync());

  final svc = read(
    'android/app/src/main/kotlin/com/fnthink/notice/NotificationMonitorService.kt',
  );
  final block = blockAfter(svc, 'private fun dispatchFnthinkHook(');

  test('尺没空转：那一支函数体读得到，且读口认得这个文件', () {
    expect(
      block.length,
      greaterThan(200),
      reason: '只切到 ${block.length} 个字符 ⇒ 签名写法变了，下面的断言是摆设',
    );
    expect(
      svc.contains('NetworkClient.sendWithRetry('),
      isTrue,
      reason: '这一支已经不经过统一的发送口 ⇒ 判据要重新找地方，别让它空转',
    );
  });

  test('载荷走 JSON 那位作者（buildPayload + GENERIC）', () {
    expect(
      block,
      contains('WebhookPayloadBuilder.buildPayload('),
      reason: '又回到自己拼正文 ⇒ "探测能过、真发不过"那种两半各造一条的形状会回来',
    );
    expect(
      block,
      contains('WebhookPayloadBuilder.WebhookType.GENERIC'),
      reason: '载荷构造没有跟着 sendWithRetry 那一侧的档位走 ⇒ 两半用的不是同一份规则',
    );
    // 反向：那一种纯文本多行正文正是 400 {} 的来源。
    expect(
      block,
      isNot(contains('buildTextBody')),
      reason: 'buildTextBody 回来的那一刻，服务端又会把这条判成"解析不了的 JSON"',
    );
  });

  test('没有改用 text/plain 蒙过客户端（端点只解析 JSON 与 query）', () {
    expect(
      block,
      isNot(contains('text/plain')),
      reason:
          '把 content-type 改成 text/plain 会让客户端不再撒谎，但端点那侧一条都进不去 —— '
          '这是把"显示 400"换成"永远收不到"，不是修',
    );
  });

  // T120（维护者 2026-10-09 的口径）：那两发 403 的根因是载荷里那枚 `type` —— 它是那条
  // Android 通知自己的分类，不是向我们申请的协议动作。**修法落在服务端**（契约
  // `endpoint.ingress.unknownTypeAs` 把认不出的值折成普通通知），客户端不许为幻念端点这一发
  // 摘掉 `type`：载荷按目标分叉只解决本机这一条，第三方照样踩，而这一面的存在理由就是接第三方。
  test('载荷照旧带 `type`：折价落在服务端，不在客户端为幻念端点特调（T120）', () {
    final builder = read(
      'android/app/src/main/kotlin/com/fnthink/notice/WebhookPayloadBuilder.kt',
    );
    expect(
      builder,
      contains('put("type", notifyType)'),
      reason:
          '通用载荷不再带那条通知自己的 type ⇒ 这一发是"为某个目标改载荷"那种分叉回来了；'
          '端点侧的折价（契约 unknownTypeAs）才是这一条的正解',
    );
    // 反向： dispatch 那一支不许自己动手补/删键 —— 它只负责把那位作者的产物交给发送口。
    expect(
      block,
      isNot(contains('"type"')),
      reason:
          '在 dispatch 里出现 "type" 字面量 ⇒ 就是在按目标特调载荷（把键摘掉或改成 notice），'
          '而服务端那侧的折价会因此永远看不出自己有没有被绕过',
    );
  });
}
