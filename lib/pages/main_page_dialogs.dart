part of 'main_page.dart';

/// 对话框域：语言切换、通知权限引导、设备名、关于。
/// R3 拆分：mixin 挂在 _MainPageState 上（同 library），行为与拆分前完全一致。
// 同 library 内有意使用 State 的 protected 成员（setState/mounted/context）
// ignore_for_file: invalid_use_of_protected_member
extension _MainPageDialogs on _MainPageState {
  Future<void> _showLanguageSwitchDialog(LocaleService localeService) async {
    if (!mounted) return;
    final newLang = PlatformDispatcher.instance.locale.languageCode;
    final label = newLang == 'zh' ? '中文' : 'English';
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          '切换语言',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryLabel(ctx),
          ),
        ),
        content: Text(
          '检测到系统语言已变为 $label，是否同步切换应用语言？',
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
              '暂不',
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
            child: const Text('切换', style: TextStyle(fontSize: 15)),
          ),
        ],
      ),
    );
  }

  void _showNotificationPermissionDialog() {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg(ctx),
        title: const Icon(
          Icons.notifications_off,
          size: 40,
          color: AppColors.orange,
        ),
        content: Text(
          l10n.notificationPermOffMsg,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: AppColors.primaryLabel(ctx),
          ),
        ),
        actions: IosDialogActions.confirm(
          ctx,
          cancelText: l10n.updateLater,
          confirmText: l10n.goSettings,
          onConfirm: () {
            Navigator.pop(ctx);
            _openPermissionSettingsPage();
          },
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  void _showDeviceNameDialog() {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(
      text: _deviceInfoService.deviceName,
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBg(context),
        title: Text(
          l10n.setDeviceName,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryLabel(context),
          ),
        ),
        content: TextField(
          controller: controller,
          style: TextStyle(color: AppColors.primaryLabel(context)),
          decoration: InputDecoration(
            hintText: l10n.deviceNameLabel,
            hintStyle: TextStyle(color: AppColors.secondaryLabel(context)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.separator(context)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.separator(context)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.blue),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            isDense: true,
            filled: true,
            fillColor: AppColors.inputBg(context),
          ),
          autofocus: true,
        ),
        actions: IosDialogActions.confirm(
          context,
          cancelText: l10n.cancel,
          confirmText: l10n.save,
          onConfirm: () {
            final name = controller.text.trim();
            if (name.isNotEmpty) {
              _deviceInfoService.saveDeviceName(name);
              setState(() {});
              Navigator.pop(context);
            }
          },
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
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
