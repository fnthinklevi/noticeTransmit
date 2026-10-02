part of 'main_page.dart';

/// 对话框域：语言切换、通知权限引导、设备名、关于。
/// R3 拆分：mixin 挂在 _MainPageState 上（同 library），行为与拆分前完全一致。
// 同 library 内有意使用 State 的 protected 成员（setState/mounted/context）
// ignore_for_file: invalid_use_of_protected_member
extension _MainPageDialogs on _MainPageState {
  /// 「系统语言变了，要不要跟着切」那一枚（T90 片22）。
  ///
  /// ⚠ **这一枚的「暂不」也要写盘** —— 它同样把语言落到「跟随系统」并记下系统语言，
  /// 只是**不**顺手刷新界面。所以它**不能**接 `askConfirm`：那一族里「取消」= 什么都不做
  /// （删除被用户撤回），把两件不同的事塞进同一个「取消」位，后人照着用必然踩
  /// ⇒ 走 `askEitherWay`（两条路都做事，返回值只答"要不要顺手刷新界面"）。
  Future<void> _showLanguageSwitchDialog(LocaleService localeService) async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final newLang = PlatformDispatcher.instance.locale.languageCode;
    final label = newLang == 'zh' ? l10n.langChinese : l10n.langEnglish;

    final alsoRefreshUi = await IosDialogActions.askEitherWay(
      context,
      title: l10n.switchLangTitle,
      message: l10n.switchLangMsg(label),
      deferText: l10n.notNow,
      confirmText: l10n.switchBtn,
    );

    await localeService.setLanguage(AppLanguage.system);
    await localeService.recordSystemLang();
    // 同步原生端桌面应用名，保持与界面语言一致（避免残留旧语言）。
    // ⚠ 这一步旧代码放在 `.then` 里、**没有 await** —— 原生那侧是 fire-and-forget 的
    // `invokeMethod`，而旧写法把它排在 `navigator.pop` 之前；现在弹层已经先关上了，
    // 把它排在 `pop` 之前没有意义，留在原地即可。
    AppChannels.notification.invokeMethod(
      'setLocaleLabel',
      localeService.currentLocale.languageCode,
    );
    // 点外面关掉（null）**什么都不做** —— 那是第三种结局，与「暂不」不是同一件事。
    if (alsoRefreshUi && mounted) {
      widget.onLocaleChanged?.call(localeService.currentLocale);
    }
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

  /// 「关于」那一枚。
  ///
  /// T90 片22：这一枚的形状就是片5 建的 `showInfo`（一句标题 + 一段正文 + 一颗「好」）——
  /// 旧代码自己手搭的 `AlertDialog` 与那三行一比一对应，唯一的差别是它把应用图标
  /// 塞进了 title 那一列。图标**留在调用方**：本组件不读 asset、也不管图标多大，
  /// 把它做成一个可选口就会变成"通用组件替调用方决定要不要图标"。
  Future<void> _showAboutDialog() async {
    final l10n = AppLocalizations.of(context);
    await IosDialogActions.showInfo(
      context,
      title: l10n.appName,
      message: l10n.author,
    );
  }
}
