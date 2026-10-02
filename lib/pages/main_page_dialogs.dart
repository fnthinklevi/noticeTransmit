part of 'main_page.dart';

/// 对话框域：语言切换、通知权限引导、设备名、关于。
/// R3 拆分：mixin 挂在 _MainPageState 上（同 library），行为与拆分前完全一致。
// 同 library 内有意使用 State 的 protected 成员（setState/mounted/context）
// ignore_for_file: invalid_use_of_protected_member
extension _MainPageDialogs on _MainPageState {
  Future<void> _showLanguageSwitchDialog(LocaleService localeService) async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final newLang = PlatformDispatcher.instance.locale.languageCode;
    final label = newLang == 'zh' ? l10n.langChinese : l10n.langEnglish;
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          l10n.switchLangTitle,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryLabel(ctx),
          ),
        ),
        content: Text(
          l10n.switchLangMsg(label),
          style: TextStyle(fontSize: 14, color: AppColors.primaryLabel(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () {
              final navigator = Navigator.of(ctx);
              localeService.setLanguage(AppLanguage.system).then((_) async {
                await localeService.recordSystemLang();
                // 同步原生端桌面应用名，保持与界面语言一致（避免残留旧语言）
                AppChannels.notification.invokeMethod(
                  'setLocaleLabel',
                  localeService.currentLocale.languageCode,
                );
                if (mounted) navigator.pop(false);
              });
            },
            child: Text(
              l10n.notNow,
              style: TextStyle(color: AppColors.secondaryLabel(ctx)),
            ),
          ),
          FilledButton(
            onPressed: () {
              final navigator = Navigator.of(ctx);
              localeService.setLanguage(AppLanguage.system).then((_) async {
                await localeService.recordSystemLang();
                if (mounted) {
                  AppChannels.notification.invokeMethod(
                    'setLocaleLabel',
                    localeService.currentLocale.languageCode,
                  );
                  navigator.pop(true);
                  widget.onLocaleChanged?.call(localeService.currentLocale);
                }
              });
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.blue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(l10n.switchBtn, style: const TextStyle(fontSize: 15)),
          ),
        ],
      ),
    );
  }

  Future<void> _showNotificationPermissionDialog() async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    // T90 片13：这一枚与片11 收的那两枚是同一形状（图标 + 说明 + 拒绝/允许），
    // 只是它**没有标题** —— 所以 title 传 null，而不是替维护者编一句文案。
    final goSettings = await IosDialogActions.showPermissionGuide(
      context,
      icon: Icons.notifications_off,
      iconColor: AppColors.orange,
      message: l10n.notificationPermOffMsg,
      rejectText: l10n.updateLater,
      allowText: l10n.goSettings,
    );
    if (goSettings) {
      _openPermissionSettingsPage();
    }
  }

  Future<void> _showDeviceNameDialog() async {
    final l10n = AppLocalizations.of(context);
    final name = await showIosInputDialog(
      context,
      title: l10n.setDeviceName,
      initialText: _deviceInfoService.deviceName,
      hintText: l10n.deviceNameLabel,
      confirmText: l10n.save,
      // 换件之前这句就是先 trim 再判空的 ⇒ 显式写出来，不靠组件默认值。
      trim: true,
      // 空值时"什么都不发生、也不关框"，与换件之前一致：这一格没有专门的提示文案，
      // 编一句要动 ARB ⇒ 措辞是维护者的决定，不在这里替他定。
      requiredField: true,
    );
    if (name == null) return;
    await _deviceInfoService.saveDeviceName(name);
    if (!mounted) return;
    setState(() {});
  }

  void _showAboutDialog() {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBg(context),
        title: Column(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(
                  'assets/app_icon.png',
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.appName,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryLabel(context),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Text(
              l10n.author,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.primaryLabel(context),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              l10n.ok,
              style: const TextStyle(
                color: AppColors.blue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
