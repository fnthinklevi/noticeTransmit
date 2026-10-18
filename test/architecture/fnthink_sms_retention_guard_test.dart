import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// T124 ① 守卫：「已监听的短信留存」被搜这一路的五个"不许再长第二份/不许说谎"。
///
/// ① 键名只住 `fnthink_read_settings.dart`（页面与执行各写一份＝界面开着、执行判成关着）；
/// ② 那一枚的缺省必须是**关**（回退到开＝"没表过态就算同意"）；
/// ③ 界面上必须有那一行，且读的就是那两个函数（没有入口的开关等于骗人说有）；
/// ④ 跨端三件（`type` 的取值、一次带几条、LIKE 的三字符表）两侧必须同源；
/// ⑤ 那一格**只在开关开时才被查**，且披露文案（zh/en 两处）与 `lastUpdate` 必须同片在场。
String read(String path) => File(path).readAsStringSync();

String strip(String code) => code
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

/// 取某个顶层函数/方法从签名到配对右花括号的体（不写行号，钉结构不钉写法）。
String bodyOf(String source, String signature) {
  final start = source.indexOf(signature);
  if (start < 0) return '';
  final open = source.indexOf('{', start);
  if (open < 0) return '';
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') {
      depth++;
    } else if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(open, i + 1);
    }
  }
  return '';
}

/// 取签名之后 n 行（**表达式体的函数没有花括号**，按花括号配对会一路滑到下一个函数，
/// 那种尺子对着半截签名恒真 —— 见 ⑨ 那条坑）。
String windowAfter(String source, String signature, {int lines = 8}) {
  final start = source.indexOf(signature);
  if (start < 0) return '';
  final rest = source.substring(start).split('\n');
  return rest.take(lines).join('\n');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const key = 'fnthink.read.sms_retention';
  final settings = strip(read('lib/services/fnthink_read_settings.dart'));
  final page = strip(read('lib/pages/fnthink_read_caps_page.dart'));
  final locator = strip(read('lib/di/service_locator.dart'));
  final retention = strip(read('lib/services/fnthink_sms_retention.dart'));
  final kotlinSearch = read(
    'android/app/src/main/kotlin/com/fnthink/notice/SmsSearch.kt',
  );
  final kotlinDispatch = read(
    'android/app/src/main/kotlin/com/fnthink/notice/SmsDispatcher.kt',
  );

  test('① 键名只住一处', () {
    final hits = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (strip(entity.readAsStringSync()).contains("'$key'")) {
        hits.add(entity.path.replaceAll(r'\', '/'));
      }
    }
    expect(hits, [
      'lib/services/fnthink_read_settings.dart',
    ], reason: '$key 出现在 $hits —— 两处各写一份的表现是"界面上开着、执行时读到另一个键"');
    expect(settings.contains("'$key'"), isTrue, reason: '锚点：键根本不在单点里＝本守卫空转');
  });

  test('② 那一枚的缺省是关（读不到就按关处理）', () {
    final body = bodyOf(
      settings,
      'Future<bool> fnthinkReadSmsRetentionEnabled()',
    );
    expect(body, isNotEmpty, reason: '锚点：函数没取到＝本守卫空转');
    expect(body, contains('?? false'), reason: '回退到开等于"没表过态就算同意过"（与另四枚同一条纪律）');
  });

  test('③ 界面上那一行必须存在，且读的就是那两个函数', () {
    final rowStart = page.indexOf("id: 'sms_retention'");
    expect(rowStart, greaterThan(-1), reason: '没有入口的开关等于骗人说有');
    final row = page.substring(rowStart, page.indexOf('),', rowStart));
    expect(row, contains('fnthinkReadSmsRetentionEnabled'));
    expect(row, contains('setFnthinkReadSmsRetentionEnabled'));
    expect(
      row,
      isNot(contains('PermissionService')),
      reason: '这一枚不申请任何系统权限 —— 搜的是本机库里那一格',
    );
  });

  test('④ 跨端同源：type 的取值 / 一次带几条 / LIKE 三字符表', () {
    final dartType = RegExp(
      r"const String kFnthinkSmsRetentionType = '([^']+)'",
    ).firstMatch(read('lib/services/fnthink_sms_retention.dart'));
    expect(dartType, isNotNull);
    expect(
      kotlinDispatch,
      contains('put("type", "${dartType!.group(1)}")'),
      reason: '留存那一路按 type 那一列筛；原生改了这个取值而 Dart 没跟上，筛出来就是空表',
    );

    final dartLimit = RegExp(
      r'const int kFnthinkSmsSearchTotalLimit = (\d+)',
    ).firstMatch(retention);
    final nativeLimit = RegExp(
      r'const val LIMIT = (\d+)',
    ).firstMatch(kotlinSearch);
    expect(dartLimit, isNotNull);
    expect(nativeLimit, isNotNull, reason: '锚点：Kotlin 那个上限没取到＝本守卫空转');
    expect(
      dartLimit!.group(1),
      nativeLimit!.group(1),
      reason: '一次搜索最多带几条，不因来源不同而变',
    );

    final nativeEscape = windowAfter(
      kotlinSearch,
      'fun escapeLike(keyword: String)',
    );
    expect(nativeEscape, isNotEmpty, reason: '锚点：Kotlin 那个转义没取到＝本守卫空转');
    final dartEscape = windowAfter(retention, 'String escapeFnthinkSmsLike(');
    expect(dartEscape, isNotEmpty, reason: '锚点：Dart 那个转义没取到＝本守卫空转');
    // 只看三字符的**次序**（写法两侧本来不同：Kotlin 用 replace + 双反斜杠，
    // Dart 用 raw 字符串 —— 钉字面抄本会假红，钉次序才钉到真正会咬人的那一条）。
    String wilds(String s) => s.replaceAll(RegExp(r'[^%_\\]'), '');
    for (final pair in [
      ('Kotlin', wilds(nativeEscape)),
      ('Dart', wilds(dartEscape)),
    ]) {
      final w = pair.$2;
      for (final i in [w.indexOf(r'\'), w.indexOf('%'), w.indexOf('_')]) {
        expect(i, isNonNegative, reason: '${pair.$1} 那份转义表里三字符不齐（缺一个就是静默多带）');
      }
      expect(
        w.indexOf('%'),
        greaterThan(w.indexOf(r'\')),
        reason: '${pair.$1} 那份必须先转反斜杠本身，否则 \\% 会变成 \\\\%',
      );
      expect(
        w.indexOf('_'),
        greaterThan(w.indexOf('%')),
        reason: '${pair.$1} 那份的三字符次序漂了',
      );
    }
  });

  test('⑤ 关掉那一枚 ⇒ 连留存那一格都不查', () {
    final body = windowAfter(
      locator,
      'Future<({String? payload, String? reason})> _fnthinkSearchSmsOnce(',
      lines: 46,
    );
    expect(body, isNotEmpty, reason: '锚点：那一发没取到＝本守卫空转');
    expect(
      body.indexOf('fnthinkReadSmsRetentionEnabled()'),
      greaterThan(-1),
      reason: '那一发里根本没读这枚开关＝开关是摆设',
    );
    expect(
      body.indexOf('fnthinkReadSmsRetentionEnabled()'),
      lessThan(body.indexOf('searchSmsRetention')),
      reason: '读开关必须早于查留存 —— 反过来的话默认关就只是个摆设',
    );
  });

  test('⑥ 披露文案两侧都在，且那条重复的通讯录说明已收成一条', () {
    const stamp = {
      'lib/l10n/arb/app_zh.arb': '最后更新：2026年10月18日',
      'lib/l10n/arb/app_en.arb': 'Last updated: October 18, 2026',
    };
    const marker = {
      'lib/l10n/arb/app_zh.arb': '本机短信留存',
      'lib/l10n/arb/app_en.arb': 'SMS retained on this device',
    };
    for (final p in stamp.keys) {
      final raw = read(p);
      // 只看权限清单那一条的值（页面标题与它同形，全文件数会自己数出自己两遍）。
      final permLine = raw
          .split('\n')
          .firstWhere((l) => l.startsWith('  "privacyPermContent": "'));
      expect(
        RegExp(marker[p]!).allMatches(permLine).length,
        1,
        reason: '$p 的权限清单里这一句必须恰好一条（两份＝其中一份是旧的）',
      );
      final infoLine = raw
          .split('\n')
          .firstWhere((l) => l.startsWith('  "privacyInfoContent": "'));
      expect(
        infoLine.contains('已监听的留存') ||
            infoLine.contains('the retention this device already holds'),
        isTrue,
        reason: '$p 的"远程读取"那一处必须说到这一路（只写在权限清单里，读者对不上号）',
      );
      expect(
        raw,
        contains(stamp[p]),
        reason: '披露正文改了而 lastUpdate 没抬＝这份政策说自己没变过',
      );
    }
    final zh = read('lib/l10n/arb/app_zh.arb');
    expect(
      RegExp(r'• 通讯录（READ_CONTACTS）').allMatches(zh).length,
      1,
      reason: 'C-4 那轮补丁没幂等留下的重复行 —— 清单里同一权限出现两遍，读者会以为有两个不同的授权',
    );
  });

  test('⑦ zh 有新键的地方 en 也必须有一个（同一条纪律）', () {
    final zh = read('lib/l10n/arb/app_zh.arb');
    final en = read('lib/l10n/arb/app_en.arb');
    for (final k in [
      'fnthinkReadSmsRetentionTitle',
      'fnthinkReadSmsRetentionSubtitle',
      'fnthinkReadSmsRetentionDenied',
    ]) {
      expect(zh.contains('"$k"'), isTrue, reason: 'zh 缺 $k');
      expect(en.contains('"$k"'), isTrue, reason: 'en 缺 $k —— 切到英文就露馅');
    }
  });
}
