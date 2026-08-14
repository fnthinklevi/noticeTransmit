import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../services/platform_channel.dart';
import '../theme/app_colors.dart';

/// 桌面小部件添加引导页
///
/// Android 桌面小部件由各厂商桌面（Launcher）托管，系统没有统一 API
/// 允许应用代码直接添加到桌面，必须由用户手动添加。
/// Android 8.0+ 提供 requestPinAppWidget 可从应用内发起添加（系统弹窗确认），
/// 本页顶部提供「一键添加」入口（2×2 / 4×2 两种规格），
/// 下方保留通用步骤 + 国内外各品牌（小米/华为/荣耀/OPPO/realme/一加/
/// vivo/iQOO/三星/原生及谷歌 Pixel 等）的添加路径指引。
class WidgetGuidePage extends StatelessWidget {
  const WidgetGuidePage({super.key});

  Future<void> _requestPinWidget(
    BuildContext context, {
    required bool wide,
  }) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await AppChannels.notification.invokeMethod<bool>(
        'requestPinWidget',
        {'wide': wide},
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            ok == true ? l10n.widgetPinSuccess : l10n.widgetPinUnsupported,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on PlatformException catch (e) {
      debugPrint('requestPinWidget error: ${e.code} ${e.message}');
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.widgetPinLowApi),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(title: Text(l10n.widgetGuide)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 一键添加（推荐）：Android 8.0+ 系统弹窗确认
          _buildSection(
            title: l10n.widgetPinTitle,
            content: l10n.widgetPinDesc,
            context: context,
            trailing: Column(
              children: [
                _buildPinButton(
                  context: context,
                  label: l10n.widgetPinAction,
                  subtitle: l10n.widgetPin2x2,
                  wide: false,
                ),
                const SizedBox(height: 10),
                _buildPinButton(
                  context: context,
                  label: l10n.widgetPinWideAction,
                  subtitle: l10n.widgetPin4x2,
                  wide: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: l10n.widgetGuideDesc,
            content: l10n.widgetGuideIntro,
            context: context,
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: l10n.widgetGuide,
            content: [
              l10n.widgetGuideStep1,
              l10n.widgetGuideStep2,
              l10n.widgetGuideStep3,
            ].join('\n'),
            context: context,
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: l10n.widgetGuideBrand,
            content: [
              l10n.widgetBrandXiaomi,
              l10n.widgetBrandHuawei,
              l10n.widgetBrandOppo,
              l10n.widgetBrandVivo,
              l10n.widgetBrandSamsung,
              l10n.widgetBrandOthers,
            ].join('\n\n'),
            context: context,
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: l10n.widgetTipsTitle,
            content: [
              '• ${l10n.widgetTip1}',
              '• ${l10n.widgetTip2}',
              '• ${l10n.widgetTip3}',
              '• ${l10n.widgetTip4}',
            ].join('\n'),
            context: context,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildPinButton({
    required BuildContext context,
    required String label,
    required String subtitle,
    required bool wide,
  }) {
    return Material(
      color: AppColors.systemBlue(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _requestPinWidget(context, wide: wide),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required String content,
    required BuildContext context,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (trailing != null) ...[trailing, const SizedBox(height: 8)],
          Text(
            content,
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.secondaryLabel(context),
            ),
          ),
        ],
      ),
    );
  }
}
