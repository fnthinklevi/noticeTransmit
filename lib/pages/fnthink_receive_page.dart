import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:get_it/get_it.dart';

import '../l10n/app_localizations.dart';
import '../services/channel_display.dart';
import '../services/channel_health_store.dart';
import '../models/fnthink_peer.dart';
import '../services/fnthink_contract_loader.dart';
import '../services/fnthink_inbox_channel_check.dart';
import '../services/fnthink_presence_scheduler.dart';
import '../services/fnthink_peer_service.dart';
import '../services/fnthink_receive_coordinator.dart';
import '../services/fnthink_relay_consent.dart';
import '../services/fnthink_settings.dart';
import '../services/fnthink_start_failure_display.dart';
import '../services/permission_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_info_note_box.dart';
import '../widgets/fnthink_card.dart';
import '../widgets/help_note_button.dart';
import '../widgets/ios_dialog_actions.dart';
import '../widgets/primary_action_button.dart';

/// 这一页要碰的四样依赖。
///
/// 与 `FnthinkSettingsDeps` 分开而不是复用它：那一包还带身份与端点（那是「这台设备是谁」，
/// 留在幻念推送页），而这一页只管「别人对本机做什么」—— 收不收、间隔多少、谁来指挥。
class FnthinkReceiveDeps {
  FnthinkReceiveDeps({
    required this.contracts,
    required this.coordinator,
    required this.presence,
    required this.loadPeers,
    this.healthOf,
    this.permission,
    this.inboxCheck,
  });

  factory FnthinkReceiveDeps.fromLocator() => FnthinkReceiveDeps(
    contracts: GetIt.instance<FnthinkContractLoader>(),
    coordinator: GetIt.instance<FnthinkReceiveCoordinator>(),
    // 「下一次自己醒」那一行只**读**这一个源（§4-9 片1d）：页面既不自己算间隔、也不自己排闹钟。
    presence: GetIt.instance<FnthinkPresenceScheduler>(),
    // T176：后台自检要读「精确闹钟 / 忽略电池优化」两项授权。测试构造时不传 ⇒ 那两行不画。
    permission: GetIt.instance<PermissionService>(),
    // T173：收件通知渠道自检（读状态 / 重建 / 测试通知）。
    inboxCheck: FnthinkInboxChannelCheck(),
    // 远程指令的「发一条」要挑收件人，而名单只能从协调者那一个读咽喉取。
    // 它不是「接收设置需要名单」，而是「这一格要推的那个页需要」——
    // 另开一条读库的路就会有两个排序口径。
    loadPeers: GetIt.instance<FnthinkPeerService>().list,
    healthOf: (host) =>
        GetIt.instance<ChannelHealthStore>().of(kFnthinkServerFamily, host),
  );

  final FnthinkContractLoader contracts;
  final FnthinkReceiveCoordinator coordinator;
  final FnthinkPresenceScheduler presence;

  /// 名单读口（仅供远程发送那一格挑收件人）。
  final Future<List<FnthinkPeer>> Function() loadPeers;

  /// 读某台服务器的健康度（null = 这台没装配健康度链路 ⇒ 那一行"从没发过"）。
  final ChannelHealth? Function(String host)? healthOf;

  /// 权限读数（T176）。null = 测试没注入 ⇒ 自检那两行不画。
  final PermissionService? permission;

  /// 收件渠道自检（T173）。null = 测试没注入 ⇒ 那一张卡不画。
  final FnthinkInboxChannelCheck? inboxCheck;
}

/// 接收设置（T44 的② + T56 同意门 + T88 间隔 + §4-9 保活那一行）与远程执行（T94 片2）。
///
/// 它从幻念推送页里独立出来，是因为维护者把幻念推送分成了两块：**推送引擎**那侧收
/// 渠道设置·设备绑定·发起推送·接收设置·远程执行，**更多页**那处只留这台设备的渠道信息
/// （服务地址·本机身份·端点·隐私边界）。而"收不收、间隔多少、谁来指挥我"与
/// "我是谁、走哪台服务器"是**两个决定** —— 混在一页里，用户改完一件事分不清自己刚动的是哪一个，
/// 而这两个的代价完全不同（关掉接收 = 收不到东西，换地址码 = 对面全部要重新配对）。
class FnthinkReceivePage extends StatefulWidget {
  const FnthinkReceivePage({super.key, this.deps});

  final FnthinkReceiveDeps? deps;

  @override
  State<FnthinkReceivePage> createState() => _FnthinkReceivePageState();
}

class _FnthinkReceivePageState extends State<FnthinkReceivePage>
    with WidgetsBindingObserver {
  late final FnthinkReceiveDeps _deps;
  late final FnthinkReceiveCoordinator _coordinator;

  FnthinkSettings? _settings;

  /// 契约不可用的原话。非空时整页只显示这一条 —— 开关与间隔的默认值都要从契约读，
  /// 拿不到契约还让人翻开关，等于把一个值写进没人能解释的地方。
  String? _contractError;

  /// 总开关（prefs）与同意门（prefs）是**两个真值**，互不派生：前者是"要不要收"，
  /// 后者是"允不允许经服务器中转"。合成一个字段就会在某处漏掉重读，而漏掉的那一处
  /// 表现是"界面说已同意、协调者说不认"。
  bool _enabled = false;
  bool _consented = false;

  /// 撤销那一发的结论（T119）。null = 这一页还没撤销过 —— 撤销之后"已同意"那行字会消失，
  /// 用户需要一句"那刚才发生了什么、什么没被删"，否则他分不清"我撤销成功了"与"页面坏了"。
  String? _consentResult;

  bool _running = false;
  String? _startNote;
  String? _lastRound;
  String? _roundNote;

  /// T60（approach B）：这一台对着当前服务器最近一次发送通没通过。
  ChannelHealth? _serverHealth;

  /// 「下一次自己醒」那一行读回来的那一份（null = 还没读到，或读口抛了）。
  ///
  /// ⚠ null 与 `armed == false` 是**两件事**：前者是"不知道"，后者是"确实没排"。
  FnthinkPresenceStatus? _presence;

  /// T176 自检：上一次**成功**收取的时刻（0 = 从没成功过）。
  int _lastRoundAt = 0;

  /// T176 自检：两项后台授权（null = 还没读到 / 测试没注入权限服务）。
  bool? _exactAlarmGranted;
  bool? _batteryOptimizationIgnored;

  /// T173：收件渠道读数与自检动作的结果。
  FnthinkInboxChannelState? _inboxChannelState;
  String? _inboxCheckNote;
  bool _checkingInbox = false;

  /// T180：读到这一份排程时的"此刻"（毫秒）。退避剩余时间按它算：
  /// 每次 `_readPresence` 刷新，不在 `build` 里另读一次墙钟（同一屏的几行来自同一时刻）。
  int _backoffNow = 0;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _deps = widget.deps ?? FnthinkReceiveDeps.fromLocator();
    _coordinator = _deps.coordinator;
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从系统权限页回来 / 从后台回来：读数都可能在后台变了。只重读，不主动跑一轮
    // （回前台补收那一发在根页面，整个 App 共用一次）。
    if (state == AppLifecycleState.resumed) unawaited(_readPresence());
  }

  Future<void> _load() async {
    final FnthinkContract contract;
    try {
      contract = await _deps.contracts.load();
    } on FnthinkContractUnavailable catch (e) {
      if (mounted) setState(() => _contractError = e.reason);
      return;
    }
    final settings = FnthinkSettings(contract: contract);
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _running = _coordinator.isRunning;
    });
    await Future.wait<void>([_readEnabled(), _readPresence()]);
  }

  /// 「下一次自己醒」那一行（§4-9 片1d）—— 读的是**原生那份排程**，不是本机自己算的。
  ///
  /// T176：同一发把自检要的另外三份读数一起取回来（上次收取 / 两条 WorkManager 链 /
  /// 精确闹钟与电池优化授权）。它们回答的是同一个问题："锁屏之后还有没有人去收货"，
  /// 分成几次读会让屏幕上的四行来自四个时刻。
  Future<void> _readPresence() async {
    FnthinkPresenceStatus? status;
    int lastRoundAt = 0;
    bool? exactAlarm;
    bool? batteryIgnored;
    try {
      status = await _deps.presence.status();
    } catch (_) {
      // 读口抛 ⇒ 这一行**不画**（"还没读到"与"确实没排"是两句不同的话，见字段注释）。
      status = null;
    }
    try {
      lastRoundAt = await _coordinator.lastRoundAt();
    } catch (_) {}
    final permission = _deps.permission;
    if (permission != null) {
      try {
        await permission.checkAllPermissions();
        exactAlarm = await permission.canScheduleExactAlarms();
        batteryIgnored = permission.batteryOptimizationIgnored;
      } catch (e) {
        debugPrint('[fnthink] 读后台授权失败：$e');
      }
    }
    final inboxState = _deps.inboxCheck == null
        ? null
        : await _deps.inboxCheck!.state();
    if (!mounted) return;
    setState(() {
      _presence = status;
      _lastRoundAt = lastRoundAt;
      _exactAlarmGranted = exactAlarm;
      _batteryOptimizationIgnored = batteryIgnored;
      _inboxChannelState = inboxState;
      _backoffNow = DateTime.now().millisecondsSinceEpoch;
    });
  }

  bool get _backoffActive {
    final status = _presence;
    if (status == null || status.backoffSeconds <= 0) return false;
    final now = _backoffNow > 0
        ? _backoffNow
        : DateTime.now().millisecondsSinceEpoch;
    return status.nextRoundAt > now;
  }

  String _backoffText(AppLocalizations l10n) {
    final status = _presence!;
    final now = _backoffNow > 0
        ? _backoffNow
        : DateTime.now().millisecondsSinceEpoch;
    final total = ((status.nextRoundAt - now) / 1000).ceil().clamp(0, 1 << 30);
    return l10n.fnthinkPresenceBackoff(total ~/ 60, total % 60);
  }

  Future<void> _refreshInboxCheck() async {
    final check = _deps.inboxCheck;
    if (check == null || _checkingInbox) return;
    setState(() {
      _checkingInbox = true;
      _inboxCheckNote = null;
    });
    final state = await check.state();
    if (!mounted) return;
    setState(() {
      _checkingInbox = false;
      _inboxChannelState = state;
    });
  }

  Future<void> _rebuildInboxChannel() async {
    final check = _deps.inboxCheck;
    if (check == null || _checkingInbox) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _checkingInbox = true);
    final id = await check.rebuild();
    final state = await check.state();
    if (!mounted) return;
    setState(() {
      _checkingInbox = false;
      _inboxChannelState = state;
      _inboxCheckNote = id == null
          ? l10n.fnthinkInboxSelfCheckTestFailed
          : l10n.fnthinkInboxSelfCheckRebuilt(id);
    });
  }

  Future<void> _testInboxNotification() async {
    final check = _deps.inboxCheck;
    if (check == null) return;
    final l10n = AppLocalizations.of(context);
    final ok = await check.showTest();
    if (!mounted) return;
    setState(() {
      _inboxCheckNote = ok
          ? l10n.fnthinkInboxSelfCheckTestSent
          : l10n.fnthinkInboxSelfCheckTestFailed;
    });
  }

  String _inboxIssueText(
    AppLocalizations l10n,
    FnthinkInboxChannelIssue issue,
  ) => switch (issue) {
    FnthinkInboxChannelIssue.notificationsDisabled =>
      l10n.fnthinkInboxIssueNotificationsOff,
    FnthinkInboxChannelIssue.channelMissing =>
      l10n.fnthinkInboxIssueChannelMissing,
    FnthinkInboxChannelIssue.notHighImportance => l10n.fnthinkInboxIssueNotHigh,
    FnthinkInboxChannelIssue.noSound => l10n.fnthinkInboxIssueNoSound,
    FnthinkInboxChannelIssue.noVibration => l10n.fnthinkInboxIssueNoVibration,
    FnthinkInboxChannelIssue.lockscreenNotPublic =>
      l10n.fnthinkInboxIssueLockscreen,
  };

  Future<void> _requestExactAlarm() async {
    await _deps.permission?.requestExactAlarmPermission();
    await _readPresence();
  }

  Future<void> _requestIgnoreBatteryOptimization() async {
    await _deps.permission?.requestBatteryOptimization();
    await _readPresence();
  }

  /// 「下一次自己醒」那句话的时刻部分。本机不自己算时钟（那是一份第二的计时账），
  /// 只把原生交上来的那个毫秒数格式化一下。
  String _presenceClock(int millis) {
    final at = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
  }

  /// T196：后台一轮的读数。优先用结束时刻；还在跑时用开始时刻并把结果读成 `running`。
  /// 两个时刻都是 0 才是真的"还没有记录"。
  String _diagWorkerText(AppLocalizations l10n, FnthinkDiagSnapshot diag) {
    final at = diag.lastWorkerFinishedAt > 0
        ? diag.lastWorkerFinishedAt
        : diag.lastWorkerStartedAt;
    if (at <= 0) return l10n.fnthinkDiagWorkerNever;
    final result = diag.lastWorkerResult.isEmpty
        ? 'running'
        : diag.lastWorkerResult;
    return l10n.fnthinkDiagWorkerAt(result, _presenceClock(at));
  }

  String _diagBool(AppLocalizations l10n, bool value) =>
      value ? l10n.fnthinkDiagYes : l10n.fnthinkDiagNo;

  /// 那一行落在哪一档（T140 层2 察）。判据的**唯一作者**是 `judgePresenceLiveness`：
  /// 页面只把手上那三份事实交进去，不在这儿自己比 `nextRoundAt == 0` —— 那一比就会长出
  /// 第二份"什么叫死了"，而它和原生的 cancel 语义迟早漂开（cancel 把 cadence 也清了）。
  FnthinkPresenceLiveness _presenceLiveness() => judgePresenceLiveness(
    enabled: _enabled,
    consented: _consented,
    status: _presence!,
  );

  /// 没有 cadence 就没有「下一次」：只把 clock 那零点几秒写成「下一次」，
  /// 用户会以为这下一下随时都会发生。
  String _presenceText(AppLocalizations l10n) {
    final status = _presence!;
    // T181 B：常驻轮询档不是"下一次自己醒"，它就是"现在一直在收"。
    // 锁没拿上时如实说——"已开启"与"真的能醒"是两件事。
    if (status.liveMode && _enabled && _consented) {
      return status.wakeLock
          ? l10n.fnthinkPresenceLive(status.liveSeconds)
          : l10n.fnthinkPresenceLiveNoLock(status.liveSeconds);
    }
    switch (_presenceLiveness()) {
      case FnthinkPresenceLiveness.dead:
        // 真坏的那一档：这台曾经醒过、现在没排上，而开关与同意都还在。
        return l10n.fnthinkPresenceDead;
      case FnthinkPresenceLiveness.pendingFirstRound:
        // 不是故障：刚把接收开起来，第一轮还没跑完（闹钟是每一轮结束时续排的）。
        return l10n.fnthinkPresencePendingFirstRound;
      case FnthinkPresenceLiveness.configIncomplete:
        return l10n.fnthinkPresenceAsleep;
      case FnthinkPresenceLiveness.armed:
        final clock = _presenceClock(status.nextRoundAt);
        // T180：退避那一颗**不是常设节奏** —— 这一行不写"每 N 秒"，退避另起一行说。
        if (_backoffActive) return l10n.fnthinkPresenceNextNoCadence(clock);
        return status.cadenceSeconds > 0
            ? l10n.fnthinkPresenceNext(clock, status.cadenceSeconds)
            : l10n.fnthinkPresenceNextNoCadence(clock);
    }
  }

  /// 「立即恢复」（T140 层3 复）：只走 `startIfEnabled` 那条**现成的**咽喉 ——
  /// 与开关同一条路。在这儿新写一条"起链"的路，就等于让"什么时候该醒"有两套说法，
  /// 而那正是这一片要消掉的东西（旧形状里限流一发就撤闹钟，撤的人与排的人不是同一个）。
  Future<void> _recoverPresence() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final result = await _coordinator.startIfEnabled();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _running = _coordinator.isRunning;
      // 起成了就把话留在上一档（那一行本身会变成"下一次 HH:mm:ss"，比一句"已恢复"更实）；
      // 起不成才要说理由 —— 那些理由与开关那一发用的是同一个作者。
      _startNote = result.started
          ? null
          : _describeStartFailure(result.reason, l10n);
    });
    await _readPresence();
  }

  Future<void> _readEnabled() async {
    final settings = _settings;
    if (settings == null) return;
    final values = await Future.wait<bool>([
      settings.receiveEnabled,
      settings.hasRelayConsent(),
    ]);
    if (!mounted) return;
    setState(() {
      _enabled = values[0];
      _consented = values[1];
    });
    await _readServerHealth();
  }

  /// 服务器健康度那一行（T60 approach B）。只在**同意之后**才有意义 ——
  /// 没同意时任何一发都在本机就被挡下，画出来只会把"还没同意"读成"服务器坏了"。
  Future<void> _readServerHealth() async {
    final healthOf = _deps.healthOf;
    final settings = _settings;
    if (healthOf == null || settings == null) return;
    String host;
    try {
      host = await settings.host;
    } on FnthinkSettingsInvalid {
      // 地址坏掉时不是"服务器连不上"，是"根本没有服务器可比" ⇒ 这一格不画。
      return;
    }
    final health = healthOf(host);
    if (!mounted) return;
    setState(() => _serverHealth = health);
  }

  /// 起不来那句（T139 ① / T180）。换人话的判据只有一位作者
  /// （`fnthinkStartFailureText`），这一页不另抄正则。
  String _describeStartFailure(String reason, AppLocalizations l10n) =>
      fnthinkStartFailureText(l10n, reason);

  String _serverHealthText(AppLocalizations l10n) {
    final health = _serverHealth;
    if (health == null) return l10n.fnthinkHealthNever;
    return health.reachable
        ? l10n.fnthinkHealthReachable
        : l10n.fnthinkHealthUnreachable;
  }

  /// 同意门（T56）。**同意本身也过二次确认**：这一下点下去的后果是
  /// **通知内容此后可以经服务器中转**，比"换一枚地址码"更需要先看一眼。
  /// 一次性同意「通知内容经服务器中转」（T56）。三情形说明放在确认弹层里，确认键才写下同意。
  ///
  /// ⚠ **同意是一次显式动作**，所以它走 `askConfirm` 而不是「点一下开关就算」：
  /// 这一格的后果是「通知内容会离开这台设备、经服务器中转」，那是本产品里最重的一件事，
  /// 静默发生就是把用户没做过的决定代他做了。取消 ⇒ 一个字节都不写，也不改任一开关。
  Future<void> _grantConsent() async {
    if (_busy) return;
    final settings = _settings;
    if (settings == null) return;
    final l10n = AppLocalizations.of(context);
    final ok = await IosDialogActions.askConfirm(
      context,
      title: l10n.fnthinkConsentTitle,
      message: l10n.fnthinkConsentMsg,
      confirmText: l10n.fnthinkConsentAgree,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    // T76 ⓫ 首启选路：**在同意之后**选一次（T76 §6 ③ 的次序），不在这之前 ——
    // 选路要发一次 HTTPS 请求，而「用户还没同意把内容交给服务器中转」那一刻连字节都不该出机。
    // 选完落盘 ⇒ 之后无论探测怎么变都不再自动改（§6 ⑤）。
    // ⚠ 探不到就落契约 default（`ensureFirstRunHost` 内部已兜），这一格不许因为探测失败
    //   而把「同意」这一步卡住 —— 用户已经点了同意，卡住他的后果比选错服务器更糟。
    await settings.ensureFirstRunHost();
    await settings.grantRelayConsent();
    if (!mounted) return;
    setState(() {
      _consented = true;
      _busy = false;
    });
    // 同意之前收货循环起不来（协调者 early-return not-consented）；用户刚同意 ⇒ 若开关已开，
    // 立刻试一次起来，让「同意」这件事当场有可见后果（否则要等下一轮后台闹钟）。
    if (_enabled) unawaited(_toggleReceive(true));
  }

  /// 撤销那一发（T119）：确认后清那一枚键，然后**重读状态** —— 于是这一页自己回到
  /// 「还没同意」那一屏（`fnthink-consent-pending`），不留一个"写着已同意而其实已撤销"的中间态。
  /// 取消 ⇒ 这里什么都不写（连这行结论都不写：没发生过的事不该出现在屏幕上）。
  Future<void> _revokeConsent() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context);
    final revoked = await confirmAndRevokeRelayConsent(
      context: context,
      settings: _settings,
    );
    if (!mounted) return;
    if (!revoked) {
      setState(() => _busy = false);
      return;
    }
    setState(() {
      _consented = false;
      _consentResult = l10n.fnthinkConsentRevokeDone;
      _busy = false;
    });
    await _readEnabled();
  }

  /// 翻总开关。⚠ **起不来时不回弹**：prefs 里已经是"开"的那一份，回弹说的是"你没点上"这句假话，
  /// 而真相要两格分开：开关=用户要的，状态行=实际的。
  /// 开关。⚠ 这里有一个必须写下来的取舍：**开关那一格显示的是「用户要的状态」（prefs 真值），
  /// 运行那一格显示的是「实际状态」**，两者不一致时把原话贴在下面，而不是把开关回弹。
  /// 回弹会让他以为没点上而再点一次（结果一样），而「已开但起不来」才是可诊断的那句话。
  Future<void> _toggleReceive(bool value) async {
    final settings = _settings;
    if (settings == null || _busy) return;
    final l10n = AppLocalizations.of(context);
    // 开关那一格跟着**写进 prefs 的那一份**走：先落库再改口，界面与 prefs 不会各说一段。
    setState(() {
      _busy = true;
      _enabled = value;
    });
    await settings.setReceiveEnabled(value);
    if (value) {
      final result = await _coordinator.startIfEnabled();
      if (!mounted) return;
      setState(() {
        _running = _coordinator.isRunning;
        // 「没同意中转」是本片新增的那一档，机器理由 `not-consented` 用户读不懂 ⇒ 换成人话。
        // T139 ①：注册被限流那一档同理 —— 那一句必须说出"还要等多久、会自动重试"，
        // 只显示机器码或"没在跑"，用户读到的还是"坏了"。
        _startNote = result.started
            ? null
            : (result.reason == 'not-consented'
                  ? l10n.fnthinkConsentNotGranted
                  : _describeStartFailure(result.reason, l10n));
        _busy = false;
      });
      // 开关翻开 ⇒ 协调者刚排过闹钟（或刚因为起不来撤过）：那一行必须跟着重读，
      // 否则它会一直显示翻开之前的样子。不 await：这是显示刷新，开关那一发该做的已经做完了。
      unawaited(_readPresence());
      return;
    }
    _coordinator.stop();
    if (!mounted) return;
    setState(() {
      _running = false;
      _startNote = null;
      _busy = false;
    });
    unawaited(_readPresence());
  }

  /// 立即收取（手动跑一轮）。
  ///
  /// "还在途""开关没开""这一轮取到 0 条"是三件不同的事，三句都要分开说 ——
  /// 合并之后用户只剩一句"好像没反应"。
  Future<void> _receiveNow() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final round = await _coordinator.receiveOnce();
    if (!mounted) return;
    setState(() {
      _running = _coordinator.isRunning;
      if (round.report == null) {
        // T139 ③：没跑成的原因各有各的话 —— "接收没开"只许说给真的没开的那一档，
        // 限流/没同意/签不出名盖在那句话下面，用户照着修的层级就是错的。
        _roundNote = round.skipReason == 'disabled'
            ? l10n.fnthinkReceiveDisabled
            : round.skipReason == 'not-consented'
            ? l10n.fnthinkConsentNotGranted
            : _describeStartFailure(round.skipReason ?? '', l10n);
        _lastRound = null;
      } else if (round.report!.skipped) {
        _roundNote = l10n.fnthinkReceiveSkipped;
      } else {
        _roundNote = null;
        // summary 只有计数（没有标题、正文与消息 id），所以可以直接上界面。
        _lastRound = round.report!.summary;
        _startNote = null;
      }
      _busy = false;
    });
    await _readPresence();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final error = _contractError;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.fnthinkReceive)),
      backgroundColor: AppColors.bgColor(context),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (error != null)
            FnthinkNote(keyName: 'fnthink-contract-error', text: error)
          else ...[
            // 远程执行那一格 T97 片C 搬去「远程控制」独立页了 —— 那件事（别人能不能指挥这台）
            // 与这一页（这台收不收别人的东西）代价不同，混一页会让"我关了接收"被读成
            // "远程执行也关了"。入口在通知引擎 hub 那一行（带前置三选一）。
            _buildReceiveCard(l10n),
            if (_deps.inboxCheck != null) _buildInboxCheckCard(l10n),
          ],
        ],
      ),
    );
  }

  /// T173：收件通知自检。只读原生渠道状态；三个动作都不改收件设置。
  Widget _buildInboxCheckCard(AppLocalizations l10n) {
    final state = _inboxChannelState;
    final issues = state == null
        ? const <FnthinkInboxChannelIssue>[]
        : fnthinkInboxChannelIssues(state);
    return FnthinkCard(
      title: l10n.fnthinkInboxSelfCheckTitle,
      children: [
        if (state != null)
          FnthinkNote(
            keyName: 'fnthink-inbox-selfcheck-state',
            text: issues.isEmpty
                ? l10n.fnthinkInboxSelfCheckOk
                : issues.map((i) => _inboxIssueText(l10n, i)).join('、'),
          ),
        if (_inboxCheckNote case final String note)
          FnthinkNote(keyName: 'fnthink-inbox-selfcheck-note', text: note),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FnthinkInlineAction(
              key: const ValueKey('fnthink-inbox-selfcheck-refresh'),
              label: l10n.fnthinkInboxSelfCheckRefresh,
              tone: FnthinkActionTone.neutral,
              onPressed: _checkingInbox ? null : _refreshInboxCheck,
            ),
            FnthinkInlineAction(
              key: const ValueKey('fnthink-inbox-selfcheck-settings'),
              label: l10n.fnthinkInboxSelfCheckSettings,
              tone: FnthinkActionTone.neutral,
              onPressed: () => _deps.inboxCheck?.openSystemSettings(),
            ),
            FnthinkInlineAction(
              key: const ValueKey('fnthink-inbox-selfcheck-rebuild'),
              label: l10n.fnthinkInboxSelfCheckRebuild,
              tone: FnthinkActionTone.neutral,
              onPressed: _checkingInbox ? null : _rebuildInboxChannel,
            ),
            FnthinkInlineAction(
              key: const ValueKey('fnthink-inbox-selfcheck-test'),
              label: l10n.fnthinkInboxSelfCheckTest,
              tone: FnthinkActionTone.neutral,
              onPressed: _testInboxNotification,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReceiveCard(AppLocalizations l10n) {
    return FnthinkCard(
      title: l10n.fnthinkReceive,
      children: [
        Row(
          children: [
            Expanded(
              child: AppInfoNoteBox(
                text: l10n.fnthinkReceiveDesc,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // onChanged 传 null 就是灰态：契约拿不到时这一格不许被翻开。
            CupertinoSwitch(
              key: const ValueKey('fnthink-receive-switch'),
              value: _enabled,
              onChanged: _contractError == null && !_busy
                  ? _toggleReceive
                  : null,
            ),
          ],
        ),
        FnthinkStatusRow(
          keyName: 'fnthink-receive-status',
          dot: _running,
          text: _running ? l10n.fnthinkStatusRunning : l10n.fnthinkStatusIdle,
        ),
        // T137 验收③：只报**我们自己那侧** + 一键跳系统。
        // 厂商（MIUI 等）的悬浮/锁屏/声音开关不在任何 APK 可读的 API 里（六厂商官方
        // 口径一致），所以这里没有"读回来告诉你哪一档被关了"的那一半 —— 写得出"我们
        // 建的渠道是什么样"，厂商那几枚只能请用户去系统里亲眼核对，跳转直达那一页。
        // T149 片2：那三档 + 厂商层的**整段**摆在这儿读不动（127 字），挪进问号弹层，
        // 页面只留一句"由系统那一侧决定"——正文一字没删（维护者 2026-10-12 第 4 条）。
        HelpNoteRow(
          noteKey: 'fnthink-channel-disclosure',
          helpKey: 'fnthink-channel-disclosure-help',
          text: l10n.fnthinkChannelDisclosureShort,
          helpTitle: l10n.fnthinkReceive,
          helpBody: l10n.fnthinkChannelDisclosure,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: SecondaryActionButton(
            keyName: 'fnthink-open-channel-settings',
            label: l10n.fnthinkOpenChannelSettings,
            onPressed: () =>
                GetIt.instance<PermissionService>().openInboxChannelSettings(),
          ),
        ),
        // 同意门（T56）：**开着开关也不等于同意中转**。这一行在没同意时始终在场，
        // 并把三情形说明摆在按钮后面 —— 用户要能一眼看出"关掉接收"与"不让人中转内容"
        // 是两件不同的事，而后者没有任何一处会自动替他做。
        if (!_consented) ...[
          FnthinkNote(
            keyName: 'fnthink-consent-pending',
            text: l10n.fnthinkConsentPending,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: CupertinoButton.filled(
              key: const ValueKey('fnthink-consent-agree'),
              onPressed: _busy ? null : _grantConsent,
              child: Text(l10n.fnthinkConsentTitle),
            ),
          ),
        ] else ...[
          FnthinkNote(
            keyName: 'fnthink-consent-granted',
            text: l10n.fnthinkConsentGranted,
          ),
          // 撤销那一发（T119）：**同意是一次显式动作，撤销也是** —— 所以它是一枚要点第二下的按钮，
          // 不是把上面那行字改成可点。两处入口（这一页与「幻念推送设置」那一页）调的是
          // **同一个实现** `confirmAndRevokeRelayConsent`，清的是同一枚键 —— 两边各写一遍
          // 迟早一处清了键、另一处还显示"已同意"。
          Align(
            alignment: Alignment.centerLeft,
            child: SecondaryActionButton(
              keyName: 'fnthink-consent-revoke',
              label: l10n.fnthinkConsentRevoke,
              onPressed: _busy ? null : _revokeConsent,
            ),
          ),
          if (_consentResult case final String note)
            FnthinkNote(keyName: 'fnthink-consent-result', text: note),
        ],
        // T60（approach B）：这一台对着当前服务器最近一次发送通没通过。
        // 只在同意之后画 —— 没同意时任何一发都在本机就被挡下（没有"服务器通不通"这回事），
        // 画出来只会把"还没同意"错读成"服务器坏了"。
        if (_consented)
          // T152 片D：这是**状态读数**（最近一发对着当前服务器通没通）⇒ 走带点亮那一枚的
          // `FnthinkStatusRow`。⚠ 那一枚点只说"此刻通／此刻不通"，三档原话（没测过／不通／通）
          // 仍由 `_serverHealthText` 一个人给 —— 点不亮**不等于**"坏了"，那句区分在文字里，
          // 所以这里不许把点当成第二个结论源（T140 那一格量的就是"两枚读数当一枚用"）。
          FnthinkStatusRow(
            keyName: 'fnthink-server-health',
            dot: _serverHealth?.reachable == true,
            text: _serverHealthText(l10n),
          ),
        // 「被杀之后还有没有人去问一次货」（T33 第二片 / §4-9）：这一行读的是**原生那份排程**。
        // 收货循环活着 ≠ 闹钟排着（进程被杀之后正是"循环没了而闹钟还在"），所以两行必须分开说。
        // 还没有读到（读口抛过、或这一页刚起来）时**不画这一行** —— 画一句"没在醒着"是假话。
        if (_presence != null)
          FnthinkNote(
            keyName: 'fnthink-presence-next',
            text: _presenceText(l10n),
          ),
        // T180：一次性退避单独一行，与上面的常设节奏分开说；倒计时由一秒一跳的计时器刷新。
        if (_backoffActive)
          FnthinkNote(
            keyName: 'fnthink-presence-backoff',
            text: _backoffText(l10n),
          ),
        // T176 自检：上次成功收取 / 两条 WorkManager 链 / 待发条数。
        // 这三行与上面那一行是同一个问题的四份读数；只给"下一次"会让人以为链一定在跑。
        if (_presence != null)
          FnthinkNote(
            keyName: 'fnthink-last-round-at',
            text: _lastRoundAt > 0
                ? l10n.fnthinkLastRoundAt(_presenceClock(_lastRoundAt))
                : l10n.fnthinkLastRoundNever,
          ),
        if (_presence != null &&
            (_presence!.presenceWork.isNotEmpty ||
                _presence!.fanoutWork.isNotEmpty))
          FnthinkNote(
            keyName: 'fnthink-work-chain',
            text: l10n.fnthinkWorkChain(
              _presence!.presenceWork.isEmpty ? '—' : _presence!.presenceWork,
              _presence!.fanoutWork.isEmpty ? '—' : _presence!.fanoutWork,
              _presence!.fanoutQueue,
            ),
          ),
        // T196：最后一层到底走到哪一步。旧原生没有 `diag` 这一格 ⇒ 整块不画；
        // 有这一格但某一格是 0/空 ⇒ 说"还没有记录"，不把它读成"刚刚发生过"。
        if (_presence?.diag case final FnthinkDiagSnapshot diag) ...[
          FnthinkNote(
            keyName: 'fnthink-diag-alarm',
            text: diag.lastAlarmFiredAt > 0
                ? l10n.fnthinkDiagAlarmAt(_presenceClock(diag.lastAlarmFiredAt))
                : l10n.fnthinkDiagAlarmNever,
          ),
          FnthinkNote(
            keyName: 'fnthink-diag-worker',
            text: _diagWorkerText(l10n, diag),
          ),
          FnthinkNote(
            keyName: 'fnthink-diag-poll',
            text: diag.lastPollAt > 0
                ? l10n.fnthinkDiagPollAt(
                    _presenceClock(diag.lastPollAt),
                    diag.lastPollStatus.isEmpty ? '—' : diag.lastPollStatus,
                  )
                : l10n.fnthinkDiagPollNever,
          ),
          FnthinkNote(
            keyName: 'fnthink-diag-stream',
            text: diag.lastStreamByteAt > 0
                ? l10n.fnthinkDiagStreamAt(
                    _presenceClock(diag.lastStreamByteAt),
                  )
                : l10n.fnthinkDiagStreamNever,
          ),
          FnthinkNote(
            keyName: 'fnthink-diag-system',
            text: l10n.fnthinkDiagSystem(
              _diagBool(l10n, diag.deviceIdle),
              _diagBool(l10n, diag.batteryOptimizationIgnored),
              _diagBool(l10n, diag.powerSaveMode),
              _diagBool(l10n, diag.exactAlarmAllowed),
            ),
          ),
        ],
        // 缺授权时给路径，不替用户调：这两项都要跳系统页，回来由生命周期重读。
        if (_exactAlarmGranted == false) ...[
          FnthinkNote(
            keyName: 'fnthink-exact-alarm-missing',
            text: l10n.fnthinkExactAlarmMissing,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FnthinkInlineAction(
              key: const ValueKey('fnthink-grant-exact-alarm'),
              label: l10n.fnthinkGrantNow,
              tone: FnthinkActionTone.neutral,
              onPressed: _busy ? null : _requestExactAlarm,
            ),
          ),
        ],
        if (_batteryOptimizationIgnored == false) ...[
          FnthinkNote(
            keyName: 'fnthink-battery-opt-missing',
            text: l10n.fnthinkBatteryOptMissing,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FnthinkInlineAction(
              key: const ValueKey('fnthink-grant-battery-opt'),
              label: l10n.fnthinkGrantNow,
              tone: FnthinkActionTone.neutral,
              onPressed: _busy ? null : _requestIgnoreBatteryOptimization,
            ),
          ),
        ],
        // 只有链死那一档给按钮：其余三档按了也不会有任何变化，而界面不许摆一枚不做事的按钮。
        if (_presence != null &&
            _presenceLiveness() == FnthinkPresenceLiveness.dead)
          Align(
            alignment: Alignment.centerLeft,
            child: FnthinkInlineAction(
              key: const ValueKey('fnthink-presence-recover'),
              label: l10n.fnthinkPresenceRecover,
              tone: FnthinkActionTone.neutral,
              onPressed: _busy ? null : _recoverPresence,
            ),
          ),
        if (_startNote != null)
          FnthinkNote(keyName: 'fnthink-start-note', text: _startNote!),
        if (_roundNote != null)
          FnthinkNote(keyName: 'fnthink-round-note', text: _roundNote!),
        if (_lastRound != null)
          FnthinkNote(keyName: 'fnthink-last-round', text: _lastRound!),
        // 这一页的主操作（§1 判据④）：旧写法是一枚左对齐、无填充的 `CupertinoButton`，
        // 与上面那些「行」混在一起分不出主次。
        PrimaryActionButton(
          key: const ValueKey('fnthink-receive-now'),
          label: l10n.fnthinkReceiveNow,
          // T180：退避期间点它只会再吃一次 429（那一发 register 仍是同一个身份但分钟档照记）。
          // 禁用而不是藏掉，旁边的退避行已经说清为什么。
          onPressed: _enabled && !_busy && !_backoffActive ? _receiveNow : null,
        ),
      ],
    );
  }
}
