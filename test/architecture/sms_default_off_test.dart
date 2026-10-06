import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// 短信监听这一族**默认必须关**（维护者 2026-10-06 指令：「短信监测默认关闭！首页开关为关！」）。
///
/// 为什么要有这条守卫，而不是改完就算：这个"默认值"一共住在**四处**、跨**两种语言**，
/// 中间没有任何编译器或类型把它们绑在一起 ——
///  ① Dart 字段初值与 `prefs.getBool(...) ?? X`（`SmsService`）
///  ② 首页那一格的默认参数（`NotificationPage.smsMonitorEnabled`）
///  ③ 备份恢复时缺键的回退（`BackupService` 的 `_bool(..., X)`）
///  ④ 原生读的那一份（`ConfigManager.getSmsMonitorEnabled()` 的 `getBoolean(key, X)`）
/// 只改 ① 的话：原生仍会在家没写过 prefs 时按"开"处理，而导入一份缺这个键的备份会把
/// 开关悄悄打开 —— 两种坏法在 Dart 侧的测试里都看不出来。
///
/// 断言打在**契约**上（每一处读到的默认值必须是 false），不是打在某一行上：按标识符定位，
/// 行号漂了不影响；但锚点必须恰好命中一次，命中不到就红着喊"本条读不到东西"，
/// 绝不让"没读到"通过。
void main() {
  final root = projectRoot();

  /// 取出 `path` 里**包含** `needle` 的那一行；断言它恰好出现一次，返回该行文本。
  String lineOf(String path, String needle, {required String why}) {
    final f = File('$root/$path');
    expect(f.existsSync(), isTrue, reason: '读不到 $path ⇒ 本条在空转（$why）');
    final hits = f
        .readAsStringSync()
        .split('\n')
        .where((l) => l.contains(needle))
        .toList();
    expect(
      hits.length,
      1,
      reason:
          '$path 里「$needle」命中 ${hits.length} 次，应为 1 次（$why）'
          ' —— 锚点不唯一时"读到 false"毫无意义，先修锚点。',
    );
    return hits.first.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  group('短信监听默认关｜四处各自的默认值', () {
    test('① Dart 字段初值：总开关与「监听验证码」都是 false', () {
      final a = lineOf(
        'lib/services/sms_service.dart',
        'bool _smsMonitorEnabled =',
        why: '总开关初值',
      );
      final b = lineOf(
        'lib/services/sms_service.dart',
        'bool _codeMonitorEnabled =',
        why: '验证码子开关初值',
      );
      expect(a, contains('= false'), reason: '总开关初值不是关：$a');
      expect(b, contains('= false'), reason: '验证码子开关初值不是关：$b');
    });

    test('① Dart prefs 缺键回退：读不到 ⇒ 关（不是"默认授权"）', () {
      final a = lineOf(
        'lib/services/sms_service.dart',
        "getBool('sms_monitor_enabled')",
        why: '总开关缺键回退',
      );
      final b = lineOf(
        'lib/services/sms_service.dart',
        "getBool('sms_code_monitor_enabled')",
        why: '验证码开关缺键回退',
      );
      expect(a, contains('?? false'), reason: '总开关缺键仍回退到开：$a');
      expect(b, contains('?? false'), reason: '验证码开关缺键仍回退到开：$b');
    });

    test('② 首页那一格的默认参数是关（没读到服务值时不许画成"开"）', () {
      final l = lineOf(
        'lib/pages/notification_page.dart',
        'this.smsMonitorEnabled =',
        why: '首页开关默认参数',
      );
      expect(l, contains('= false'), reason: '首页默认参数是开：$l');
    });

    test('③ 备份恢复缺键回退是关（导入不能把这一族悄悄打开）', () {
      final src = File(
        '${projectRoot()}/lib/services/backup_service.dart',
      ).readAsStringSync();
      final a = lineOf(
        'lib/services/backup_service.dart',
        "'sms_monitor_enabled': _bool(",
        why: '恢复时总开关的回退',
      );
      // 回退值是 `_bool(` 之后的**第二个**实参，可能换行 —— 按调用段读，不按单行。
      final at = src.indexOf("'sms_monitor_enabled': _bool(");
      final seg = src.substring(at, at + 160);
      expect(
        RegExp(
          r"_bool\(\s*sms\['sms_monitor_enabled'\]\s*,\s*false\s*\)",
        ).hasMatch(seg),
        isTrue,
        reason: '恢复时缺键回退不是 false ⇒ 一次导入就能把读短信这一族打开。片段：$a',
      );
      final at2 = src.indexOf("'sms_code_monitor_enabled': _bool(");
      expect(at2, greaterThan(at), reason: '找不到验证码那处恢复回退');
      expect(
        RegExp(
          r"_bool\(\s*sms\['sms_code_monitor_enabled'\]\s*,\s*false\s*,?\s*\)",
        ).hasMatch(src.substring(at2, at2 + 200)),
        isTrue,
        reason: '恢复时验证码缺键回退不是 false',
      );
    });

    test('④ 原生读的那一份默认也是关（跨语言不能只改 Dart）', () {
      final a = lineOf(
        'android/app/src/main/kotlin/com/fnthink/notice/ConfigManager.kt',
        'getBoolean(KEY_SMS_MONITOR_ENABLED,',
        why: '原生总开关默认值',
      );
      final b = lineOf(
        'android/app/src/main/kotlin/com/fnthink/notice/ConfigManager.kt',
        'getBoolean(KEY_SMS_CODE_MONITOR_ENABLED,',
        why: '原生验证码默认值',
      );
      expect(a, contains(', false)'), reason: '原生默认仍是开（只改了 Dart）：$a');
      expect(b, contains(', false)'), reason: '原生验证码默认是开：$b');
    });
  });

  group('短信监听默认关｜两侧说的是同一个键', () {
    // 默认值一致还不够：原生读的是 SharedPreferences 里带 `flutter.` 前缀的那把键，
    // 而前缀与裸键名分属两份源码。这里只钉"裸键名两侧同名"，前缀规则由
    // SharedPreferences 自己保证（已有链路测试覆盖写入侧）。
    test('Dart 写的裸键名与原生常量里的裸键名一致', () {
      final dartLine = lineOf(
        'lib/services/sms_service.dart',
        "getBool('sms_monitor_enabled')",
        why: 'Dart 侧键名',
      );
      final ktLine = lineOf(
        'android/app/src/main/kotlin/com/fnthink/notice/ConfigManager.kt',
        'KEY_SMS_MONITOR_ENABLED =',
        why: '原生侧键名',
      );
      expect(dartLine, contains("'sms_monitor_enabled'"));
      expect(ktLine, contains('"flutter.sms_monitor_enabled"'));
    });
  });
}
