import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../di/service_locator.dart';
import 'fnthink_contract_loader.dart';
import 'fnthink_settings.dart';
import 'platform_channel.dart';

/// 幻念推送"被杀之后还有人去问一次货"的 Dart 侧（T33 第二片 / §4-9 片1b）。
///
/// 分工与原生那一片（`80bd66f`）严格对齐，一句都不含糊：
///  - **闹钟的数值与决定权在这里**（间隔从契约 `presence.pollIntervalSeconds` 读，
///    要醒就排、不要醒就撤）。Kotlin 只负责"把这个数交给系统"和"到点之后交给执行器"；
///  - **真正干活的是那一轮收货本身**：后台引擎起起来之后调的就是下面那个入口，
///    它跑的是与前台同一套判据（同一份内核、同一个协调者），这里不加第二条收货路径。
///
/// ⚠ 三条"两边各写一份字符串"的都对不齐就没人报错，所以逐个钉：
///  - 排/撤/查那三个方法走 **App 自己那条通道**（`com.fnthink.notice/notification` 上的
///    [AppChannels.notification]，由 `FnthinkChannelHandler` 接）—— 不是 presence 通道；
///    presence 通道只承载 `roundDone` 那一发回报（worker 自己接）。
///  - `com.fnthink.notice/presence` ↔ `FnthinkPresenceWorker.PRESENCE_CHANNEL`；
///  - `fnthink_presence_handle` ↔ `FnthinkPresenceWorker.KEY_HANDLE`（prefs 落盘时会自动加
///    `flutter.` 前缀，原生读的是带前缀那一份）。
/// 错一个字符的表现都是"闹钟响过、任务跑过、而没人说这一轮结束了"，只能等到超时。
class FnthinkPresenceScheduler {
  FnthinkPresenceScheduler({required this.contracts, MethodChannel? channel})
    : _channel = channel ?? AppChannels.notification;

  /// 节奏的唯一来源。与协调者一样留成公开字段：`required this.contracts` 才有初始化形参可用
  /// （私有字段的命名参数在 Dart 里不合法），而它是 final，改不了。
  final FnthinkContractLoader contracts;
  final MethodChannel _channel;

  /// T181 B：兜底闹钟下一次大致到点的时刻（毫秒）。只用来回答"该不该再排一次"，
  /// 真值仍在原生（`nextRoundAt`）。
  int _backstopArmedForMs = 0;

  /// 还要不要继续醒着。
  ///
  /// `keepAwake == true` 时先补一次 handle 再排：handle 是"这台引擎该进哪个 Dart 函数"的
  /// 唯一线索，而它**只有在前台跑过一次才会写进 prefs** —— 新装包第一次开开关就走到这里，
  /// 少了这一步，后台那一轮会永远在 `no-entry-handle` 上跳过（日志有，界面上没有）。
  ///
  /// ⚠ 顺序要紧：**handle 没落盘就不排**。排了一颗进不了函数的闹钟，等于让用户为一次
  /// 必然白跑的唤醒付电 —— 而界面上看不出区别。前台收货不受影响（那条走的是循环，不是闹钟）。
  ///
  /// 撤（`keepAwake == false`）**不读契约**：契约此刻多半正不可用（读不到/不校验），
  /// 而"关掉就该停"不该被契约读数挡住；反过来排的那一次必须读契约，因为间隔只有一个作者。
  ///
  /// [afterSeconds]（T139 ①）：**一次性退避**——只来自"注册被限流"那一档，值是服务端
  /// `Retry-After` 的原话。它不是第二份节奏：到点那一轮之后，节奏照旧回契约；
  /// 若把退避值喂回节奏，等于让"服务端一句限流"变成这台的常设间隔。
  Future<void> notice({required bool keepAwake, int? afterSeconds}) async {
    if (!keepAwake) {
      _clearLiveGlobals();
      _backstopArmedForMs = 0;
      await _stopLive();
      await _channel.invokeMethod<void>('cancelFnthinkPresence');
      return;
    }
    final backoff = afterSeconds != null && afterSeconds > 0;
    // T185 第二步：SSE 健康时门铃负责即时性，网络回包本身会唤醒 CPU —— 这时不再
    // 常驻持锁、也不再高频轮询。后台那一轮同样不开常驻档：那颗引擎只活一轮。
    final liveWanted = !fnthinkStreamHealthy && !fnthinkBackgroundIsolate;
    // T197 片1：后台那一轮**不许碰共享的原生开关**。旧写法在这里调 stopFnthinkLive，
    // 会把主 isolate 正持有的锁关掉，而主 isolate 可能已经睡着、没人再把它打开。
    // 退避那一档要在**第一个 await 之前**就把常驻档关掉：循环排下一轮时读的是这颗全局。
    if (!fnthinkBackgroundIsolate && (backoff || !liveWanted)) {
      _clearLiveGlobals();
      await _stopLive();
    } else if (!fnthinkBackgroundIsolate) {
      final liveSeconds = await _liveSeconds();
      _setLiveGlobals(liveSeconds);
      var live = false;
      try {
        live =
            await _channel.invokeMethod<bool>('startFnthinkLive', {
              'seconds': liveSeconds,
            }) ??
            false;
      } catch (e) {
        debugPrint('[fnthink] 常驻轮询档没打开（退回闹钟链）：$e');
      }
      if (!live) _clearLiveGlobals();
    }

    if (!await publishEntryHandle()) {
      debugPrint('[fnthink] 拿不到后台入口 handle ⇒ 这次不排闹钟（排了也起不了引擎，白耗一次唤醒）');
      return;
    }
    // 常驻档活着时，闹钟只当"进程被杀"的兜底：退到契约允许的**最慢**那一档，
    // 循环还在跑时它不会真的响；循环一停，最迟那一档之后由 worker 接手。
    //
    // T185 第二步的三档：
    //  - SSE 健康 ⇒ 兜底退到 `stream.safetyPollSeconds`（正常时门铃立刻叫醒，
    //    这一颗只防"流静默死了但连接还在"）；
    //  - 后台那一轮 / 常驻档 ⇒ 契约最慢档（60s），是"进程被杀"的接手间隔；
    //  - 都没有 ⇒ 用户选的那一档常态 cadence。
    final int alarmSeconds;
    if (backoff) {
      alarmSeconds = afterSeconds;
    } else if (fnthinkStreamHealthy) {
      alarmSeconds = await _streamSafetySeconds();
    } else if (fnthinkLiveModeActive || fnthinkBackgroundIsolate) {
      alarmSeconds = await _backstopSeconds();
    } else {
      alarmSeconds = await _cadenceSeconds();
    }
    if (backoff) {
      _backstopArmedForMs = 0;
    } else if (fnthinkLiveModeActive) {
      // 兜底闹钟只需要"在被响之前往前推"，不必每轮都打扰 AlarmManager：
      // 常驻档 5 秒一轮，每轮都重排就是一分钟 12 次精确闹钟 —— 系统本来就会限流，
      // 被限流的那些还会把"推进"变成"没推进"。留一半余量再推一次。
      final now = DateTime.now().millisecondsSinceEpoch;
      if (_backstopArmedForMs - now > _kBackstopRearmWindowMs) return;
      _backstopArmedForMs = now + alarmSeconds * 1000;
    } else {
      _backstopArmedForMs = 0;
    }
    await _channel.invokeMethod<void>('scheduleFnthinkPresence', {
      'seconds': alarmSeconds,
      // T180：退避是**一次性**参数，与常态 cadence 分两格落到原生。正常排程显式传 0，
      // 把上一次的退避标记清掉。
      'backoffSeconds': backoff ? afterSeconds : 0,
    });
  }

  /// 撤常驻档。**失败不外抛**：它排在撤闹钟那一发之前，抛出去会让"关掉接收"
  /// 只关了一半（锁撤了、闹钟还挂着），而那正是这一片要消灭的静默不一致。
  Future<void> _stopLive() async {
    try {
      await _channel.invokeMethod<void>('stopFnthinkLive');
    } catch (e) {
      debugPrint('[fnthink] 常驻轮询档没撤掉（闹钟照常撤）：$e');
    }
  }

  /// 常驻轮询档的间隔：契约 `presence.burstWhenPending.intervalSeconds`。
  /// 不在这里写那个数 —— 那是第二份节奏，改契约时不会有任何东西报错。
  Future<int> _liveSeconds() async {
    final contract = await contracts.load();
    return contract.burstWhenPending.intervalSeconds;
  }

  /// 常驻档活着时闹钟的兜底间隔：契约允许的最慢一档（`presence.pollIntervalSeconds.max`）。
  /// 它只是"进程被杀之后多久由 worker 接手"，不是收货节奏 —— 收货节奏的唯一作者仍是契约。
  Future<int> _backstopSeconds() async {
    final contract = await contracts.load();
    return contract.pollIntervalRange.max;
  }

  /// SSE 健康时的兜底间隔：契约 `presence.stream.safetyPollSeconds`。
  /// 段缺（旧契约）时退回契约最慢档 —— 宁可 60 秒兜一次，也不在实现里写一个数。
  Future<int> _streamSafetySeconds() async {
    final contract = await contracts.load();
    return contract.streamSpec?.safetyPollSeconds ??
        contract.pollIntervalRange.max;
  }

  /// 下一轮的间隔：T192 起「收取间隔」滑杆下线，固定用契约
  /// `presence.pollIntervalSeconds` 的 default（经 `FnthinkSettings` 那道门面）。
  /// 旧 prefs 里的用户档位不再参与；取不到契约就抛，仍不在实现里补一个数。
  Future<int> _cadenceSeconds() async {
    final contract = await contracts.load();
    return FnthinkSettings(contract: contract).fallbackPollSeconds;
  }

  /// T197 片2：让原生按**此刻**的屏幕/开关状态对一次锁。
  ///
  /// 服务在屏幕事件与启动时会对账，但用户在本页翻开关时屏幕可能一直灭着 ——
  /// 不主动叫一次，锁要等到下一次 5 分钟续期才跟着变。失败只留日志：
  /// 锁是「更及时」的加速器，不是收货本身；叫不动它不能让开关那一发报错。
  Future<void> refreshScreenLock() async {
    try {
      await _channel.invokeMethod<void>('refreshFnthinkScreenLock');
    } catch (e) {
      debugPrint('[fnthink] 锁屏持续接收获取状态失败：$e');
    }
  }

  /// 读回原生那份状态（"到底还有没有人醒"）。界面上那一行与排查用的日志都从这里取。
  Future<FnthinkPresenceStatus> status() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'fnthinkPresenceStatus',
    );
    return FnthinkPresenceStatus.fromMap(raw);
  }
}

/// 那一行要说的话有几种（T140 层2 察）。
///
/// 判据**只在这一处**（页面不许自己比 `nextRoundAt == 0`）：四档里只有 `dead` 是真的坏，
/// 把另外三档混着报，要么把"刚开机"说成故障，要么把故障说成刚开机 —— 后者才是这次要修的。
enum FnthinkPresenceLiveness {
  /// 闹钟排着：链条活着。
  armed,

  /// 开关开着、也同意了，可这台**曾经醒过而现在没排上** ⇒ 复起链断了（要人按一下才回来）。
  dead,

  /// 配置齐了但从没排上过（刚开开关、第一轮还没跑完）⇒ 不是故障，别吓用户。
  pendingFirstRound,

  /// 开关或同意没齐 ⇒ 本来就不该醒着。
  configIncomplete,
}

/// 上面那四档的唯一判据。纯函数：调用方把三份事实交进来，不自己算时钟也不自己比零。
///
/// ⚠ 顺序要紧：**排着就先说排着**。开关关着而闹钟还挂着是真事（开机补排那条路上有机会出现），
/// 把它压成"开关关着"就把这格不一致藏回去了 —— 界面在此刻的职责是报读数，不是替用户解释读数。
FnthinkPresenceLiveness judgePresenceLiveness({
  required bool enabled,
  required bool consented,
  required FnthinkPresenceStatus status,
}) {
  if (status.armed) return FnthinkPresenceLiveness.armed;
  if (!enabled || !consented) return FnthinkPresenceLiveness.configIncomplete;
  // 被撤过（`cancel()` 清 nextRoundAt 与 cadence，但**不清** everArmedAt）才叫"断了"；
  // 从没排过的是"还没排上第一轮"，那一档的说法完全不同。
  return status.everArmedAt > 0
      ? FnthinkPresenceLiveness.dead
      : FnthinkPresenceLiveness.pendingFirstRound;
}

/// T196：原生 `FnthinkDiag.snapshot()` 的那一份只读读数。
///
/// `null`（旧原生没有 `diag` 这一格）与"全 0"必须分开：前者是"这一版读不到"，
/// 后者是"读得到，但确实还没有记录"。页面据此决定画不画这一块，不许把两者混成一句。
class FnthinkDiagSnapshot {
  const FnthinkDiagSnapshot({
    this.lastAlarmFiredAt = 0,
    this.lastWorkerStartedAt = 0,
    this.lastWorkerFinishedAt = 0,
    this.lastWorkerResult = '',
    this.lastPollAt = 0,
    this.lastPollStatus = '',
    this.lastStreamByteAt = 0,
    this.serviceStartedAt = 0,
    this.processStartedAt = 0,
    this.deviceIdle = false,
    this.batteryOptimizationIgnored = false,
    this.powerSaveMode = false,
    this.exactAlarmAllowed = false,
    this.screenInteractive,
    this.screenKeepalive,
    this.screenLockHeld,
  });

  factory FnthinkDiagSnapshot.fromMap(Map<dynamic, dynamic> raw) {
    int ms(String key) => (raw[key] as num?)?.toInt() ?? 0;
    return FnthinkDiagSnapshot(
      lastAlarmFiredAt: ms('lastAlarmFiredAt'),
      lastWorkerStartedAt: ms('lastWorkerStartedAt'),
      lastWorkerFinishedAt: ms('lastWorkerFinishedAt'),
      lastWorkerResult: '${raw['lastWorkerResult'] ?? ''}',
      lastPollAt: ms('lastPollAt'),
      lastPollStatus: '${raw['lastPollStatus'] ?? ''}',
      lastStreamByteAt: ms('lastStreamByteAt'),
      serviceStartedAt: ms('serviceStartedAt'),
      processStartedAt: ms('processStartedAt'),
      deviceIdle: raw['deviceIdle'] == true,
      batteryOptimizationIgnored: raw['batteryOptimizationIgnored'] == true,
      powerSaveMode: raw['powerSaveMode'] == true,
      exactAlarmAllowed: raw['exactAlarmAllowed'] == true,
      screenInteractive: raw['screenInteractive'] is bool
          ? raw['screenInteractive'] as bool
          : null,
      screenKeepalive: raw['screenKeepalive'] is bool
          ? raw['screenKeepalive'] as bool
          : null,
      screenLockHeld: raw['screenLockHeld'] is bool
          ? raw['screenLockHeld'] as bool
          : null,
    );
  }

  final int lastAlarmFiredAt;
  final int lastWorkerStartedAt;
  final int lastWorkerFinishedAt;
  final String lastWorkerResult;
  final int lastPollAt;
  final String lastPollStatus;
  final int lastStreamByteAt;
  final int serviceStartedAt;
  final int processStartedAt;
  final bool deviceIdle;
  final bool batteryOptimizationIgnored;
  final bool powerSaveMode;
  final bool exactAlarmAllowed;

  /// T197 片2：屏幕亮着没有 / 高可靠开关 / 服务是否真的持着锁。
  /// null = 旧原生没有这一格（页面不画这一行，不拿 false 冒充“关着”）。
  final bool? screenInteractive;
  final bool? screenKeepalive;
  final bool? screenLockHeld;
}

class FnthinkPresenceStatus {
  const FnthinkPresenceStatus({
    required this.nextRoundAt,
    required this.cadenceSeconds,
    this.backoffSeconds = 0,
    this.everArmedAt = 0,
    this.presenceWork = '',
    this.fanoutWork = '',
    this.fanoutQueue = 0,
    this.liveMode = false,
    this.liveSeconds = 0,
    this.wakeLock = false,
    this.diag,
  });

  /// 原生 `fnthinkPresenceStatus` 的读法**只有这一处**：页面与测试都从这里拿，
  /// 不许各自再抄一份键名映射（旧原生缺的格子按 0/空串落，不补一个猜的值）。
  factory FnthinkPresenceStatus.fromMap(Map<dynamic, dynamic>? raw) {
    final diagRaw = raw?['diag'];
    return FnthinkPresenceStatus(
      nextRoundAt: (raw?['nextRoundAt'] as num?)?.toInt() ?? 0,
      cadenceSeconds: (raw?['cadenceSeconds'] as num?)?.toInt() ?? 0,
      // 旧原生没有这一格 ⇒ 0（按常态节奏处理，不凭空造一个退避）。
      backoffSeconds: (raw?['backoffSeconds'] as num?)?.toInt() ?? 0,
      everArmedAt: (raw?['everArmedAt'] as num?)?.toInt() ?? 0,
      // T176：两条 WorkManager 链与待发条数。旧原生没有这三格 ⇒ 空串 / 0，
      // 页面据此说"读不到"，不编一个 `none`。
      presenceWork: '${raw?['presenceWork'] ?? ''}',
      fanoutWork: '${raw?['fanoutWork'] ?? ''}',
      fanoutQueue: (raw?['fanoutQueue'] as num?)?.toInt() ?? 0,
      liveMode: raw?['liveMode'] == true,
      liveSeconds: (raw?['liveSeconds'] as num?)?.toInt() ?? 0,
      wakeLock: raw?['wakeLock'] == true,
      diag: diagRaw is Map ? FnthinkDiagSnapshot.fromMap(diagRaw) : null,
    );
  }

  /// 下一轮被排在什么时候（毫秒）。0 = 没排。
  final int nextRoundAt;

  /// Dart 上次交下来的**常态**间隔（秒）。0 = 没交过（或被撤时一起清了）。
  ///
  /// ⚠ T180：一次性退避不再写进这一格（原生另一个 `backoff_seconds`），否则页面会把
  /// "服务端让我等 700 秒"读成"这台常态每 700 秒问一次货"。
  final int cadenceSeconds;

  /// 上一颗闹钟是**一次性退避**多少秒（0 = 常态节奏）。退避期间「立即收取」要禁用，
  /// 且页面要把它与常设间隔分两行说。
  final int backoffSeconds;

  /// 这台**第一次真的排上**闹钟的时刻（毫秒）。0 = 从没排上过。见原生 `KEY_EVER_ARMED_AT`。
  final int everArmedAt;

  /// T181 B：常驻前台轮询档是否开着（与闹钟链是两条腿，可以同时为真）。
  final bool liveMode;

  /// 常驻档的间隔（秒）；0 = 没开。
  final int liveSeconds;

  /// 原生是否真的持着那把 PARTIAL_WAKE_LOCK。`liveMode=true` 而它为 false，
  /// 说明锁没拿上（ROM 拒绝/异常），页面必须如实说，不许只报"已开启"。
  final bool wakeLock;

  /// 收货那一轮 WorkManager 的状态（`ENQUEUED`/`RUNNING`/…；空串 = 旧原生没这一格）。
  final String presenceWork;

  /// 幻念转发队列 worker 的状态（同上）。
  final String fanoutWork;

  /// 转发待发队列里还有几条（T175 的队列）。
  final int fanoutQueue;

  /// T196：后台收货的只读诊断读数。null = 旧原生没有这一格（页面不画）。
  final FnthinkDiagSnapshot? diag;

  bool get armed => nextRoundAt > 0;
}

/// 后台入口的 handle 在 prefs 里的键（**不带** `flutter.` 前缀：那是 shared_preferences
/// 落盘时加的，原生读的是 `flutter.fnthink_presence_handle` —— 这一对关系由守卫钉住）。
const String kFnthinkPresenceHandleKey = 'fnthink_presence_handle';

/// 常驻档下兜底闹钟"再往前推一次"的余量：比它更近就不重排，免得每轮都去敲 AlarmManager。
const int _kBackstopRearmWindowMs = 30000;

/// T185 第二步：SSE 门铃是否健康。主 isolate 由流服务写；后台 isolate 从 [kFnthinkStreamHealthyKey]
/// 读同一份 —— 那颗引擎只活一轮，不能因为"它不知道门铃开着"就去开常驻档。
bool fnthinkStreamHealthy = false;

/// 后台那一轮（WorkManager 起的另一颗引擎）。它只活一轮，**永远**不开常驻档/不持锁。
bool fnthinkBackgroundIsolate = false;

/// 流健康状态落盘的键（Dart 自己写的裸键；后台 isolate 读同一份）。
const String kFnthinkStreamHealthyKey = 'fnthink_stream_healthy';

/// 当前这颗 isolate 是否处在常驻轮询档。循环排下一轮时用 [fnthinkLiveClampDelay] 压间隔。
///
/// 只活在本 isolate：前台 UI 与后台 worker 各有一份，互不冒充。
/// 落盘那一份归原生（`FnthinkLiveMode`）：这里不再写 prefs，否则同一组键就有两个作者。
bool fnthinkLiveModeActive = false;
int fnthinkLiveSecondsActive = 0;

void _setLiveGlobals(int cadence) {
  fnthinkLiveSecondsActive = cadence;
  fnthinkLiveModeActive = cadence > 0;
}

void _clearLiveGlobals() {
  fnthinkLiveSecondsActive = 0;
  fnthinkLiveModeActive = false;
}

/// 常驻档的间隔上限：契约 `burstWhenPending.intervalSeconds`。
///
/// ⚠ 只在常驻档生效；关掉时原样返回 kernel 给的 delay，不改常态节奏。
Duration fnthinkLiveClampDelay(Duration delay) {
  if (!fnthinkLiveModeActive || fnthinkLiveSecondsActive <= 0) return delay;
  final cap = Duration(seconds: fnthinkLiveSecondsActive);
  return delay > cap ? cap : delay;
}

/// 与原生 worker 那条回报通道同名（`FnthinkPresenceWorker.PRESENCE_CHANNEL`）。
const String kFnthinkPresenceChannel = 'com.fnthink.notice/presence';

/// 把"后台引擎该进哪个 Dart 函数"写进 prefs。返回**到底落盘了没有**。
///
/// 为什么值得每次续排都写一遍：这是一个幂等的整数写入，而"没写"的表现是后台那一轮
/// 每次都跳过（`no-entry-handle`）—— 用一次多余的写换掉一整类"装了新包但闹钟还在跑旧的 handle"
/// 的排查（handle 会变：函数搬家、重新编译，而 prefs 里那份不会自己跟上）。
Future<bool> publishEntryHandle() async {
  final handle = PluginUtilities.getCallbackHandle(fnthinkPresenceEntrypoint);
  if (handle == null) return false;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(kFnthinkPresenceHandleKey, handle.toRawHandle());
  return true;
}

/// 后台引擎的入口（被 `FnthinkPresenceWorker` 用 handle 调起来）。
///
/// ⚠ 这个函数**必须**是 top-level 且带 `@pragma('vm:entry-point')`：
/// tree-shaking 不看调用点（没有 Dart 代码调它，只有原生按 handle 进），
/// 少了这一行 pragma 的表现是 release 包里函数被摇掉，handle 指向一个不存在的符号 ——
/// 而那条错误要等到第一次"被杀之后"才会现形，正是最难查的那种。
///
/// ⚠ **先 `WidgetsFlutterBinding.ensureInitialized()`**（真机实测的教训，2026-09-30）：
/// 这是**另一颗 isolate**，没有跑过 `runApp` ⇒ 没有 binding ⇒ `MethodChannel` 拿不到
/// `defaultBinaryMessenger`，那一发 `roundDone` 会以 `Null check operator used on a null
/// value` 收场（日志里每 20 秒一行「roundDone 没送到」），而 SharedPreferences /
/// secure storage 这些插件同理全不可用。顺序也要紧：先建 binding，再注册插件。
///
/// `roundDone` 放在 `finally`：**不管这一轮成不成都要交回结果**。不交，worker 只能等到 90 秒
/// 超时，而 WorkManager 那侧看到的是"任务卡住"，不是"这一轮失败了"。
@pragma('vm:entry-point')
Future<void> fnthinkPresenceEntrypoint() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  // T185 第二步：这一颗引擎只跑一轮（worker 交回 roundDone 后就结束）。
  // 它不开常驻档、不持锁 —— 持锁是主 isolate 的事，而这里的锁会在引擎销毁后留在进程里。
  fnthinkBackgroundIsolate = true;
  const channel = MethodChannel(kFnthinkPresenceChannel);
  try {
    await runFnthinkPresenceRound();
  } catch (e) {
    // 后台 isolate 里没有 UI 也没有崩溃上报入口：留一行可 grep 的日志，不悄悄吞。
    debugPrint('[fnthink] 后台那一轮失败：$e');
  } finally {
    try {
      await channel.invokeMethod<void>('roundDone');
    } catch (e) {
      debugPrint('[fnthink] roundDone 没送到（worker 会等到超时）：$e');
    }
  }
}

/// 一轮收货。**默认值自带装配**（指向 `di/service_locator.dart` 里那个 bootstrap），
/// 于是"后台 isolate 里 getIt 是空的"这件事在那一个函数里就地解决，不指望任何人先跑过
/// `setupLocator()`。
///
/// ⚠ 这一版的形状是被真机改出来的（2026-09-30）：上一版把默认值写成"占位实现会抛"，
/// 装配那一行放在 `setupLocator()` 里 —— 而后台 isolate **永远不跑 `setupLocator()`**，
/// 于是变量一直是占位：每一轮都失败，日志里每 20 秒一行「没有装配」。那个 lambda 内部的
/// `isRegistered` 检查救不了它，因为**变量本身从来没被赋过值**。
/// 教训记在守卫里：默认值不许是空实现/占位，必须是"自己能装配起来"的那一个。
Future<void> Function() runFnthinkPresenceRound = fnthinkBackgroundRound;
