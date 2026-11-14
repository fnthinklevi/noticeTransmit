import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../l10n/app_localizations.dart';
import '../services/locale_service.dart';
import '../services/platform_channel.dart';
import '../services/services.dart';
import '../theme/app_colors.dart';

/// 装配链**每一步**的期限（T253）。
///
/// 20 秒的 watchdog 只回答"整条链没跑完"，不回答"卡在哪一步"——而数据库被后台残留
/// 连接占住时，那一步的 `await` 根本不会回来（框架连接池的等待没有超时）。
/// 8 秒还没回来就把它交给显式出口，比等 watchdog 再显示一句"初始化超过 20 秒"有用。
const Duration kStartupStepDeadline = Duration(seconds: 8);

/// 某一步超过 [kStartupStepDeadline] 仍未完成（启动页把它显示成"库被占用"的显式错误）。
class StartupStalledException implements Exception {
  const StartupStalledException(this.step);

  final String step;

  @override
  String toString() =>
      'startup step "$step" exceeded ${kStartupStepDeadline.inSeconds}s';
}

/// 有界跑一步：超时 ⇒ [StartupStalledException]（**不吞**，交给启动页的显式出口）；
/// 其余异常照旧只记一行日志、不挡启动（与原来每一步的 try/catch 同语义）。
Future<void> runBoundedStartupStep(
  String step,
  Future<void> Function() action, {
  Duration deadline = kStartupStepDeadline,
}) async {
  try {
    await action().timeout(deadline);
  } on TimeoutException {
    log('[startup] $step 超过 ${deadline.inSeconds} 秒未完成');
    throw StartupStalledException(step);
  } catch (e) {
    log('$step失败: $e');
  }
}

class SplashPage extends StatefulWidget {
  final VoidCallback onInitCompleted;

  const SplashPage({super.key, required this.onInitCompleted});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  String? _statusText;

  /// T222：初始化失败的显式出口。**不许**再让界面停在「初始化完成」等一个不会再来的结果。
  String? _error;

  /// T253：当前这个错误是"某一步卡死"（库被后台残留连接占住）而不是普通异常 ——
  /// 只有这一档才显示「重启应用」：残留连接与悬挂事务活在**本进程**里，重试只会再卡一次。
  bool _stalled = false;
  Timer? _watchdog;
  bool _done = false;

  /// 启动 watchdog 的上界。5 秒是安全存储单次调用的上界；这里给整条装配链留 20 秒。
  static const Duration initDeadline = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));
    _controller.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startInit();
    });
  }

  void _startInit() {
    _watchdog?.cancel();
    _watchdog = Timer(initDeadline, () {
      if (!mounted || _done) return;
      final l10n = AppLocalizations.of(context);
      setState(() => _error = l10n.initTimeout(initDeadline.inSeconds));
    });
    unawaited(_initServices());
  }

  /// 重试只重跑装配链：**不重建数据、不动安全存储**（清数据那条路只能由用户自己去系统设置走）。
  void _retry() {
    setState(() {
      _error = null;
      _statusText = null;
      _stalled = false;
      _done = false;
    });
    _startInit();
  }

  /// 启动页上唯一的真出口（T253）：残留连接与它的悬挂事务活在**本进程**的静态表里，
  /// 重建页面/引擎都不释放，只有换一个进程能清掉。原生收到这一发先回 success 再杀进程。
  Future<void> _restartApp() async {
    try {
      await AppChannels.notification.invokeMethod<bool>('restartApp');
    } catch (e) {
      log('[startup] 重启应用调用失败: $e');
    }
  }

  Future<void> _initServices() async {
    try {
      await _initServicesInner();
    } on StartupStalledException catch (e, stack) {
      log('[startup] SplashPage 初始化卡死：${e.step}', error: e, stackTrace: stack);
      if (!mounted) return;
      _watchdog?.cancel();
      setState(() {
        _done = true;
        _stalled = true;
        _error = AppLocalizations.of(context).startupDbStalled;
      });
    } catch (e, stack) {
      log('[startup] SplashPage 初始化失败：$e', error: e, stackTrace: stack);
      if (!mounted) return;
      _watchdog?.cancel();
      setState(() {
        _done = true;
        _error = '$e';
      });
    }
  }

  Future<void> _initServicesInner() async {
    final l10n = AppLocalizations.of(context);
    log('=== SplashPage 开始初始化服务 ===');

    // 语言装配必须先于任何显示通道名的步骤（LocaleService 默认 system 模式，
    // init() 过去挂在 MyApp 的 _onServicesInitialized 里 = splash 装配完之后）。
    // 历史上它还**同时决定存储键**（webhook:钉钉 / webhook:DingTalk），于是系统语言
    // 非中文、应用内选中文的用户会在 loadRecords / drainPendingDeliveries 阶段写出
    // 中英双键（历史重复徽标 / 旧键永远「发送中」）。DB v11 起存储键改为与语言无关的
    // chan:<slug>，该缺陷类别从根上消除；此处顺序约束只剩显示层。
    await runBoundedStartupStep('locale', () async {
      await GetIt.instance<LocaleService>().init();
    });

    // 通道描述符（第 5 步）：设置页的表单字段、类型选择器、secret/模板显隐都按它渲染。
    // 顺序约束 = 必须早于 `onInitCompleted()`（那之后通道页才可达）。取不到时服务
    // 保持未就绪，页面自己会再 load() 一次，且不会因此把已存配置写空。
    log('加载通道描述符');
    await runBoundedStartupStep('channel-descriptor', () async {
      await GetIt.instance<ChannelDescriptorService>().load();
    });
    // 健康度缓存同样先装载：徽标是同步渲染的（build 里读内存快照），装载晚于装配
    // 就等于首帧没徽标、且各页面会各自去读 prefs（三份实现的旧账）。
    log('加载通道健康缓存');
    await runBoundedStartupStep('channel-health', () async {
      await GetIt.instance<ChannelHealthStore>().load();
    });

    if (mounted) setState(() => _statusText = l10n.loadWebhook);
    log('加载 Webhook 配置');
    await runBoundedStartupStep('webhook', () async {
      await GetIt.instance<WebhookService>().loadChannels();
    });

    if (mounted) setState(() => _statusText = l10n.loadBattery);
    log('加载电池配置');
    await runBoundedStartupStep('battery', () async {
      await GetIt.instance<BatteryService>().loadSettings();
    });

    if (mounted) setState(() => _statusText = l10n.loadRecords);
    log('加载通知记录');
    await runBoundedStartupStep('records', () async {
      final notificationService = GetIt.instance<NotificationService>();
      await notificationService.loadRecords();
      await notificationService.loadServiceState();
    });

    if (mounted) setState(() => _statusText = l10n.loadFilter);
    log('加载过滤配置');
    await runBoundedStartupStep('filter', () async {
      await GetIt.instance<FilterService>().loadSettings();
    });

    if (mounted) setState(() => _statusText = l10n.initUpdate);
    log('初始化更新服务');
    await runBoundedStartupStep('update', () async {
      await GetIt.instance<UpdateService>().init();
    });

    if (mounted) setState(() => _statusText = l10n.initComplete);
    log('=== 所有服务初始化完成 ===');

    // 装配链已经跑完：撤掉 watchdog，再交给根组件切主页面。
    _done = true;
    _watchdog?.cancel();

    await Future.delayed(const Duration(milliseconds: 300));

    if (mounted) {
      widget.onInitCompleted();
    }
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppColors.blue,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.blue.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.notifications_active,
                  size: 56,
                  color: AppColors.onAccent,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                l10n.appName,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 32),
              if (_error != null) ...[
                Text(
                  l10n.initFailed,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: AppColors.secondaryLabel(context),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  key: const ValueKey('splash-retry'),
                  onPressed: _retry,
                  child: Text(l10n.retry),
                ),
                // T253：卡死档（库被后台残留连接占住）光重试没用 —— 残留连接活在
                // 本进程里，只有换一个进程能清掉。这一枚只在卡死档出现，别的错误不误导。
                if (_stalled) ...[
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    key: const ValueKey('splash-restart'),
                    onPressed: _restartApp,
                    child: Text(l10n.restartApp),
                  ),
                ],
              ] else ...[
                Text(
                  _statusText ?? l10n.initializing,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 40,
                  height: 4,
                  child: LinearProgressIndicator(
                    backgroundColor: AppColors.systemGray(context),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.blue,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
