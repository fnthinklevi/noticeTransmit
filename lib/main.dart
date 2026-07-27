import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pages/main_page.dart';
import 'pages/splash_page.dart';
import 'di/service_locator.dart';
import 'theme/app_theme.dart';
import 'theme/app_colors.dart';
import 'services/theme_service.dart';

void main() {
  FlutterError.onError = (details) {
    log(
      'FlutterError: ${details.exception}',
      error: details.exception,
      stackTrace: details.stack,
    );
    FlutterError.presentError(details);
  };

  runZonedGuarded(
    () {
      log('=== 应用启动开始 ===');
      WidgetsFlutterBinding.ensureInitialized();
      log('FlutterBinding 初始化完成');

      try {
        setupLocator();
        log('依赖注入配置完成');
      } catch (e, stack) {
        log('依赖注入失败: $e', error: e, stackTrace: stack);
        runApp(const DIErrorApp());
        return;
      }

      runApp(const MyApp());
      log('runApp 调用完成');
    },
    (error, stackTrace) {
      log('全局未捕获异常: $error', error: error, stackTrace: stackTrace);
    },
  );
}

class DIErrorApp extends StatelessWidget {
  const DIErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '通知推送助手',
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                '应用启动失败',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('依赖注入初始化失败，请重启应用'),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => runApp(const MyApp()),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
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
  final _navigatorKey = GlobalKey<NavigatorState>();
  bool _themeInitialized = false;
  bool _servicesInitialized = false;
  bool? _privacyAccepted;
  bool _privacyDialogShown = false;

  static const _privacyAcceptedKey = 'privacy_policy_accepted';

  @override
  void initState() {
    super.initState();
    _initTheme();
  }

  Future<void> _initTheme() async {
    await GetIt.instance<ThemeService>().init();
    final prefs = await SharedPreferences.getInstance();
    _privacyAccepted = prefs.getBool(_privacyAcceptedKey) ?? false;
    setState(() => _themeInitialized = true);
  }

  Future<void> _acceptPrivacy() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_privacyAcceptedKey, true);
    setState(() => _privacyAccepted = true);
  }

  void _rejectPrivacy() {
    exit(0);
  }

  void _onDisagreeFirst(BuildContext dialogCtx) {
    showDialog(
      context: dialogCtx,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 44,
              color: AppColors.orange,
            ),
            const SizedBox(height: 14),
            Text(
              '注意',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryLabel(ctx),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '您需要同意隐私政策才能使用本软件。\n\n'
              '不同意将无法继续使用，软件将会退出。\n\n'
              '确定要退出吗？',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppColors.primaryLabel(ctx),
              ),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              '返回同意',
              style: TextStyle(
                color: AppColors.secondaryLabel(ctx),
                fontSize: 15,
              ),
            ),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).popUntil((route) => route.isFirst);
              _rejectPrivacy();
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('确定退出', style: TextStyle(fontSize: 15)),
          ),
        ],
      ),
    );
  }

  void _showPrivacyDialog() {
    final navContext = _navigatorKey.currentState?.overlay?.context;
    if (navContext == null) return;
    showDialog(
      context: navContext,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        contentPadding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        title: null,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shield_outlined, size: 44, color: AppColors.blue),
            const SizedBox(height: 14),
            Text(
              '隐私政策',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryLabel(ctx),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '欢迎使用通知推送助手！\n\n'
              '在使用本应用前，请您仔细阅读我们的隐私政策。\n\n'
              '• 所有通知内容仅在设备本地处理，不会上传到任何服务器\n'
              '• 推送历史使用 AES-256 加密存储在本地\n'
              '• 仅收集必要的崩溃日志（腾讯 Bugly）用于修复应用问题：崩溃堆栈、设备型号、系统版本、应用版本，不采集个人身份信息\n'
              '• Webhook 配置使用 AndroidKeyStore 加密存储\n\n'
              '点击"同意"即表示您已阅读并接受我们的隐私政策。',
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppColors.primaryLabel(ctx),
              ),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          TextButton(
            onPressed: () => _onDisagreeFirst(ctx),
            child: Text(
              '不同意',
              style: TextStyle(
                color: AppColors.secondaryLabel(ctx),
                fontSize: 15,
              ),
            ),
          ),
          FilledButton(
            onPressed: () {
              _acceptPrivacy();
              Navigator.of(ctx).pop();
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.blue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('同意', style: TextStyle(fontSize: 15)),
          ),
        ],
      ),
    );
  }

  void _onServicesInitialized() {
    setState(() => _servicesInitialized = true);
  }

  bool get _initialized => _themeInitialized && _servicesInitialized;

  @override
  Widget build(BuildContext context) {
    final themeService = GetIt.instance<ThemeService>();

    // 开屏页加载完成后弹出隐私政策
    if (_themeInitialized &&
        _servicesInitialized &&
        _privacyAccepted == false &&
        !_privacyDialogShown) {
      _privacyDialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _privacyAccepted == false) {
          _showPrivacyDialog();
        }
      });
    }

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeService.themeModeNotifier,
      builder: (context, themeMode, child) {
        return MaterialApp(
          navigatorKey: _navigatorKey,
          title: '通知推送助手',
          theme: AppTheme.lightTheme(),
          darkTheme: AppTheme.darkTheme(),
          themeMode: themeMode,
          home: _initialized
              ? const MainPage()
              : SplashPage(onInitCompleted: _onServicesInitialized),
        );
      },
    );
  }
}
