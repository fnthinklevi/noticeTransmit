import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:notice_transmit/services/fnthink_endpoint_guide.dart';

/// T87：接入端点「怎么调用」那一格的形状判定。
///
/// 这一格看着只是文案，但它同时压着三条红线，而每条错了都是静默的：
///  ① **路径只有契约那一份作者** —— 教程里重打一遍 `/api/fnthink/p/…`，服务器换前缀时
///     界面会安静地教一条 404 的路径，用户只会读成"幻念推送坏了"；
///  ② **口令只在本次创建的内存里活着** —— 「一键复制」可用窗口 = 页面上还有明文那一段时间；
///     为了按钮常亮而把它存起来，就是破"这一把只出现一次"（同一条红线，不是两条）；
///  ③ **GET 那一支永远只给形状** —— 口令进路径段 ⇒ 必然进反代 access log，而本站日志脱敏
///     （T89）还没配。所以这一支连"可整行复制"都不给。
void main() {
  FnthinkContract contract([String? mutate]) {
    final raw = File('protocol/fnthink-v1.json').readAsStringSync();
    return FnthinkContract.parse(mutate ?? raw);
  }

  const postPath = '/api/fnthink/p/:endpointId';
  const getPath = '/api/fnthink/p/:endpointId/:secret';

  FnthinkEndpointGuide build({
    String host = 'push.example.com',
    String endpointId = 'ep_2f71c0d4e5a67890',
    String? secret = 'SECRETPASSPHRASE1234',
    FnthinkContract? contractOverride,
  }) => FnthinkEndpointGuide.from(
    host: host,
    endpointId: endpointId,
    secret: secret,
    contract: contractOverride ?? contract(),
  );

  group('路径与别名都只有契约那一份作者', () {
    test('两条 URL 的路径段就是契约里那两条（不重打）', () {
      expect(
        contract().endpointIngressPath('postBearerPath'),
        postPath,
        reason: '契约里那条变了而这里还断旧值 ⇒ 教程教的是一条服务器上不存在的路径',
      );
      expect(
        contract().endpointIngressPath('pathPattern'),
        getPath,
        reason: '同上：GET 那支的路径段是口令的落点，说错一句就多一条进日志的凭证',
      );
      expect(
        build().postUrl,
        'https://push.example.com/api/fnthink/p/ep_2f71c0d4e5a67890',
      );
    });

    test('改契约里的路径 ⇒ 教程跟着变（证明没在页面侧另写一份）', () {
      final moved = contract(
        File('protocol/fnthink-v1.json').readAsStringSync().replaceAll(
          postPath,
          '/api/fnthink/ingress/:endpointId',
        ),
      );
      final guide = build(endpointId: 'ep_1', contractOverride: moved);
      expect(
        guide.postUrl,
        contains('/api/fnthink/ingress/ep_1'),
        reason: '契约换了前缀而教程还在教老路径 ⇒ 用户复制下来只会拿到 404',
      );
      expect(guide.getShape, contains('/api/fnthink/ingress/'));
    });

    test('字段别名照契约那份名单念（顺序不改，嵌一层的形状也在里面）', () {
      final guide = build();
      expect(guide.titleAliases, [
        'title',
        'subject',
        'message',
        'text',
        'msg',
      ]);
      expect(
        guide.bodyAliases,
        const <String>[
          'body',
          'content',
          'description',
          'text.content',
          'content.text',
          'data.content',
        ],
        reason:
            'T99：钉钉/企微的正文在 text.content、飞书 legacy 在 content.text —— '
            '只读顶层就等于把"通用 webhook"这句话只说给自己听',
      );
    });

    test('契约缺那两条路径就抛，不补默认值', () {
      final stripped = contract(
        File(
          'protocol/fnthink-v1.json',
        ).readAsStringSync().replaceAll('"postBearerPath": "$postPath",', ''),
      );
      expect(
        () => build(contractOverride: stripped),
        throwsStateError,
        reason: '补一个"默认路径"等于把"教程说错话"变成静默错 —— 宁可这一格装配不起来',
      );
    });
  });

  group('口令的两条红线', () {
    test('GET 那一支永远只有占位符：明文不进去，可复制命令也不产', () {
      final guide = build();
      expect(guide.getShape, contains('<secret>'));
      expect(
        guide.getShape,
        isNot(contains('SECRETPASSPHRASE1234')),
        reason: 'GET 把口令写进 URL ⇒ 进反代 access log；脱敏（T89）配好之前这一支只给形状',
      );
      expect(
        guide.copyCommand,
        isNot(contains(guide.getShape)),
        reason: '一键复制的那条必须是 POST —— 复制一条带口令的 GET 就是把凭证送进别人的终端历史',
      );
    });

    test('可复制命令只在 id 与口令都在手时存在，且口令只进请求头', () {
      expect(build().canCopyCommand, isTrue);
      expect(
        build(secret: null).canCopyCommand,
        isFalse,
        reason: '没有明文 ⇒ 按钮必须置灰',
      );
      expect(build(secret: '   ').canCopyCommand, isFalse);
      expect(
        build(endpointId: '').canCopyCommand,
        isFalse,
        reason: '只有口令没有 id（用户只是读了一遍列表）也拼不出一条能用的命令',
      );
      final command = build(secret: 'ABCDEF234567').copyCommand!;
      expect(command, startsWith('curl -X POST '));
      expect(command, contains("Authorization: Bearer ABCDEF234567"));
      expect(
        Uri.parse(command.split("'")[1]).path,
        isNot(contains('ABCDEF234567')),
        reason: '口令出现在 URL 路径里就说明写成了 GET 那一支',
      );
    });

    // T99：路径形态的推送地址 —— 给"只有一个 webhook 输入框、发不了请求头"的第三方软件用。
    test('推送地址只在明文在手那一段时间里给，路径段仍是契约那一份作者', () {
      final guide = build(secret: 'ABCDEF234567');
      expect(guide.canCopyPushUrl, isTrue);
      expect(
        guide.pushUrl,
        'https://push.example.com/api/fnthink/p/ep_2f71c0d4e5a67890/ABCDEF234567',
      );
      expect(
        build(secret: null).canCopyPushUrl,
        isFalse,
        reason: '没有明文 ⇒ 按钮必须置灰',
      );
      expect(build(secret: '   ').canCopyPushUrl, isFalse);
      expect(build(endpointId: '').canCopyPushUrl, isFalse);
      // 这条红线没被这次改动挪走：可整行复制的 GET 命令仍然不产，GET 那一支只有占位符。
      expect(guide.getShape, contains('<secret>'));
      expect(
        guide.getShape,
        isNot(contains('ABCDEF234567')),
        reason: '给了路径形态的 POST 入口，不等于顺手给一条会把口令写进终端历史的 GET',
      );
    });

    test('地址为空 ⇒ 两条都交空串，不给半条拼坏的 URL', () {
      final guide = build(host: '');
      expect(guide.postUrl, isEmpty);
      expect(guide.getShape, isEmpty);
      expect(guide.pushUrl, isEmpty);
      expect(guide.canCopyCommand, isFalse);
      expect(guide.canCopyPushUrl, isFalse);
    });
  });
}
