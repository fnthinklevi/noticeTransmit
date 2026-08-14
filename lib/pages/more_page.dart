import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../services/update_service.dart';
import '../services/locale_service.dart';
import '../services/platform_channel.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';
import '../widgets/icon_picker_tile.dart';
import 'stats_page.dart';

/// 同步语言到原生端，更新桌面应用名
void _syncNativeLocale(AppLanguage lang) {
  final localeCode = switch (lang) {
    AppLanguage.en => 'en',
    AppLanguage.zh => 'zh',
    AppLanguage.system => 'zh',
  };
  AppChannels.notification.invokeMethod('setLocaleLabel', localeCode);
}

class MorePage extends StatelessWidget {
  final List<Map<String, dynamic>> webhookChannels;
  final String deviceName;
  final int enabledPackagesCount;
  final String appFilterMode; // 'allow' = 通知应用；'block' = 不通知应用
  final int blacklistCount;
  final int whitelistCount;
  final int ruleCount;
  final bool isCheckingUpdate;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final VoidCallback onOpenWebhookSettings;
  final VoidCallback onOpenEmailSettings;
  final VoidCallback onShowDeviceNameDialog;
  final VoidCallback onShowAboutDialog;
  final VoidCallback onOpenAppFilter;
  final VoidCallback onOpenKeywords;
  final VoidCallback onOpenRules;
  final VoidCallback onCheckUpdate;
  final VoidCallback onOpenPrivacyPolicy;
  final ValueChanged<AppLanguage> onChangeLanguage;

  const MorePage({
    super.key,
    required this.webhookChannels,
    required this.deviceName,
    required this.enabledPackagesCount,
    this.appFilterMode = 'allow',
    required this.blacklistCount,
    required this.whitelistCount,
    required this.ruleCount,
    required this.isCheckingUpdate,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onOpenWebhookSettings,
    required this.onOpenEmailSettings,
    required this.onShowDeviceNameDialog,
    required this.onShowAboutDialog,
    required this.onOpenAppFilter,
    required this.onOpenKeywords,
    required this.onOpenRules,
    required this.onCheckUpdate,
    required this.onOpenPrivacyPolicy,
    required this.onChangeLanguage,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final enabledCount = webhookChannels
        .where((c) => c['enabled'] == true)
        .length;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabMore)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _buildSectionHeader(l10n.appearance, context),
          _buildGroup([
            _buildThemeTile(context),
            _buildDivider(context),
            _buildLanguageTile(context),
            _buildDivider(context),
            const IconPickerTile(),
          ], context),
          const SizedBox(height: 24),
          _buildSectionHeader(l10n.pushChannels, context),
          _buildGroup([
            _buildNavTile(
              icon: Icons.link,
              iconColor: AppColors.blue,
              title: l10n.webhookChannel,
              subtitle: webhookChannels.isEmpty
                  ? l10n.webhookNotConfigured
                  : l10n.webhookConfigured(
                      webhookChannels.length,
                      enabledCount,
                    ),
              onTap: onOpenWebhookSettings,
              context: context,
            ),
            _buildNavTile(
              icon: Icons.email,
              iconColor: AppColors.orange,
              title: l10n.emailChannel,
              subtitle: l10n.emailChannelDesc,
              onTap: onOpenEmailSettings,
              context: context,
            ),
          ], context),
          const SizedBox(height: 24),
          _buildSectionHeader(l10n.filterRules, context),
          _buildGroup([
            _buildNavTile(
              icon: Icons.apps,
              iconColor: const Color(0xFFAF52DE),
              title: l10n.appFilter,
              subtitle: _appFilterSubtitle(context),
              onTap: onOpenAppFilter,
              context: context,
            ),
            _buildDivider(context),
            _buildNavTile(
              icon: Icons.filter_list,
              iconColor: const Color(0xFFFF9500),
              title: l10n.keywordFilter,
              subtitle: l10n.keywordWhitelistBlacklist(
                whitelistCount,
                blacklistCount,
              ),
              onTap: onOpenKeywords,
              context: context,
            ),
            _buildDivider(context),
            _buildNavTile(
              icon: Icons.rule,
              iconColor: const Color(0xFFAF52DE),
              title: l10n.ruleEngine,
              subtitle: ruleCount > 0
                  ? l10n.ruleCount(ruleCount)
                  : l10n.ruleEmpty,
              onTap: onOpenRules,
              context: context,
            ),
          ], context),
          const SizedBox(height: 24),
          _buildSectionHeader(l10n.device, context),
          _buildGroup([
            _buildNavTile(
              icon: Icons.smartphone,
              iconColor: AppColors.green,
              title: l10n.deviceName,
              subtitle: deviceName.isEmpty ? l10n.notSet : deviceName,
              onTap: onShowDeviceNameDialog,
              context: context,
            ),
            _buildDivider(context),
            _buildNavTile(
              icon: Icons.bar_chart,
              iconColor: const Color(0xFF5856D6),
              title: l10n.pushStats,
              subtitle: l10n.pushStatsDesc,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const StatsPage()),
              ),
              context: context,
            ),
          ], context),
          const SizedBox(height: 24),
          _buildSectionHeader(l10n.aboutUpdate, context),
          _buildGroup([
            _buildNavTile(
              icon: Icons.update,
              iconColor: AppColors.blue,
              title: l10n.checkUpdate,
              subtitle: isCheckingUpdate ? l10n.checking : l10n.clickToCheck,
              trailing: isCheckingUpdate
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              onTap: isCheckingUpdate ? null : onCheckUpdate,
              context: context,
            ),
            _buildDivider(context),
            _buildNavTile(
              icon: Icons.privacy_tip_outlined,
              iconColor: AppColors.green,
              title: l10n.privacyPolicyTitle,
              subtitle: l10n.privacyPolicyDesc,
              onTap: onOpenPrivacyPolicy,
              context: context,
            ),
            _buildDivider(context),
            _buildNavTile(
              icon: Icons.info_outline,
              iconColor: const Color(0xFF8E8E93),
              title: l10n.aboutTitle,
              subtitle: l10n.aboutDesc,
              onTap: onShowAboutDialog,
              context: context,
            ),
          ], context),
          const SizedBox(height: 32),
          Center(
            child: Text(
              'v${GetIt.instance<UpdateService>().currentVersion}',
              style: TextStyle(
                color: AppColors.secondaryLabel(context),
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _appFilterSubtitle(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (enabledPackagesCount > 0) {
      return appFilterMode == 'block'
          ? l10n.appFilterBlocked(enabledPackagesCount)
          : l10n.appFilterSelected(enabledPackagesCount);
    }
    return l10n.appFilterAll;
  }

  Widget _buildSectionHeader(String title, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.secondaryLabel(context),
        ),
      ),
    );
  }

  Widget _buildGroup(List<Widget> children, BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 52),
      child: Divider(
        height: 0.5,
        thickness: 0.5,
        color: AppColors.separator(context),
      ),
    );
  }

  Widget _buildThemeTile(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final themeNames = {
      ThemeMode.system: l10n.followSystem,
      ThemeMode.light: l10n.lightMode,
      ThemeMode.dark: l10n.darkMode,
    };
    final themeIcons = {
      ThemeMode.system: Icons.brightness_auto,
      ThemeMode.light: Icons.light_mode,
      ThemeMode.dark: Icons.dark_mode,
    };
    final themeIconColors = {
      ThemeMode.system: const Color(0xFF8E8E93),
      ThemeMode.light: const Color(0xFFFF9500),
      ThemeMode.dark: const Color(0xFF5856D6),
    };
    return InkWell(
      onTap: () {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.cardBg(context),
            title: Text(
              l10n.darkMode,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryLabel(context),
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 4),
                ...ThemeMode.values.map(
                  (mode) => ListTile(
                    onTap: () {
                      onThemeModeChanged(mode);
                      Navigator.pop(context);
                    },
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: (themeIconColors[mode] ?? Colors.grey)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        themeIcons[mode] ?? Icons.brightness_auto,
                        color: themeIconColors[mode] ?? Colors.grey,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      themeNames[mode] ?? '',
                      style: TextStyle(color: AppColors.primaryLabel(context)),
                    ),
                    trailing: themeMode == mode
                        ? const Icon(Icons.check, color: AppColors.blue)
                        : null,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                ),
              ],
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF5AC8FA),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.dark_mode, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.darkMode,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AppColors.primaryLabel(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    themeNames[themeMode] ?? l10n.followSystem,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.secondaryLabel(context),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: AppColors.tertiaryLabel(context),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageTile(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeService = GetIt.instance<LocaleService>();
    final langNames = {
      AppLanguage.system: l10n.langDefault,
      AppLanguage.zh: l10n.langChinese,
      AppLanguage.en: l10n.langEnglish,
    };
    final langIcons = {
      AppLanguage.system: Icons.phone_android,
      AppLanguage.zh: Icons.translate,
      AppLanguage.en: Icons.g_translate,
    };
    return InkWell(
      onTap: () {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.cardBg(ctx),
            title: Text(
              l10n.language,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryLabel(ctx),
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 4),
                ...AppLanguage.values.map(
                  (lang) => ListTile(
                    leading: Icon(
                      langIcons[lang],
                      color: localeService.language == lang
                          ? AppColors.blue
                          : AppColors.secondaryLabel(ctx),
                      size: 22,
                    ),
                    onTap: () {
                      final navigator = Navigator.of(ctx);
                      localeService.setLanguage(lang).then((_) {
                        onChangeLanguage(lang);
                        _syncNativeLocale(lang);
                        navigator.pop();
                      });
                    },
                    title: Text(
                      langNames[lang] ?? '',
                      style: TextStyle(
                        color: AppColors.primaryLabel(ctx),
                        fontWeight: localeService.language == lang
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    trailing: localeService.language == lang
                        ? const Icon(Icons.check, color: AppColors.blue)
                        : null,
                  ),
                ),
              ],
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.blue,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.language, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.language,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AppColors.primaryLabel(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    langNames[localeService.language] ?? l10n.langDefault,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.secondaryLabel(context),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: AppColors.tertiaryLabel(context),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    required BuildContext context,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: iconColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.primaryLabel(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.secondaryLabel(context),
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null)
              trailing
            else if (onTap != null)
              Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColors.tertiaryLabel(context),
              ),
          ],
        ),
      ),
    );
  }
}
