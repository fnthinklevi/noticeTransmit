import 'dart:io';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/models/delivery_status.dart';
import 'package:notice_transmit/services/fnthink_remote_reason_words.dart';

import '../support/source_guards.dart';

/// T144 片2 立的「理由」人话表 —— 双向差集 + 每一词中英都真翻 + 页面必须吃这张表。
///
/// ## 为什么这张表值得双向钉
/// 表少一枚 ⇒ 那一枚在屏上是机器词（**半翻**，比全不翻更坏：用户分不清哪句是系统结论）；
/// 表多一枚 ⇒ 死词占着 ARB（这一族本仓有死词条台账）。两个方向各是一条独立判据，
/// 合在一个计数里就永远看不出少了一枚同时多了一枚（本仓砸过的"合成计数造假绿"）。
///
/// ## 抽源码那一侧的口径：**按造理由的位置**，不按字符串长相
/// 只按长相（"含连字符的小写串"）抽会把契约词、通道 slug、prefs 键全拖进来 ⇒
/// 差集里剩下的全是噪音，而真正漏掉的那一枚被噪音盖住。
///
/// ## T201：抽口扩到真实造码的三处
/// 之前只读 8 个 `lib/services/*`，而发起端那一格的理由还来自
/// `fnthink_remote_out_record.dart`、包侧 `send_kernel.dart`（11 枚状态名 + 几枚
/// `<族>:<细节>` 理由）与原生 `WebhookResponseParser.DeliveryStatus` 的失败码
/// （`BIZ_FAIL` / `HTTP_FAIL` / `NETWORK_FAIL` / `RATE_LIMITED`）。
/// 少扫任何一处，那些码就会以英文裸串的形式落到屏上而本守卫仍然是绿的。
void main() {
  final root = projectRoot();

  /// 造理由的文件（现读：判定层 / 状态机 / 两侧执行器 / 词表校验 / 名单裁决 / 发起端 out 行）。
  const producers = [
    'services/fnthink_remote_command_handler.dart',
    'services/fnthink_remote_execution.dart',
    'services/fnthink_remote_runner.dart',
    'services/fnthink_remote_executors.dart',
    'services/fnthink_l2_actions.dart',
    'services/fnthink_l3_settings.dart',
    'services/fnthink_grant_items.dart',
    'services/fnthink_sender_grant.dart',
    'services/fnthink_remote_out_record.dart',
  ];

  /// 包装前缀：`item:` 只是"这一项的问题"这层包装，不是一族（表在 `remoteReasonText` 里剥）。
  const wrappers = {'item'};

  final dartSource = [
    for (final rel in producers) stripComments(librarySource(root, 'lib/$rel')),
  ].join('\n');
  final sendKernel = stripComments(
    File('$root/packages/fnthink_push/lib/src/send_kernel.dart')
        .readAsStringSync(),
  );
  final nativeParser = File(
    '$root/android/app/src/main/kotlin/com/fnthink/notice/WebhookResponseParser.kt',
  ).readAsStringSync();
  final source = '$dartSource\n$sendKernel';

  /// `auth:` 三枚子词的出生地是凭据判定，被 `'auth:${auth.reason}'` 拼起来 ⇒
  /// 反向差集对它们走"子词字面量必须在场"这一条。
  Set<String> producedLiterals() => {
    for (final re in [
      // RemoteCommandRejected(command, sender, 'switch-off', source) 与它的多行形状
      RegExp(r"sender,\s*'([a-z][a-z0-9-]*)'"),
      RegExp(r"'([a-z][a-z0-9-]*)',\s*\n\s*source"),
      // 记录/审计侧的具名理由
      RegExp(r"reason:\s*'([a-z][a-z0-9-]*)'"),
      // T201：发送内核 `_lastReason = 'ts-expired-needs-calibration'` 这一类
      RegExp(r"_lastReason\s*=\s*'([a-z][a-z0-9-]*)'"),
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

  /// T201：包侧 `enum FnthinkSendStatus` 的 11 枚名字（发送页在 reason 缺失时直接用它）。
  Set<String> producedSendStatuses() {
    final start = sendKernel.indexOf('enum FnthinkSendStatus {');
    expect(start, greaterThanOrEqualTo(0), reason: '包侧状态枚举被改名或删掉了？');
    final end = sendKernel.indexOf('}', start);
    final body = sendKernel.substring(start, end);
    return {
      for (final m in RegExp(
        r'^\s{2}([a-zA-Z][a-zA-Z0-9]*),',
        multiLine: true,
      ).allMatches(body))
        m.group(1)!,
    };
  }

  /// T201：原生通道的失败码（`DeliveryStatus` 里以 `_FAIL` 结尾或 `RATE_LIMITED`）。
  Set<String> producedNativeCodes() {
    final start = nativeParser.indexOf('enum class DeliveryStatus');
    expect(
      start,
      greaterThanOrEqualTo(0),
      reason: '原生 DeliveryStatus 枚举被改名或删掉了？',
    );
    final end = nativeParser.indexOf('}', start);
    final body = nativeParser.substring(start, end);
    return {
      for (final m in RegExp(
        r'^\s*([A-Z][A-Z0-9_]*)',
        multiLine: true,
      ).allMatches(body))
        m.group(1)!,
    }.where((n) => n.endsWith('_FAIL') || n == 'RATE_LIMITED').toSet();
  }

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
      for (final s in producedSendStatuses())
        if (!known.contains(s)) s,
      for (final n in producedNativeCodes())
        if (!known.contains(n)) n,
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
    // T200：`no-receipt` 与送达清扫**共用同一枚常量**（一处作者），所以源码里不写
    // 那个字面量、写的是常量名。判据不放松：要么字面量在场，要么这枚共享常量在场。
    final constProduced = <String, String>{
      deliveryNoReceiptReason: 'deliveryNoReceiptReason',
    };
    final produced = producedLiterals()
        .union(producedSendStatuses())
        .union(producedNativeCodes());
    final dead = <String>[
      for (final key in remoteReasonExactKeys)
        if (!produced.contains(key) &&
            !source.contains("'$key'") &&
            !source.contains(constProduced[key] ?? '\u0000') &&
            // `<族>:<子词>` 由源码两侧分开拼（`'auth:${auth.reason}'` + `Rejected('wrong')`）
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

  test('④ 词表外承认「没写过」，原文照带，不替本机编一句原因', () {
    final zh = lookupAppLocalizations(const Locale('zh'));
    // T201 ③：这一档从「原样返回裸码」改成「这条我们还没写过说明（原文：…）」。
    final unknown = remoteReasonText('brand-new-token', zh);
    expect(unknown, isNot('brand-new-token'));
    expect(unknown, contains('还没写过说明'));
    expect(unknown, contains('brand-new-token'));
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
    // 族名不在表里 ⇒ 承认没写过（原文照带）。
    final unknownFamily = remoteReasonText('brand-new-family:tail', zh);
    expect(unknownFamily, contains('还没写过说明'));
    expect(unknownFamily, contains('brand-new-family:tail'));
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
    // 现值：整串 43 枚 + 前缀族 24 族。
    expect(remoteReasonExactKeys.length, greaterThan(20));
    expect(remoteReasonFamilyNames.length, greaterThan(15));
    expect(FnthinkContract.readFile(), isNotNull);
  });

  test('⑦ 共享常量那一枚也真翻成人话（它不经字面量，边界靠这一条）', () {
    final zh = lookupAppLocalizations(const Locale('zh'));
    // T200：源码写的是 `deliveryNoReceiptReason` 而不是 `'no-receipt'` 字面量 ⇒
    // ① 抽不到它、② 也看不见它。缺表时屏上会原样出现机器词，只有这一条会红。
    final text = remoteReasonText(deliveryNoReceiptReason, zh);
    expect(text, isNot(deliveryNoReceiptReason));
    expect(text, contains('没拿到回执'));
  });

  test('⑧ T201：报错说明弹层的正文从同一张表生成（不是第二份抄本）', () {
    final zh = lookupAppLocalizations(const Locale('zh'));
    final body = remoteReasonHelpBody(zh);
    for (final key in ['rejectedCapability', 'badInput', 'BIZ_FAIL']) {
      expect(body, contains(key), reason: '说明里少了 $key ⇒ 用户点了问号也查不到这一条');
    }
    expect(body, contains(remoteReasonText('rejectedCapability', zh)));
    expect(body, contains('还没写过说明'));
  });

  test('⑨ T201：那句「这一屏有几条没写过」只在真有条数时出现', () {
    final zh = lookupAppLocalizations(const Locale('zh'));
    final plain = remoteReasonHelpBody(zh);
    final withMiss = remoteReasonHelpBody(zh, missCount: 2);
    // 0 = 一句不加：这一屏没有缺口却宣称有，就是一句不实陈述。
    expect(plain, isNot(contains(zh.remoteReasonMissSeen(0))));
    expect(
      withMiss,
      contains(zh.remoteReasonMissSeen(2)),
      reason: '条数没进正文 ⇒ 漏词条在屏上又变得看不见了（T201 ③ 要的正是要看得见）',
    );
    // 只**追加**一句：不许因为多一个数字就把那张表重排或改写。
    expect(withMiss, '$plain\n${zh.remoteReasonMissSeen(2)}');
  });

  test('⑩ T201：「认不认得」与「翻不翻得出」是同一张三档表（不许长第二个判据）', () {
    final zh = lookupAppLocalizations(const Locale('zh'));
    // 诊断读数走 `remoteReasonIsKnown`、界面那句走 `remoteReasonText`。两处各写一份口径
    // 的后果是"屏上说了没写过、读数却记成认识"（或反过来）—— 数字与话对不上时没人能信其中一个。
    for (final key in remoteReasonExactKeys) {
      expect(
        remoteReasonIsKnown(key),
        isTrue,
        reason: '$key 在整串表里却被判成不认识 ⇒ 两处口径已分叉',
      );
      expect(
        remoteReasonText(key, zh),
        isNot(zh.remoteReasonUnknownCode(key)),
        reason: '$key 在表里却被翻成「还没写过说明」',
      );
    }
    for (final family in remoteReasonFamilyNames) {
      final code = '$family:tail';
      expect(remoteReasonIsKnown(code), isTrue, reason: '$code 是被声明的前缀族');
      expect(
        remoteReasonText(code, zh),
        isNot(zh.remoteReasonUnknownCode(code)),
      );
    }
    // `auth:` 那一族在 `remoteReasonText` 里是**特例**（不在 `_families` 里，直接走
    // `remoteReasonUnknown`）—— 认不认得那一侧必须同样认它，否则同一枚码一边有解释一边进读数。
    expect(remoteReasonIsKnown('auth:any-fresh-detail'), isTrue);
    expect(
      remoteReasonText('auth:any-fresh-detail', zh),
      isNot(zh.remoteReasonUnknownCode('auth:any-fresh-detail')),
    );
    // 词表外：两边都要说"没写过"，且 `item:` 那层包装两边都得先剥。
    expect(remoteReasonIsKnown('brand-new-token'), isFalse);
    expect(
      remoteReasonText('brand-new-token', zh),
      zh.remoteReasonUnknownCode('brand-new-token'),
    );
    expect(remoteReasonIsKnown('item:switch-off'), isTrue);
    expect(remoteReasonIsKnown('item:brand-new-token'), isFalse);
    // 空串不算"认识"，也不算"没写过"：reason 为空的那一行在界面上根本不画。
    expect(remoteReasonIsKnown(''), isFalse);
  });
}
