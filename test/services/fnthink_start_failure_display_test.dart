import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/l10n/app_localizations_zh.dart';
import 'package:notice_transmit/services/fnthink_start_failure_display.dart';

/// T180：起不来那一句的三档（日额度 / 分钟档 / 原话）。
void main() {
  final l10n = AppLocalizationsZh();

  test('日额度 ⇒ 说「今日额度用完，明日恢复」，不说倒计时', () {
    final text = fnthinkStartFailureText(
      l10n,
      'register-failed: rate-limited-day:73447',
    );
    expect(text, l10n.fnthinkRegisterDayQuota);
    expect(text, isNot(contains('734')));
  });

  test('分钟档 ⇒ 仍是倒计时（等几分钟再来）', () {
    expect(
      fnthinkStartFailureText(l10n, 'register-failed: rate-limited:2208'),
      l10n.fnthinkRegisterRateLimited(36, 48),
    );
  });

  test('其余失败 ⇒ 原话（机器码是排查入口）', () {
    expect(
      fnthinkStartFailureText(l10n, 'register-failed: rejected-unsigned'),
      'register-failed: rejected-unsigned',
    );
  });
}
