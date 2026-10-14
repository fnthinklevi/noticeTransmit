import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/services/fnthink_remote_reason_words.dart';

import '../support/source_guards.dart';

/// T144 片2：远程执行「理由」那一格的人话表 —— 双向差集 + 每一词中英都真翻 + 页面必须吃这张表。
///
/// ## 为什么这张表值得双向钉
/// 表少一枚 ⇒ 那一枚在屏上是机器词（**半翻**，比全不翻更坏：用户分不清哪句是系统结论）；
/// 表多一枚 ⇒ 死词占着 ARB（这一族本仓有死词条台账）。两个方向各是一条独立判据，
/// 合在一个计数里就永远看不出少了一枚同时多了一枚（本仓砸过的"合成计数造假绿"）。
///
/// ## 抽源码那一侧的口径：**按造理由的位置**，不按字符串长相
/// 只按长相（"含连字符的小写串"）抽会把契约词、通道 slug、prefs 键全拖进来 ⇒
/// 差集里剩下的全是噪音，而真正漏掉的那一枚被噪音盖住。
void main() {
  final root = projectRoot();

  /// 造理由的文件（现读：判定层 / 状态机 / 两侧执行器 / 词表校验 / 名单裁决）。
  const producers = [
    'services/fnthink_remote_command_handler.dart',
    'services/fnthink_remote_execution.dart',
    'services/fnthink_remote_runner.dart',
    'services/fnthink_remote_executors.dart',
    'services/fnthink_l2_actions.dart',
    'services/fnthink_l3_settings.dart',
    'services/fnthink_grant_items.dart',
    'services/fnthink_sender_grant.dart',
  ];

  /// 包装前缀：`item:` 只是"这一项的问题"这层包装，不是一族（表在 `remoteReasonText` 里剥）。
  const wrappers = {'item'};

  /// `auth:` 三枚子词的出生地是凭据判定，被 `'auth:${auth.reason}'` 拼起来 ⇒
  /// 反向差集对它们走"子词字面量必须在场"这一条。
  final source = [
    for (final rel in producers) stripComments(librarySource(root, 'lib/$rel')),
  ].join('\n');

  Set<String> producedLiterals() => {
    for (final re in [
      // RemoteCommandRejected(command, sender, 'switch-off', source) 与它的多行形状
      RegExp(r"sender,\s*'([a-z][a-z0-9-]*)'"),
      RegExp(r"'([a-z][a-z0-9-]*)',\s*\n\s*source"),
      // 记录/审计侧的具名理由
      RegExp(r"reason:\s*'([a-z][a-z0-9-]*)'"),
      // 执行器与词表校验：FnthinkL2Result.failed('…') / FnthinkL2Rejected('…') / L3Rejected('…')
      RegExp(r"\.failed\(\s*'([a-z][a-z0-9-]*)'"),
      RegExp(r"Rejected\(\s*'([a-z][a-z0-9-]*)'"),
      RegExp(r"return\s+'([a-z][a-z0-9-]*)';"),
    ].expand((re) => re.allMatches(source)))
      re.group(1)!,
  };

  /// 带尾串的那几枚：源码写成 `'<族>:$x'` ⇒ 提出族名。
  Set<String> producedFamilies() => {
    for (final re in [
      RegExp(r"'([a-z][a-z0-9-]*):[$]"),
      RegExp(r"'([a-z][a-z0-9-]*):\$\{"),
    ].expand((re) => re.allMatches(source)))
      re.group(1)!,
  };

  test('① 源码造出的每一枚，表里都有（少一枚就是屏上的机器词）', () {
    // 整串词里 `<族>:<子词>` 那一形状：源码把两侧**分开写**
    // （`'auth:${auth.reason}'` 配 `RemoteExecutionAuthRejected('wrong')`、
    //  `'listener:${enabled ? "start" : "stop"}'` 配 `'listener:start'` 的 case 分支）
    // ⇒ 前缀与子词各自算已知，但只从"表里真有这一枚整串词"推出来，不放开口径。
    final splitShapes = <String>{
      for (final key in remoteReasonExactKeys)
        if (key.contains(':')) ...[
          key.substring(0, key.indexOf(':')),
          key.substring(key.indexOf(':') + 1),
        ],
    };
    final known = remoteReasonExactKeys
        .union(remoteReasonFamilyNames)
        .union(wrappers)
        .union(splitShapes);
    final missing = <String>[
      for (final t in producedLiterals())
        if (!known.contains(t) && !known.contains(t.split(':').first)) t,
      for (final f in producedFamilies())
        if (!known.contains(f)) '$f:<尾串>',
    ]..sort();
    expect(
      missing,
      isEmpty,
      reason:
          '这些理由串会原样落在历史那一格上：$missing ⇒ 屏上人话与机器词混排，'
          '用户分不清哪句是系统的结论（roadmap T144 那句「半翻比不翻更坏」）',
    );
  });

  test('② 表里的每一枚，源码都真造得出来（挡死词与占位的翻译）', () {
    final dead = <String>[
      for (final key in remoteReasonExactKeys)
        if (!source.contains("'$key'") &&
            !(key.contains(':') &&
                source.contains("'${key.substring(0, key.indexOf(':'))}") &&
                source.contains(key.split(':').last)))
          key,
    ]..sort();
    expect(
      dead,
      isEmpty,
      reason:
          '表里有、源码造不出来 ⇒ 这一枚是占位翻译（白占一条 ARB 词条，'
          '还会让后来人以为那条路存在）：$dead',
    );
    for (final family in remoteReasonFamilyNames) {
      expect(
        source.contains("'$family"),
        isTrue,
        reason: '前缀族 $family 在源码里找不到 ⇒ 死族',
      );
    }
  });

  test('③ 每一枚都中英各一份、且英文不是中文的复制', () {
    final zh = lookupAppLocalizations(const Locale('zh'));
    final en = lookupAppLocalizations(const Locale('en'));
    for (final key in remoteReasonExactKeys.union(
      {for (final f in remoteReasonFamilyNames) '$f:tail'}.toSet(),
    )) {
      final a = remoteReasonText(key, zh);
      final b = remoteReasonText(key, en);
      expect(a, isNotEmpty, reason: '$key 中文翻成空串');
      expect(
        RegExp(r'[一-鿿]').hasMatch(a),
        isTrue,
        reason: '$key 的中文没真翻（读出来还是 ASCII 或原串）：$a',
      );
      expect(b, isNot(a), reason: '$key 的英文与中文一模一样 ⇒ 少了一门翻译');
    }
  });

  test('④ 词表外原样回，不替本机编一句原因', () {
    final zh = lookupAppLocalizations(const Locale('zh'));
    expect(remoteReasonText('brand-new-token', zh), 'brand-new-token');
    // `threw:` 只说"抛了异常"，尾巴原样带出（不许挑原因）。
    final t = remoteReasonText('threw:java.net.SocketTimeout', zh);
    expect(t, contains('java.net.SocketTimeout'));
    expect(t, contains('抛了异常'));
    // `item:` 是包装：剥掉之后照走表。
    expect(
      remoteReasonText('item:unknown-setting:monitoring', zh),
      remoteReasonText('unknown-setting:monitoring', zh),
    );
    // 整串判而不是前缀判：`listener:start` 是失败码，不许被翻成"动作名 + 参数"那副说法。
    expect(remoteReasonText('listener:start', zh), isNot(contains('开始监听')));
    // 参数形状那一族：尾巴（动作名／那一段参数）原样带出，不在这格二次翻动作名。
    final arg = remoteReasonText('unexpected-argument:setVibration', zh);
    expect(arg, contains('setVibration'));
    expect(arg, isNot('unexpected-argument:setVibration'));
    // 族名不在表里 ⇒ 整串原样回（兜底话只给 `auth:`，不许拿它盖住一个没人认领的族）。
    expect(
      remoteReasonText('brand-new-family:tail', zh),
      'brand-new-family:tail',
    );
    // `auth:` 那三枚是整串词，第四种模式（将来新加的凭据方式）落兜底、把子词带着。
    final auth = remoteReasonText('auth:some-future-mode', zh);
    expect(auth, contains('some-future-mode'));
    expect(auth, isNot('auth:some-future-mode'));
  });

  test('⑤ 页面必须吃这张表（不许再把 row.reason 直出上屏）', () {
    final page = stripComments(
      librarySource(root, 'lib/pages/remote_history_page.dart'),
    );
    expect(page.contains('remoteReasonText(row.reason, l10n)'), isTrue);
    expect(
      page.contains('remoteHistoryReason(row.reason)'),
      isFalse,
      reason: '页面直出原始 reason ⇒ 这张表被绕开，屏上又会长出机器词',
    );
  });

  test('⑥ 尺认得合成样本（防 ①② 退化成"恒不匹配＝恒绿"）', () {
    const sample =
        "reason: 'made-up-word',\n  .failed('another-one')\n  'level:\$x'";
    expect(
      RegExp(r"reason:\s*'([a-z][a-z0-9-]*)'").hasMatch(sample),
      isTrue,
      reason: '抽取器连"位置"都认不得 ⇒ ① 拦的是不存在的东西',
    );
    expect(RegExp(r"'([a-z][a-z0-9-]*):[$]").hasMatch(sample), isTrue);
    // 表非空是这条尺自己的下限（空表会让 ① 恒绿）。
    // 现值：整串 24 枚 + 前缀族 19 族（含 8 枚参数形状族，守卫 ① 量出来的那批）。
    expect(remoteReasonExactKeys.length, greaterThan(20));
    expect(remoteReasonFamilyNames.length, greaterThan(15));
    expect(FnthinkContract.readFile(), isNotNull);
  });
}
