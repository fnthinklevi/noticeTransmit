import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../l10n/app_localizations.dart';
import '../services/locale_service.dart';
import '../services/services.dart';
import '../theme/app_colors.dart';

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
      _initServices();
    });
  }

  Future<void> _initServices() async {
    final l10n = AppLocalizations.of(context);
    log('=== SplashPage 开始初始化服务 ===');

    // 语言装配必须先于任何显示通道名的步骤（LocaleService 默认 system 模式，
    // init() 过去挂在 MyApp 的 _onServicesInitialized 里 = splash 装配完之后）。
    // 历史上它还**同时决定存储键**（webhook:钉钉 / webhook:DingTalk），于是系统语言
    // 非中文、应用内选中文的用户会在 loadRecords / drainPendingDeliveries 阶段写出
    // 中英双键（历史重复徽标 / 旧键永远「发送中」）。DB v11 起存储键改为与语言无关的
    // chan:<slug>，该缺陷类别从根上消除；此处顺序约束只剩显示层。
    try {
      await GetIt.instance<LocaleService>().init();
    } catch (e) {
      log('初始化语言失败: $e');
    }

    // 通道描述符（第 5 步）：设置页的表单字段、类型选择器、secret/模板显隐都按它渲染。
    // 顺序约束 = 必须早于 `onInitCompleted()`（那之后通道页才可达）。取不到时服务
    // 保持未就绪，页面自己会再 load() 一次，且不会因此把已存配置写空。
    log('加载通道描述符');
    await GetIt.instance<ChannelDescriptorService>().load();

    try {
      if (mounted) setState(() => _statusText = l10n.loadWebhook);
      log('加载 Webhook 配置');
      final webhookService = GetIt.instance<WebhookService>();
      await webhookService.loadChannels();
    } catch (e) {
      log('加载 Webhook 配置失败: $e');
    }

    try {
      if (mounted) setState(() => _statusText = l10n.loadBattery);
      log('加载电池配置');
      final batteryService = GetIt.instance<BatteryService>();
      await batteryService.loadSettings();
    } catch (e) {
      log('加载电池配置失败: $e');
    }

    try {
      if (mounted) setState(() => _statusText = l10n.loadRecords);
      log('加载通知记录');
      final notificationService = GetIt.instance<NotificationService>();
      await notificationService.loadRecords();
      await notificationService.loadServiceState();
    } catch (e) {
      log('加载通知记录失败: $e');
    }

    try {
      if (mounted) setState(() => _statusText = l10n.loadFilter);
      log('加载过滤配置');
      final filterService = GetIt.instance<FilterService>();
      await filterService.loadSettings();
    } catch (e) {
      log('加载过滤配置失败: $e');
    }

    try {
      if (mounted) setState(() => _statusText = l10n.initUpdate);
      log('初始化更新服务');
      final updateService = GetIt.instance<UpdateService>();
      await updateService.init();
    } catch (e) {
      log('初始化更新服务失败: $e');
    }

    if (mounted) setState(() => _statusText = l10n.initComplete);
    log('=== 所有服务初始化完成 ===');

    await Future.delayed(const Duration(milliseconds: 300));

    if (mounted) {
      widget.onInitCompleted();
    }
  }

  @override
  void dispose() {
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
                  color: Colors.white,
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
              Text(
                _statusText ?? l10n.initializing,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
              const SizedBox(height: 16),
              const SizedBox(
                width: 40,
                height: 4,
                child: LinearProgressIndicator(
                  backgroundColor: Colors.grey,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.blue),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
