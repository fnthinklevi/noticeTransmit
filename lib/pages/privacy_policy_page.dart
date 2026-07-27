import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(title: Text(l10n.privacyPolicyTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection(
            title: l10n.privacyOverviewTitle,
            content: l10n.privacyOverviewContent,
            context: context,
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: l10n.privacyInfoTitle,
            content: l10n.privacyInfoContent,
            context: context,
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: l10n.privacyNoCollectTitle,
            content: l10n.privacyNoCollectContent,
            context: context,
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: l10n.privacyStorageTitle,
            content: l10n.privacyStorageContent,
            context: context,
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: l10n.privacyThirdPartyTitle,
            content: l10n.privacyThirdPartyContent,
            context: context,
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: l10n.privacyPermTitle,
            content: l10n.privacyPermContent,
            context: context,
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: l10n.privacyUpdateTitle,
            content: l10n.privacyUpdateContent,
            context: context,
          ),
          const SizedBox(height: 32),
          Center(
            child: Text(
              l10n.lastUpdate,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.secondaryLabel(context),
              ),
            ),
          ),
          const SizedBox(height: 16),
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
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryLabel(context),
            ),
          ),
          const SizedBox(height: 10),
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
