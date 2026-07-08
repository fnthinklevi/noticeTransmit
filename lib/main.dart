import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'update_manager.dart';

typedef NotificationRecord = Map<String, dynamic>;

class AppThemeColors extends ThemeExtension<AppThemeColors> {
  final Color bgColor;
  final Color cardBg;
  final Color separator;
  final Color primaryLabel;
  final Color secondaryLabel;
  final Color tertiaryLabel;
  final Color inputBg;
  final Color systemBlue;
  final Color systemGreen;
  final Color systemOrange;
  final Color systemRed;
  final Color systemPurple;
  final Color systemCyan;
  final Color systemYellow;

  const AppThemeColors({
    required this.bgColor,
    required this.cardBg,
    required this.separator,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.tertiaryLabel,
    required this.inputBg,
    required this.systemBlue,
    required this.systemGreen,
    required this.systemOrange,
    required this.systemRed,
    required this.systemPurple,
    required this.systemCyan,
    required this.systemYellow,
  });

  factory AppThemeColors.light() {
    return const AppThemeColors(
      bgColor: Color(0xFFF2F2F7),
      cardBg: Color(0xFFFFFFFF),
      separator: Color(0xFFE5E5EA),
      primaryLabel: Color(0xFF000000),
      secondaryLabel: Color(0xFF8E8E93),
      tertiaryLabel: Color(0xFFC7C7CC),
      inputBg: Color(0xFFF2F2F7),
      systemBlue: Color(0xFF007AFF),
      systemGreen: Color(0xFF34C759),
      systemOrange: Color(0xFFFF9500),
      systemRed: Color(0xFFFF3B30),
      systemPurple: Color(0xFFAF52DE),
      systemCyan: Color(0xFF5AC8FA),
      systemYellow: Color(0xFFFFCC00),
    );
  }

  factory AppThemeColors.dark() {
    return const AppThemeColors(
      bgColor: Color(0xFF000000),
      cardBg: Color(0xFF1C1C1E),
      separator: Color(0xFF38383A),
      primaryLabel: Color(0xFFFFFFFF),
      secondaryLabel: Color(0xFF8E8E93),
      tertiaryLabel: Color(0xFF48484A),
      inputBg: Color(0xFF2C2C2E),
      systemBlue: Color(0xFF0A84FF),
      systemGreen: Color(0xFF30D158),
      systemOrange: Color(0xFFFF9F0A),
      systemRed: Color(0xFFFF453A),
      systemPurple: Color(0xFFBF5AF2),
      systemCyan: Color(0xFF64D2FF),
      systemYellow: Color(0xFFFFD60A),
    );
  }

  @override
  ThemeExtension<AppThemeColors> copyWith({
    Color? bgColor,
    Color? cardBg,
    Color? separator,
    Color? primaryLabel,
    Color? secondaryLabel,
    Color? tertiaryLabel,
    Color? inputBg,
    Color? systemBlue,
    Color? systemGreen,
    Color? systemOrange,
    Color? systemRed,
    Color? systemPurple,
    Color? systemCyan,
    Color? systemYellow,
  }) {
    return AppThemeColors(
      bgColor: bgColor ?? this.bgColor,
      cardBg: cardBg ?? this.cardBg,
      separator: separator ?? this.separator,
      primaryLabel: primaryLabel ?? this.primaryLabel,
      secondaryLabel: secondaryLabel ?? this.secondaryLabel,
      tertiaryLabel: tertiaryLabel ?? this.tertiaryLabel,
      inputBg: inputBg ?? this.inputBg,
      systemBlue: systemBlue ?? this.systemBlue,
      systemGreen: systemGreen ?? this.systemGreen,
      systemOrange: systemOrange ?? this.systemOrange,
      systemRed: systemRed ?? this.systemRed,
      systemPurple: systemPurple ?? this.systemPurple,
      systemCyan: systemCyan ?? this.systemCyan,
      systemYellow: systemYellow ?? this.systemYellow,
    );
  }

  @override
  ThemeExtension<AppThemeColors> lerp(
    ThemeExtension<AppThemeColors>? other,
    double t,
  ) {
    if (other is! AppThemeColors) return this;
    return AppThemeColors(
      bgColor: Color.lerp(bgColor, other.bgColor, t)!,
      cardBg: Color.lerp(cardBg, other.cardBg, t)!,
      separator: Color.lerp(separator, other.separator, t)!,
      primaryLabel: Color.lerp(primaryLabel, other.primaryLabel, t)!,
      secondaryLabel: Color.lerp(secondaryLabel, other.secondaryLabel, t)!,
      tertiaryLabel: Color.lerp(tertiaryLabel, other.tertiaryLabel, t)!,
      inputBg: Color.lerp(inputBg, other.inputBg, t)!,
      systemBlue: Color.lerp(systemBlue, other.systemBlue, t)!,
      systemGreen: Color.lerp(systemGreen, other.systemGreen, t)!,
      systemOrange: Color.lerp(systemOrange, other.systemOrange, t)!,
      systemRed: Color.lerp(systemRed, other.systemRed, t)!,
      systemPurple: Color.lerp(systemPurple, other.systemPurple, t)!,
      systemCyan: Color.lerp(systemCyan, other.systemCyan, t)!,
      systemYellow: Color.lerp(systemYellow, other.systemYellow, t)!,
    );
  }
}

class AppColors {
  static AppThemeColors of(BuildContext context) {
    return Theme.of(context).extension<AppThemeColors>() ??
        AppThemeColors.light();
  }

  static bool isDark(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  static Color bgColor(BuildContext context) => of(context).bgColor;
  static Color cardBg(BuildContext context) => of(context).cardBg;
  static Color separator(BuildContext context) => of(context).separator;
  static Color primaryLabel(BuildContext context) => of(context).primaryLabel;
  static Color secondaryLabel(BuildContext context) =>
      of(context).secondaryLabel;
  static Color tertiaryLabel(BuildContext context) => of(context).tertiaryLabel;
  static Color inputBg(BuildContext context) => of(context).inputBg;
  static Color systemBlue(BuildContext context) => of(context).systemBlue;
  static Color systemGreen(BuildContext context) => of(context).systemGreen;
  static Color systemOrange(BuildContext context) => of(context).systemOrange;
  static Color systemRed(BuildContext context) => of(context).systemRed;
  static Color systemPurple(BuildContext context) => of(context).systemPurple;
  static Color systemCyan(BuildContext context) => of(context).systemCyan;
  static Color systemYellow(BuildContext context) => of(context).systemYellow;
}

void main() {
  runApp(const MyApp());
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
          result.map((e) => Map<String, dynamic>.from(e)).toList(),
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
              list.map((e) => Map<String, dynamic>.from(e)).toList(),
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
      _notificationRecords.take(_maxRecords).toList(),
    );
    await prefs.setString('notification_records', recordsJson);
  }

  void _addNotificationRecord(Map<String, dynamic> record) {
    setState(() {
      _notificationRecords.insert(0, record);
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
      'records': _notificationRecords,
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
                color: const Color(0xFF007AFF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.notifications_active,
                size: 32,
                color: Colors.white,
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

class PermissionSettingsPage extends StatefulWidget {
  final bool notificationPermissionGranted;
  final bool batteryOptimizationIgnored;
  final bool smsPermissionGranted;
  final bool phonePermissionGranted;
  final bool appListPermissionGranted;
  final String manufacturer;
  final Future<void> Function() onRefresh;
  final VoidCallback onRequestNotificationPermission;
  final VoidCallback onRequestBatteryOptimization;
  final VoidCallback onRequestXiaomiAutoStart;
  final VoidCallback onRequestMeizuBackground;
  final VoidCallback onRequestHuaweiLaunch;
  final VoidCallback onRequestOppoBackground;
  final VoidCallback onRequestVivoBackground;
  final VoidCallback onRequestSmsPermission;
  final VoidCallback onRequestPhonePermission;
  final VoidCallback onRequestAppListPermission;

  const PermissionSettingsPage({
    super.key,
    required this.notificationPermissionGranted,
    required this.batteryOptimizationIgnored,
    required this.smsPermissionGranted,
    required this.phonePermissionGranted,
    required this.appListPermissionGranted,
    required this.manufacturer,
    required this.onRefresh,
    required this.onRequestNotificationPermission,
    required this.onRequestBatteryOptimization,
    required this.onRequestXiaomiAutoStart,
    required this.onRequestMeizuBackground,
    required this.onRequestHuaweiLaunch,
    required this.onRequestOppoBackground,
    required this.onRequestVivoBackground,
    required this.onRequestSmsPermission,
    required this.onRequestPhonePermission,
    required this.onRequestAppListPermission,
  });

  @override
  State<PermissionSettingsPage> createState() => _PermissionSettingsPageState();
}

class _PermissionSettingsPageState extends State<PermissionSettingsPage> {
  bool get _isXiaomi =>
      widget.manufacturer.toLowerCase().contains('xiaomi') ||
      widget.manufacturer.toLowerCase().contains('redmi') ||
      widget.manufacturer.toLowerCase().contains('mi ');

  bool get _isMeizu => widget.manufacturer.toLowerCase().contains('meizu');

  bool get _isHuawei =>
      widget.manufacturer.toLowerCase().contains('huawei') ||
      widget.manufacturer.toLowerCase().contains('honor');

  bool get _isOppo =>
      widget.manufacturer.toLowerCase().contains('oppo') ||
      widget.manufacturer.toLowerCase().contains('realme') ||
      widget.manufacturer.toLowerCase().contains('oneplus');

  bool get _isVivo =>
      widget.manufacturer.toLowerCase().contains('vivo') ||
      widget.manufacturer.toLowerCase().contains('iqoo');

  bool get _isSamsung => widget.manufacturer.toLowerCase().contains('samsung');

  bool get _isStockAndroid =>
      widget.manufacturer.toLowerCase().contains('google') ||
      widget.manufacturer.toLowerCase().contains('android') ||
      !_isXiaomi &&
          !_isMeizu &&
          !_isHuawei &&
          !_isOppo &&
          !_isVivo &&
          !_isSamsung;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('权限设置')),
      body: RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _buildSectionHeader('必要权限', context),
            _buildGroup([
              _buildPermissionTile(
                icon: Icons.notifications_active,
                title: '通知访问权限',
                subtitle: widget.notificationPermissionGranted ? '已开启' : '未开启',
                isOn: widget.notificationPermissionGranted,
                onTap: widget.notificationPermissionGranted
                    ? null
                    : widget.onRequestNotificationPermission,
                context: context,
              ),
              _buildDivider(context),
              _buildPermissionTile(
                icon: Icons.battery_full,
                title: '忽略电池优化',
                subtitle: widget.batteryOptimizationIgnored ? '已开启' : '未开启',
                isOn: widget.batteryOptimizationIgnored,
                onTap: widget.batteryOptimizationIgnored
                    ? null
                    : widget.onRequestBatteryOptimization,
                context: context,
              ),
            ], context),
            const SizedBox(height: 24),
            if (_isXiaomi ||
                _isMeizu ||
                _isHuawei ||
                _isOppo ||
                _isVivo ||
                _isSamsung ||
                _isStockAndroid) ...[
              _buildSectionHeader('厂商后台设置', context),
              _buildGroup([
                if (_isXiaomi)
                  _buildPermissionTile(
                    icon: Icons.rocket_launch,
                    title: '小米自启动',
                    subtitle: '点击前往设置',
                    isOn: false,
                    onTap: widget.onRequestXiaomiAutoStart,
                    isWarning: true,
                    context: context,
                  ),
                if (_isMeizu)
                  _buildPermissionTile(
                    icon: Icons.rocket_launch,
                    title: '魅族后台运行',
                    subtitle: '点击前往设置',
                    isOn: false,
                    onTap: widget.onRequestMeizuBackground,
                    isWarning: true,
                    context: context,
                  ),
                if (_isHuawei)
                  _buildPermissionTile(
                    icon: Icons.rocket_launch,
                    title: '华为自启动/受保护应用',
                    subtitle: '点击前往设置',
                    isOn: false,
                    onTap: widget.onRequestHuaweiLaunch,
                    isWarning: true,
                    context: context,
                  ),
                if (_isOppo)
                  _buildPermissionTile(
                    icon: Icons.rocket_launch,
                    title: 'OPPO自启动管理',
                    subtitle: '点击前往设置',
                    isOn: false,
                    onTap: widget.onRequestOppoBackground,
                    isWarning: true,
                    context: context,
                  ),
                if (_isVivo)
                  _buildPermissionTile(
                    icon: Icons.rocket_launch,
                    title: 'vivo后台启动管理',
                    subtitle: '点击前往设置',
                    isOn: false,
                    onTap: widget.onRequestVivoBackground,
                    isWarning: true,
                    context: context,
                  ),
                if (_isSamsung)
                  _buildPermissionTile(
                    icon: Icons.info_outline,
                    title: '三星设备设置',
                    subtitle: '请在智能管理器中将本应用加入自启动白名单',
                    isOn: false,
                    onTap: null,
                    isWarning: true,
                    context: context,
                  ),
                if (_isStockAndroid)
                  _buildPermissionTile(
                    icon: Icons.info_outline,
                    title: '原生Android设置',
                    subtitle: '请在系统设置中确认电池优化已关闭',
                    isOn: false,
                    onTap: null,
                    isWarning: true,
                    context: context,
                  ),
              ], context),
              const SizedBox(height: 24),
            ],
            _buildSectionHeader('非必要权限', context),
            _buildGroup([
              _buildPermissionTile(
                icon: Icons.message,
                title: '短信权限',
                subtitle: widget.smsPermissionGranted ? '已开启' : '未开启',
                isOn: widget.smsPermissionGranted,
                onTap: widget.smsPermissionGranted
                    ? null
                    : widget.onRequestSmsPermission,
                context: context,
              ),
              _buildDivider(context),
              _buildPermissionTile(
                icon: Icons.call,
                title: '电话权限',
                subtitle: widget.phonePermissionGranted ? '已开启' : '未开启',
                isOn: widget.phonePermissionGranted,
                onTap: widget.phonePermissionGranted
                    ? null
                    : widget.onRequestPhonePermission,
                context: context,
              ),
              _buildDivider(context),
              _buildPermissionTile(
                icon: Icons.apps,
                title: '应用列表权限',
                subtitle: widget.appListPermissionGranted ? '已开启' : '未开启',
                isOn: widget.appListPermissionGranted,
                onTap: widget.appListPermissionGranted
                    ? null
                    : widget.onRequestAppListPermission,
                context: context,
              ),
            ], context),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '非必要权限用于提升特定功能的准确性，不开启不影响核心功能使用',
                style: TextStyle(
                  color: AppColors.secondaryLabel(context),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
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

  Widget _buildPermissionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isOn,
    required VoidCallback? onTap,
    required BuildContext context,
    bool isWarning = false,
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
                color: isOn
                    ? const Color(0xFF34C759)
                    : isWarning
                    ? const Color(0xFFFF9500)
                    : const Color(0xFF007AFF),
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
            if (onTap != null)
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

class NotificationPage extends StatelessWidget {
  final bool notificationPermissionGranted;
  final bool foregroundServiceRunning;
  final int notificationCount;
  final VoidCallback onStartService;
  final VoidCallback onStopService;
  final Future<void> Function() onRefresh;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenPermissionSettings;

  const NotificationPage({
    super.key,
    required this.notificationPermissionGranted,
    required this.foregroundServiceRunning,
    required this.notificationCount,
    required this.onStartService,
    required this.onStopService,
    required this.onRefresh,
    required this.onOpenHistory,
    required this.onOpenPermissionSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('通知推送助手')),
      body: RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
          children: [
            const SizedBox(height: 40),
            Center(
              child: GestureDetector(
                onTap: foregroundServiceRunning
                    ? onStopService
                    : onStartService,
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: foregroundServiceRunning
                        ? const Color(0xFF34C759)
                        : const Color(0xFFFF3B30),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (foregroundServiceRunning
                                    ? const Color(0xFF34C759)
                                    : const Color(0xFFFF3B30))
                                .withValues(alpha: 0.3),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        foregroundServiceRunning
                            ? Icons.notifications_active
                            : Icons.notifications_off,
                        size: 48,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        foregroundServiceRunning ? '运行中' : '已停止',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                foregroundServiceRunning
                    ? '通知监听服务正在运行，点击可停止'
                    : '通知监听服务未启动，点击可启动',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
            ),
            const SizedBox(height: 40),
            _buildQuickAction(
              icon: Icons.settings,
              iconColor: const Color(0xFF007AFF),
              title: '权限设置',
              subtitle: '配置通知、电池、后台运行等权限',
              onTap: onOpenPermissionSettings,
              context: context,
            ),
            const SizedBox(height: 12),
            _buildQuickAction(
              icon: Icons.history,
              iconColor: const Color(0xFF34C759),
              title: '推送历史',
              subtitle: '共 $notificationCount 条记录',
              onTap: onOpenHistory,
              context: context,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required BuildContext context,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.cardBg(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 22, color: iconColor),
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
                      fontWeight: FontWeight.w600,
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

class BatteryPage extends StatefulWidget {
  final bool notifyEnabled;
  final List<Map<String, dynamic>> rules;
  final int currentLevel;
  final bool isCharging;
  final ValueChanged<bool> onToggleNotify;
  final void Function(Map<String, dynamic>) onAddRule;
  final void Function(String) onDeleteRule;
  final void Function(String, Map<String, dynamic>) onUpdateRule;
  final void Function(String, bool) onToggleRule;
  final Future<void> Function() onRefresh;

  const BatteryPage({
    super.key,
    required this.notifyEnabled,
    required this.rules,
    required this.currentLevel,
    required this.isCharging,
    required this.onToggleNotify,
    required this.onAddRule,
    required this.onDeleteRule,
    required this.onUpdateRule,
    required this.onToggleRule,
    required this.onRefresh,
  });

  @override
  State<BatteryPage> createState() => _BatteryPageState();
}

class _BatteryPageState extends State<BatteryPage> {
  @override
  Widget build(BuildContext context) {
    final batteryColor = widget.currentLevel >= 50
        ? const Color(0xFF34C759)
        : widget.currentLevel >= 20
        ? const Color(0xFFFF9500)
        : const Color(0xFFFF3B30);

    return Scaffold(
      appBar: AppBar(
        title: const Text('电量'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加规则',
            onPressed: widget.notifyEnabled ? _showAddRuleDialog : null,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const SizedBox(height: 16),
            Center(
              child: Column(
                children: [
                  Icon(
                    widget.isCharging
                        ? Icons.battery_charging_full
                        : Icons.battery_full,
                    size: 80,
                    color: batteryColor,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.currentLevel < 0 ? '未知' : '${widget.currentLevel}%',
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w300,
                      color: batteryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.isCharging ? '充电中' : '未充电',
                    style: TextStyle(
                      fontSize: 15,
                      color: AppColors.secondaryLabel(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            _buildSectionHeader('提醒设置', context),
            _buildGroup([
              _buildSwitchRow(
                icon: Icons.power_settings_new,
                iconColor: const Color(0xFF007AFF),
                title: '电量通知总开关',
                subtitle: '开启后以下提醒才会生效',
                value: widget.notifyEnabled,
                onChanged: widget.onToggleNotify,
                context: context,
              ),
            ], context),
            const SizedBox(height: 24),
            _buildSectionHeader('通知规则', context),
            _buildGroup(
              widget.rules.asMap().entries.map((entry) {
                final index = entry.key;
                final rule = entry.value;
                return Column(
                  children: [
                    if (index > 0) _buildDivider(context),
                    _buildRuleTile(rule, context),
                  ],
                );
              }).toList(),
              context,
            ),
            const SizedBox(height: 24),
            _buildSectionHeader('说明', context),
            _buildGroup([
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DescRow(text: '低电量提醒仅在非充电状态下触发', context: context),
                    const SizedBox(height: 8),
                    _DescRow(text: '电量回升到阈值以上才会重置提醒状态', context: context),
                    const SizedBox(height: 8),
                    _DescRow(text: '电量通知随通知监听服务一起运行', context: context),
                    const SizedBox(height: 8),
                    _DescRow(text: '点击规则可编辑，左滑或长按可删除', context: context),
                  ],
                ),
              ),
            ], context),
          ],
        ),
      ),
    );
  }

  Widget _buildRuleTile(Map<String, dynamic> rule, BuildContext context) {
    final type = rule['type'] as String;
    final value = rule['value'] as int;
    final enabled = rule['enabled'] as bool;
    final title = rule['title'] as String;

    IconData icon;
    Color iconColor;
    String subtitle;

    switch (type) {
      case 'charging':
        icon = Icons.battery_charging_full;
        iconColor = const Color(0xFF34C759);
        subtitle = '手机接入充电器时推送';
        break;
      case 'discharging':
        icon = Icons.battery_0_bar;
        iconColor = const Color(0xFFFF9500);
        subtitle = '手机断开充电器时推送';
        break;
      case 'level_above':
        icon = Icons.battery_full;
        iconColor = const Color(0xFF007AFF);
        subtitle = '电量达到 $value% 时推送';
        break;
      case 'level_below':
        icon = Icons.battery_alert;
        iconColor = const Color(0xFFFF3B30);
        subtitle = '电量低于 $value% 时推送';
        break;
      case 'level_equals':
        icon = Icons.equalizer;
        iconColor = const Color(0xFFAF52DE);
        subtitle = '电量等于 $value% 时推送';
        break;
      default:
        icon = Icons.help_outline;
        iconColor = Colors.grey;
        subtitle = '未知规则类型';
    }

    return InkWell(
      onTap: widget.notifyEnabled && enabled
          ? () => _showEditRuleDialog(rule)
          : null,
      child: _buildSwitchRow(
        icon: icon,
        iconColor: iconColor,
        title: title,
        subtitle: subtitle,
        value: enabled,
        onChanged: widget.notifyEnabled
            ? (v) => widget.onToggleRule(rule['id'] as String, v)
            : null,
        context: context,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              color: AppColors.secondaryLabel(context),
              onPressed: widget.notifyEnabled
                  ? () => _showDeleteConfirmDialog(rule['id'] as String)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  void _showAddRuleDialog() {
    _showRuleDialog(null);
  }

  void _showEditRuleDialog(Map<String, dynamic> rule) {
    _showRuleDialog(rule);
  }

  void _showRuleDialog(Map<String, dynamic>? existingRule) {
    final isEdit = existingRule != null;
    final typeController = TextEditingController(
      text: existingRule?['type'] ?? 'level_below',
    );
    final valueController = TextEditingController(
      text: (existingRule?['value'] ?? 20).toString(),
    );
    final titleController = TextEditingController(
      text: existingRule?['title'] ?? '',
    );
    String selectedType = existingRule?['type'] ?? 'level_below';
    int selectedValue = existingRule?['value'] ?? 20;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isEdit ? '编辑规则' : '添加规则'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '规则类型',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildTypeChip(
                          'charging',
                          '开始充电',
                          selectedType,
                          setDialogState,
                          typeController,
                        ),
                        _buildTypeChip(
                          'discharging',
                          '断开充电',
                          selectedType,
                          setDialogState,
                          typeController,
                        ),
                        _buildTypeChip(
                          'level_below',
                          '低于某值',
                          selectedType,
                          setDialogState,
                          typeController,
                        ),
                        _buildTypeChip(
                          'level_above',
                          '高于某值',
                          selectedType,
                          setDialogState,
                          typeController,
                        ),
                        _buildTypeChip(
                          'level_equals',
                          '等于某值',
                          selectedType,
                          setDialogState,
                          typeController,
                        ),
                      ],
                    ),
                    if ([
                      'level_below',
                      'level_above',
                      'level_equals',
                    ].contains(selectedType)) ...[
                      const SizedBox(height: 16),
                      const Text(
                        '电量阈值（%）',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Slider(
                              value: selectedValue.toDouble(),
                              min: 1,
                              max: 100,
                              divisions: 99,
                              label: '$selectedValue%',
                              onChanged: (v) {
                                setDialogState(() {
                                  selectedValue = v.round();
                                  valueController.text = selectedValue
                                      .toString();
                                });
                              },
                            ),
                          ),
                          SizedBox(
                            width: 50,
                            child: Text(
                              '$selectedValue%',
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    const Text(
                      '自定义标题（可选）',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        hintText: '留空则使用默认标题',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () {
                    final id = isEdit
                        ? existingRule['id'] as String
                        : 'rule_${DateTime.now().millisecondsSinceEpoch}';
                    final newRule = {
                      'id': id,
                      'type': selectedType,
                      'value': selectedValue,
                      'enabled': existingRule?['enabled'] ?? true,
                      'title': titleController.text.trim().isNotEmpty
                          ? titleController.text.trim()
                          : _defaultTitleForType(selectedType, selectedValue),
                      'content': '',
                    };
                    if (isEdit) {
                      widget.onUpdateRule(id, newRule);
                    } else {
                      widget.onAddRule(newRule);
                    }
                    Navigator.pop(context);
                  },
                  child: Text(isEdit ? '保存' : '添加'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildTypeChip(
    String type,
    String label,
    String selectedType,
    StateSetter setDialogState,
    TextEditingController controller,
  ) {
    final isSelected = selectedType == type;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setDialogState(() {
            controller.text = type;
          });
        }
      },
    );
  }

  String _defaultTitleForType(String type, int value) {
    switch (type) {
      case 'charging':
        return '开始充电';
      case 'discharging':
        return '断开充电';
      case 'level_above':
        return '电量达到$value%';
      case 'level_below':
        return '电量低于$value%';
      case 'level_equals':
        return '电量等于$value%';
      default:
        return '电量提醒';
    }
  }

  void _showDeleteConfirmDialog(String id) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除规则'),
          content: const Text('确定要删除这条通知规则吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFFF3B30),
              ),
              onPressed: () {
                widget.onDeleteRule(id);
                Navigator.pop(context);
              },
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
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

  Widget _buildSwitchRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
    required BuildContext context,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                    fontSize: 12,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
              ],
            ),
          ),
          trailing ?? const SizedBox.shrink(),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(title: const Text('隐私政策')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection(
            title: '隐私政策概述',
            content:
                '通知推送助手（以下简称"本应用"）非常重视用户的隐私保护。本隐私政策将帮助您了解我们如何收集、使用和保护您的信息。',
            context: context,
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: '信息收集与使用',
            content:
                '本应用仅收集以下类型的信息：\n\n'
                '1. 崩溃统计信息\n'
                '   - 通过腾讯 Bugly SDK 收集应用崩溃时的堆栈信息\n'
                '   - 收集设备型号、系统版本、应用版本号、CPU 架构等基础信息\n'
                '   - 用于定位和修复崩溃问题，提升应用稳定性\n\n'
                '2. 通知内容（本地处理）\n'
                '   - 应用通过通知监听服务获取系统通知内容\n'
                '   - 所有通知内容仅在设备本地处理，不会上传到任何服务器\n'
                '   - 仅通过用户自行配置的 Webhook URL 进行推送',
            context: context,
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: '我们不收集的信息',
            content:
                '本应用不会收集以下个人隐私信息：\n\n'
                '• 通讯录、短信内容\n'
                '• 位置信息\n'
                '• 通话记录\n'
                '• 相册、文件\n'
                '• 麦克风、摄像头数据\n'
                '• 其他个人身份信息',
            context: context,
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: '数据存储与安全',
            content:
                '• 所有通知历史记录仅保存在设备本地\n'
                '• 配置数据仅保存在设备本地的 SharedPreferences 中\n'
                '• 不会将您的任何个人数据上传到开发者服务器\n'
                '• Webhook 推送通过您自行配置的地址发送，请确保您信任该地址',
            context: context,
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: '第三方服务',
            content:
                '本应用使用以下第三方服务：\n\n'
                '腾讯 Bugly（崩溃统计）\n'
                '• 服务商：深圳市腾讯计算机系统有限公司\n'
                '• 用途：收集应用崩溃信息，帮助定位和修复问题\n'
                '• 隐私政策：https://privacy.qq.com/\n'
                '• 采集数据：崩溃堆栈、设备型号、系统版本、应用版本',
            context: context,
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: '权限说明',
            content:
                '本应用申请的权限及其用途：\n\n'
                '• 通知访问权限：用于监听系统通知，实现推送功能\n'
                '• 网络权限：用于 Webhook 推送和版本更新检查\n'
                '• 前台服务：保活通知监听服务，确保消息及时推送\n'
                '• 开机自启动：开机后自动启动通知监听服务\n'
                '• 电量优化白名单：避免系统杀死后台服务',
            context: context,
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: '政策更新',
            content: '本隐私政策可能会不定期更新。更新后的政策将在应用内发布，继续使用即表示您同意更新后的政策。',
            context: context,
          ),
          const SizedBox(height: 32),
          Center(
            child: Text(
              '最后更新：2026年7月2日',
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

class _DescRow extends StatelessWidget {
  final String text;
  final BuildContext context;
  const _DescRow({required this.text, required this.context});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 4),
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: AppColors.tertiaryLabel(this.context),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: AppColors.secondaryLabel(this.context),
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

class MorePage extends StatelessWidget {
  final List<Map<String, dynamic>> webhookChannels;
  final String deviceName;
  final int enabledPackagesCount;
  final int blacklistCount;
  final int whitelistCount;
  final bool isCheckingUpdate;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final VoidCallback onOpenWebhookSettings;
  final VoidCallback onShowDeviceNameDialog;
  final VoidCallback onShowAboutDialog;
  final VoidCallback onOpenAppFilter;
  final VoidCallback onOpenKeywords;
  final VoidCallback onCheckUpdate;
  final VoidCallback onOpenPrivacyPolicy;

  const MorePage({
    super.key,
    required this.webhookChannels,
    required this.deviceName,
    required this.enabledPackagesCount,
    required this.blacklistCount,
    required this.whitelistCount,
    required this.isCheckingUpdate,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onOpenWebhookSettings,
    required this.onShowDeviceNameDialog,
    required this.onShowAboutDialog,
    required this.onOpenAppFilter,
    required this.onOpenKeywords,
    required this.onCheckUpdate,
    required this.onOpenPrivacyPolicy,
  });

  @override
  Widget build(BuildContext context) {
    final enabledCount = webhookChannels
        .where((c) => c['enabled'] == true)
        .length;
    return Scaffold(
      appBar: AppBar(title: const Text('更多')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _buildSectionHeader('外观设置', context),
          _buildGroup([_buildThemeTile(context)], context),
          const SizedBox(height: 24),
          _buildSectionHeader('推送设置', context),
          _buildGroup([
            _buildNavTile(
              icon: Icons.link,
              iconColor: const Color(0xFF007AFF),
              title: 'Webhook 推送通道',
              subtitle: webhookChannels.isEmpty
                  ? '未配置'
                  : '已配置 ${webhookChannels.length} 个 · 启用 $enabledCount 个',
              onTap: onOpenWebhookSettings,
              context: context,
            ),
            _buildDivider(context),
            _buildNavTile(
              icon: Icons.apps,
              iconColor: const Color(0xFFAF52DE),
              title: '应用筛选',
              subtitle: enabledPackagesCount > 0
                  ? '已选择 $enabledPackagesCount 个应用'
                  : '全部应用都推送',
              onTap: onOpenAppFilter,
              context: context,
            ),
            _buildDivider(context),
            _buildNavTile(
              icon: Icons.filter_list,
              iconColor: const Color(0xFFFF9500),
              title: '关键词过滤',
              subtitle: '白名单 $whitelistCount 条 · 黑名单 $blacklistCount 条',
              onTap: onOpenKeywords,
              context: context,
            ),
          ], context),
          const SizedBox(height: 24),
          _buildSectionHeader('设备', context),
          _buildGroup([
            _buildNavTile(
              icon: Icons.smartphone,
              iconColor: const Color(0xFF34C759),
              title: '设备名称',
              subtitle: deviceName.isEmpty ? '未设置' : deviceName,
              onTap: onShowDeviceNameDialog,
              context: context,
            ),
          ], context),
          const SizedBox(height: 24),
          _buildSectionHeader('关于与更新', context),
          _buildGroup([
            _buildNavTile(
              icon: Icons.update,
              iconColor: const Color(0xFF007AFF),
              title: '检查更新',
              subtitle: isCheckingUpdate ? '正在检查...' : '点击检查新版本',
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
              iconColor: const Color(0xFF34C759),
              title: '隐私政策',
              subtitle: '数据采集与隐私保护说明',
              onTap: onOpenPrivacyPolicy,
              context: context,
            ),
            _buildDivider(context),
            _buildNavTile(
              icon: Icons.info_outline,
              iconColor: const Color(0xFF8E8E93),
              title: '关于',
              subtitle: '版本信息、作者介绍',
              onTap: onShowAboutDialog,
              context: context,
            ),
          ], context),
          const SizedBox(height: 32),
          Center(
            child: Text(
              'v${AppUpdateManager.instance.currentVersion} (build ${AppUpdateManager.instance.currentBuild})',
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
    final themeNames = {
      ThemeMode.system: '跟随系统',
      ThemeMode.light: '浅色模式',
      ThemeMode.dark: '深色模式',
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
              '深色模式',
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
                        ? const Icon(Icons.check, color: Color(0xFF007AFF))
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
                    '深色模式',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AppColors.primaryLabel(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    themeNames[themeMode] ?? '跟随系统',
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

class WebhookSettingsPage extends StatefulWidget {
  final List<Map<String, dynamic>> webhookChannels;

  const WebhookSettingsPage({super.key, required this.webhookChannels});

  @override
  State<WebhookSettingsPage> createState() => _WebhookSettingsPageState();
}

class _WebhookSettingsPageState extends State<WebhookSettingsPage> {
  static const platform = MethodChannel('com.fnthink.notice/notification');

  late List<TextEditingController> _webhookControllers;
  late List<bool> _webhookEnabled;
  bool _isTesting = false;
  String? _testResult;
  bool? _testSuccess;
  int? _testIndex;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _webhookControllers = widget.webhookChannels
        .map((c) => TextEditingController(text: c['url'] as String? ?? ''))
        .toList();
    _webhookEnabled = widget.webhookChannels
        .map((c) => c['enabled'] as bool? ?? true)
        .toList();
    if (_webhookControllers.isEmpty) {
      _webhookControllers.add(TextEditingController());
      _webhookEnabled.add(true);
    }
  }

  void _addWebhookField() {
    setState(() {
      _webhookControllers.add(TextEditingController());
      _webhookEnabled.add(true);
    });
  }

  void _removeWebhookField(int index) {
    setState(() {
      _webhookControllers[index].dispose();
      _webhookControllers.removeAt(index);
      _webhookEnabled.removeAt(index);
      if (_webhookControllers.isEmpty) {
        _webhookControllers.add(TextEditingController());
        _webhookEnabled.add(true);
      }
    });
  }

  void _toggleWebhookEnabled(int index) {
    setState(() {
      _webhookEnabled[index] = !_webhookEnabled[index];
    });
  }

  Future<void> _saveAndBack() async {
    setState(() {
      _isSaving = true;
    });
    final channels = <Map<String, dynamic>>[];
    for (int i = 0; i < _webhookControllers.length; i++) {
      final url = _webhookControllers[i].text.trim();
      if (url.isNotEmpty) {
        channels.add({'url': url, 'enabled': _webhookEnabled[i]});
      }
    }
    if (!mounted) return;
    Navigator.pop(context, channels);
  }

  Future<void> _testWebhook(int index) async {
    final url = _webhookControllers[index].text.trim();
    if (url.isEmpty) {
      setState(() {
        _testSuccess = false;
        _testResult = '请先输入 Webhook URL';
        _testIndex = index;
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
      _testSuccess = null;
      _testIndex = index;
    });

    try {
      final result = await platform.invokeMethod('testWebhook', {'url': url});
      final success = result['success'] as bool;
      final message = result['message'] as String;

      setState(() {
        _isTesting = false;
        _testSuccess = success;
        _testResult = message;
      });
    } catch (e) {
      setState(() {
        _isTesting = false;
        _testSuccess = false;
        _testResult = '测试失败: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(
        title: const Text('Webhook 推送通道'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveAndBack,
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    '保存',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _buildSectionHeader('通道列表', context),
          _buildGroup([
            ...List.generate(_webhookControllers.length, (index) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (index > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Divider(
                        height: 0.5,
                        thickness: 0.5,
                        color: AppColors.separator(context),
                      ),
                    ),
                  _buildChannelItem(index, context),
                ],
              );
            }),
          ], context),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppColors.cardBg(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _addWebhookField,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(
                      Icons.add_circle_outline,
                      size: 20,
                      color: Color(0xFF007AFF),
                    ),
                    SizedBox(width: 6),
                    Text(
                      '添加通道',
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFF007AFF),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('说明', context),
          _buildGroup([
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DescRow(
                    text: '支持同时配置多个 Webhook 通道，每个通道可独立开关',
                    context: context,
                  ),
                  const SizedBox(height: 8),
                  _DescRow(text: '自动识别企业微信、钉钉、飞书等平台格式', context: context),
                  const SizedBox(height: 8),
                  _DescRow(text: '新添加的通道默认启用', context: context),
                ],
              ),
            ),
          ], context),
        ],
      ),
    );
  }

  Widget _buildChannelItem(int index, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '通道 ${index + 1}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF007AFF),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              Switch(
                value: _webhookEnabled[index],
                onChanged: (_) => _toggleWebhookEnabled(index),
              ),
              if (_webhookControllers.length > 1)
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: Color(0xFFFF3B30),
                  ),
                  onPressed: () => _removeWebhookField(index),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _webhookControllers[index],
            decoration: InputDecoration(
              hintText: 'https://example.com/webhook',
              hintStyle: TextStyle(color: AppColors.tertiaryLabel(context)),
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
            style: TextStyle(
              fontSize: 15,
              color: AppColors.primaryLabel(context),
            ),
            maxLines: 1,
            onChanged: (_) {
              setState(() {});
            },
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildWebhookTypeHint(
                  _webhookControllers[index].text,
                  context,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 36,
                child: TextButton.icon(
                  onPressed: (_isTesting && _testIndex == index)
                      ? null
                      : () => _testWebhook(index),
                  icon: (_isTesting && _testIndex == index)
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send, size: 16),
                  label: Text(
                    (_isTesting && _testIndex == index) ? '测试中' : '测试',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF007AFF),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_testResult != null && _testIndex == index) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (_testSuccess ?? false)
                    ? const Color(0xFF34C759).withValues(alpha: 0.1)
                    : const Color(0xFFFF3B30).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _testSuccess == true ? Icons.check_circle : Icons.error,
                    color: _testSuccess == true
                        ? const Color(0xFF34C759)
                        : const Color(0xFFFF3B30),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _testResult!,
                      style: TextStyle(
                        fontSize: 12,
                        color: _testSuccess == true
                            ? const Color(0xFF34C759)
                            : const Color(0xFFFF3B30),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
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

  Widget _buildWebhookTypeHint(String urlStr, BuildContext context) {
    final url = urlStr.trim().toLowerCase();
    String typeName;
    IconData icon;
    Color color;
    String desc;

    if (url.contains('qyapi.weixin.qq.com') || url.contains('weixin.qq.com')) {
      typeName = '企业微信';
      icon = Icons.chat;
      color = const Color(0xFF07C160);
      desc = '文本格式推送';
    } else if (url.contains('oapi.dingtalk.com') || url.contains('dingtalk')) {
      typeName = '钉钉';
      icon = Icons.work;
      color = const Color(0xFF1677FF);
      desc = '文本格式推送';
    } else if (url.contains('feishu.cn') || url.contains('larksuite.com')) {
      typeName = '飞书';
      icon = Icons.flight;
      color = const Color(0xFF007AFF);
      desc = '文本格式推送';
    } else if (url.isEmpty) {
      typeName = '待输入';
      icon = Icons.link_off;
      color = const Color(0xFF8E8E93);
      desc = '请输入 Webhook URL';
    } else {
      typeName = '通用 JSON';
      icon = Icons.code;
      color = const Color(0xFFFF9500);
      desc = '自定义 JSON 格式';
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  typeName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: color,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    for (final controller in _webhookControllers) {
      controller.dispose();
    }
    super.dispose();
  }
}

class AppFilterPage extends StatefulWidget {
  final List<Map<String, dynamic>> installedApps;
  final List<String> enabledPackages;

  const AppFilterPage({
    super.key,
    required this.installedApps,
    required this.enabledPackages,
  });

  @override
  State<AppFilterPage> createState() => _AppFilterPageState();
}

class _AppFilterPageState extends State<AppFilterPage> {
  static const platform = MethodChannel('com.fnthink.notice/notification');

  List<Map<String, dynamic>> _allApps = [];
  List<Map<String, dynamic>> _filteredApps = [];
  Set<String> _selectedPackages = {};
  final _searchController = TextEditingController();
  bool _loading = true;
  bool _refreshing = false;
  bool _showSystemApps = false;
  bool _hasPermission = true;
  bool _checkedPermission = false;

  @override
  void initState() {
    super.initState();
    _selectedPackages = Set<String>.from(widget.enabledPackages);
    _initLoad();
    _searchController.addListener(_filterApps);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initLoad() async {
    setState(() => _loading = true);

    final hasPermission = await _checkPermission();
    setState(() {
      _hasPermission = hasPermission;
      _checkedPermission = true;
    });

    if (hasPermission) {
      await _loadCachedApps();
      _refreshAppsInBackground();
    }

    setState(() => _loading = false);
  }

  Future<bool> _checkPermission() async {
    try {
      final result =
          await platform.invokeMethod('canQueryAllPackages') as bool?;
      return result ?? true;
    } catch (e) {
      debugPrint('检查应用列表权限失败: $e');
      return true;
    }
  }

  Future<void> _requestPermission() async {
    try {
      await platform.invokeMethod('requestQueryAllPackagesPermission');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请在设置中找到「所有应用访问权限」并开启'),
          action: SnackBarAction(
            label: '我已开启',
            onPressed: () {
              _initLoad();
            },
          ),
        ),
      );
    } catch (e) {
      debugPrint('请求应用列表权限失败: $e');
    }
  }

  Future<void> _loadCachedApps() async {
    try {
      final List<dynamic> result = await platform.invokeMethod(
        'getCachedInstalledApps',
      );
      if (result.isNotEmpty) {
        setState(() {
          _allApps = result.map((e) => Map<String, dynamic>.from(e)).toList();
          _filterApps();
        });
      }
    } catch (e) {
      debugPrint('加载缓存应用列表失败: $e');
    }
  }

  Future<void> _refreshAppsInBackground() async {
    if (_refreshing) return;
    _refreshing = true;

    try {
      final List<dynamic> result = await platform.invokeMethod(
        'getInstalledApps',
      );
      final newApps = result.map((e) => Map<String, dynamic>.from(e)).toList();

      if (!mounted) return;

      final existingPackages = _allApps
          .map((e) => e['packageName'] as String)
          .toSet();
      final newPackages = newApps
          .map((e) => e['packageName'] as String)
          .toSet();
      final hasChanges =
          !existingPackages.containsAll(newPackages) ||
          existingPackages.length != newPackages.length;

      if (hasChanges) {
        setState(() {
          _allApps = newApps;
          _filterApps();
        });
      }
    } catch (e) {
      debugPrint('刷新应用列表失败: $e');
    } finally {
      _refreshing = false;
    }
  }

  void _filterApps() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredApps = _allApps.where((app) {
        if (!_showSystemApps && (app['isSystemApp'] as bool? ?? false)) {
          return false;
        }
        if (query.isEmpty) return true;
        final name = (app['appName'] as String? ?? '').toLowerCase();
        final pkg = (app['packageName'] as String? ?? '').toLowerCase();
        return name.contains(query) || pkg.contains(query);
      }).toList();
    });
  }

  void _togglePackage(String packageName, bool selected) {
    setState(() {
      if (selected) {
        _selectedPackages.add(packageName);
      } else {
        _selectedPackages.remove(packageName);
      }
    });
  }

  void _selectAll(bool selected) {
    setState(() {
      if (selected) {
        for (final app in _filteredApps) {
          _selectedPackages.add(app['packageName'] as String);
        }
      } else {
        for (final app in _filteredApps) {
          _selectedPackages.remove(app['packageName'] as String);
        }
      }
    });
  }

  void _clearAll() {
    setState(() {
      _selectedPackages.clear();
    });
  }

  void _saveAndBack() {
    Navigator.pop(context, _selectedPackages.toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(
        title: const Text(
          '应用筛选',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: _saveAndBack,
            child: const Text(
              '完成',
              style: TextStyle(
                fontSize: 16,
                color: Color(0xFF007AFF),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: _checkedPermission && !_hasPermission
          ? _buildPermissionRequestView()
          : _buildAppListView(),
    );
  }

  Widget _buildPermissionRequestView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFFF9500).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.security,
                size: 36,
                color: Color(0xFFFF9500),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '需要应用列表权限',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryLabel(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '为了能够筛选需要推送通知的应用，请授予应用读取已安装应用列表的权限。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.secondaryLabel(context),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _requestPermission,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF007AFF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  '前往开启权限',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _initLoad,
              child: Text(
                '刷新重试',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppListView() {
    return Column(
      children: [
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.inputBg(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search,
                  color: AppColors.secondaryLabel(context),
                  size: 20,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: '搜索应用名称或包名',
                      hintStyle: TextStyle(
                        color: AppColors.secondaryLabel(context),
                        fontSize: 15,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    style: TextStyle(
                      color: AppColors.primaryLabel(context),
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.cardBg(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Text(
                        '显示系统应用',
                        style: TextStyle(
                          fontSize: 15,
                          color: AppColors.primaryLabel(context),
                        ),
                      ),
                      const Spacer(),
                      Switch(
                        value: _showSystemApps,
                        onChanged: (v) {
                          setState(() {
                            _showSystemApps = v;
                            _filterApps();
                          });
                        },
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Divider(
                    height: 0.5,
                    thickness: 0.5,
                    color: AppColors.separator(context),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => _selectAll(true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF007AFF,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            '全选',
                            style: TextStyle(
                              color: Color(0xFF007AFF),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _clearAll,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.secondaryLabel(
                              context,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '清空',
                            style: TextStyle(
                              color: AppColors.secondaryLabel(context),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '已选 ${_selectedPackages.length}',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.secondaryLabel(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF007AFF).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline,
                  color: Color(0xFF007AFF),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedPackages.isEmpty
                        ? '当前模式：所有应用都推送通知（默认）'
                        : '已选择 ${_selectedPackages.length} 个应用，仅这些应用的通知会被推送',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF007AFF),
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF007AFF)),
                )
              : _filteredApps.isEmpty
              ? Center(
                  child: Text(
                    '没有找到应用',
                    style: TextStyle(color: AppColors.secondaryLabel(context)),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _filteredApps.length,
                  separatorBuilder: (_, _) => Padding(
                    padding: const EdgeInsets.only(left: 60),
                    child: Divider(
                      height: 0.5,
                      thickness: 0.5,
                      color: AppColors.separator(context),
                    ),
                  ),
                  itemBuilder: (context, index) {
                    final app = _filteredApps[index];
                    final packageName = app['packageName'] as String;
                    final appName = app['appName'] as String;
                    final isSelected = _selectedPackages.contains(packageName);
                    return Container(
                      decoration: BoxDecoration(
                        color: AppColors.cardBg(context),
                        borderRadius: BorderRadius.only(
                          topLeft: index == 0
                              ? const Radius.circular(12)
                              : Radius.zero,
                          topRight: index == 0
                              ? const Radius.circular(12)
                              : Radius.zero,
                          bottomLeft: index == _filteredApps.length - 1
                              ? const Radius.circular(12)
                              : Radius.zero,
                          bottomRight: index == _filteredApps.length - 1
                              ? const Radius.circular(12)
                              : Radius.zero,
                        ),
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF007AFF,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.android,
                            color: Color(0xFF007AFF),
                            size: 22,
                          ),
                        ),
                        title: Text(
                          appName,
                          style: TextStyle(
                            fontSize: 15,
                            color: AppColors.primaryLabel(context),
                          ),
                        ),
                        subtitle: Text(
                          packageName,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.secondaryLabel(context),
                          ),
                        ),
                        trailing: Icon(
                          isSelected
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          color: isSelected
                              ? const Color(0xFF34C759)
                              : AppColors.tertiaryLabel(context),
                          size: 24,
                        ),
                        onTap: () => _togglePackage(packageName, !isSelected),
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class KeywordsPage extends StatefulWidget {
  final List<String> blacklistKeywords;
  final List<String> whitelistKeywords;

  const KeywordsPage({
    super.key,
    required this.blacklistKeywords,
    required this.whitelistKeywords,
  });

  @override
  State<KeywordsPage> createState() => _KeywordsPageState();
}

class _KeywordsPageState extends State<KeywordsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late List<String> _blacklist;
  late List<String> _whitelist;
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _blacklist = List<String>.from(widget.blacklistKeywords);
    _whitelist = List<String>.from(widget.whitelistKeywords);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _addKeyword() {
    final keyword = _textController.text.trim();
    if (keyword.isEmpty) return;
    setState(() {
      if (_tabController.index == 0) {
        if (!_whitelist.contains(keyword)) {
          _whitelist.add(keyword);
        }
      } else {
        if (!_blacklist.contains(keyword)) {
          _blacklist.add(keyword);
        }
      }
      _textController.clear();
    });
  }

  void _removeKeyword(int index) {
    setState(() {
      if (_tabController.index == 0) {
        _whitelist.removeAt(index);
      } else {
        _blacklist.removeAt(index);
      }
    });
  }

  void _saveAndBack() {
    Navigator.pop(context, {'whitelist': _whitelist, 'blacklist': _blacklist});
  }

  @override
  Widget build(BuildContext context) {
    final currentList = _tabController.index == 0 ? _whitelist : _blacklist;
    final isWhitelist = _tabController.index == 0;

    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(
        title: const Text(
          '关键词过滤',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        bottom: TabBar(
          controller: _tabController,
          onTap: (_) => setState(() {}),
          labelColor: const Color(0xFF007AFF),
          unselectedLabelColor: AppColors.secondaryLabel(context),
          indicatorColor: const Color(0xFF007AFF),
          labelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          tabs: const [
            Tab(text: '白名单'),
            Tab(text: '黑名单'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _saveAndBack,
            child: const Text(
              '保存',
              style: TextStyle(
                fontSize: 16,
                color: Color(0xFF007AFF),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg(context),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.separator(context)),
                    ),
                    child: TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        hintText: isWhitelist ? '输入白名单关键词' : '输入黑名单关键词',
                        hintStyle: TextStyle(
                          color: AppColors.secondaryLabel(context),
                          fontSize: 15,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      style: TextStyle(
                        color: AppColors.primaryLabel(context),
                        fontSize: 15,
                      ),
                      onSubmitted: (_) => _addKeyword(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: _addKeyword,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text(
                      '添加',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF007AFF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isWhitelist
                    ? const Color(0xFF34C759).withValues(alpha: 0.1)
                    : const Color(0xFFFF9500).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    isWhitelist ? Icons.check_circle : Icons.info_outline,
                    color: isWhitelist
                        ? const Color(0xFF34C759)
                        : const Color(0xFFFF9500),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isWhitelist
                          ? '白名单：通知内容包含任一关键词时，即使应用未被选中也会推送（优先级最高）'
                          : '黑名单：通知内容包含任一关键词时，即使应用被选中也不会推送',
                      style: TextStyle(
                        fontSize: 13,
                        color: isWhitelist
                            ? const Color(0xFF34C759)
                            : const Color(0xFFFF9500),
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: currentList.isEmpty
                ? Center(
                    child: Text(
                      isWhitelist ? '暂无白名单关键词' : '暂无黑名单关键词',
                      style: TextStyle(
                        color: AppColors.secondaryLabel(context),
                        fontSize: 15,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: currentList.length,
                    separatorBuilder: (_, _) => Padding(
                      padding: const EdgeInsets.only(left: 56),
                      child: Divider(
                        height: 0.5,
                        thickness: 0.5,
                        color: AppColors.separator(context),
                      ),
                    ),
                    itemBuilder: (context, index) {
                      return Container(
                        decoration: BoxDecoration(
                          color: AppColors.cardBg(context),
                          borderRadius: BorderRadius.only(
                            topLeft: index == 0
                                ? const Radius.circular(12)
                                : Radius.zero,
                            topRight: index == 0
                                ? const Radius.circular(12)
                                : Radius.zero,
                            bottomLeft: index == currentList.length - 1
                                ? const Radius.circular(12)
                                : Radius.zero,
                            bottomRight: index == currentList.length - 1
                                ? const Radius.circular(12)
                                : Radius.zero,
                          ),
                        ),
                        child: ListTile(
                          leading: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: isWhitelist
                                  ? const Color(
                                      0xFF34C759,
                                    ).withValues(alpha: 0.12)
                                  : const Color(
                                      0xFFFF9500,
                                    ).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              isWhitelist ? Icons.check : Icons.block,
                              color: isWhitelist
                                  ? const Color(0xFF34C759)
                                  : const Color(0xFFFF9500),
                              size: 18,
                            ),
                          ),
                          title: Text(
                            currentList[index],
                            style: TextStyle(
                              fontSize: 15,
                              color: AppColors.primaryLabel(context),
                            ),
                          ),
                          trailing: GestureDetector(
                            onTap: () => _removeKeyword(index),
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFFF3B30,
                                ).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: const Icon(
                                Icons.close,
                                color: Color(0xFFFF3B30),
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class HistoryPage extends StatefulWidget {
  final List<NotificationRecord> records;
  final Future<void> Function() onClear;
  final Future<String> Function() onExport;

  const HistoryPage({
    super.key,
    required this.records,
    required this.onClear,
    required this.onExport,
  });

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  List<NotificationRecord> get _filteredRecords {
    if (_searchQuery.isEmpty) return widget.records;
    final q = _searchQuery.toLowerCase();
    return widget.records.where((r) {
      final title = (r['title'] ?? '').toString().toLowerCase();
      final content = (r['content'] ?? '').toString().toLowerCase();
      final app = (r['appName'] ?? '').toString().toLowerCase();
      final pkg = (r['packageName'] ?? '').toString().toLowerCase();
      return title.contains(q) ||
          content.contains(q) ||
          app.contains(q) ||
          pkg.contains(q);
    }).toList();
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return '';
    final ms = timestamp is int
        ? timestamp
        : int.tryParse(timestamp.toString()) ?? 0;
    if (ms == 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Color _getTypeColor(String? type) {
    switch (type) {
      case 'sms':
        return const Color(0xFFFF9500);
      case 'call_incoming':
      case 'call_answered':
      case 'call_ended':
        return const Color(0xFF34C759);
      case 'wechat':
        return const Color(0xFF07C160);
      case 'qq':
        return const Color(0xFF12B7F5);
      case 'alipay':
        return const Color(0xFF1677FF);
      case 'system':
        return const Color(0xFF8E8E93);
      case 'battery_charging':
      case 'battery_full':
      case 'battery_low_30':
      case 'battery_low_20':
        return const Color(0xFF007AFF);
      default:
        return const Color(0xFF5856D6);
    }
  }

  bool _isKnownType(String? type) {
    const knownTypes = {
      'sms',
      'call_incoming',
      'call_answered',
      'call_ended',
      'wechat',
      'qq',
      'alipay',
      'system',
      'battery_charging',
      'battery_full',
      'battery_low_30',
      'battery_low_20',
      'test',
    };
    return knownTypes.contains(type);
  }

  Color _getAppColor(String appName) {
    if (appName.isEmpty) return const Color(0xFF5856D6);
    final hash = appName.hashCode;
    final colors = [
      const Color(0xFF007AFF),
      const Color(0xFFFF9500),
      const Color(0xFF34C759),
      const Color(0xFFFF3B30),
      const Color(0xFFAF52DE),
      const Color(0xFF5856D6),
      const Color(0xFF00C7BE),
      const Color(0xFFFF2D55),
      const Color(0xFFFFCC00),
    ];
    return colors[hash.abs() % colors.length];
  }

  String _getTypeLabel(String? type) {
    switch (type) {
      case 'sms':
        return '短信';
      case 'call_incoming':
        return '来电';
      case 'call_answered':
        return '接听';
      case 'call_ended':
        return '挂断';
      case 'wechat':
        return '微信';
      case 'qq':
        return 'QQ';
      case 'alipay':
        return '支付宝';
      case 'system':
        return '系统';
      case 'test':
        return '测试';
      case 'battery_charging':
        return '充电';
      case 'battery_full':
        return '充满';
      case 'battery_low_30':
        return '低电量30%';
      case 'battery_low_20':
        return '低电量20%';
      default:
        return '通知';
    }
  }

  Future<void> _handleClear() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBg(context),
        title: Text(
          '确认清空',
          style: TextStyle(color: AppColors.primaryLabel(context)),
        ),
        content: Text(
          '确定要清空全部 ${widget.records.length} 条记录吗？',
          style: TextStyle(color: AppColors.primaryLabel(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFF3B30),
            ),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await widget.onClear();
      setState(() {});
    }
  }

  Future<void> _handleExport() async {
    try {
      final path = await widget.onExport();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已导出到: $path'),
          backgroundColor: const Color(0xFF34C759),
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('导出失败: $e'),
          backgroundColor: const Color(0xFFFF3B30),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showRecordDetail(NotificationRecord record) {
    final appName = (record['appName'] ?? '通知详情').toString();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBg(context),
        title: Text(
          appName,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryLabel(context),
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '详细信息',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.inputBg(context),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    const JsonEncoder.withIndent('  ').convert(record),
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: AppColors.primaryLabel(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              '关闭',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(
        title: Text('历史记录 (${_filteredRecords.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: '导出 JSON',
            onPressed: widget.records.isEmpty ? null : _handleExport,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '清空记录',
            onPressed: widget.records.isEmpty ? null : _handleClear,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.inputBg(context),
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '搜索标题/内容/应用',
                  hintStyle: TextStyle(
                    fontSize: 14,
                    color: AppColors.secondaryLabel(context),
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    size: 18,
                    color: AppColors.secondaryLabel(context),
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.cancel,
                            size: 18,
                            color: AppColors.secondaryLabel(context),
                          ),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  isDense: true,
                ),
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.primaryLabel(context),
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            ),
          ),
          Expanded(
            child: _filteredRecords.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 56,
                          color: AppColors.tertiaryLabel(context),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.records.isEmpty ? '暂无推送记录' : '没有匹配的记录',
                          style: TextStyle(
                            color: AppColors.secondaryLabel(context),
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filteredRecords.length,
                    separatorBuilder: (_, _) => Padding(
                      padding: const EdgeInsets.only(left: 56),
                      child: Divider(
                        height: 0.5,
                        thickness: 0.5,
                        color: AppColors.separator(context),
                      ),
                    ),
                    itemBuilder: (context, index) {
                      final record = _filteredRecords[index];
                      final type = record['type'] as String?;
                      final title = (record['title'] ?? '（无标题）').toString();
                      final content = (record['content'] ?? '').toString();
                      final appName = (record['appName'] ?? '').toString();
                      final time = _formatTime(
                        record['postTime'] ?? record['timestamp'],
                      );
                      final isKnownType = _isKnownType(type);
                      final color = isKnownType
                          ? _getTypeColor(type)
                          : _getAppColor(appName);
                      final label = isKnownType ? _getTypeLabel(type) : appName;

                      return InkWell(
                        onTap: () => _showRecordDetail(record),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.cardBg(context),
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(index == 0 ? 12 : 0),
                              topRight: Radius.circular(index == 0 ? 12 : 0),
                              bottomLeft: Radius.circular(
                                index == _filteredRecords.length - 1 ? 12 : 0,
                              ),
                              bottomRight: Radius.circular(
                                index == _filteredRecords.length - 1 ? 12 : 0,
                              ),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text(
                                    label.isNotEmpty
                                        ? label.substring(0, 1)
                                        : '通',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: color,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            title,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w500,
                                              color: AppColors.primaryLabel(
                                                context,
                                              ),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Text(
                                          time,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.secondaryLabel(
                                              context,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    if (content.isNotEmpty)
                                      Text(
                                        content,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: AppColors.secondaryLabel(
                                            context,
                                          ),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    if (appName.isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        appName,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.secondaryLabel(
                                            context,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
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
    debugPrint('Foreground task destroyed at $timestamp, isTimeout: $isTimeout');
  }

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }
}
