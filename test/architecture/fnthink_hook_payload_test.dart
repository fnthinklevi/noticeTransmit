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
}
