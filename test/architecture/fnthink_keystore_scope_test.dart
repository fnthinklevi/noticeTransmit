import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T26 第③件：`keystoreBacked` 是**本机事实**，不许悄悄长成一档跨端权限。
///
/// 来历：契约 `protocol/fnthink-v1.json` 的 `identity.identityKey` 段声明了
/// `keystoreBackedScope = "localOnly"`，并在 `keystoreBackedScopeWhy` 里点名
/// **本文件**作为那条声明的守卫。此前这个文件不存在 —— 那份声明等于一张没有背书的收据：
/// 事实今天碰巧成立（服务端确实没读它），但没有任何东西让它**继续**成立。
///
/// 为什么这件事值得一条守卫：`keystoreBacked` 说的是"这台设备的私钥有没有硬件背书"。
/// 一旦服务端能读到它并据此放行，包裹路径（`keystoreBacked=false`，不可导出的其实是
/// **包裹密钥**而不是私钥本体）就能冒充硬件背书路径 —— 那是凭空多出来的准入档位，
/// 而它是靠"对端把自己的布尔值发过来"自证的。契约里写了两条出路都有代价
/// （进已签信封 ⇒ 改所有事件的签名形状、旧客户端全要升级；放顶层不带签 ⇒ **能伪造 true**，
/// 比没有这个字段更坏），所以本守卫钉的是**现状**，不是便利。
///
/// 钉三件事，每件都是不同主语（不是同一件事的两半），外加一条反向自检：
///  ① 服务端源码**读不到**它 —— 契约那句"零命中"的本体。
///  ② 契约确实把 scope 声明成 `localOnly` —— 防"把声明删了就等于没约束"。
///  ③ 它不在已签信封的 canonical key 名单里 —— 堵掉契约里那条 ① 号出路。
///     ⚠ 这一条同时管两端：Dart 侧 `canonical_bytes.dart` 与
///     `packages/fnthink_push/lib/src/contract.dart` 都是**从契约读** `canonicalOrder`
///     的，所以再补一条"Dart 侧也没写死"就是把同一个声明量第二遍。
///  ④ 反向自检：扫描管线**真的扫到了**服务端代码（防路径写错时"零命中"变成空集全绿）。
void main() {
  final root = projectRoot();
  final serverDir = Directory('$root/server');
  if (!serverDir.existsSync()) {
    throw StateError('server/ 不存在（root=$root，cwd=${Directory.current.path}）');
  }

  /// 服务端全部 .js，排除 node_modules（第三方包里的同名标识与本约束无关）。
  List<File> serverJsFiles() {
    return serverDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.js'))
        .where((f) => !f.path.replaceAll('\\', '/').contains('/node_modules/'))
        .toList();
  }

  final files = serverJsFiles();

  /// 命中位置逐个点名到 文件:行 —— 只报"有 N 处"的话，改的人不知道该看哪一行。
  List<String> hitsOf(String token) {
    final hits = <String>[];
    for (final f in files) {
      final stripped = stripComments(f.readAsStringSync()); // 注释里提到 ≠ 代码读了它
      final rel = f.path.replaceAll('\\', '/').substring(root.length + 1);
      final lines = stripped.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains(token)) hits.add('$rel:${i + 1}');
      }
    }
    return hits;
  }

  final contract =
      jsonDecode(File('$root/protocol/fnthink-v1.json').readAsStringSync())
          as Map<String, dynamic>;
  // 这三个键都住在 `identity.identityKey` 那一节（与 Dart 侧 `contract.dart` 里
  // `boolOf(['identity','identityKey','keystoreBackedCapability'])` 同一个节点）。
  final identityKey =
      (contract['identity'] as Map<String, dynamic>)['identityKey']
          as Map<String, dynamic>;
  final canonical =
      ((contract['signature'] as Map<String, dynamic>)['canonicalOrder']
              as List)
          .map((e) => e.toString())
          .toList();

  group('T26 第③件｜keystoreBacked 只在本机，不跨端', () {
    test('① 服务端源码读不到 keystoreBacked', () {
      expect(
        hitsOf('keystoreBacked'),
        isEmpty,
        reason:
            '服务端开始消费 keystoreBacked 了。这不是"加个字段"那么轻 —— '
            '契约 identity.identityKey.keystoreBackedScopeWhy 里那两条出路都要先走完取舍：'
            '① 进已签信封 ⇒ 改所有事件的签名形状、旧客户端全部要升级（与 T26『不抬协议版本』冲突）；'
            '② 放顶层不带签 ⇒ 服务端只能当提交者自述，能伪造 true，比没有这个字段更坏。'
            '决定了就把本守卫改成显式的迁移检查，别让它只做"没读到"的默认拦截。',
      );
    });

    test('② 契约把它声明成本机事实（localOnly）', () {
      expect(
        identityKey['keystoreBackedScope'],
        'localOnly',
        reason:
            '声明被改或被删 ⇒ "本机事实"这条约束就不存在了，'
            '① 号断言会退化成"没人碰过"而非"有人管着"。',
      );
    });

    test('③ 它不在已签信封的 canonical key 名单里', () {
      expect(
        canonical,
        isNot(contains('keystoreBacked')),
        reason:
            '进了 canonicalOrder 就是把它放进签名 —— 出路①，'
            '抬协议版本、旧客户端全要升级，必须与维护者另行定稿，不能顺手加。',
      );
      // ⚠ 名单**本身**（就这 6 个键）不在这里重复钉：它已经由
      //   `packages/fnthink_push/test/contract_test.dart` 与
      //   `server/test/fnthink-contract.test.js` 各钉一遍，同一声明量第三遍只会
      //   在下一次合法演进时多送一条假红。本条只钉"这一个键不许进来"。
    });

    test('④ 反向自检：扫描真的覆盖到服务端代码（防空集假绿）', () {
      expect(files, isNotEmpty, reason: '一个 .js 都没扫到 ⇒ ① 恒真');
      // 拿一个服务端一定有的标识当探针：扫不到它，就说明扫描/剥注释管线本身是坏的。
      expect(
        hitsOf('canonicalOrder'),
        isNotEmpty,
        reason:
            'canonicalOrder 在 server/lib/fnthink/ 里多处使用；'
            '这里取不到 ⇒ ① 的"零命中"是量尺坏了，不是约束成立。',
      );
      // 覆盖面要真的包含**将来最可能消费它的那一层**，否则"零命中"可能只是
      // 扫了一堆不相干的目录。
      final rels = files.map(
        (f) => f.path.replaceAll('\\', '/').substring(root.length + 1),
      );
      expect(
        rels.where((r) => r.startsWith('server/lib/fnthink/')),
        isNotEmpty,
        reason: '没扫到 server/lib/fnthink/ ⇒ 扫描范围写错了，① 的结论不算数。',
      );
    });
  });
}
