import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'pages/main_page.dart';
import 'pages/splash_page.dart';
import 'di/service_locator.dart';
import 'theme/app_theme.dart';
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
  bool _themeInitialized = false;
  bool _servicesInitialized = false;

  @override
  void initState() {
    super.initState();
    _initTheme();
  }

  Future<void> _initTheme() async {
    await GetIt.instance<ThemeService>().init();
    setState(() => _themeInitialized = true);
  }

  void _onServicesInitialized() {
    setState(() => _servicesInitialized = true);
  }

  bool get _initialized => _themeInitialized && _servicesInitialized;

  @override
  Widget build(BuildContext context) {
    final themeService = GetIt.instance<ThemeService>();
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeService.themeModeNotifier,
      builder: (context, themeMode, child) {
        return MaterialApp(
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
