import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'l10n/app_localizations.dart';
import 'pages/main_page.dart';
import 'pages/privacy_policy_page.dart';
import 'pages/splash_page.dart';
import 'di/service_locator.dart';
import 'theme/app_colors.dart';
import 'widgets/app_root.dart';
import 'widgets/privacy_gate_body.dart';
import 'services/theme_service.dart';
import 'services/locale_service.dart';
import 'services/archive_worker.dart';
import 'services/fnthink_receive_coordinator.dart';
import 'services/fnthink_fanout_entrypoint.dart';

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
      // 幻念转发那一发的后台入口 handle（T94 片4）。**每次冷启动都重写**：
      // handle 会随编译变，而 prefs 里那一份不会自己跟上 —— 拿着旧 handle 的话，
      // 表现是每一条通知都落进待发队列然后被原生丢掉（日志一行 no-entry-handle），
      // 而界面上看不出任何异常。写失败不拦启动：这一族不写只是不自动转发。
      unawaited(publishFnthinkFanoutEntryHandle());
    },
    (error, stackTrace) {
      log('全局未捕获异常: $error', error: error, stackTrace: stackTrace);
    },
  );
}

class DIErrorApp extends StatelessWidget {
  const DIErrorApp({super.key});

  /// DI 崩了 ⇒ 不能依赖 `LocaleService`，只能从平台语言里挑一个受支持档。
  static Locale _fallbackLocale() {
    final locales = WidgetsBinding.instance.platformDispatcher.locales;
    final code = locales.isEmpty ? 'zh' : locales.first.languageCode;
    return code == 'en' ? const Locale('en') : const Locale('zh');
  }

  @override
  Widget build(BuildContext context) {
    return AppRoot(
      locale: _fallbackLocale(),
      dark:
          WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark,
      title: lookupAppLocalizations(_fallbackLocale()).appName,
      home: const _DIErrorPage(),
    );
  }
}

class _DIErrorPage extends StatelessWidget {
  const _DIErrorPage();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CupertinoPageScaffold(
      backgroundColor: AppColors.bgColor(context),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              CupertinoIcons.exclamationmark_circle_fill,
              size: 56,
              color: AppColors.red,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.initFailed,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(l10n.initFailedMsg, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 24),
            CupertinoButton.filled(
              onPressed: () => runApp(const MyApp()),
              child: Text(l10n.retry),
            ),
          ],
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

class MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  bool _themeInitialized = false;
  bool _servicesInitialized = false;
  bool? _privacyAccepted;
  bool _privacyDialogShown = false;
  Locale _locale = const Locale('zh');

  /// 「跟随系统」那一档要用的平台亮度。以前由 `MaterialApp.themeMode` 代劳，
  /// 根组件换成 `CupertinoApp` 之后没人代劳 —— 裁决点挪到这里（见 [_brightnessFor]）。
  Brightness _platformBrightness =
      WidgetsBinding.instance.platformDispatcher.platformBrightness;

  static const _privacyAcceptedKey = 'privacy_policy_accepted';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initTheme();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    if (!mounted) return;
    setState(
      () => _platformBrightness =
          WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
  }

  /// 用户档（浅/深/跟随系统）× 平台亮度 ⇒ 实际明暗。全站只有这一处裁决。
  Brightness _brightnessFor(ThemeMode mode) => switch (mode) {
    ThemeMode.light => Brightness.light,
    ThemeMode.dark => Brightness.dark,
    ThemeMode.system => _platformBrightness,
  };

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
    showCupertinoDialog(
      context: dialogCtx,
      barrierDismissible: false,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return CupertinoAlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                CupertinoIcons.exclamationmark_triangle_fill,
                size: 22,
                color: AppColors.orange,
              ),
              const SizedBox(width: 8),
              Flexible(child: Text(l10n.privacyWarnTitle)),
            ],
          ),
          content: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              l10n.privacyWarnBody,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppColors.secondaryLabel(ctx),
              ),
            ),
          ),
          actions: [
            // 「返回并同意」不是确认，走次要档；退出这条才是破坏性动作。
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.returnAgree),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.of(ctx).popUntil((route) => route.isFirst);
                _rejectPrivacy();
              },
              child: Text(l10n.confirmExit),
            ),
          ],
        );
      },
    );
  }

  void _showPrivacyDialog() {
    final navContext = _navigatorKey.currentState?.overlay?.context;
    if (navContext == null) return;
    showCupertinoDialog(
      context: navContext,
      barrierDismissible: false,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return CupertinoAlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                CupertinoIcons.checkmark_shield_fill,
                size: 22,
                color: AppColors.blue,
              ),
              const SizedBox(width: 8),
              Flexible(child: Text(l10n.privacyTitle)),
            ],
          ),
          content: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: PrivacyGateBody(
              // 用 Cupertino 转场推它：全文页本身仍是 Material 的 Scaffold，但
              // 根组件已是 CupertinoApp，不该再往「MaterialPageRoute 只许变薄」那本
              // 台账里加一处（见 ui_style_guards_test.dart 的 kMaterialRouteSites）。
              onOpenPolicy: () => Navigator.of(ctx).push(
                CupertinoPageRoute(builder: (_) => const PrivacyPolicyPage()),
              ),
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => _onDisagreeFirst(ctx),
              child: Text(l10n.disagree),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () {
                _acceptPrivacy();
                Navigator.of(ctx).pop();
              },
              child: Text(l10n.agree),
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
  /// 在这一行之前，全仓只有 `fnthink_settings_page` 那两处调 `startIfEnabled()` ——
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
        return AppRoot(
          navigatorKey: _navigatorKey,
          locale: _locale,
          dark: _brightnessFor(themeMode) == Brightness.dark,
          home: _initialized
              ? MainPage(onLocaleChanged: _onLocaleChanged)
              : SplashPage(onInitCompleted: _onServicesInitialized),
        );
      },
    );
  }
}
