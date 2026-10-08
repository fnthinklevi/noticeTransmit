import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T87 的形状守卫：接入端点那一格的**教程与复制**不许长出第二个作者。
///
/// 钉的全是"错了不报错、只是慢慢说假话"的那几处：路径重打一份、URL 自己拼、
/// 复制按钮为了常亮而把口令存下来。三条各对应一次会在用户那侧静默发生的失真。
void main() {
  final root = projectRoot();
  String read(String rel) =>
      File('$root/$rel').readAsStringSync().replaceAll('\r\n', '\n');

  const guide = 'lib/services/fnthink_endpoint_guide.dart';
  // T97 片B：教程与四枚复制从混合页搬进了这一页 —— 判据跟着主语走，不跟文件名走。
  const page = 'lib/pages/fnthink_endpoint_page.dart';
  const contract = 'packages/fnthink_push/lib/src/contract.dart';

  test('收单路径只有契约那一份作者：教程与页面都不许重打', () {
    for (final rel in [guide, page]) {
      expect(
        stripComments(read(rel)),
        isNot(contains('/api/fnthink/p')),
        reason:
            '$rel 里重打了一遍收单路径 ⇒ 服务器换前缀时教程安静地教一条 404，'
            '而那条 404 看起来完全像"幻念推送坏了"',
      );
    }
    // 契约那两条仍在，且是唯一读点
    final src = stripComments(read(contract));
    expect(src, contains("'endpoint', 'ingress', which"));
    expect(
      RegExp(r"endpointIngressPath\(String which\)").allMatches(src).length,
      1,
      reason: '读径长出第二个 ⇒ "教程与服务器说的不是同一条路径"就没人拦了',
    );
  });

  test('URL 只由 guide 拼一次：页面不许自己连 https://', () {
    expect(
      stripComments(read(page)),
      isNot(contains("'https://")),
      reason:
          '页面里自己拼 URL ⇒ https-only 那条判据就有了第二个作者，'
          '漏一处的下一幕是把口令写进明文网址',
    );
    expect(
      RegExp(r"'https://").allMatches(stripComments(read(guide))).length,
      3,
      reason:
          'guide 里那三枚 = POST 那条、GET 形状那条、T99 加的路径形态推送地址那条。'
          '多一枚就要问是不是又开了一条拼法（少一枚就是那条入口被谁悄悄撤了）',
    );
  });

  test('复制按钮的可用性只读 guide 那两个判据：口令不许为了常亮而持久化', () {
    final src = stripComments(read(page));
    expect(
      src,
      contains('guide.canCopyCommand'),
      reason: '页面自己判"口令在不在手上"= 第二个判据，而第二个判据最容易写成"存一下就好了"',
    );
    expect(
      src,
      contains('guide.canCopyPushUrl'),
      reason:
          'T99 那条路径形态与 Bearer 那条共用同一个门槛：页面若绕过 canCopyPushUrl '
          '自己判空，下一幕就是"列表里读到 id 也把口令拼上去"',
    );
    for (final rel in [guide, page]) {
      final text = stripComments(read(rel));
      expect(
        text,
        isNot(anyOf([contains('SharedPreferences'), contains('setString')])),
        reason:
            '$rel 里出现持久化写入 ⇒ "这一把只出现一次"那条红线破了，'
            '而按钮常亮就是它的动机',
      );
    }
  });

  test('GET 那一支的占位符不许被换成真口令（T89 未配之前）', () {
    final src = stripComments(read(guide));
    final shape = src.substring(
      src.indexOf("final shapePath = contract"),
      src.indexOf('final held = secret'),
    );
    expect(
      shape,
      contains("replaceAll(':secret', '<secret>')"),
      reason:
          '形状那支被换成真口令 ⇒ GET 把凭证写进 URL，也就写进反代的 access log；'
          '本站日志脱敏（T89）还没配，这一步必须留在"只讲形状"',
    );
  });

  test('教程那一格的出现条件只有一处，且它判的是"真用过"', () {
    final src = stripComments(read(page));
    expect(
      RegExp(
        r'if \(_endpointUsed\(created, rotated, listing\)\)',
      ).allMatches(src).length,
      1,
      reason:
          '出现条件被摘掉或挪走 ⇒ 教程再也不出现（或每次都不分状态地出现）—— '
          '两种都比"少一格"糟：前者用户找不到口令怎么用，后者把"还没读"当"没有"',
    );
    final used = src.substring(src.indexOf('bool _endpointUsed('));
    expect(
      used.split('\n  }').first,
      contains('listing?.ok == true'),
      reason: '三态里只有"读到且有"能点亮这一格；`listing == null` 是"还没读"，不是"没有"（判据①）',
    );
  });

  test('T97 片D：那五条说明收进右上问号，且长文一字未删', () {
    final src = stripComments(read(page));
    // ① 新家那枚问号：正文接的是 `_tutorialBody`。
    expect(
      RegExp(r"keyName: 'fnthink-endpoint-help'").allMatches(src).length,
      1,
      reason: '问号要么没有、要么有两个 —— 前者那五段说明等于被删，后者两枚会各讲一套',
    );
    expect(
      src,
      contains('body: _tutorialBody(l10n, guide),'),
      reason: '问号没接正文 ⇒ 点开是空的（或点开还是那几个网址，而说明不知道去哪儿了）',
    );
    // 问号**不在**教程块里：教程块要"真用过"才出现，而那几段说明是静态的 ——
    // 放在块里就会跟着一起消失，用户刚建第一把之前根本读不到怎么用。
    final tutorialBlock = src.substring(
      src.indexOf('List<Widget> _buildEndpointTutorial('),
    );
    expect(
      tutorialBlock.contains('HelpNoteButton('),
      isFalse,
      reason: '问号长进了教程块 ⇒ 它跟着"真用过"一起出现/消失',
    );
    // ② 页面上不许再有那五条（键名一个都不在）。
    for (final gone in const [
      "keyName: 'fnthink-endpoint-post-why'",
      "keyName: 'fnthink-endpoint-get-warning'",
      "keyName: 'fnthink-endpoint-push-url-why'",
      "keyName: 'fnthink-endpoint-fields'",
      "keyName: 'fnthink-endpoint-copy-hint'",
    ]) {
      expect(src, isNot(contains(gone)), reason: '$gone 长回页面 ⇒ 又成段堆小字了');
    }
    // ③ 长文没删：那五段各在页面里出现**恰好一次**（就是弹窗正文那一处）。
    //    ⚠ 这里认的是**键名**而不是措辞：措辞改了守卫照样该绿，键没了才是"说明丢了"。
    for (final key in const [
      'l10n.fnthinkEndpointPostWhy',
      'l10n.fnthinkEndpointGetWarning',
      'l10n.fnthinkEndpointPushUrlWhy',
      'l10n.fnthinkEndpointFieldAlias',
      'l10n.fnthinkEndpointCopyHint',
    ]) {
      expect(
        RegExp(key.replaceAll('.', r'\.')).allMatches(src).length,
        1,
        reason: '$key 不再恰好出现一次 ⇒ 要么被删了，要么又被画回页面上（两处各说一遍）',
      );
    }
  });

  test('教程只有一个作者：lib/pages 下含 `_endpointUsed(` 的文件恰好这一页', () {
    // 上面那三条都是"读一个文件"，因此它们**看不见第二个作者**：谁在别的页里再抄一份
    // 出现条件，那三条各自都还是绿的。T97 片B 把这一格搬成独立页，恰好就是最容易
    // 留下旧抄本的那种改动 ⇒ 这一条按"整个目录只有一份"来断，不按文件名断。
    final hits =
        Directory('$root/lib/pages')
            .listSync(followLinks: false)
            .whereType<File>()
            .map((f) => 'lib/pages/${f.uri.pathSegments.last}')
            .where((rel) => rel.endsWith('_page.dart'))
            .where((rel) => stripComments(read(rel)).contains('_endpointUsed('))
            .toList()
          ..sort();
    expect(
      hits,
      [page],
      reason:
          '出现条件长出第二个作者 ⇒ 两张页对"该不该给教程"各有自己的说法，'
          '而其中一张迟早把"还没读"当成"没有"（$hits）',
    );
  });
}
