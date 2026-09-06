import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/platform_channel.dart';
import '../services/services.dart';
import '../services/theme_service.dart';
import '../services/email_service.dart';
import '../services/locale_service.dart';
import '../services/sms_service.dart';
import '../update_manager.dart';
import '../models/notification_rule.dart';
import '../models/email_channel.dart';
import '../theme/app_colors.dart';
import 'notification_page.dart';
import 'battery_page.dart';
import 'more_page.dart';
import 'history_page.dart';
import 'permission_settings_page.dart';
import 'email_settings_page.dart';
import 'webhook_settings_page.dart';
import 'app_filter_page.dart';
import 'keywords_page.dart';
import 'rule_list_page.dart';
import 'privacy_policy_page.dart';
import 'sms_monitor_settings_page.dart';

// R3 拆分：容器页按域拆分（part 共享 State 私有成员，行为零变化）
// main_page_update: 更新检查/弹窗/下载安装
// main_page_dialogs: 语言切换/权限引导/设备名/关于对话框
// main_page_actions: 页面导航与保存回调、电池规则 CRUD、权限检查与服务启停
part 'main_page_update.dart';
part 'main_page_dialogs.dart';
part 'main_page_actions.dart';

class MainPage extends StatefulWidget {
  final ValueChanged<Locale>? onLocaleChanged;

  const MainPage({super.key, this.onLocaleChanged});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _isCheckingUpdate = false;
  bool _isDownloading = false;
  // 首页推送记录总数（统一以 DB 为准，与更多页统计/状态栏统计共用同一数据源）
  int _notificationTotalCount = 0;

  final WebhookService _webhookService = GetIt.instance<WebhookService>();
  final BatteryService _batteryService = GetIt.instance<BatteryService>();
  final NotificationService _notificationService =
      GetIt.instance<NotificationService>();
  final PermissionService _permissionService =
      GetIt.instance<PermissionService>();
  final FilterService _filterService = GetIt.instance<FilterService>();
  final UpdateService _updateService = GetIt.instance<UpdateService>();
  final DeviceInfoService _deviceInfoService =
      GetIt.instance<DeviceInfoService>();
  final ThemeService _themeService = GetIt.instance<ThemeService>();
  final SmsService _smsService = GetIt.instance<SmsService>();

  List<Map<String, String>> _getActiveChannels() {
    final channels = <Map<String, String>>[];
    final webhookChannels = _webhookService.channels
        .where((c) => c['enabled'] == true)
        .toList();
    for (final c in webhookChannels) {
      final type = c['type']?.toString() ?? 'generic';
      channels.add({
        'type': _webhookTypeLabel(type),
        'name': c['name']?.toString() ?? '',
        'status': 'ok',
      });
    }
    final emailService = GetIt.instance<EmailService>();
    for (final c in emailService.cachedChannels) {
      if (c.enabled) {
        final tested = emailService.cachedTestResults[c.id];
        // 未测试过或测试失败都视为异常
        channels.add({
          'type': '邮件',
          'name': c.name,
          'status': (tested == true) ? 'ok' : 'error',
        });
      }
    }
    return channels;
  }

  String _webhookTypeLabel(String type) {
    switch (type) {
      case '0':
      case 'wechatWork':
      case 'wechat_work':
        return 'webhook:企业微信';
      case '1':
      case 'dingtalk':
        return 'webhook:钉钉';
      case '2':
      case 'feishu':
        return 'webhook:飞书';
      case 'telegram':
        return 'webhook:Telegram';
      case 'bark':
        return 'webhook:Bark';
      case 'server_chan':
      case 'serverChan':
        return 'webhook:Server酱';
      case 'push_plus':
      case 'pushPlus':
        return 'webhook:PushPlus';
      default:
        return 'webhook';
    }
  }

  List<Widget> _buildPages() {
    return [
      NotificationPage(
        notificationPermissionGranted:
            _permissionService.notificationListenerGranted,
        foregroundServiceRunning: _notificationService.serviceRunning,
        notificationCount: _notificationTotalCount,
        activeChannels: _getActiveChannels(),
        smsMonitorEnabled: _smsService.smsMonitorEnabled,
        onStartService: _startForegroundService,
        onStopService: _stopForegroundService,
        onRefresh: _checkPermissions,
        onOpenHistory: _openHistoryPage,
        onOpenPermissionSettings: _openPermissionSettingsPage,
        onToggleSmsMonitor: (v) async {
          await _smsService.saveSmsMonitorEnabled(v);
          setState(() {});
        },
        onOpenSmsMonitorSettings: _openSmsMonitorSettingsPage,
      ),
      BatteryPage(
        notifyEnabled: _batteryService.notifyEnabled,
        rules: _batteryService.rules,
        currentLevel: _batteryService.currentLevel,
        isCharging: _batteryService.currentIsCharging,
        onToggleNotify: (v) => _saveBatteryNotifyEnabled(v),
        onAddRule: _addBatteryRule,
        onDeleteRule: _deleteBatteryRule,
        onUpdateRule: _updateBatteryRule,
        onToggleRule: _toggleBatteryRule,
        onRefresh: _refreshBatteryStatus,
      ),
      MorePage(
        key: ValueKey('more_${_themeService.themeMode.index}'),
        webhookChannels: _webhookService.channels,
        deviceName: _deviceInfoService.deviceName,
        enabledPackagesCount: _filterService.enabledPackages.length,
        appFilterMode: _filterService.appFilterMode,
        blacklistCount: _filterService.blacklistKeywords.length,
        whitelistCount: _filterService.whitelistKeywords.length,
        ruleCount: _filterService.notificationRules.length,
        isCheckingUpdate: _isCheckingUpdate,
        themeMode: _themeService.themeMode,
        onThemeModeChanged: (mode) {
          _themeService.setThemeMode(mode);
          setState(() {});
        },
        onOpenWebhookSettings: _openWebhookSettingsPage,
        onOpenEmailSettings: _openEmailSettingsPage,
        onShowDeviceNameDialog: _showDeviceNameDialog,
        onShowAboutDialog: _showAboutDialog,
        onOpenAppFilter: _openAppFilterPage,
        onOpenKeywords: _openKeywordsPage,
        onOpenRules: _openRuleListPage,
        onCheckUpdate: _manualCheckUpdate,
        onOpenPrivacyPolicy: _openPrivacyPolicyPage,
        onChangeLanguage: _onChangeLanguage,
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupMethodChannel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _postInit();
    });
  }

  Future<void> _postInit() async {
    try {
      await _checkPermissions();
      _getDeviceInfo();
      _refreshBatteryStatus();
      _batteryService.startRefreshTimer();

      // 首页/更多页/状态栏统计统一：刷新首页总计数 + 同步原生今日计数基数
      await _refreshTotalCount();
      await _notificationService.syncDailyCountToNative();

      // 加载推送通道配置 + 启动每日归档定时器
      await _webhookService.loadChannels();
      final emailService = GetIt.instance<EmailService>();
      await emailService.loadChannels();
      await _smsService.loadSettings();
      _notificationService.startDailyExport();
      setState(() {});

      await _checkFirstLaunch();

      if (!_notificationService.serviceManuallyStopped) {
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted) {
            _startForegroundService();
          }
        });
      }

      _checkUpdateOnStartup();
    } catch (e) {
      debugPrint('页面初始化失败: $e');
    }
  }

  /// 刷新首页"推送历史"总条数（以 DB 为准，统计口径与更多页/状态栏统一）
  Future<void> _refreshTotalCount() async {
    final count = await _notificationService.getTotalCount();
    if (mounted && count != _notificationTotalCount) {
      setState(() => _notificationTotalCount = count);
    }
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final hasLaunched = prefs.getBool('has_launched') ?? false;
    if (!hasLaunched) {
      await prefs.setBool('has_launched', true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _batteryService.stopRefreshTimer();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      // 回到前台时补偿拉取 Activity 销毁期间丢失的送达结果（修复"一直显示推送中"）
      unawaited(_notificationService.drainPendingDeliveries());
      final localeService = GetIt.instance<LocaleService>();
      if (localeService.shouldPromptSwitch) {
        await _showLanguageSwitchDialog(localeService);
      }
    }
  }

  /// 显示短时效的提示条（2 秒），并在弹出前/跳转前先收起上一条，
  /// 满足“显示时间缩短、跳转到其他页面时消失”的要求。
  void _showInfo(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  /// 统一的页面跳转入口：跳转前收起底部提示条，使其不再残留到其他页面。
  Future<T?> _pushPage<T>(Widget page) {
    if (!mounted) return Future<T?>.value(null);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    return Navigator.push<T>(context, MaterialPageRoute(builder: (_) => page));
  }

  void _setupMethodChannel() {
    AppChannels.notification.setMethodCallHandler((call) async {
      if (call.method == 'onNotificationReceived') {
        final Map<String, dynamic> record = Map<String, dynamic>.from(
          call.arguments,
        );
        _notificationService.addRecord(record);
        _refreshTotalCount();
        setState(() {});
      } else if (call.method == 'onDeliveryResult') {
        // webhook 送达结果回传：更新对应记录的状态
        final Map<String, dynamic> data = Map<String, dynamic>.from(
          call.arguments,
        );
        await _notificationService.updateDelivery(
          data['notificationId']?.toString() ?? '',
          data['webhookType']?.toString() ?? '',
          data['status']?.toString() ?? '',
          data['message']?.toString() ?? '',
          httpCode: (data['httpCode'] as num?)?.toInt() ?? 0,
          channelUrl: data['channelUrl']?.toString() ?? '',
        );
        setState(() {});
      } else if (call.method == 'onBatteryChanged') {
        final Map<String, dynamic> data = Map<String, dynamic>.from(
          call.arguments,
        );
        _batteryService.updateBatteryStatus(data);
        setState(() {});
      } else if (call.method == 'onSmsPermissionResult') {
        setState(() {});
      } else if (call.method == 'onPhonePermissionResult') {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pages = _buildPages();
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          setState(() => _currentIndex = index);
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.notifications),
            selectedIcon: const Icon(Icons.notifications_active),
            label: l10n.tabNotification,
          ),
          NavigationDestination(
            icon: const Icon(Icons.battery_full),
            selectedIcon: const Icon(Icons.battery_charging_full),
            label: l10n.tabBattery,
          ),
          NavigationDestination(
            icon: const Icon(Icons.more_horiz),
            selectedIcon: const Icon(Icons.more_horiz),
            label: l10n.tabMore,
          ),
        ],
      ),
    );
  }
}
