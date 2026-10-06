part of 'main_page.dart';

/// 导航与配置回调域：各设置/历史/规则页面的打开与结果保存、电池规则 CRUD、
/// 权限检查与前后台服务启停。
/// R3 拆分：mixin 挂在 _MainPageState 上（同 library），行为与拆分前完全一致。
// 同 library 内有意使用 State 的 protected 成员（setState/mounted/context）
// ignore_for_file: invalid_use_of_protected_member
extension _MainPageActions on _MainPageState {
  Future<void> _onChangeLanguage(AppLanguage lang) async {
    final localeService = GetIt.instance<LocaleService>();
    await localeService.setLanguage(lang);
    // 只守卫 rebuild：后面的原生标签同步与父页回调**不该因为本页已销毁而被跳过**
    if (mounted) setState(() {});
    // 同步原生端桌面应用名（最近任务页）为当前实际语言
    AppChannels.notification.invokeMethod(
      'setLocaleLabel',
      localeService.currentLocale.languageCode,
    );
    widget.onLocaleChanged?.call(localeService.currentLocale);
  }

  // 电量/温度设置页不在这份接线里：两页都订阅各自的服务（T16 先例），
  // 从「通知引擎」tab 直接 push。此前这里为 BatteryPage 逐个包一层
  // "调服务 + 父页 setState"，而父页 rebuild 根本到不了被 push 出去的子页 ——
  // 那六层包装等于没有效果的错觉代码。
  Future<void> _checkPermissions() async {
    await _permissionService.checkAllPermissions();
    if (!mounted) return;
    setState(() {});
  }

  /// 首页下拉那一发（#182）：除了权限，还要**立刻**把三族通道各探一遍 ——
  /// 用户拉这个手势的动机就是"首页那张卡上的状态到底准不准"。
  ///
  /// ⚠ 必须 `force: true`：走 stale-only 的话，刚探过的通道一个请求都不发，
  /// 圈转完屏幕上什么都没变 ⇒ 这个手势成了装饰品。回前台那一轮（`didChangeAppLifecycleState`）
  /// 仍是 stale-only，两处不是一件事。
  Future<void> _pullToRefreshHome() async {
    await _checkPermissions();
    await probeChannelsAcrossFamilies(
      force: true,
      onUpdated: () {
        if (mounted) setState(() {});
      },
    );
    if (!mounted) return;
    setState(() {});
  }

  /// 通道健康度的**主动**节奏（#183）：立刻探一轮 + 每 [ChannelHealthStore.staleness] 再一轮。
  ///
  /// 三处细节都是刻意的：
  /// ① 周期读的是那个时效常量，不是另写一个「30 分钟」字面量 —— 周期与时效必须是同一个数，
  ///    否则「记录已过期但下一轮还没到」的空档会重新出现（#174 修的就是这类空档）；
  /// ② 每一轮仍是 stale-only：过期的才真发请求，所以一轮的工作量上界就是过期条数；
  /// ③ 冷启动与每次回前台都重起定时器（先 cancel 再起 ⇒ 反复前后台不会叠出两条轮询）。
  void _startHealthProbeCadence() {
    unawaited(probeChannelsAcrossFamilies());
    _healthProbeTimer?.cancel();
    _healthProbeTimer = Timer.periodic(
      ChannelHealthStore.staleness,
      (_) => unawaited(probeChannelsAcrossFamilies()),
    );
  }

  Future<void> _getDeviceInfo() async {
    await _deviceInfoService.loadDeviceInfo();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _startForegroundService() async {
    await _permissionService.checkAllPermissions();
    if (!_permissionService.notificationListenerGranted) {
      if (mounted) _showNotificationPermissionDialog();
      setState(() {});
      return;
    }
    await _notificationService.startService();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _stopForegroundService() async {
    await _notificationService.stopService();
    if (!mounted) return;
    setState(() {});
  }

  void _openRuleListPage() async {
    await _pushPage<List<NotificationRule>>(
      RuleListPage(
        rules: _filterService.notificationRules,
        onSave: (rules) {
          _filterService.saveNotificationRules(rules);
          if (mounted) setState(() {});
        },
      ),
    );
  }

  void _openPrivacyPolicyPage() {
    _pushPage(const PrivacyPolicyPage());
  }

  /// 顶栏「添加设备」那一格（T43）：与新装了同软件或幻念推送的设备进行匹配 ⇒ 进配对页。
  ///
  /// 复用配对链接那条路用的同一个页（`main_page_actions.dart:220` 那个），不另造入口：
  /// 「谁来配对」这件事的读者只有一个，就是这张名单。
  void _openFnthinkPeersPage() async {
    await _pushPage(const FnthinkPeersPage());
  }

  /// 顶栏「设置」那一格（T43）：设置功能住在「更多」那一格 tab 里，
  /// 所以这里切 tab 而不是 push 一个新页 —— push 会让用户在一个新页里找设置项，
  /// 而那份清单就是「更多」页本身。
  void _openMoreTab() {
    if (!mounted) return;
    if (_currentIndex == 2) return;
    setState(() => _currentIndex = 2);
  }

  void _openHistoryPage({
    String direction = 'forwarded',
    String? focusMessageId,
  }) {
    _pushPage(
      HistoryPage(
        initialDirection: direction,
        // 只有从通知进来时才非空：页面读完那张表之后自动展开这一条（T83）。
        focusMessageId: focusMessageId,
        records: _notificationService.records,
        onClear: () async {
          await _notificationService.clearRecords();
          await _refreshTotalCount();
          await _notificationService.syncDailyCountToNative();
          if (mounted) setState(() {});
        },
        onExport: () async {
          // 安全确认：导出前弹出对话框验证用户意图（UI 统一：iOS 分割线双按钮）
          final l10n = AppLocalizations.of(context);
          final confirm = await IosDialogActions.askConfirm(
            context,
            title: l10n.confirmExport,
            message: l10n.exportConfirmDesc,
            confirmText: l10n.exportBtn,
            destructive: false,
          );
          if (!confirm) {
            return {'success': false, 'message': l10n.exportCancelled};
          }
          final json = await _notificationService.buildExportJson(
            _deviceInfoService.deviceName,
            _deviceInfoService.deviceModel,
            _deviceInfoService.manufacturer,
          );
          final result = await AppChannels.notification.invokeMethod(
            'saveFile',
            {
              'fileName':
                  'notice_export_${DateTime.now().millisecondsSinceEpoch}.json',
              'content': json,
            },
          );
          if (result is Map) return Map<String, dynamic>.from(result);
          return {'success': false, 'message': l10n.exportError};
        },
        onClearToday: () async {
          final count = await _notificationService.clearToday();
          await _refreshTotalCount();
          await _notificationService.syncDailyCountToNative();
          if (mounted) setState(() {});
          return count;
        },
        onClearLastN: (int n) async {
          final count = await _notificationService.clearLastN(n);
          await _refreshTotalCount();
          await _notificationService.syncDailyCountToNative();
          if (mounted) setState(() {});
          return count;
        },
        // 历史记录"现在推送"：暂停期间未发送的消息手动补推
        onPushNow: (record) async {
          await _notificationService.pushRecordNow(record);
          if (mounted) setState(() {});
        },
      ),
      // 返回时重取未读数：在收件档里点开读过的那几条，未读数必须跟着下来，
      // 否则首页那一格会一直举着一个已经不存在的数字（"3 条未读"点进去一条都没有）。
    ).then((_) => _refreshFnthinkInboxUnread());
  }

  /// 首页「幻念收件」那一格的去处：**同一个历史页**，但一进来就停在收件档。
  /// 不另开一页的理由与历史页把"方向"做成数据源切换同源：收件行与转发行是两张表，
  /// 分两页会让用户要记住"哪一类在哪一页"。
  void _openFnthinkInboxPage() => _openHistoryPage(direction: 'received');

  /// 点通知跳进来的那一条：**冷启动那一路**的取法（第一帧之后主动来取）。
  ///
  /// 取不到就**一次导航都不做**。这一发每次打开 App 都会跑，"没有待跳的那条"才是常态 ——
  /// 若在这里顺手打开收件列表，副表现就变成"每次启动都被送到历史页"，
  /// 那比原来的"点了没反应"更难以解释。
  Future<void> _consumeNotificationOpenTargetOnLaunch() async {
    final messageId = await FnthinkInboxDisplay().takeOpenTarget();
    if (messageId == null || !mounted) return;
    _openHistoryPage(direction: 'received', focusMessageId: messageId);
  }

  /// 点通知跳进来的那一条：**App 活着时**的那一路（原生 `onNewIntent` 之后推一发讯号过来）。
  ///
  /// 判据③：拿不到 messageId（系统重放一条没有 extra 的老通知）也要把人送到收件列表 ——
  /// 他确实点了一条通知，"打开列表"与"什么都不发生"之间的差别就是这次点击有没有被接住。
  /// 只有讯号、没有 id 的时候不许猜一条。
  Future<void> _openFnthinkMessageFromNotification() async {
    final messageId = await FnthinkInboxDisplay().takeOpenTarget();
    if (!mounted) return;
    _openHistoryPage(direction: 'received', focusMessageId: messageId);
  }

  /// 点开的那条配对链接（#176 片4）。冷启动那一发与热恢复那一发**共用这一个方法**：
  /// 取只有一个出口（原生 `FnthinkPairLink.take()` 取走即清），所以两条路不可能各弹一次。
  ///
  /// ⚠ 与上面那条通知跳转有一个**方向相反**的判据：`take()` 回 null 在这里意味着
  /// "根本没人点过链接"（这一发每次打开 App 都会跑），所以**一次导航都不做**；
  /// 而通知那一路 null 也要打开列表，因为点击确实发生过。把两条写成同一个形状，
  /// 表现就是"每次启动都被送到幻念推送页"。
  /// 非 null 但判不过 ⇒ 仍然导航过去并说一句：用户点了一条链接，"点了没反应"正是这片要修的缺陷形状。
  ///
  /// ⚠ T94：落点是**绑定页**而不是幻念推送页 —— 一条配对链接的主语就是"我和谁有关系"，
  /// 那件事搬去推送引擎那侧的独立页之后，先开渠道信息页再等用户自己点进绑定，
  /// 等于让用户点完链接还要再点一次"管理已配对的设备"才看到弹层。
  Future<void> _consumeFnthinkPairLink() async {
    final outcome = await FnthinkPairLinkReader(
      contracts: GetIt.instance<FnthinkContractLoader>(),
    ).take();
    if (outcome == null || !mounted) return;
    await _pushPage(FnthinkPeersPage(pairLink: outcome));
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
        l3GrantRows: await _l3GrantRows(),
        manufacturer: _deviceInfoService.manufacturer,
        onRefresh: _checkPermissions,
        onRequestNotificationListenerPermission:
            _permissionService.requestNotificationListenerPermission,
        // T55：通知权限给了之后**顺手**把提升/悬浮通知（POST_PROMOTED_NOTIFICATIONS，36+）
        // 一起申请。
        // ⚠ 为什么挂在这一格而不是权限页另开一行：那一档只在 36+ 存在，在 34/35 的设备上
        //   显示一个永远"已开启"的开关，比不显示更糟（用户会去点一个点不动的东西）。
        // ⚠ 为什么必须真的申请：manifest 里声明了不等于有 —— 声明而不申请，
        //   FLAG_PROMOTED_ONGOING 就是**静默无效**（上不了岛），没有任何报错可查。
        onRequestPostNotificationPermission: () async {
          await _permissionService.requestPostNotificationPermission();
          await _permissionService.requestPromotedNotificationPermission();
        },
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
    if (!mounted) return;
    setState(() {});
  }

  /// 契约 `capabilities.l3.settings` 那几项在这一台设备上的读数（T52 那一格）。
  ///
  /// ⚠ 这里只**取数**，不判状态、不排序：判状态的是 `collectL3GrantRows`（读法只有一处）。
  /// 拿不到读数的一律给 null —— 那显示成「读不到这台设备的状态」，
  /// **猜成 false 会把它显示成「你还没去开」**，而那两件事的修法完全不同（一个是缺口，一个是催用户）。
  Future<List<FnthinkL3GrantRow>> _l3GrantRows() async {
    final l10n = AppLocalizations.of(context);
    // ⚠ 先刷新再读：`serviceRunning` 默认 false，拿旧值出来会被显示成「还没给这台设备授权」——
    // 那是把「我们没问」说成「用户没给」，正是 T52 四态里刻意分开的那两档。
    await _notificationService.loadServiceState();
    final contract = await GetIt.instance<FnthinkContractLoader>().load();
    final settings = FnthinkSettings(contract: contract);
    return collectL3GrantRows(
      contract,
      readers: l3ReadersFrom(
        notification: _permissionService.notificationListenerGranted,
        batteryOptimization: _permissionService.batteryOptimizationIgnored,
        exactAlarm: await _permissionService.canScheduleExactAlarms(),
        // 自启动：原生只有按厂商分流的跳转，系统不提供统一读数。
        autostart: null,
        // 监听开关：原生 `isMonitoringEnabled()`（读 SharedPreferences）经 `isServiceRunning`
        // 通道出来，上面那一次 loadServiceState 就是刷新它。
        monitoring: _notificationService.serviceRunning,
        collectInbox: await settings.receiveEnabled,
      ),
      notes: {
        'autostart': l10n.l3NoteAutostart,
        'monitoring': l10n.l3NoteLivesInFnthinkPage,
        'collect_inbox': l10n.l3NoteLivesInFnthinkPage,
      },
    );
  }

  /// 打开短信/来电监听设置页
  void _openSmsMonitorSettingsPage() async {
    await _pushPage(SmsMonitorSettingsPage(smsService: _smsService));
    if (!mounted) return;
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
      if (!mounted) return;
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
      if (!mounted) return;
      setState(() {});
    }
  }

  /// Webhook 通道页（T07-B）：进**列表页**，那一页自己读写 `WebhookService`。
  ///
  /// 不再传构造期快照、也不再收"整表 pop 回来再 saveChannels"的结果 —— 那份快照正是
  /// "只想改一条却把别的通道一起覆盖"的来源，而 pop 契约让设置页没法只写一条。
  Future<void> _openWebhookChannelsPage() async {
    await _pushPage(const WebhookChannelListPage());
    if (!mounted) return;
    setState(() {});
  }

  /// 打开自建应用通道设置页
  Future<void> _openAppChannelsSettingsPage() async {
    await _pushPage(const AppChannelListPage());
    if (!mounted) return;
    setState(() {});
  }

  /// 温度规则页：页面自己订阅 `TemperatureService` 取最新列表，
  /// 所以这里**不再传快照、也不再回调 setState** —— 那些回调从来没能刷新这个路由
  /// （T16 的病灶就是把 push 那一刻的 List 引用传进去，服务换新列表后页面还看着旧列表）。
  Future<void> _openEmailSettingsPage() async {
    final l10n = AppLocalizations.of(context);
    final emailService = GetIt.instance<EmailService>();
    final channels = await emailService.loadChannels();
    final result = await _pushPage<List<Map<String, dynamic>>>(
      EmailSettingsPage(
        emailChannels: channels
            .map((c) => c.toMap(includePassword: true))
            .toList(),
      ),
    );
    if (result != null) {
      final updatedChannels = result
          .map((m) => EmailChannel.fromMap(m))
          .toList();
      await emailService.saveChannels(updatedChannels);
      if (!mounted) return;
      setState(() {});
      _showInfo(l10n.emailConfigSaved);
    }
  }

  /// 升级后的一次性「主备通道」引导（维护者 1.5.76 反馈 #2 的第二半）。
  ///
  /// 判据全在 [ChannelRoleGuide]（纯函数，可脱离界面逐分支测）；这里只负责"弹一次 + 记一次"。
  /// 记的是**应用版本号**而不是布尔：每个新版本还能再提醒一次，而不是这辈子只提醒一次。
  /// ⚠ 版本号取的是 `AppUpdateManager.currentVersion`，原生读数没回来之前是编译期回退值 ——
  ///   两者不一致时最多多提醒一次（不会漏），所以这里不为它加等待。
  /// 「去设置」直接复用首页那条入口（[_openChannelStatusPage]），不另开一条导航路径。
  Future<void> _maybeShowRoleGuide() async {
    final prefs = await SharedPreferences.getInstance();
    final version = AppUpdateManager.instance.currentVersion;
    final decision = ChannelRoleGuide.decide(
      seenVersion: prefs.getString(ChannelRoleGuide.seenVersionKey),
      currentVersion: version,
      channels: collectActiveChannels(),
    );
    if (!decision.prompt || !mounted) return;

    final l10n = AppLocalizations.of(context);
    final go = await IosDialogActions.askConfirm(
      context,
      title: l10n.roleGuideTitle,
      message: l10n.roleGuideBody(decision.count),
      confirmText: l10n.roleGuideAction,
      cancelText: l10n.roleGuideLater,
      destructive: false,
    );
    // 点「以后再说」也算提示过 —— 它的字面意思就是"以后不要再弹"。
    await prefs.setString(ChannelRoleGuide.seenVersionKey, version);
    if (go) await _openChannelStatusPage();
  }

  /// 通道状态页（T10）：从首页「当前推送通道」那张卡点进来。
  /// 点某一行按族进对应配置页 —— 直接复用上面三个开页方法：
  /// webhook / email 都是"先把数据取进来、退出时把结果存回去"的形态，
  /// 在状态页里再写一份加载与回存逻辑就会和这里漂移。
  Future<void> _openChannelStatusPage() async {
    await _pushPage(
      ChannelStatusPage(
        onOpenChannel: (family) async {
          switch (family) {
            case 'webhook':
              await _openWebhookChannelsPage();
            case 'email':
              await _openEmailSettingsPage();
            default:
              await _openAppChannelsSettingsPage();
          }
        },
      ),
    );
    if (!mounted) return;
    setState(() {});
  }
}
