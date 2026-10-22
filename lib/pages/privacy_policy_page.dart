import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';
import '../widgets/app_info_note_box.dart';

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
            title: l10n.privacyShareTitle,
            content: l10n.privacyShareContent,
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
            title: l10n.privacyChildTitle,
            content: l10n.privacyChildContent,
            context: context,
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: l10n.privacyRightsTitle,
            content: l10n.privacyRightsContent,
            context: context,
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: l10n.privacyUpdateTitle,
            content: l10n.privacyUpdateContent,
            context: context,
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: l10n.privacyContactTitle,
            content: l10n.privacyContactContent,
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
    return AppInfoNoteBox(
      title: title,
      text: content,
      padding: const EdgeInsets.all(16),
      radius: 12,
    );
  }
}
