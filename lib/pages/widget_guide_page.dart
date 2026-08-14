import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';

/// 桌面小部件添加引导页
///
/// Android 桌面小部件由各厂商桌面（Launcher）托管，系统没有统一 API
/// 允许应用代码直接添加到桌面，必须由用户手动添加。
/// 本页提供通用步骤 + 国内外各品牌（小米/华为/荣耀/OPPO/realme/一加/
/// vivo/iQOO/三星/原生及谷歌 Pixel 等）的添加路径指引。
class WidgetGuidePage extends StatelessWidget {
  const WidgetGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(title: Text(l10n.widgetGuide)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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

  Widget _buildSection({
    required String title,
    required String content,
    required BuildContext context,
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
