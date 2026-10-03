import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/platform_channel.dart';
import '../services/services.dart';
import '../services/theme_service.dart';
import '../services/email_service.dart';
import '../services/locale_service.dart';
import '../services/active_channels.dart';
import '../services/channel_role_guide.dart';
import '../services/app_channel_service.dart';
import '../services/fnthink_inbox_service.dart';
import '../services/fnthink_inbox_display.dart';
import '../services/fnthink_contract_loader.dart';
import '../services/fnthink_l3_grants.dart';
import '../services/fnthink_settings.dart';
import '../services/fnthink_pair_link.dart';
import '../services/sms_service.dart';
import '../update_manager.dart';
import '../models/notification_rule.dart';
import '../models/email_channel.dart';
import '../theme/app_colors.dart';
import 'notification_page.dart';
import 'channel_status_page.dart';
import 'notification_engine_page.dart';
import 'more_page.dart';
import 'history_page.dart';
import 'fnthink_push_page.dart';
import 'permission_settings_page.dart';
import 'email_settings_page.dart';
import 'webhook_channel_list_page.dart';
import 'app_filter_page.dart';
import 'keywords_page.dart';
import 'rule_list_page.dart';
import 'privacy_policy_page.dart';
import 'sms_monitor_settings_page.dart';
import 'app_channel_list_page.dart';
import '../widgets/ios_dialog_actions.dart';
import '../widgets/ios_input_dialog.dart';
import '../widgets/ios_progress_dialog.dart';

// R3 拆分：容器页按域拆分（part 共享 State 私有成员，行为零变化）
// main_page_update: 更新检查/弹窗/下载安装
// main_page_dialogs: 语言切换/权限引导/设备名/关于对话框
// main_page_actions: 页面导航与保存回调、电池规则 CRUD、权限检查与服务启停
part 'main_page_update.dart';
part 'main_page_dialogs.dart';
part 'main_page_actions.dart';

class MainPage extends StatefulWidget {
  final ValueChanged<Locale>? onLocaleChanged;

  const MainPage({super.key, this.onLocaleChanged});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _isCheckingUpdate = false;
  bool _isDownloading = false;
  // 首页推送记录总数（统一以 DB 为准，与更多页统计/状态栏统计共用同一数据源）
  int _notificationTotalCount = 0;

  /// 通道健康度的主动探测节奏（#183）。只在**前台**跑：退到后台就停 ——
  /// 后台的网络轮询在 ROM 那里就是"耗电的常驻服务"，被杀之后的那一轮归 §4-9 那颗闹钟管。
  Timer? _healthProbeTimer;

  /// 首页「幻念收件」那一格的未读数。**这一页不数**，只从收件咽喉取（`FnthinkInboxService`），
  /// 于是它与历史页收件档、详情里那个未读点是同一个数。
  int _fnthinkInboxUnread = 0;

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
  final SmsService _smsService = GetIt.instance<SmsService>();
  final FnthinkInboxService _fnthinkInbox =
      GetIt.instance<FnthinkInboxService>();

  /// 首页「当前推送通道」：条目、健康态与显示格式都来自 [collectActiveChannels]（第 6 步单点），
  /// 与历史记录入库时的送达键快照同源。这里只做显示形状。
  /// status 三态（ok / error / unknown）来自健康单点 `channel_health_*`：
  /// **没有新鲜探测结果就报未知，不再一律报正常**（T01）。要让首页少出现未知，
  /// 靠 T09/6e 的非侵入探测，而不是把标签改回恒绿。
  List<Map<String, String>> _getActiveChannels() {
    return collectActiveChannels()
        .map((c) => {'label': c.displayLine, 'status': c.statusLabel})
        .toList(growable: false);
  }

  List<Widget> _buildPages() {
    return [
      NotificationPage(
        notificationPermissionGranted:
            _permissionService.notificationListenerGranted,
        foregroundServiceRunning: _notificationService.serviceRunning,
        notificationCount: _notificationTotalCount,
        activeChannels: _getActiveChannels(),
        smsMonitorEnabled: _smsService.smsMonitorEnabled,
        onStartService: _startForegroundService,
        onStopService: _stopForegroundService,
        onRefresh: _pullToRefreshHome,
        onOpenHistory: _openHistoryPage,
        onOpenChannelStatus: _openChannelStatusPage,
        onOpenPermissionSettings: _openPermissionSettingsPage,
        onToggleSmsMonitor: (v) async {
          await _smsService.saveSmsMonitorEnabled(v);
          // 开关落库是异步的：用户在等待期间离开页面时本 State 已 dispose，
          // 裸 setState 会抛 "setState() called after dispose()"（㊽ 的发版闸门日志里就是这么冒出来的）
          if (!mounted) return;
          setState(() {});
        },
        onOpenSmsMonitorSettings: _openSmsMonitorSettingsPage,
        fnthinkInboxUnread: _fnthinkInboxUnread,
        onOpenInbox: _openFnthinkInboxPage,
      ),
      // 中间那一格＝通知引擎骨架页（T15）：电量/温度两类设备侧告警的入口。
      // 电量页原先直接挂在这里、由本页逐个包回调，现在它订阅自己的服务并由骨架页 push。
      const NotificationEnginePage(),
      MorePage(
        key: ValueKey('more_${_themeService.themeMode.index}'),
        webhookChannels: _webhookService.channels,
        appChannels: GetIt.instance<AppChannelService>().channels,
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
        onOpenWebhookSettings: _openWebhookChannelsPage,
        onOpenEmailSettings: _openEmailSettingsPage,
        onOpenAppChannels: _openAppChannelsSettingsPage,
        onShowDeviceNameDialog: _showDeviceNameDialog,
        onShowAboutDialog: _showAboutDialog,
        onOpenAppFilter: _openAppFilterPage,
        onOpenKeywords: _openKeywordsPage,
        onOpenRules: _openRuleListPage,
        onCheckUpdate: _manualCheckUpdate,
        onOpenPrivacyPolicy: _openPrivacyPolicyPage,
        onChangeLanguage: _onChangeLanguage,
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupMethodChannel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _postInit();
      // T83：冷启动（含进程被杀之后从通知进来）那枚 messageId 由**这里**来取，不在原生推：
      // `configureFlutterEngine` 比这个 handler 装起来更早，那时推出去会静默丢掉，
      // 表现正是维护者报的"点了通知只打开软件"。没有待跳的那条时这一发不会做任何导航。
      unawaited(_consumeNotificationOpenTargetOnLaunch());
      // #176 片4：冷启动是"点开配对链接"那一路（系统直接把 VIEW intent 交给 Activity）。
      // 与上面同一条理由：这一刻原生推不动（handler 还没装），只能由 Dart 来取。
      unawaited(_consumeFnthinkPairLink());
    });
  }

  Future<void> _postInit() async {
    // 自建应用通道：启动加载（送达标签/首页通道状态共用数据源）
    await GetIt.instance<AppChannelService>().loadChannels();
    try {
      // P2：冷启动时把当前实际语言同步给原生端（最近任务页应用名 / Webhook 文案 / 桌面图标别名）。
      // 此前只在"用户手动切换语言"时才调用 setLocaleLabel，system 模式下 flutter.locale 从未写入，
      // 原生端只能退回默认 "zh"，导致系统语言为英文场景下最近任务页仍显示中文；
      // 反向地，曾手动切到英文再切回"默认"时，残留的 flutter.locale="en" 会让中文系统显示英文名。
      // 这里在冷启动即按 LocaleService.currentLocale 校正一次，确保原生端与界面语言一致。
      _syncNativeLocaleOnStartup();

      await _checkPermissions();
      _getDeviceInfo();
      await _batteryService.refreshStatus();
      _batteryService.startRefreshTimer();
      GetIt.instance<TemperatureService>().loadSettings();

      // 首页/更多页/状态栏统计统一：刷新首页总计数 + 同步原生今日计数基数
      await _refreshTotalCount();
      await _notificationService.syncDailyCountToNative();
      // 收件未读数与推送总数同一批取：两个都是"首页那两张计数卡"的数字，分两批读就会出现
      // 一格是新的、一格是旧的。
      await _refreshFnthinkInboxUnread();

      // 加载推送通道配置 + 启动每日归档定时器
      await _webhookService.loadChannels();
      final emailService = GetIt.instance<EmailService>();
      await emailService.loadChannels();
      await _smsService.loadSettings();
      _notificationService.startDailyExport();
      // 通道健康度的主动节奏（#183）：冷启动立刻探一轮，之后每
      // [ChannelHealthStore.staleness] 一轮。必须排在三个 loadChannels 之后 ——
      // 探测目标读的是服务里的内存列表，早一步就是对着空列表交一份"无事可做"。
      _startHealthProbeCadence();
      // 装配链里前面已有 4 个 await：页面在此期间被销毁时，裸 setState 抛异常会被下面的
      // catch 吞掉，连带**跳过** `_checkFirstLaunch()` 与延迟启动服务那一段（㊽ 实测冒出来的正是它）。
      // 守卫放在这里而不是靠 catch：语义不变（页面没了就不该继续），但不再靠异常控制流。
      if (!mounted) return;
      setState(() {});

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
      // 这条 catch 吞掉的不是"一点小毛病"，而是**整条装配链的后半段**：首启引导、
      // 延迟启动前台服务、更新检查都在 catch 之前，异常一抛它们全部没跑（㊽ 的那次实测
      // 就是这个形状）。所以必须让用户看见"这一步没成"，而不是只在日志里留一行。
      // ⚠ 只在 mounted 时说：页面已销毁时 context 不可用，这正是 ㊽ 的原始病灶。
      if (mounted) {
        _showInfo(AppLocalizations.of(context).pageInitFailed('$e'));
      }
    }
  }

  /// P2：把当前语言同步到原生端（幂等）。
  /// system 模式按当前系统语言解析，与 LocaleService.currentLocale 的语义保持一致。
  void _syncNativeLocaleOnStartup() {
    try {
      final localeService = GetIt.instance<LocaleService>();
      final locale = localeService.currentLocale;
      AppChannels.notification.invokeMethod(
        'setLocaleLabel',
        locale.languageCode,
      );
    } catch (e) {
      debugPrint('同步原生语言失败: $e');
    }
  }

  /// 刷新首页"推送历史"总条数（以 DB 为准，统计口径与更多页/状态栏统一）
  Future<void> _refreshTotalCount() async {
    final count = await _notificationService.getTotalCount();
    if (mounted && count != _notificationTotalCount) {
      setState(() => _notificationTotalCount = count);
    }
  }

  /// 刷新首页「幻念收件」那一格的未读数。
  ///
  /// ⚠ 取失败时**保留上一次的数**，不回落成 0：0 在这张卡上的意思是"没有未读"，
  /// 而"没读到"与"没有"是两件事 —— 把它画成 0 等于当着用户的面宣布消息没了（本仓那条
  /// "不静默丢失"的不变量也包括不悄悄把待读说成已读）。首帧本来就是 0，那时还没有过承诺。
  Future<void> _refreshFnthinkInboxUnread() async {
    try {
      final n = await _fnthinkInbox.unreadCount();
      if (mounted && n != _fnthinkInboxUnread) {
        setState(() => _fnthinkInboxUnread = n);
      }
    } catch (e) {
      debugPrint('[fnthink] 收件未读数没取到，沿用上一个数: $e');
    }
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final hasLaunched = prefs.getBool('has_launched') ?? false;
    if (!hasLaunched) {
      await prefs.setBool('has_launched', true);
    }
    await _maybeShowRoleGuide();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _batteryService.stopRefreshTimer();
    _healthProbeTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      // 回到前台时补偿拉取 Activity 销毁期间丢失的送达结果（修复"一直显示推送中"）
      unawaited(_notificationService.drainPendingDeliveries());
      // 收件未读数也在这里重取：收货循环在后台跑，它落库的那几条不会往 UI 推事件。
      // 不接实时事件总闸的理由是这一格的时效要求是"回到前台就该对"，而不是"秒级跳变"。
      unawaited(_refreshFnthinkInboxUnread());
      // 通道健康度同理（#174）：6h 时效一过，"上次成功"会被判成「未知」，而此前只有
      // 进那三个族页才会重探 —— 首页这张卡/状态页会一直挂着"未知"没人管。
      // 通道健康度同理（#174 → #183）：时效一过，"上次成功"会被判成「未知」，而此前只有
      // 走进那三个族页才会重探 —— 首页这张卡/通道状态页会一直挂着"未知"没人管。
      // 打开软件（含回前台）立刻探一轮，顺带把定时器重新起起来。
      // 仍是 stale-only：真发请求的只有过时效的那几条 —— 周期与时效是同一个数，
      // 所以"最迟一轮"就等于"过期的那条最多撑一轮"。
      _startHealthProbeCadence();
      final localeService = GetIt.instance<LocaleService>();
      if (localeService.shouldPromptSwitch) {
        await _showLanguageSwitchDialog(localeService);
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // 后台不留网络轮询：ROM 把它算成"耗电的常驻服务"。进程被杀之后的那一轮归 §4-9 那颗闹钟。
      _healthProbeTimer?.cancel();
    }
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
    AppChannels.notification.setMethodCallHandler((call) async {
      if (call.method == 'onNotificationReceived') {
        final Map<String, dynamic> record = Map<String, dynamic>.from(
          call.arguments,
        );
        _notificationService.addRecord(record);
        _refreshTotalCount();
        setState(() {});
      } else if (call.method == 'onDeliveryResult') {
        // webhook 送达结果回传：更新对应记录的状态
        final Map<String, dynamic> data = Map<String, dynamic>.from(
          call.arguments,
        );
        await _notificationService.updateDelivery(
          data['notificationId']?.toString() ?? '',
          data['webhookType']?.toString() ?? '',
          data['status']?.toString() ?? '',
          data['message']?.toString() ?? '',
          httpCode: (data['httpCode'] as num?)?.toInt() ?? 0,
          channelUrl: data['channelUrl']?.toString() ?? '',
          viaBackup: data['viaBackup'] == true,
        );
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
      } else if (call.method == 'onFnthinkNotificationOpened') {
        // T83：App 还活着时点了一条幻念收件通知。原生这一发**只交一个"去问一次"的讯号**，
        // id 仍然只从 `takeFnthinkOpenTarget` 那一个出口走 ⇒ 同一条不会经由两个通道各跳一次。
        unawaited(_openFnthinkMessageFromNotification());
      } else if (call.method == 'onFnthinkPairLinkReceived') {
        // #176 片4：App 活着时点开了配对链接。同样只交一个讯号 —— 那一串只从
        // `takeFnthinkPairLink` 一个出口走，所以冷启动那一发与这一发不可能各弹一次输入层。
        unawaited(_consumeFnthinkPairLink());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pages = _buildPages();
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          setState(() => _currentIndex = index);
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: l10n.tabHome,
          ),
          // 中间这一格是「通知引擎」：电量 / 温度 / 设备状态这类**设备侧触发**的告警
          // 都归它（内容骨架 = T15）。本批只换导航形状，child 暂时仍是电量页 ——
          // 顺序上先立形状，是为了让集成测试的 tab 文案只被改动一次。
          NavigationDestination(
            icon: const Icon(Icons.bolt_outlined),
            selectedIcon: const Icon(Icons.bolt),
            label: l10n.tabNotificationEngine,
          ),
          NavigationDestination(
            icon: const Icon(Icons.more_horiz),
            selectedIcon: const Icon(Icons.more_horiz),
            label: l10n.tabMore,
          ),
        ],
      ),
    );
  }
}
