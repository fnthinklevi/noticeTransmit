import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../update_manager.dart';
import '../models/notification_rule.dart';
import '../models/notification_record.dart';
import '../theme/app_colors.dart';
import 'notification_page.dart';
import 'battery_page.dart';
import 'more_page.dart';
import 'history_page.dart';
import 'permission_settings_page.dart';
import 'webhook_settings_page.dart';
import 'app_filter_page.dart';
import 'keywords_page.dart';
import 'rule_list_page.dart';
import 'privacy_policy_page.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  static const platform = MethodChannel('com.fnthink.notice/notification');

  int _currentIndex = 0;

  bool _notificationPermissionGranted = false;
  bool _batteryOptimizationIgnored = false;
  bool _foregroundServiceRunning = false;
  bool _smsPermissionGranted = false;
  bool _phonePermissionGranted = false;
  bool _appListPermissionGranted = false;
  bool _serviceManuallyStopped = false;
  List<Map<String, dynamic>> _webhookChannels = [];
  String _deviceName = '';
  String _deviceModel = '';
  String _manufacturer = '';
  final List<NotificationRecord> _notificationRecords = [];
  static const int _maxRecords = 500;

  bool _batteryNotifyEnabled = true;
  List<Map<String, dynamic>> _batteryRules = [];
  int _currentBatteryLevel = -1;
  bool _currentIsCharging = false;
  Timer? _batteryRefreshTimer;

  bool _isCheckingUpdate = false;
  bool _isDownloading = false;

  Set<String> _enabledPackages = {};
  List<String> _blacklistKeywords = [];
  List<String> _whitelistKeywords = [];
  List<NotificationRule> _notificationRules = [];
  final List<Map<String, dynamic>> _installedApps = [];

  List<Widget> _buildPages() {
    return [
      NotificationPage(
        notificationPermissionGranted: _notificationPermissionGranted,
        foregroundServiceRunning: _foregroundServiceRunning,
        notificationCount: _notificationRecords.length,
        onStartService: _startForegroundService,
        onStopService: _stopForegroundService,
        onRefresh: _checkPermissions,
        onOpenHistory: _openHistoryPage,
        onOpenPermissionSettings: _openPermissionSettingsPage,
      ),
      BatteryPage(
        notifyEnabled: _batteryNotifyEnabled,
        rules: _batteryRules,
        currentLevel: _currentBatteryLevel,
        isCharging: _currentIsCharging,
        onToggleNotify: (v) => _saveBatteryNotifyEnabled(v),
        onAddRule: _addBatteryRule,
        onDeleteRule: _deleteBatteryRule,
        onUpdateRule: _updateBatteryRule,
        onToggleRule: _toggleBatteryRule,
        onRefresh: _refreshBatteryStatus,
      ),
      MorePage(
        key: ValueKey('more_${MyApp.of(context)?.themeMode.index ?? 0}'),
        webhookChannels: _webhookChannels,
        deviceName: _deviceName,
        enabledPackagesCount: _enabledPackages.length,
        blacklistCount: _blacklistKeywords.length,
        whitelistCount: _whitelistKeywords.length,
        ruleCount: _notificationRules.length,
        isCheckingUpdate: _isCheckingUpdate,
        themeMode: MyApp.of(context)?.themeMode ?? ThemeMode.system,
        onThemeModeChanged: (mode) {
          MyApp.of(context)?.setThemeMode(mode);
        },
        onOpenWebhookSettings: _openWebhookSettingsPage,
        onShowDeviceNameDialog: _showDeviceNameDialog,
        onShowAboutDialog: _showAboutDialog,
        onOpenAppFilter: _openAppFilterPage,
        onOpenKeywords: _openKeywordsPage,
        onOpenRules: _openRuleListPage,
        onCheckUpdate: _manualCheckUpdate,
        onOpenPrivacyPolicy: _openPrivacyPolicyPage,
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _setupMethodChannel();
    _initForegroundTask();
    _loadAllSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPermissions();
      _getDeviceInfo();
      _refreshBatteryStatus();
      _startBatteryRefreshTimer();
    });
  }

  @override
  void dispose() {
    _batteryRefreshTimer?.cancel();
    _batteryRefreshTimer = null;
    super.dispose();
  }

  void _startBatteryRefreshTimer() {
    _batteryRefreshTimer?.cancel();
    _batteryRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _refreshBatteryStatus();
    });
  }

  void _setupMethodChannel() {
    platform.setMethodCallHandler((call) async {
      if (call.method == 'onNotificationReceived') {
        final Map<String, dynamic> record = Map<String, dynamic>.from(
          call.arguments,
        );
        _addNotificationRecord(record);
      } else if (call.method == 'onBatteryChanged') {
        final Map<String, dynamic> data = Map<String, dynamic>.from(
          call.arguments,
        );
        setState(() {
          _currentBatteryLevel = data['level'] ?? -1;
          _currentIsCharging = data['isCharging'] ?? false;
        });
      } else if (call.method == 'onSmsPermissionResult') {
        final Map<String, dynamic> data = Map<String, dynamic>.from(
          call.arguments,
        );
        setState(() {
          _smsPermissionGranted = data['granted'] ?? false;
        });
      } else if (call.method == 'onPhonePermissionResult') {
        final Map<String, dynamic> data = Map<String, dynamic>.from(
          call.arguments,
        );
        setState(() {
          _phonePermissionGranted = data['granted'] ?? false;
        });
      }
    });
  }

  Future<void> _initForegroundTask() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'notification_monitor',
        channelName: '通知监听服务',
        channelDescription: '后台运行通知监听服务',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<void> _loadAllSettings() async {
    final prefs = await SharedPreferences.getInstance();
    List<Map<String, dynamic>> channels = [];
    bool loadedFromNative = false;
    try {
      final List<dynamic> result = await platform.invokeMethod(
        'getWebhookChannels',
      );
      channels = result.map((e) => Map<String, dynamic>.from(e)).toList();
      loadedFromNative = true;
    } catch (e) {
      debugPrint('从原生端加载webhook失败: $e');
      final urlsJson = prefs.getString('webhook_channels');
      if (urlsJson != null) {
        try {
          final List<dynamic> list = jsonDecode(urlsJson);
          channels = list.map((e) => Map<String, dynamic>.from(e)).toList();
        } catch (_) {
          channels = [];
        }
      } else {
        final oldUrlsJson = prefs.getString('webhook_urls');
        if (oldUrlsJson != null) {
          try {
            final List<dynamic> list = jsonDecode(oldUrlsJson);
            channels = list
                .map((e) => {'url': e.toString(), 'enabled': true})
                .toList();
          } catch (_) {
            channels = [];
          }
        } else {
          final singleUrl = prefs.getString('webhook_url');
          if (singleUrl != null && singleUrl.isNotEmpty) {
            channels = [
              {'url': singleUrl, 'enabled': true},
            ];
          }
        }
      }
    }
    if (loadedFromNative && channels.isNotEmpty) {
      await prefs.setString('webhook_channels', jsonEncode(channels));
    }

    String deviceName = '';
    try {
      final nativeDeviceName =
          await platform.invokeMethod('getDeviceName') as String?;
      if (nativeDeviceName != null && nativeDeviceName.isNotEmpty) {
        deviceName = nativeDeviceName;
        await prefs.setString('device_name', nativeDeviceName);
      }
    } catch (e) {
      debugPrint('从原生端获取设备名失败: $e');
      deviceName = prefs.getString('device_name') ?? '';
    }

    await AppUpdateManager.instance.init();

    setState(() {
      _webhookChannels = channels;
      _deviceName = deviceName;
      _serviceManuallyStopped =
          prefs.getBool('service_manually_stopped') ?? false;
      _batteryNotifyEnabled = prefs.getBool('battery_notify_enabled') ?? true;
      _batteryRules = _loadBatteryRules(prefs);
    });
    final enabledUrls = _webhookChannels
        .where((c) => c['enabled'] == true)
        .map((c) => c['url'] as String)
        .toList();
    if (enabledUrls.isNotEmpty) {
      await _setNativeWebhookUrls(enabledUrls);
    }
    if (!_serviceManuallyStopped) {
      Future.delayed(const Duration(milliseconds: 2000), () {
        if (mounted) {
          _startForegroundService();
        }
      });
    }
    _loadNotificationRecords();
    _loadFilterSettings();
    _checkUpdateOnStartup();
  }

  Future<void> _checkUpdateOnStartup() async {
    if (!AppUpdateManager.instance.autoCheck) return;
    final shouldCheck = await AppUpdateManager.instance.shouldCheckNow();
    if (!shouldCheck) return;
    await _performUpdateCheck(isManual: false);
  }

  Future<void> _performUpdateCheck({bool isManual = false}) async {
    if (!mounted) return;

    try {
      final hotfixResult = await AppUpdateManager.instance.checkHotfix(
        force: isManual,
      );
      if (hotfixResult != null && hotfixResult.hasUpdate && mounted) {
        await _downloadAndApplyHotfix(hotfixResult);
      }
    } catch (e) {
      debugPrint('热更新检查失败: $e');
    }

    final result = await AppUpdateManager.instance.checkUpdate(force: isManual);

    if (!mounted) return;

    if (result != null) {
      if (result.hasUpdate) {
        if (!isManual && !result.forceUpdate) {
          final ignored = await AppUpdateManager.instance.getIgnoredVersion();
          if (ignored == result.latestVersion) {
            return;
          }
        }
        _showUpdateDialog(result);
      } else if (isManual) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('当前已是最新版本')));
      }
    } else if (isManual) {
      final error = AppUpdateManager.instance.lastError;
      final errorMsg = error != null && error.isNotEmpty
          ? '检查更新失败：$error'
          : '检查更新失败，请检查网络连接';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMsg)));
    }
  }

  Future<void> _loadFilterSettings() async {
    try {
      final List<dynamic> enabledPkgs = await platform.invokeMethod(
        'getEnabledPackages',
      );
      final List<dynamic> blacklist = await platform.invokeMethod(
        'getBlacklistKeywords',
      );
      final List<dynamic> whitelist = await platform.invokeMethod(
        'getWhitelistKeywords',
      );
      setState(() {
        _enabledPackages = Set<String>.from(
          enabledPkgs.map((e) => e.toString()),
        );
        _blacklistKeywords = blacklist.map((e) => e.toString()).toList();
        _whitelistKeywords = whitelist.map((e) => e.toString()).toList();
      });
    } catch (e) {
      debugPrint('加载过滤配置失败: $e');
    }
  }

  Future<void> _saveWebhookChannels(List<Map<String, dynamic>> channels) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('webhook_channels', jsonEncode(channels));
    try {
      await platform.invokeMethod('setWebhookChannels', {'channels': channels});
    } catch (e) {
      debugPrint('保存webhook到原生端失败: $e');
    }
    setState(() {
      _webhookChannels = channels;
    });
  }

  Future<void> _saveDeviceName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('device_name', name);
    setState(() {
      _deviceName = name;
    });
    try {
      await platform.invokeMethod('setDeviceName', {'name': name});
    } catch (_) {}
  }

  List<Map<String, dynamic>> _loadBatteryRules(SharedPreferences prefs) {
    final jsonStr = prefs.getString('battery_rules');
    if (jsonStr != null) {
      try {
        final List<dynamic> list = jsonDecode(jsonStr);
        return list.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
    }
    return _defaultBatteryRules();
  }

  List<Map<String, dynamic>> _defaultBatteryRules() {
    return [
      {
        'id': 'charging',
        'type': 'charging',
        'value': 0,
        'enabled': true,
        'title': '开始充电',
        'content': '',
      },
      {
        'id': 'full',
        'type': 'level_above',
        'value': 100,
        'enabled': true,
        'title': '电量充满',
        'content': '',
      },
      {
        'id': 'low30',
        'type': 'level_below',
        'value': 30,
        'enabled': true,
        'title': '电量低于30%',
        'content': '',
      },
      {
        'id': 'low20',
        'type': 'level_below',
        'value': 20,
        'enabled': true,
        'title': '电量低于20%',
        'content': '',
      },
      {
        'id': 'discharging',
        'type': 'discharging',
        'value': 0,
        'enabled': false,
        'title': '断开充电',
        'content': '',
      },
    ];
  }

  Future<void> _saveBatteryNotifyEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('battery_notify_enabled', value);
    setState(() {
      _batteryNotifyEnabled = value;
    });
    try {
      await platform.invokeMethod('setBatterySetting', {
        'key': 'battery_notify_enabled',
        'value': value,
      });
    } catch (e) {
      debugPrint('同步电量设置失败: $e');
    }
  }

  Future<void> _syncBatteryRules() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('battery_rules', jsonEncode(_batteryRules));
    try {
      await platform.invokeMethod('setBatteryRules', {'rules': _batteryRules});
    } catch (e) {
      debugPrint('同步电量规则失败: $e');
    }
  }

  Future<void> _addBatteryRule(Map<String, dynamic> rule) async {
    setState(() {
      _batteryRules = [..._batteryRules, rule];
    });
    await _syncBatteryRules();
  }

  Future<void> _deleteBatteryRule(String id) async {
    setState(() {
      _batteryRules = _batteryRules.where((r) => r['id'] != id).toList();
    });
    await _syncBatteryRules();
  }

  Future<void> _updateBatteryRule(
    String id,
    Map<String, dynamic> newRule,
  ) async {
    setState(() {
      _batteryRules = _batteryRules.map((r) {
        if (r['id'] == id) return newRule;
        return r;
      }).toList();
    });
    await _syncBatteryRules();
  }

  Future<void> _toggleBatteryRule(String id, bool enabled) async {
    setState(() {
      _batteryRules = _batteryRules.map((r) {
        if (r['id'] == id) {
          return {...r, 'enabled': enabled};
        }
        return r;
      }).toList();
    });
    await _syncBatteryRules();
  }

  Future<void> _loadNotificationRecords() async {
    try {
      final List<dynamic> result = await platform.invokeMethod(
        'getNotificationRecords',
      );
      setState(() {
        _notificationRecords.clear();
        _notificationRecords.addAll(
          result
              .map(
                (e) => NotificationRecord.fromMap(Map<String, dynamic>.from(e)),
              )
              .toList(),
        );
      });
    } catch (e) {
      debugPrint('从原生端加载历史记录失败: $e');
      final prefs = await SharedPreferences.getInstance();
      final recordsJson = prefs.getString('notification_records');
      if (recordsJson != null) {
        try {
          final List<dynamic> list = jsonDecode(recordsJson);
          setState(() {
            _notificationRecords.clear();
            _notificationRecords.addAll(
              list
                  .map(
                    (e) => NotificationRecord.fromMap(
                      Map<String, dynamic>.from(e),
                    ),
                  )
                  .toList(),
            );
          });
        } catch (e2) {
          debugPrint('加载本地历史记录失败: $e2');
        }
      }
    }
  }

  Future<void> _saveNotificationRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final recordsJson = jsonEncode(
      _notificationRecords.take(_maxRecords).map((r) => r.toMap()).toList(),
    );
    await prefs.setString('notification_records', recordsJson);
  }

  void _addNotificationRecord(Map<String, dynamic> record) {
    setState(() {
      _notificationRecords.insert(0, NotificationRecord.fromMap(record));
      if (_notificationRecords.length > _maxRecords) {
        _notificationRecords.removeRange(
          _maxRecords,
          _notificationRecords.length,
        );
      }
    });
    _saveNotificationRecords();
  }

  Future<void> _clearNotificationRecords() async {
    try {
      await platform.invokeMethod('clearNotificationRecords');
    } catch (e) {
      debugPrint('清空原生端历史记录失败: $e');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('notification_records');
    setState(() {
      _notificationRecords.clear();
    });
  }

  Future<String> _exportNotificationRecords() async {
    final directory = await getExternalStorageDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File(
      '${directory?.path}/notification_records_$timestamp.json',
    );
    final exportData = {
      'exportTime': DateTime.now().toIso8601String(),
      'deviceName': _deviceName,
      'deviceModel': _deviceModel,
      'manufacturer': _manufacturer,
      'totalCount': _notificationRecords.length,
      'records': _notificationRecords.map((r) => r.toMap()).toList(),
    };
    await file.writeAsString(jsonEncode(exportData), mode: FileMode.write);
    return file.path;
  }

  Future<void> _setNativeWebhookUrls(List<String> urls) async {
    try {
      await platform.invokeMethod('setWebhookUrls', {'urls': urls});
    } catch (e) {
      debugPrint('设置webhook失败: $e');
    }
  }

  Future<void> _getDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      setState(() {
        _deviceModel = androidInfo.model;
        _manufacturer = androidInfo.manufacturer;
      });
    } catch (e) {
      debugPrint('获取设备信息失败: $e');
    }

    try {
      final model = await platform.invokeMethod('getDeviceModel') as String?;
      final manu = await platform.invokeMethod('getManufacturer') as String?;
      if (model != null) _deviceModel = model;
      if (manu != null) _manufacturer = manu;
    } catch (e) {
      debugPrint('获取设备型号失败: $e');
    }
  }

  Future<void> _checkPermissions() async {
    try {
      final granted =
          await platform.invokeMethod('isNotificationPermissionGranted')
              as bool?;
      final batteryOk =
          await platform.invokeMethod('isIgnoringBatteryOptimizations')
              as bool?;
      final running = await FlutterForegroundTask.isRunningService;
      final smsGranted =
          await platform.invokeMethod('isSmsPermissionGranted') as bool?;
      final phoneGranted =
          await platform.invokeMethod('isPhonePermissionGranted') as bool?;
      final appListGranted =
          await platform.invokeMethod('isAppListPermissionGranted') as bool?;

      setState(() {
        _notificationPermissionGranted = granted ?? false;
        _batteryOptimizationIgnored = batteryOk ?? false;
        _foregroundServiceRunning = running;
        _smsPermissionGranted = smsGranted ?? false;
        _phonePermissionGranted = phoneGranted ?? false;
        _appListPermissionGranted = appListGranted ?? false;
      });
    } catch (e) {
      debugPrint('检查权限失败: $e');
    }
  }

  Future<void> _refreshBatteryStatus() async {
    try {
      final result = await platform.invokeMethod('getBatteryStatus');
      setState(() {
        _currentBatteryLevel = result['level'] ?? -1;
        _currentIsCharging = result['isCharging'] ?? false;
      });
    } catch (e) {
      debugPrint('获取电量状态失败: $e');
    }
  }

  Future<void> _requestNotificationPermission() async {
    try {
      await platform.invokeMethod('requestNotificationPermission');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请在设置中开启通知访问权限')));
      }
    } catch (e) {
      debugPrint('请求通知权限失败: $e');
    }
  }

  Future<void> _requestBatteryOptimization() async {
    try {
      await platform.invokeMethod('requestBatteryOptimization');
    } catch (e) {
      debugPrint('请求电池优化失败: $e');
    }
  }

  Future<void> _requestXiaomiAutoStart() async {
    try {
      await platform.invokeMethod('requestXiaomiAutoStart');
    } catch (e) {
      debugPrint('打开小米自启动失败: $e');
    }
  }

  Future<void> _requestMeizuBackground() async {
    try {
      await platform.invokeMethod('requestMeizuBackground');
    } catch (e) {
      debugPrint('打开魅族后台失败: $e');
    }
  }

  Future<void> _requestHuaweiLaunch() async {
    try {
      await platform.invokeMethod('requestHuaweiLaunch');
    } catch (e) {
      debugPrint('打开华为自启动失败: $e');
    }
  }

  Future<void> _requestOppoBackground() async {
    try {
      await platform.invokeMethod('requestOppoBackground');
    } catch (e) {
      debugPrint('打开OPPO后台失败: $e');
    }
  }

  Future<void> _requestVivoBackground() async {
    try {
      await platform.invokeMethod('requestVivoBackground');
    } catch (e) {
      debugPrint('打开vivo后台失败: $e');
    }
  }

  Future<void> _requestSmsPermission() async {
    try {
      await platform.invokeMethod('requestSmsPermission');
    } catch (e) {
      debugPrint('请求短信权限失败: $e');
    }
  }

  Future<void> _requestPhonePermission() async {
    try {
      await platform.invokeMethod('requestPhonePermission');
    } catch (e) {
      debugPrint('请求电话权限失败: $e');
    }
  }

  Future<void> _requestAppListPermission() async {
    try {
      await platform.invokeMethod('requestAppListPermission');
    } catch (e) {
      debugPrint('请求应用列表权限失败: $e');
    }
  }

  Future<void> _startForegroundService() async {
    final result = await FlutterForegroundTask.startService(
      notificationTitle: '通知监听中',
      notificationText: '正在监听通知栏消息并推送',
      callback: _foregroundTaskCallback,
    );

    final isSuccess = result is ServiceRequestSuccess;

    setState(() {
      _foregroundServiceRunning = isSuccess;
      _serviceManuallyStopped = !isSuccess;
    });

    if (isSuccess) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('service_manually_stopped', false);
      try {
        await platform.invokeMethod('startNotificationListener');
      } catch (e) {
        debugPrint('启动通知监听失败: $e');
      }
    }
  }

  @pragma('vm:entry-point')
  static void _foregroundTaskCallback() {
    FlutterForegroundTask.setTaskHandler(NotificationTaskHandler());
  }

  Future<void> _stopForegroundService() async {
    final result = await FlutterForegroundTask.stopService();
    final isStopped = result is ServiceRequestSuccess;
    setState(() {
      _foregroundServiceRunning = !isStopped;
      _serviceManuallyStopped = isStopped;
    });
    if (isStopped) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('service_manually_stopped', true);
    }
  }

  void _showDeviceNameDialog() {
    final controller = TextEditingController(text: _deviceName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBg(context),
        title: Text(
          '设置设备名称',
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
            hintText: '设备名称',
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
              borderSide: const BorderSide(color: Color(0xFF007AFF)),
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: Color(0xFF007AFF))),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                _saveDeviceName(name);
                Navigator.pop(context);
              }
            },
            child: const Text(
              '保存',
              style: TextStyle(
                color: Color(0xFF007AFF),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  void _showAboutDialog() {
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
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: const Offset(0, 2),
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
              '通知推送助手',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryLabel(context),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'v${AppUpdateManager.instance.currentVersion} (build ${AppUpdateManager.instance.currentBuild})',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.secondaryLabel(context),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Text(
              '作者：幻念团队 fnthinklevi',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.primaryLabel(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '监听通知栏所有通知并推送到 Webhook',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.secondaryLabel(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '支持：微信 / QQ / 短信 / 来电 / 电量提醒',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.secondaryLabel(context),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              '好的',
              style: TextStyle(
                color: Color(0xFF007AFF),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  void _openRuleListPage() async {
    final result = await Navigator.push<List<NotificationRule>>(
      context,
      MaterialPageRoute(
        builder: (context) => RuleListPage(
          rules: _notificationRules,
          onSave: (rules) {
            setState(() {
              _notificationRules = rules;
            });
          },
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _notificationRules = result;
      });
    }
  }

  void _openPrivacyPolicyPage() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const PrivacyPolicyPage()));
  }

  void _showUpdateDialog(VersionCheckResult result) {
    showDialog(
      context: context,
      barrierDismissible: !result.forceUpdate,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBg(context),
        title: Column(
          children: [
            if (result.forceUpdate) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF3B30),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '重要更新',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              result.forceUpdate ? '必须更新才能继续使用' : '发现新版本',
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  '最新版本：',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
                Text(
                  'v${result.latestVersion} (build ${result.latestBuild})',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primaryLabel(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  '当前版本：',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
                Text(
                  'v${AppUpdateManager.instance.currentVersion} (build ${AppUpdateManager.instance.currentBuild})',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.primaryLabel(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  '文件大小：',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
                Text(
                  result.fileSizeStr,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.primaryLabel(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '更新内容',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryLabel(context),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.inputBg(context),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    result.changelog.replaceAll('\\n', '\n'),
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppColors.primaryLabel(context),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: result.forceUpdate
            ? [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _startDownloadUpdate(result),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF007AFF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      '立即更新',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ]
            : [
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          AppUpdateManager.instance.setIgnoredVersion(
                            result.latestVersion,
                          );
                        },
                        child: Text(
                          '忽略',
                          style: TextStyle(
                            color: AppColors.secondaryLabel(context),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          '稍后',
                          style: TextStyle(color: Color(0xFF007AFF)),
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: () => _startDownloadUpdate(result),
                        child: const Text(
                          '更新',
                          style: TextStyle(
                            color: Color(0xFF007AFF),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  void _startDownloadUpdate(VersionCheckResult result) {
    if (_isDownloading) return;
    Navigator.pop(context);
    final progressNotifier = ValueNotifier<double>(0);
    setState(() {
      _isDownloading = true;
    });

    showDialog(
      context: context,
      barrierDismissible: !result.forceUpdate,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBg(context),
        title: Text(
          '正在下载更新',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryLabel(context),
          ),
        ),
        content: ValueListenableBuilder<double>(
          valueListenable: progressNotifier,
          builder: (context, progress, child) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress > 0 ? progress : null,
                    minHeight: 6,
                    backgroundColor: AppColors.separator(context),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF007AFF),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${(progress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primaryLabel(context),
                  ),
                ),
              ],
            );
          },
        ),
        actions: result.forceUpdate
            ? []
            : [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    setState(() => _isDownloading = false);
                  },
                  child: const Text(
                    '取消',
                    style: TextStyle(color: Color(0xFFFF3B30)),
                  ),
                ),
              ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );

    AppUpdateManager.instance
        .downloadApk(
          result.downloadUrl,
          totalSize: result.fileSize,
          appName: result.appName,
          version: result.latestVersion,
          onProgress: (progress) {
            progressNotifier.value = progress;
            if (mounted) {
              setState(() {});
            }
          },
        )
        .then((filePath) {
          setState(() => _isDownloading = false);
          if (!mounted) return;
          Navigator.of(context, rootNavigator: true).pop();
          AppUpdateManager.instance.installApk(filePath);
        })
        .catchError((e) {
          setState(() => _isDownloading = false);
          if (!mounted) return;
          Navigator.of(context, rootNavigator: true).pop();
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('下载失败：${e.toString()}')));
        });
  }

  Future<void> _downloadAndApplyHotfix(HotfixCheckResult result) async {
    try {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('正在下载热更新包...')));

      final zipPath = await AppUpdateManager.instance.downloadHotfix(
        result.downloadUrl,
        totalSize: result.fileSize,
      );

      final success = await AppUpdateManager.instance.applyHotfix(
        zipPath,
        result.latestContentVersion,
      );

      if (!mounted) return;

      if (success) {
        try {
          await platform.invokeMethod('reloadHotfix');
        } catch (e) {
          debugPrint('通知服务重载热更新失败: $e');
        }
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('热更新完成，已生效')));
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('热更新失败')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('热更新失败：${e.toString()}')));
    }
  }

  Future<void> _manualCheckUpdate() async {
    setState(() => _isCheckingUpdate = true);
    final minWait = Future.delayed(const Duration(milliseconds: 500));
    try {
      await _performUpdateCheck(isManual: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('检查更新失败：${e.toString()}')));
      }
    } finally {
      await minWait;
      if (mounted) {
        setState(() => _isCheckingUpdate = false);
      }
    }
  }

  void _openHistoryPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HistoryPage(
          records: _notificationRecords,
          onClear: _clearNotificationRecords,
          onExport: _exportNotificationRecords,
        ),
      ),
    );
  }

  void _openPermissionSettingsPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PermissionSettingsPage(
          notificationPermissionGranted: _notificationPermissionGranted,
          batteryOptimizationIgnored: _batteryOptimizationIgnored,
          smsPermissionGranted: _smsPermissionGranted,
          phonePermissionGranted: _phonePermissionGranted,
          appListPermissionGranted: _appListPermissionGranted,
          manufacturer: _manufacturer,
          onRefresh: _checkPermissions,
          onRequestNotificationPermission: _requestNotificationPermission,
          onRequestBatteryOptimization: _requestBatteryOptimization,
          onRequestXiaomiAutoStart: _requestXiaomiAutoStart,
          onRequestMeizuBackground: _requestMeizuBackground,
          onRequestHuaweiLaunch: _requestHuaweiLaunch,
          onRequestOppoBackground: _requestOppoBackground,
          onRequestVivoBackground: _requestVivoBackground,
          onRequestSmsPermission: _requestSmsPermission,
          onRequestPhonePermission: _requestPhonePermission,
          onRequestAppListPermission: _requestAppListPermission,
        ),
      ),
    );
  }

  void _openAppFilterPage() async {
    final result = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (context) => AppFilterPage(
          installedApps: _installedApps,
          enabledPackages: _enabledPackages.toList(),
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _enabledPackages = Set<String>.from(result);
      });
      try {
        await platform.invokeMethod('setEnabledPackages', {'packages': result});
      } catch (e) {
        debugPrint('保存包名白名单失败: $e');
      }
    }
  }

  void _openKeywordsPage() async {
    final result = await Navigator.push<Map<String, List<String>>>(
      context,
      MaterialPageRoute(
        builder: (context) => KeywordsPage(
          blacklistKeywords: _blacklistKeywords,
          whitelistKeywords: _whitelistKeywords,
        ),
      ),
    );
    if (result != null) {
      final blacklist = result['blacklist'] ?? [];
      final whitelist = result['whitelist'] ?? [];
      setState(() {
        _blacklistKeywords = blacklist;
        _whitelistKeywords = whitelist;
      });
      try {
        await platform.invokeMethod('setBlacklistKeywords', {
          'keywords': blacklist,
        });
        await platform.invokeMethod('setWhitelistKeywords', {
          'keywords': whitelist,
        });
      } catch (e) {
        debugPrint('保存关键词失败: $e');
      }
    }
  }

  void _openWebhookSettingsPage() async {
    final result = await Navigator.push<List<Map<String, dynamic>>>(
      context,
      MaterialPageRoute(
        builder: (context) => WebhookSettingsPage(
          webhookChannels: List<Map<String, dynamic>>.from(_webhookChannels),
        ),
      ),
    );
    if (result != null) {
      await _saveWebhookChannels(result);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Webhook 配置已保存')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeNotifier = MyApp.of(context)?.themeModeNotifier;
    if (themeNotifier == null) {
      final pages = _buildPages();
      return Scaffold(
        body: IndexedStack(index: _currentIndex, children: pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.notifications),
              selectedIcon: Icon(Icons.notifications_active),
              label: '通知',
            ),
            NavigationDestination(
              icon: Icon(Icons.battery_full),
              selectedIcon: Icon(Icons.battery_charging_full),
              label: '电量',
            ),
            NavigationDestination(
              icon: Icon(Icons.more_horiz),
              selectedIcon: Icon(Icons.more_horiz),
              label: '更多',
            ),
          ],
        ),
      );
    }
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, mode, child) {
        final pages = _buildPages();
        return Scaffold(
          body: IndexedStack(index: _currentIndex, children: pages),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.notifications),
                selectedIcon: Icon(Icons.notifications_active),
                label: '通知',
              ),
              NavigationDestination(
                icon: Icon(Icons.battery_full),
                selectedIcon: Icon(Icons.battery_charging_full),
                label: '电量',
              ),
              NavigationDestination(
                icon: Icon(Icons.more_horiz),
                selectedIcon: Icon(Icons.more_horiz),
                label: '更多',
              ),
            ],
          ),
        );
      },
    );
  }
}

class NotificationTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('Foreground task started at $timestamp');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint(
      'Foreground task destroyed at $timestamp, isTimeout: $isTimeout',
    );
  }

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => MyAppState();

  static MyAppState? of(BuildContext context) {
    return context.findAncestorStateOfType<MyAppState>();
  }
}

class MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.system;
  final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier<ThemeMode>(
    ThemeMode.system,
  );

  ThemeMode get themeMode => _themeMode;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('theme_mode') ?? 'system';
    final newMode = switch (mode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    setState(() {
      _themeMode = newMode;
    });
    themeModeNotifier.value = newMode;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    setState(() {
      _themeMode = mode;
    });
    themeModeNotifier.value = mode;
    final prefs = await SharedPreferences.getInstance();
    final modeStr = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await prefs.setString('theme_mode', modeStr);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '通知推送助手',
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      themeMode: _themeMode,
      home: const SplashPage(),
    );
  }

  ThemeData _buildLightTheme() {
    final colors = AppThemeColors.light();
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: colors.systemBlue,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: colors.bgColor,
      extensions: <ThemeExtension<dynamic>>[colors],
      appBarTheme: AppBarTheme(
        backgroundColor: colors.bgColor,
        foregroundColor: colors.primaryLabel,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: colors.primaryLabel,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        minLeadingWidth: 32,
        iconColor: colors.systemBlue,
      ),
      dividerTheme: DividerThemeData(
        color: colors.separator,
        space: 1,
        thickness: 0.5,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return Colors.grey.shade200;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.systemGreen;
          }
          return Colors.grey.shade300;
        }),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.cardBg.withValues(alpha: 0.95),
        elevation: 0,
        height: 64,
        indicatorColor: colors.systemBlue.withValues(alpha: 0.1),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: colors.systemBlue,
            );
          }
          return TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: colors.secondaryLabel,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: colors.systemBlue);
          }
          return IconThemeData(color: colors.secondaryLabel);
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.inputBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colors.systemBlue, width: 1.5),
        ),
        hintStyle: TextStyle(color: colors.tertiaryLabel),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.cardBg,
        contentTextStyle: TextStyle(color: colors.primaryLabel),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
        elevation: 4,
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    final colors = AppThemeColors.dark();
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: colors.systemBlue,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: colors.bgColor,
      extensions: <ThemeExtension<dynamic>>[colors],
      appBarTheme: AppBarTheme(
        backgroundColor: colors.bgColor,
        foregroundColor: colors.primaryLabel,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: colors.primaryLabel,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        minLeadingWidth: 32,
        iconColor: colors.systemBlue,
      ),
      dividerTheme: DividerThemeData(
        color: colors.separator,
        space: 1,
        thickness: 0.5,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return Colors.grey.shade400;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.systemGreen;
          }
          return Colors.grey.shade700;
        }),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.cardBg.withValues(alpha: 0.95),
        elevation: 0,
        height: 64,
        indicatorColor: colors.systemBlue.withValues(alpha: 0.3),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: colors.systemBlue,
            );
          }
          return TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: colors.secondaryLabel,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: colors.systemBlue);
          }
          return IconThemeData(color: colors.secondaryLabel);
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.inputBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colors.systemBlue, width: 1.5),
        ),
        hintStyle: TextStyle(color: colors.tertiaryLabel),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.cardBg,
        contentTextStyle: TextStyle(color: colors.primaryLabel),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
        elevation: 4,
      ),
    );
  }
}

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 666), () {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) =>
                  const MainPage(),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                    return FadeTransition(opacity: animation, child: child);
                  },
              transitionDuration: const Duration(milliseconds: 300),
            ),
          );
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark =
        MyApp.of(context)?.themeMode == ThemeMode.dark ||
        (MyApp.of(context)?.themeMode == ThemeMode.system &&
            MediaQuery.of(context).platformBrightness == Brightness.dark);
    final bgColor = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFFFFFFF);
    final textColor = isDark
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF1C1C1E);
    final secondaryColor = isDark
        ? const Color(0xFF8E8E93)
        : const Color(0xFF8E8E93);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            Center(
              child: Column(
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF007AFF).withValues(alpha: 0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Image.asset(
                        'assets/app_icon.png',
                        width: 96,
                        height: 96,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '通知推送助手',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: Text(
                '幻念团队',
                style: TextStyle(
                  fontSize: 13,
                  color: secondaryColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
