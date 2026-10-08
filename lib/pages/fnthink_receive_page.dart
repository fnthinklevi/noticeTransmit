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
import '../services/fnthink_presence_scheduler.dart';
import '../services/fnthink_peer_service.dart';
import '../services/fnthink_receive_coordinator.dart';
import '../services/fnthink_settings.dart';
import '../theme/app_colors.dart';
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
  });

  factory FnthinkReceiveDeps.fromLocator() => FnthinkReceiveDeps(
    contracts: GetIt.instance<FnthinkContractLoader>(),
    coordinator: GetIt.instance<FnthinkReceiveCoordinator>(),
    // 「下一次自己醒」那一行只**读**这一个源（§4-9 片1d）：页面既不自己算间隔、也不自己排闹钟。
    presence: GetIt.instance<FnthinkPresenceScheduler>(),
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

class _FnthinkReceivePageState extends State<FnthinkReceivePage> {
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

  bool _running = false;
  String? _startNote;
  String? _lastRound;
  String? _roundNote;

  /// T60（approach B）：这一台对着当前服务器最近一次发送通没通过。
  ChannelHealth? _serverHealth;

  /// 「多久问一次货」那一格（T88）。整格从 `settings.pollSetting()` 一次读齐 ——
  /// 范围来自契约，页面不写任何一个节奏数字。
  FnthinkPollSetting? _poll;

  /// 拖拽中的那一档（只有拖动过程用，松手才落盘）。null = 没在拖。
  double? _pollDrag;

  /// 保存这一格失败时那句"协议不允许"（写了 `_poll.problem` 之外的另一种失败：用户刚犯的）。
  String? _pollError;

  /// 「下一次自己醒」那一行读回来的那一份（null = 还没读到，或读口抛了）。
  ///
  /// ⚠ null 与 `armed == false` 是**两件事**：前者是"不知道"，后者是"确实没排"。
  FnthinkPresenceStatus? _presence;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _deps = widget.deps ?? FnthinkReceiveDeps.fromLocator();
    _coordinator = _deps.coordinator;
    unawaited(_load());
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
    await Future.wait<void>([_readEnabled(), _readPresence(), _readPoll()]);
  }

  /// 读「收取间隔」那一格（T88）。
  ///
  /// 范围与生效值都从 `FnthinkSettings` 那一个合成处来，页面自己不碰契约那个字段 ——
  /// 那是守卫钉的（页面成为第二个节奏作者时，改契约那一刀不会有任何东西报错）。
  /// 读失败时**整格不画**并留下那句原话，而不是退到一个猜出来的秒数上。
  Future<void> _readPoll() async {
    final settings = _settings;
    if (settings == null) return;
    final poll = await settings.pollSetting();
    if (!mounted) return;
    setState(() => _poll = poll);
  }

  /// 改节奏。越界不写、也**不重启**：什么都没改变断一次线，等于把「改了没反应」做成
  /// 「每改一次断一次」（那一句话要留在屏幕上，所以这里不重读、只把忙态摘掉）。
  Future<void> _savePollSeconds(int seconds) async {
    final settings = _settings;
    if (settings == null) return;
    setState(() => _busy = true);
    var saved = false;
    try {
      await settings.setPollSeconds(seconds);
      _pollError = null;
      saved = true;
    } on FnthinkSettingsInvalid catch (e) {
      _pollError = e.reason;
    }
    if (!saved) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    await _restartLoopAndReread();
  }

  /// 抹掉「用户选过」这件事 ⇒ 回到协议默认那一档（不是把默认值写进去，见 `clearPollSeconds`）。
  Future<void> _resetPollSeconds() async {
    final settings = _settings;
    if (settings == null) return;
    setState(() => _busy = true);
    await settings.clearPollSeconds();
    _pollError = null;
    await _restartLoopAndReread();
  }

  /// 改完节奏必须**重启**循环：循环握的是启动那一刻定型的间隔，继续跑等于还在按旧档问货。
  /// 重启完把这一格重读回来 —— 界面上的数必须来自 prefs，而不是刚敲进去的那个值。
  Future<void> _restartLoopAndReread() async {
    _coordinator.stop();
    await _coordinator.startIfEnabled();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _pollDrag = null;
      _running = _coordinator.isRunning;
    });
    await Future.wait<void>([_readPoll(), _readPresence()]);
  }

  /// 「下一次自己醒」那一行（§4-9 片1d）—— 读的是**原生那份排程**，不是本机自己算的。
  Future<void> _readPresence() async {
    try {
      final status = await _deps.presence.status();
      if (!mounted) return;
      setState(() => _presence = status);
    } catch (_) {
      // 读口抛 ⇒ 这一行**不画**（"还没读到"与"确实没排"是两句不同的话，见字段注释）。
      if (mounted) setState(() => _presence = null);
    }
  }

  /// 「下一次自己醒」那句话的时刻部分。本机不自己算时钟（那是一份第二的计时账），
  /// 只把原生交上来的那个毫秒数格式化一下。
  String _presenceClock(int millis) {
    final at = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
  }

  /// 没有 cadence 就没有「下一次」：只把 clock 那零点几秒写成「下一次」，
  /// 用户会以为这下一下随时都会发生。
  String _presenceText(AppLocalizations l10n) {
    final status = _presence!;
    if (!status.armed) return l10n.fnthinkPresenceAsleep;
    final clock = _presenceClock(status.nextRoundAt);
    return status.cadenceSeconds > 0
        ? l10n.fnthinkPresenceNext(clock, status.cadenceSeconds)
        : l10n.fnthinkPresenceNextNoCadence(clock);
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
        _startNote = result.started
            ? null
            : (result.reason == 'not-consented'
                  ? l10n.fnthinkConsentNotGranted
                  : result.reason);
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
    final report = await _coordinator.receiveOnce();
    if (!mounted) return;
    setState(() {
      _running = _coordinator.isRunning;
      if (report == null) {
        _roundNote = l10n.fnthinkReceiveDisabled;
        _lastRound = null;
      } else if (report.skipped) {
        _roundNote = l10n.fnthinkReceiveSkipped;
      } else {
        _roundNote = null;
        // summary 只有计数（没有标题、正文与消息 id），所以可以直接上界面。
        _lastRound = report.summary;
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
          ],
        ],
      ),
    );
  }

  Widget _buildReceiveCard(AppLocalizations l10n) {
    return FnthinkCard(
      title: l10n.fnthinkReceive,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.fnthinkReceiveDesc,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
            ),
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
        ] else
          FnthinkNote(
            keyName: 'fnthink-consent-granted',
            text: l10n.fnthinkConsentGranted,
          ),
        // T60（approach B）：这一台对着当前服务器最近一次发送通没通过。
        // 只在同意之后画 —— 没同意时任何一发都在本机就被挡下（没有"服务器通不通"这回事），
        // 画出来只会把"还没同意"错读成"服务器坏了"。
        if (_consented)
          FnthinkNote(
            keyName: 'fnthink-server-health',
            text: _serverHealthText(l10n),
          ),
        // 「多久问一次货」那一格（T88）。范围与生效值都来自契约经 `FnthinkSettings` 合成后的
        // 那一份 —— 页面一个节奏数字都不写。契约那边给不出范围时**整格不画**：画一根没有
        // 范围的滑杆等于任用户选到协议不许的那一档，而那一档的代价是这台被服务端按额度持续 429。
        if (_poll case final FnthinkPollSetting poll) ...[
          FnthinkNote(
            keyName: 'fnthink-poll-title',
            text: l10n.fnthinkPollIntervalTitle,
          ),
          FnthinkNote(
            keyName: 'fnthink-poll-value',
            text: poll.chosen == null
                ? l10n.fnthinkPollIntervalUsingDefault(poll.effective)
                : l10n.fnthinkPollIntervalChosen(poll.effective),
          ),
          CupertinoSlider(
            key: const ValueKey('fnthink-poll-slider'),
            value: (_pollDrag ?? poll.effective.toDouble()).clamp(
              poll.range.min.toDouble(),
              poll.range.max.toDouble(),
            ),
            min: poll.range.min.toDouble(),
            max: poll.range.max.toDouble(),
            divisions: poll.range.max - poll.range.min,
            // 这一版本 SDK 的 `CupertinoSlider` 没有 `label`（拖动时那颗气泡），
            // 所以拖动过程中界面上那句话仍是**已生效**的那一档 —— 松手落盘并重读之后才跟上。
            // 只由"这一格正在忙"把关，**不由接收开关把关**：这是设置而不是运行状态 ——
            // 开着关着的设备都该能在换机后先把这一档配好。（关掉时下面那发重启本身就是空转。）
            onChanged: _busy ? null : (v) => setState(() => _pollDrag = v),
            onChangeEnd: _busy ? null : (v) => _savePollSeconds(v.round()),
          ),
          FnthinkNote(
            keyName: 'fnthink-poll-range',
            text: l10n.fnthinkPollIntervalRange(poll.range.min, poll.range.max),
          ),
          // 原来这里直接画一句 172 字的「往短/往长各付什么」—— 就是被点名的那种
          // "页面里成段小字"。现在只留一行短说，**长文原样搬进问号弹窗、一个字不删**。
          HelpNoteRow(
            noteKey: 'fnthink-poll-tradeoff',
            helpKey: 'fnthink-poll-tradeoff-help',
            text: l10n.fnthinkPollIntervalShort,
            helpTitle: l10n.fnthinkPollIntervalTradeoffTitle,
            helpBody: l10n.fnthinkPollIntervalTradeoff,
          ),
          // prefs 里存着协议不许的那一档（备份恢复灌回来的那一种）与"刚刚那一盘被拒"是两处，
          // 分开画：前者是历史留下的、后者是这一次做的，用户的下一步动作不一样。
          if (poll.problem case final String problem)
            FnthinkNote(
              keyName: 'fnthink-poll-problem',
              text: l10n.fnthinkPollIntervalInvalid(problem),
            ),
          if (_pollError case final String reason)
            FnthinkNote(
              keyName: 'fnthink-poll-error',
              text: l10n.fnthinkPollIntervalInvalid(reason),
            ),
          if (poll.chosen != null)
            Align(
              alignment: Alignment.centerLeft,
              child: CupertinoButton(
                key: const ValueKey('fnthink-poll-reset'),
                onPressed: _busy ? null : _resetPollSeconds,
                child: Text(l10n.fnthinkPollIntervalReset),
              ),
            ),
        ],
        // 「被杀之后还有没有人去问一次货」（T33 第二片 / §4-9）：这一行读的是**原生那份排程**。
        // 收货循环活着 ≠ 闹钟排着（进程被杀之后正是"循环没了而闹钟还在"），所以两行必须分开说。
        // 还没有读到（读口抛过、或这一页刚起来）时**不画这一行** —— 画一句"没在醒着"是假话。
        if (_presence != null)
          FnthinkNote(
            keyName: 'fnthink-presence-next',
            text: _presenceText(l10n),
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
          onPressed: _enabled && !_busy ? _receiveNow : null,
        ),
      ],
    );
  }
}
