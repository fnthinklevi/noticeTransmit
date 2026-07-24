import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/services.dart';
import '../services/theme_service.dart';
import '../update_manager.dart';
import '../models/notification_rule.dart';
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
  bool _isCheckingUpdate = false;
  bool _isDownloading = false;

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

  List<Widget> _buildPages() {
    return [
      NotificationPage(
        notificationPermissionGranted:
            _permissionService.notificationListenerGranted,
        foregroundServiceRunning: _notificationService.serviceRunning,
        notificationCount: _notificationService.records.length,
        onStartService: _startForegroundService,
        onStopService: _stopForegroundService,
        onRefresh: _checkPermissions,
        onOpenHistory: _openHistoryPage,
        onOpenPermissionSettings: _openPermissionSettingsPage,
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

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final hasLaunched = prefs.getBool('has_launched') ?? false;
    if (!hasLaunched) {
      await prefs.setBool('has_launched', true);
      if (!_permissionService.notificationListenerGranted) {
        if (mounted) {
          _showPermissionGuideDialog();
        }
      }
    }
  }

  void _showPermissionGuideDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBg(context),
        title: Column(
          children: [
            const Icon(
              Icons.notifications_active,
              size: 48,
              color: AppColors.blue,
            ),
            const SizedBox(height: 12),
            Text(
              '需要必要权限',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryLabel(context),
              ),
            ),
          ],
        ),
        content: Text(
          '为了正常监听和推送通知，需要开启「通知访问权限」。请点击下方按钮前往设置开启。',
          style: TextStyle(
            fontSize: 14,
            color: AppColors.primaryLabel(context),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '稍后',
              style: TextStyle(color: AppColors.secondaryLabel(context)),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _openPermissionSettingsPage();
            },
            child: const Text(
              '去设置',
              style: TextStyle(
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

  @override
  void dispose() {
    _batteryService.stopRefreshTimer();
    super.dispose();
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
    platform.setMethodCallHandler((call) async {
      if (call.method == 'onNotificationReceived') {
        final Map<String, dynamic> record = Map<String, dynamic>.from(
          call.arguments,
        );
        _notificationService.addRecord(record);
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

  Future<void> _checkUpdateOnStartup() async {
    final result = await _updateService.checkUpdate(force: false);
    if (!mounted) return;
    if (result != null && result.hasUpdate) {
      final ignored = await _updateService.getIgnoredVersion();
      if (ignored != result.latestVersion) {
        _showUpdateDialog(result);
      }
    }
  }

  Future<void> _performUpdateCheck({bool isManual = false}) async {
    if (!mounted) return;

    final result = await _updateService.checkUpdate(force: isManual);

    if (!mounted) return;

    if (result != null) {
      if (result.hasUpdate) {
        if (!isManual && !result.forceUpdate) {
          final ignored = await _updateService.getIgnoredVersion();
          if (ignored == result.latestVersion) {
            return;
          }
        }
        _showUpdateDialog(result);
      } else if (isManual) {
        _showInfo('当前已是最新版本');
      }
    } else if (isManual) {
      final error = _updateService.lastError;
      final errorMsg = error != null && error.isNotEmpty
          ? '检查更新失败：$error'
          : '检查更新失败，请检查网络连接';
      _showInfo(errorMsg);
    }
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
    await _notificationService.startService();
    setState(() {});
  }

  Future<void> _stopForegroundService() async {
    await _notificationService.stopService();
    setState(() {});
  }

  void _showDeviceNameDialog() {
    final controller = TextEditingController(
      text: _deviceInfoService.deviceName,
    );
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: AppColors.blue)),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                _deviceInfoService.saveDeviceName(name);
                setState(() {});
                Navigator.pop(context);
              }
            },
            child: const Text(
              '保存',
              style: TextStyle(
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
              '通知推送助手',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryLabel(context),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'v${_updateService.currentVersion} (build ${_updateService.currentBuild})',
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
                  color: AppColors.red,
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
                  'v${_updateService.currentVersion} (build ${_updateService.currentBuild})',
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
                      backgroundColor: AppColors.blue,
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
                          _updateService.setIgnoredVersion(
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
                          style: TextStyle(color: AppColors.blue),
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: () => _startDownloadUpdate(result),
                        child: const Text(
                          '更新',
                          style: TextStyle(
                            color: AppColors.blue,
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

  Future<bool> _ensureStoragePermissionForUpdate() async {
    final granted = await _updateService.storagePermissionGranted();
    if (granted) return true;
    if (!mounted) return false;

    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBg(context),
        title: Column(
          children: [
            const Icon(Icons.folder_outlined, size: 44, color: AppColors.blue),
            const SizedBox(height: 12),
            Text(
              '需要存储权限',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryLabel(context),
              ),
            ),
          ],
        ),
        content: Text(
          '在线更新需要将安装包保存到 Download/FnthinkNotice 目录，请先授予存储权限后再下载更新。',
          style: TextStyle(
            fontSize: 14,
            color: AppColors.primaryLabel(context),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              '取消',
              style: TextStyle(color: AppColors.secondaryLabel(context)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              '去开启',
              style: TextStyle(
                color: AppColors.blue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );

    if (agreed != true) return false;

    final result = await _updateService.requestStoragePermission();
    if (!result && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('未获得存储权限，无法下载更新')));
    }
    return result;
  }

  Future<void> _startDownloadUpdate(VersionCheckResult result) async {
    if (_isDownloading) return;

    // 下载前先检测本地存储权限，若无则引导用户开启
    final hasStorage = await _ensureStoragePermissionForUpdate();
    if (!hasStorage || !mounted) return;

    Navigator.pop(context);
    final progressNotifier = ValueNotifier<double>(0);
    setState(() => _isDownloading = true);

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
                      AppColors.blue,
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
                    style: TextStyle(color: AppColors.red),
                  ),
                ),
              ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );

    _updateService
        .downloadApk(
          result.downloadUrl,
          totalSize: result.fileSize,
          appName: result.appName,
          version: result.latestVersion,
          onProgress: (progress) {
            progressNotifier.value = progress;
            if (mounted) setState(() {});
          },
        )
        .then((filePath) {
          setState(() => _isDownloading = false);
          if (!mounted) return;
          Navigator.of(context, rootNavigator: true).pop();
          if (filePath != null) _updateService.installApk(filePath);
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

  Future<void> _manualCheckUpdate() async {
    setState(() => _isCheckingUpdate = true);
    final minWait = Future.delayed(const Duration(milliseconds: 500));
    try {
      await _performUpdateCheck(isManual: true);
    } catch (e) {
      if (mounted) {
        _showInfo('检查更新失败：${e.toString()}');
      }
    } finally {
      await minWait;
      if (mounted) setState(() => _isCheckingUpdate = false);
    }
  }

  void _openHistoryPage() {
    _pushPage(
      HistoryPage(
        records: _notificationService.records,
        onClear: () async {
          await _notificationService.clearRecords();
          setState(() {});
        },
        onExport: () async {
          // 安全确认：导出前弹出对话框验证用户意图
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('确认导出'),
              content: const Text(
                '通知记录将导出为 JSON 文件，包含通知内容和设备信息。\n\n'
                '文件将保存到外部存储，建议在导出后妥善保管或及时删除。\n\n确定要导出吗？',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('确定导出'),
                ),
              ],
            ),
          );
          if (confirm != true) return '';
          final path = await _notificationService.exportRecords(
            _deviceInfoService.deviceName,
            _deviceInfoService.deviceModel,
            _deviceInfoService.manufacturer,
          );
          return path;
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
      _showInfo('Webhook 配置已保存');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = _buildPages();
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          setState(() => _currentIndex = index);
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
}
