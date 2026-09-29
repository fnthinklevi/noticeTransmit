import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'l10n/app_localizations.dart';
import 'pages/main_page.dart';
import 'pages/splash_page.dart';
import 'di/service_locator.dart';
import 'theme/app_theme.dart';
import 'theme/app_colors.dart';
import 'services/theme_service.dart';
import 'services/locale_service.dart';
import 'services/archive_worker.dart';
import 'services/fnthink_receive_coordinator.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化 WorkManager（用于每日通知归档）
  Workmanager().initialize(
    archiveCallbackDispatcher,
    isInDebugMode: kDebugMode,
  );
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

  AppLocalizations _l10n(BuildContext context) {
    final l10n = Localizations.of<AppLocalizations>(context, AppLocalizations);
    if (l10n != null) return l10n;
    // 错误回退：DIErrorApp 未配置 delegates，使用当前 locale 兜底
    Locale locale = const Locale('zh');
    try {
      locale = GetIt.instance<LocaleService>().currentLocale;
    } catch (_) {}
    return locale.languageCode == 'en'
        ? lookupAppLocalizations(const Locale('en'))
        : lookupAppLocalizations(const Locale('zh'));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    return MaterialApp(
      title: l10n.appName,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                l10n.initFailed,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(l10n.initFailedMsg),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => runApp(const MyApp()),
                child: Text(l10n.retry),
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
  Locale _locale = const Locale('zh');

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
    if (!mounted) return;
    setState(() => _themeInitialized = true);
  }

  Future<void> _acceptPrivacy() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_privacyAcceptedKey, true);
    if (!mounted) return;
    setState(() => _privacyAccepted = true);
  }

  void _rejectPrivacy() {
    exit(0);
  }

  void _onLocaleChanged(Locale locale) {
    setState(() {
      _locale = locale;
    });
  }

  void _onDisagreeFirst(BuildContext dialogCtx) {
    showDialog(
      context: dialogCtx,
      barrierDismissible: false,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return AlertDialog(
          backgroundColor: AppColors.cardBg(ctx),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
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
                l10n.privacyWarnTitle,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryLabel(ctx),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.privacyWarnBody,
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
                l10n.returnAgree,
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
              child: Text(
                l10n.confirmExit,
                style: const TextStyle(fontSize: 15),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showPrivacyDialog() {
    final navContext = _navigatorKey.currentState?.overlay?.context;
    if (navContext == null) return;
    showDialog(
      context: navContext,
      barrierDismissible: false,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return AlertDialog(
          backgroundColor: AppColors.cardBg(ctx),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          contentPadding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
          title: null,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.shield_outlined,
                size: 44,
                color: AppColors.blue,
              ),
              const SizedBox(height: 14),
              Text(
                l10n.privacyTitle,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryLabel(ctx),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${l10n.privacyWelcome}\n\n${l10n.privacyBody}',
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
                l10n.disagree,
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
              child: Text(l10n.agree, style: const TextStyle(fontSize: 15)),
            ),
          ],
        );
      },
    );
  }

  void _onServicesInitialized() {
    setState(() => _servicesInitialized = true);
    // 初始化 locale：读取 SharedPreferences 中保存的语言选择
    try {
      final localeService = GetIt.instance<LocaleService>();
      localeService.init().then((_) {
        if (mounted) {
          setState(() => _locale = localeService.currentLocale);
        }
      });
    } catch (_) {}
    unawaited(_startFnthinkReceive());
  }

  /// T33 第一片：收货循环的启动点**不能只有页面**。
  ///
  /// 在这一行之前，全仓只有 `fnthink_push_page` 那两处调 `startIfEnabled()` ——
  /// 于是"总开关开着"这件事只在用户停留在幻念推送页时成立：他退回首页、切到别的 tab、
  /// 或直接把 App 划进后台（进程还活着），服务器那头的消息就不再有人来取。
  /// 用户翻那个开关时看到的说明是"这台设备会去收"，不是"停在这一页时才会收"。
  ///
  /// 起在这里而不是 `main()`：这里在 SplashPage 装配完成之后，也在隐私同意之后
  /// （`_privacyAccepted` 没通过时 App 什么都不该往网络发）；`setupLocator()` 里起是另一回事 ——
  /// 那里连 SharedPreferences 都还没读。
  ///
  /// ⚠ 这一片覆盖的是**进程活着而页面关了**那一段。进程被 ROM 杀掉之后的复起是第二片
  ///   （原生闹钟 + BootReceiver，照 T74-C 那套），别把这里当成"被杀也能收"。
  Future<void> _startFnthinkReceive() async {
    try {
      final result = await GetIt.instance<FnthinkReceiveCoordinator>()
          .startIfEnabled();
      // 'disabled' 是绝大多数人此刻的状态（默认关），不值得往日志里灌；其余的没起来都要留痕。
      if (!result.started && result.reason != 'disabled') {
        log('[fnthink] 收货循环没起来：${result.reason}');
      }
    } catch (e) {
      // 起不来不许挡启动链：这一页后面还有别的装配（与 DI 那处"坏了也不连累别的端点"同一条）。
      log('[fnthink] 收货循环启动异常：$e');
    }
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
          title: 'NoticeTransmit',
          locale: _locale,
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: AppTheme.lightTheme(),
          darkTheme: AppTheme.darkTheme(),
          themeMode: themeMode,
          home: _initialized
              ? MainPage(onLocaleChanged: _onLocaleChanged)
              : SplashPage(onInitCompleted: _onServicesInitialized),
        );
      },
    );
  }
}
