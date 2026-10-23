import '../l10n/app_localizations.dart';
import 'fnthink_receive_coordinator.dart';

/// 「起不来」那一句（T139 ① / T180，**唯一作者**）。
///
/// 三档：
///  - `rate-limited-day` ⇒ 今日额度用完、明日恢复（**不再**把十几小时抄成倒计时）；
///  - `rate-limited:<秒>` ⇒ 分钟档，给分/秒倒计时；
///  - 其余 ⇒ 原话（机器码是排查入口，翻译丢了就没法搜）。
String fnthinkStartFailureText(AppLocalizations l10n, String reason) {
  if (reason.contains('rate-limited-day')) {
    return l10n.fnthinkRegisterDayQuota;
  }
  final wait = fnthinkRegisterRateLimitedWait(reason);
  if (wait == null) return reason;
  return l10n.fnthinkRegisterRateLimited(wait.minutes, wait.seconds);
}
