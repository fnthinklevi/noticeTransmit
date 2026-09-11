part of 'main_page.dart';

/// 导航与配置回调域：各设置/历史/规则页面的打开与结果保存、电池规则 CRUD、
/// 权限检查与前后台服务启停。
/// R3 拆分：mixin 挂在 _MainPageState 上（同 library），行为与拆分前完全一致。
// 同 library 内有意使用 State 的 protected 成员（setState/mounted/context）
// ignore_for_file: invalid_use_of_protected_member
extension _MainPageActions on _MainPageState {
  Future<void> _onChangeLanguage(AppLanguage lang) async {
    final localeService = GetIt.instance<LocaleService>();
    await localeService.setLanguage(lang);
    setState(() {});
    // 同步原生端桌面应用名（最近任务页）为当前实际语言
    AppChannels.notification.invokeMethod(
      'setLocaleLabel',
      localeService.currentLocale.languageCode,
    );
    widget.onLocaleChanged?.call(localeService.currentLocale);
  }

  Future<void> _saveBatteryNotifyEnabled(bool value) async {
    await _batteryService.saveNotifyEnabled(value);
    setState(() {});
  }

  Future<void> _addBatteryRule(Map<String, dynamic> rule) async {
    await _batteryService.addRule(rule);
    setState(() {});
  }

  Future<void> _deleteBatteryRule(String id) async {
    await _batteryService.deleteRule(id);
    setState(() {});
  }

  Future<void> _updateBatteryRule(
    String id,
    Map<String, dynamic> newRule,
  ) async {
    await _batteryService.updateRule(id, newRule);
    setState(() {});
  }

  Future<void> _toggleBatteryRule(String id, bool enabled) async {
    await _batteryService.toggleRule(id, enabled);
    setState(() {});
  }

  Future<void> _refreshBatteryStatus() async {
    await _batteryService.refreshStatus();
    setState(() {});
  }

  Future<void> _checkPermissions() async {
    await _permissionService.checkAllPermissions();
    setState(() {});
  }

  Future<void> _getDeviceInfo() async {
    await _deviceInfoService.loadDeviceInfo();
    setState(() {});
  }

  Future<void> _startForegroundService() async {
    await _permissionService.checkAllPermissions();
    if (!_permissionService.notificationListenerGranted) {
      if (mounted) _showNotificationPermissionDialog();
      setState(() {});
      return;
    }
    await _notificationService.startService();
    setState(() {});
  }

  Future<void> _stopForegroundService() async {
    await _notificationService.stopService();
    setState(() {});
  }

  void _openRuleListPage() async {
    await _pushPage<List<NotificationRule>>(
      RuleListPage(
        rules: _filterService.notificationRules,
        onSave: (rules) {
          _filterService.saveNotificationRules(rules);
          setState(() {});
        },
      ),
    );
  }

  void _openPrivacyPolicyPage() {
    _pushPage(const PrivacyPolicyPage());
  }

  void _openHistoryPage() {
    _pushPage(
      HistoryPage(
        records: _notificationService.records,
        onClear: () async {
          await _notificationService.clearRecords();
          await _refreshTotalCount();
          await _notificationService.syncDailyCountToNative();
          setState(() {});
        },
        onExport: () async {
          // 安全确认：导出前弹出对话框验证用户意图（UI 统一：iOS 分割线双按钮）
          final l10n = AppLocalizations.of(context);
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppColors.cardBg(ctx),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              title: Text(
                l10n.confirmExport,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryLabel(ctx),
                ),
              ),
              content: Text(
                l10n.exportConfirmDesc,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: AppColors.primaryLabel(ctx),
                ),
              ),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(
                          l10n.cancel,
                          style: TextStyle(
                            fontSize: 16,
                            color: AppColors.secondaryLabel(ctx),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 0.5,
                      height: 20,
                      color: AppColors.separator(ctx),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(
                          l10n.exportBtn,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.blue,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
          if (confirm != true) {
            return {'success': false, 'message': l10n.exportCancelled};
          }
          final json = await _notificationService.buildExportJson(
            _deviceInfoService.deviceName,
            _deviceInfoService.deviceModel,
            _deviceInfoService.manufacturer,
          );
          final result = await AppChannels.notification.invokeMethod(
            'saveFile',
            {
              'fileName':
                  'notice_export_${DateTime.now().millisecondsSinceEpoch}.json',
              'content': json,
            },
          );
          if (result is Map) return Map<String, dynamic>.from(result);
          return {'success': false, 'message': l10n.exportError};
        },
        onClearToday: () async {
          final count = await _notificationService.clearToday();
          await _refreshTotalCount();
          await _notificationService.syncDailyCountToNative();
          setState(() {});
          return count;
        },
        onClearLastN: (int n) async {
          final count = await _notificationService.clearLastN(n);
          await _refreshTotalCount();
          await _notificationService.syncDailyCountToNative();
          setState(() {});
          return count;
        },
        // 历史记录"现在推送"：暂停期间未发送的消息手动补推
        onPushNow: (record) async {
          await _notificationService.pushRecordNow(record);
          setState(() {});
        },
      ),
    );
  }

  void _openPermissionSettingsPage() async {
    await _pushPage(
      PermissionSettingsPage(
        notificationListenerGranted:
            _permissionService.notificationListenerGranted,
        postNotificationGranted: _permissionService.postNotificationGranted,
        batteryOptimizationIgnored:
            _permissionService.batteryOptimizationIgnored,
        smsPermissionGranted: _permissionService.smsGranted,
        phonePermissionGranted: _permissionService.phoneGranted,
        appListPermissionGranted: _permissionService.appListGranted,
        manufacturer: _deviceInfoService.manufacturer,
        onRefresh: _checkPermissions,
        onRequestNotificationListenerPermission:
            _permissionService.requestNotificationListenerPermission,
        onRequestPostNotificationPermission:
            _permissionService.requestPostNotificationPermission,
        onRequestBatteryOptimization:
            _permissionService.requestBatteryOptimization,
        onRequestXiaomiAutoStart: _permissionService.requestXiaomiAutoStart,
        onRequestMeizuBackground: _permissionService.requestMeizuBackground,
        onRequestHuaweiLaunch: _permissionService.requestHuaweiLaunch,
        onRequestOppoBackground: _permissionService.requestOppoBackground,
        onRequestVivoBackground: _permissionService.requestVivoBackground,
        onRequestSmsPermission: _permissionService.requestSmsPermission,
        onRequestPhonePermission: _permissionService.requestPhonePermission,
        onRequestAppListPermission: _permissionService.requestAppListPermission,
      ),
    );
    await _checkPermissions();
    await _notificationService.loadServiceState();
    setState(() {});
  }

  /// 打开短信/来电监听设置页
  void _openSmsMonitorSettingsPage() async {
    await _pushPage(SmsMonitorSettingsPage(smsService: _smsService));
    setState(() {});
  }

  void _openAppFilterPage() async {
    final result = await _pushPage<Map<String, dynamic>>(
      AppFilterPage(
        installedApps: const [],
        initialMode: _filterService.appFilterMode,
        enabledPackages: _filterService.enabledPackages.toList(),
      ),
    );
    if (result != null) {
      final mode = result['mode'] as String? ?? 'allow';
      final packages = List<String>.from(result['packages'] ?? []);
      await _filterService.saveAppFilter(mode, packages);
      setState(() {});
    }
  }

  void _openKeywordsPage() async {
    final result = await _pushPage<Map<String, List<String>>>(
      KeywordsPage(
        blacklistKeywords: _filterService.blacklistKeywords,
        whitelistKeywords: _filterService.whitelistKeywords,
      ),
    );
    if (result != null) {
      final blacklist = result['blacklist'] ?? [];
      final whitelist = result['whitelist'] ?? [];
      await _filterService.saveBlacklistKeywords(blacklist);
      await _filterService.saveWhitelistKeywords(whitelist);
      setState(() {});
    }
  }

  void _openWebhookSettingsPage() async {
    final l10n = AppLocalizations.of(context);
    final result = await _pushPage<List<Map<String, dynamic>>>(
      WebhookSettingsPage(
        webhookChannels: List<Map<String, dynamic>>.from(
          _webhookService.channels,
        ),
      ),
    );
    if (result != null) {
      await _webhookService.saveChannels(result);
      setState(() {});
      _showInfo(l10n.webhookConfigSaved);
    }
  }

  void _openEmailSettingsPage() async {
    final l10n = AppLocalizations.of(context);
    final emailService = EmailService();
    final channels = await emailService.loadChannels();
    final result = await _pushPage<List<Map<String, dynamic>>>(
      EmailSettingsPage(
        emailChannels: channels
            .map((c) => c.toMap(includePassword: true))
            .toList(),
      ),
    );
    if (result != null) {
      final updatedChannels = result
          .map((m) => EmailChannel.fromMap(m))
          .toList();
      await emailService.saveChannels(updatedChannels);
      setState(() {});
      _showInfo(l10n.emailConfigSaved);
    }
  }
}
