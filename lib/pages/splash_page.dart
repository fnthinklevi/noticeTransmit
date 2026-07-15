import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
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
  String _statusText = '正在初始化...';

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
    log('=== SplashPage 开始初始化服务 ===');

    try {
      setState(() => _statusText = '加载 Webhook 配置...');
      log('加载 Webhook 配置');
      final webhookService = GetIt.instance<WebhookService>();
      await webhookService.loadChannels();
    } catch (e) {
      log('加载 Webhook 配置失败: $e');
    }

    try {
      setState(() => _statusText = '加载电池配置...');
      log('加载电池配置');
      final batteryService = GetIt.instance<BatteryService>();
      await batteryService.loadSettings();
    } catch (e) {
      log('加载电池配置失败: $e');
    }

    try {
      setState(() => _statusText = '加载通知记录...');
      log('加载通知记录');
      final notificationService = GetIt.instance<NotificationService>();
      await notificationService.loadRecords();
      await notificationService.loadServiceState();
    } catch (e) {
      log('加载通知记录失败: $e');
    }

    try {
      setState(() => _statusText = '加载过滤配置...');
      log('加载过滤配置');
      final filterService = GetIt.instance<FilterService>();
      await filterService.loadSettings();
    } catch (e) {
      log('加载过滤配置失败: $e');
    }

    try {
      setState(() => _statusText = '初始化更新服务...');
      log('初始化更新服务');
      final updateService = GetIt.instance<UpdateService>();
      await updateService.init();
    } catch (e) {
      log('初始化更新服务失败: $e');
    }

    try {
      setState(() => _statusText = '初始化重试服务...');
      log('初始化重试服务');
      final retryService = GetIt.instance<RetryService>();
      await retryService.init();
    } catch (e) {
      log('初始化重试服务失败: $e');
    }

    setState(() => _statusText = '初始化完成');
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
                  color: const Color(0xFF007AFF),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF007AFF).withValues(alpha: 0.3),
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
              const Text(
                '通知推送助手',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 32),
              Text(
                _statusText,
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
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF007AFF)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
