import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';

/// 首启同意门的正文：欢迎句 + 要点 + 一个**可点**的《隐私政策》链接。
///
/// 为什么链接必须是可点的、而不是把全文塞进弹层：用户在**同意之前**就该能读到
/// 完整政策（全文页零 GetIt、零路由参数，本来就打得开）。只有"请先阅读"这句话
/// 而点不到，等于给了一条没法执行的要求。
///
/// 跳转本身留给调用方 —— 这一层不知道路由长什么样。「点了到底去不去全文页」由
/// `main.dart` 那一侧与源码守卫共同钉住（见
/// `test/architecture/fnthink_privacy_policy_test.dart`）。
class PrivacyGateBody extends StatelessWidget {
  const PrivacyGateBody({super.key, required this.onOpenPolicy});

  /// 点到《隐私政策》那几个字时触发。
  final VoidCallback onOpenPolicy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Text.rich(
      key: const ValueKey('privacy-gate-body'),
      TextSpan(
        style: TextStyle(
          fontSize: 14,
          height: 1.5,
          color: AppColors.secondaryLabel(context),
        ),
        children: [
          TextSpan(text: '${l10n.privacyWelcome}\n\n${l10n.privacyBody}\n\n'),
          TextSpan(text: l10n.privacyGateLinkBefore),
          TextSpan(
            text: l10n.privacyPolicyLink,
            style: const TextStyle(
              color: AppColors.blue,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
            ),
            recognizer: TapGestureRecognizer()..onTap = onOpenPolicy,
          ),
          TextSpan(text: l10n.privacyGateLinkAfter),
        ],
      ),
    );
  }
}
