import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// 原生层「面向用户文案」国际化的棘轮守卫（2026-11-22 审计 P0-2）。
///
/// 现状：`I18n.kt` 之外仍有 375 处含 CJK 的字符串字面量（其中大量是日志，
/// 但也有通知栏/Toast/错误提示）。一次性迁移不现实，所以先立**只许变薄**的棘轮：
///  - 总量不得超过基线（新增文案必须进 `I18n.kt`）；
///  - 审计点名的锁屏脱敏提示必须已收进 I18n，且页面不再硬编码中文。
///
/// 计数口径：剥注释后，统计双引号字符串（含三引号）里含 CJK 的**字面量个数**
/// （不是字符数）。`I18n.kt` 是词表本身，不计入。
void main() {
  final root = projectRoot();
  const noticeDir = 'android/app/src/main/kotlin/com/fnthink/notice';

  /// 当前 `I18n.kt` 之外的 CJK 字面量总量（2026-11-22 迁移后基线）。
  /// 口径：剥注释后统计双引号/三引号字符串里含 CJK 的**字面量个数**（不是字符数）。
  /// 410 → 278：面向用户的错误原因、邮件正文、内置应用名、Toast/导出/下载文案
  /// 已收进 `I18n.kt` 的消息目录；剩下的 278 处是日志、日志标签、以及
  /// `NotificationProcessor` 里**必须保持中文**的匹配关键词（如 `contains("微信")`）。
  const baseline = 278;

  Map<String, int> counts() {
    final dir = Directory('$root/$noticeDir');
    expect(dir.existsSync(), isTrue, reason: '原生源码目录不存在 ⇒ 下面的 0 是假绿');
    final stringRe = RegExp(r'"""(?:[\s\S]*?)"""|"(?:\\.|[^"\\])*"');
    final cjkRe = RegExp(r'[\u4e00-\u9fff]');
    final out = <String, int>{};
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.kt')) continue;
      if (f.uri.pathSegments.last == 'I18n.kt') continue;
      final src = stripComments(f.readAsStringSync());
      final n = stringRe
          .allMatches(src)
          .where((m) => cjkRe.hasMatch(m.group(0)!))
          .length;
      if (n > 0) out[f.uri.pathSegments.last] = n;
    }
    return out;
  }

  test('I18n.kt 之外的 CJK 字面量只许变薄', () {
    final got = counts();
    final total = got.values.fold<int>(0, (a, b) => a + b);
    final top =
        (got.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            .take(8)
            .map((e) => '${e.key}=${e.value}')
            .join(', ');
    expect(
      total,
      lessThanOrEqualTo(baseline),
      reason:
          'I18n.kt 之外的 CJK 字面量从 $baseline 涨到 $total。'
          '新增面向用户的文案请收进 I18n.kt；日志类字符串若确需保留，'
          '请在同一次改动里先清掉等量的旧字面量。当前分布（前 8）：$top',
    );
  });

  test('面向用户的高频文案已收进 I18n，不在页面里硬编码', () {
    final i18n = File('$root/$noticeDir/I18n.kt').readAsStringSync();
    expect(
      i18n,
      contains('fun notificationContentMasked('),
      reason: '锁屏脱敏提示的唯一作者应在 I18n.kt',
    );
    final migrated = <String, List<String>>{
      'NotificationProcessor.kt': ['I18n.notificationContentMasked('],
      'EmailSender.kt': [
        'I18n.msg("email.authFailed")',
        'I18n.msg("email.bodyDefault")',
      ],
      'AppNameResolution.kt': ['I18n.msg("app.wechat")'],
      'ChannelRegistry.kt': ['I18n.msgf("err.bizFailCode"'],
      'AppChannelSender.kt': ['I18n.msgf("err.tokenQueued"'],
      'WebhookResponseParser.kt': ['I18n.msgf("err.httpServer"'],
      'MainActivity.kt': ['I18n.msg("export.success")'],
      'NotificationMonitorService.kt': ['I18n.msg("notif.channelName")'],
    };
    for (final entry in migrated.entries) {
      final src = File('$root/$noticeDir/${entry.key}').readAsStringSync();
      for (final needle in entry.value) {
        expect(
          src,
          contains(needle),
          reason: '${entry.key} 又绕开了 I18n（缺少 $needle）—— 英文用户会看到中文',
        );
      }
    }
    final processor = File('$root/$noticeDir/NotificationProcessor.kt')
        .readAsStringSync();
    expect(
      processor,
      isNot(contains('"验证码内容被锁屏隐藏')),
      reason: 'NotificationProcessor 里又出现了硬编码中文提示',
    );
  });
}
