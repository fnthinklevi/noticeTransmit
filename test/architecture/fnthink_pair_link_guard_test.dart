import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// #176 片4 的形状守卫：点开配对链接那一路不许长出第二个作者、第二个读者、第二种空。
///
/// 这一路的字面量天生就散在三个地方（契约的 `pairing.qrPrefix`、Kotlin 的那把前缀、清单里的
/// scheme+host），而**清单不参与编译、Kotlin 读不到契约 JSON** —— 于是"改一边另一边不报错"
/// 是这条链最省事也最致命的错法。Kotlin 侧由 `FnthinkPairLinkContractTest` 钉三处逐字相同；
/// 这一份钉的是 Dart 侧那几处"错了没人喊"的形状。
void main() {
  final root = projectRoot();
  String read(String rel) =>
      File('$root/$rel').readAsStringSync().replaceAll('\r\n', '\n');

  const reader = 'lib/services/fnthink_pair_link.dart';
  // ⚠ T94：配对链径链的落点是绑定页（链接的主语就是「我和谁有关系」）。
  const page = 'lib/pages/fnthink_peers_page.dart';
  const dialog = 'lib/widgets/fnthink_pair_dialog.dart';
  const actions = 'lib/pages/main_page_actions.dart';
  const mainPage = 'lib/pages/main_page.dart';
  const kotlinLink =
      'android/app/src/main/kotlin/com/fnthink/notice/FnthinkPairLink.kt';
  const contract = 'protocol/fnthink-v1.json';

  test('前缀的作者只有两处：Dart 侧不许出现 fnthink-push 字面量', () {
    for (final rel in [reader, page, dialog, actions, mainPage]) {
      expect(
        stripComments(read(rel)),
        isNot(contains('fnthink-push')),
        reason:
            '$rel 里重打了一遍那把前缀 ⇒ 服务器/协议改前缀时链接还能被点开，'
            '而本机安静地"什么都不发生"（判据只有契约那一份作者）',
      );
    }
    // 契约那一处仍在，且 Kotlin 那一处只认它合成出来的那把。
    final raw = jsonDecode(read(contract)) as Map<String, Object?>;
    final qrPrefix = ((raw['pairing']! as Map)['qrPrefix'])! as String;
    expect(
      stripComments(read(kotlinLink)),
      contains('"$qrPrefix?"'),
      reason: 'Kotlin 认的那把必须逐字等于契约前缀 + `?`（差一个字符就是"点了没反应"）',
    );
  });

  test('那一串只有一个读者、一个出口', () {
    expect(
      RegExp(
        r"'takeFnthinkPairLink'",
      ).allMatches(stripComments(read(reader))).length,
      1,
      reason: '第二个调用点 = 第二个读者；而 take() 取走即清，第二个读者只会拿到 null',
    );
    expect(
      stripComments(read(kotlinLink)),
      contains('fun take(): String?'),
      reason: '原生那本账的出口改名 ⇒ Dart 这一发会拿到 MissingPluginException，被当成"没有链接"',
    );
    expect(
      stripComments(read(reader)),
      isNot(contains('FnthinkPairLinkReader? _shared')),
      reason: 'Dart 侧留一份缓存 = 同一链接弹两次输入层（口令是 singleUse 的）',
    );
  });

  test('首页两个入口都指向同一个方法，且 null 必须早退', () {
    final src = librarySource(root, 'lib/pages/main_page.dart');
    expect(
      RegExp(
        r'_consumeFnthinkPairLink\(\)',
      ).allMatches(stripComments(src)).length,
      3,
      reason:
          '三处 = 定义一次 + 冷启动那一发 + 热恢复那一发。少一处就是某种进入形状没人接：'
          '只接冷启动 ⇒ 第二次点链接没反应；只接热恢复 ⇒ 从聊天里点开永远没反应',
    );
    final block = blockAfter(src, 'Future<void> _consumeFnthinkPairLink()');
    expect(
      block,
      contains('if (outcome == null || !mounted) return;'),
      reason:
          '`take()` 回 null 的意思是"没人点过链接"，而这一发每次打开 App 都会跑 —— '
          '不早退就是"每次启动都被送到幻念推送页"，比原来的"点了没反应"更难解释',
    );
    expect(
      block,
      isNot(contains('_openHistoryPage')),
      reason: '这一路只该打开幻念推送页；串到历史页去就是把两条导航合成了一条',
    );
  });

  test('判不过只说同一句：原因不进界面', () {
    final src = stripComments(read(page));
    expect(
      RegExp(r'\blink\.reason|\boutcome\.reason').hasMatch(src),
      isFalse,
      reason:
          '`pairing.internalReason` 那条纪律说的是"四种失败塌成一句"；界面上能分辨哪种写法能被接受，'
          '对着一份抄来的链接就是枚举器',
    );
    expect(
      src,
      contains(
        'if (!link.accepted || link.request == null || contract == null)',
      ),
      reason: '"判不过 / 没契约 / 没有链接"三件事里前两件都要走到那一句，不能各自分叉出第三种文案',
    );
    for (final arb in ['lib/l10n/arb/app_zh.arb', 'lib/l10n/arb/app_en.arb']) {
      final text =
          (jsonDecode(read(arb))
                  as Map<String, Object?>)['fnthinkPairLinkRejected']!
              as String;
      expect(
        text.contains('{'),
        isFalse,
        reason: '$arb：那句 rejection 文案一旦带上占位符，就是在把内部原因念给用户听',
      );
    }
  });

  test('一次进入只处理一次，预填只进弹层这一层', () {
    final src = stripComments(read(page));
    final consume = blockAfter(src, 'Future<void> _consumePairLink()');
    expect(
      consume.indexOf('_pairLinkHandled = true') <
          consume.indexOf('await _pairWithPeer('),
      isTrue,
      reason: '标记要早于那一次开层：否则重放（rebuild / 依赖变化）会再弹一次，把口令往"再看一眼"推',
    );
    expect(
      RegExp(r'String\w*\s+_pairLink\w*(Code|Target|Prefill)').hasMatch(src),
      isFalse,
      reason: '页面里出现"装着口令/地址码的字段"= 那份一次性的东西开始有副本',
    );
    // 页面只留一个布尔：它说的是"这一条判不过"，不是"原因是什么"。
    expect(src, contains('bool _pairLinkRejected = false;'));
    final sheet = stripComments(read(dialog));
    expect(
      RegExp(
        r'widget\.prefill\?\.(addressCode|pairingCode)',
      ).allMatches(sheet).length,
      2,
      reason: '预填只用于两枚 controller 的初值；第三处就要问是不是页面开始自己填东西',
    );
  });
}
