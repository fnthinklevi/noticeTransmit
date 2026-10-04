import 'dart:async';

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:fnthink_push/fnthink_push.dart';

import 'remote_execution_notifier.dart';

import '../models/fnthink_remote_execution_record.dart';
import 'fnthink_l2_actions.dart';
import 'fnthink_l3_settings.dart';
import 'fnthink_remote_command_handler.dart';
import 'fnthink_remote_execution.dart';

/// 远程执行 片3c-3：**执行链编排**（落历史 → 回执 → 延时窗口 → 动手 → 终态回执）。
///
/// 判定层（[RemoteCommandRecognizer]）只答"该不该执行"，执行器
/// （`fnthink_remote_executors.dart`）只答"怎么动手"，**中间那一段在这里**：
/// 按契约的窗口计时、到点动手、把每次状态迁移落一行、两段回执各发一次、
/// 以及给撤销留一个咽喉。
///
/// ## 三件最容易做错的事（都写在各自那一格上）
///  ① **回执走消息不走 ack**（契约 `receiptsWhy`）—— 所以 [sendReceipt] 是一个
///     "往某个对端发一条消息"的依赖，而 ack 是收货循环自己在管的那一条链路；
///  ② **第一段回执在收到就发**，不等窗口走完 —— 它的含义是"我收下了、已经进流程、
///     现在还在撤得回来的窗口里"，不是"已经在执行了"；
///  ③ **本机触发那一路不发回执**（契约 `localTriggerReceipt`）—— 那条路上没有远端发送方。
///
/// ## 进程重启之后那批 `pending` 怎么办
/// 延时窗口靠的是进程内的 Timer，进程一死它们就没了 —— 而历史表里那些行**还写着
/// `pending`**。不扫一遍的话，界面上永远显示"待执行"，而"撤销"那一下点下去也没有任何反应
/// （撤销靠的就是那个 Timer）。所以 [sweepInterrupted] 在装配处跑一次：
/// 把所有未决的行记成 `failed` + `interrupted`，**如实说"没做成"而不是让它永远显示在等**。
/// ⚠ 它是 [ChangeNotifier]：执行链的状态每一次变（来了新指令 / 到点了 / 撤销了 /
///   执行完了）都 `notifyListeners()`，而撤销入口那两处横幅靠这个**立刻**重画。
///   只给它们一个 `pendingAt` 问口的话，横幅只能每秒轮询一次 ——
///   于是"指令到了、横幅 1 秒后才出现"，而那 1 秒正是用户最想按它的时刻。
/// ⚠ 只依赖 foundation，不引 material：这一层是服务，不该沾界面库。
class RemoteCommandRunner extends ChangeNotifier {
  RemoteCommandRunner({
    required this.contract,
    required this.windowSeconds,
    required this.l2,
    required this.l3,
    required this.saveRecord,
    required this.sendReceipt,
    required this.now,
    this.schedule = _defaultSchedule,
    this.newId = newRemoteExecutionId,
    this.statusBar,
  });

  final FnthinkContract contract;

  /// 延时窗口秒数（**由调用方从设置读好传进来**）。
  ///
  /// ⚠ 这里不自己读设置：这一层的用例要在不碰 SharedPreferences 的情况下把
  /// 「窗口 0 立刻走」与「窗口 10 秒等」两条都跑一遍，而设置那一格的取值
  /// （用户选了哪一档、有没有越界）由 `FnthinkRemoteSettings` 单独断。
  final Future<int> Function() windowSeconds;

  final FnthinkL2Executor l2;
  final FnthinkL3Executor l3;

  /// 落一行历史（`exec_id` 重复时覆盖 —— 同一行从 pending 走到终态是同一行）。
  final Future<void> Function(FnthinkRemoteExecutionRecord record) saveRecord;

  /// 把一段回执发给某个对端。回 false = 没送出去。
  ///
  /// ⚠ **发不出去不等于执行失败**：本机已经做完了，对面没收到是另一件事。
  /// 所以它只进 [FnthinkRemoteExecutionRecord.reason]，不改执行状态。
  final Future<bool> Function(String peer, RemoteReceipt receipt) sendReceipt;

  final DateTime Function() now;

  /// 排一次延时（注入：测试里自己点火，不必睡真表）。默认走 [Timer]。
  ///
  /// ⚠ **返回那个 [Timer]**：撤销与 [dispose] 要能真的把它取消掉。
  /// 写成 `void Function(...)` 就只能"到点让它空转"，而那会留下一批
  /// orphan Timer —— 进程里每收一条指令就多一个，撤了也不消失。
  final Timer Function(Duration delay, void Function() onFire) schedule;

  /// 状态栏那一枚通知（契约 `delay.cancelChannels` 的 `statusBar`，片3c-5）。
  /// null = 这一版没接（测试与某些构建形态）⇒ 只剩界面横幅那一个撤销入口。
  final RemoteExecutionNotifier? statusBar;

  final String Function(String seed) newId;

  static Timer _defaultSchedule(Duration delay, void Function() onFire) =>
      Timer(delay, onFire);

  /// 执行中的那些（`exec_id` → 那一条要动手的东西）。**工作集，不是历史** ——
  /// 撤销与到点执行都要从这里取参数，而历史表只回答"后来怎么了"。
  final Map<String, _InFlight> _inFlight = <String, _InFlight>{};

  /// 正在等窗口的那些（到点要撤掉的那一个）。`exec_id` → Timer 的句柄。
  final Map<String, Timer> _timers = <String, Timer>{};

  /// 现在有几条在等窗口（界面与用例都要看得到）。
  int get waitingCount => _timers.length;

  /// 现在有几条未决（含 executing）。撤销入口那两处横幅靠它显示"有可撤的"。
  int get unsettledCount => _inFlight.length;

  bool isUnsettled(String execId) => _inFlight.containsKey(execId);

  /// 正在窗口里的那几条（**给界面看的那一份**：撤销入口那两处横幅）。
  ///
  /// ⚠ 每问一次都现算剩余秒数，而不是在 [run] 里算好存着 ——
  /// 存下来的那个数在横幅画出来之前就开始过时，而界面上一个不动的倒计时
  /// 会让用户以为窗口已经过了却还留着「撤销」那一下（撤不动，只会更困惑）。
  List<RemotePendingView> pendingAt(DateTime now) {
    final views = <RemotePendingView>[];
    for (final entry in _inFlight.entries) {
      final flight = entry.value;
      if (flight.started) continue; // 已动手：撤不回来，界面上不该还给按钮
      final remain = flight.startedAt
          .add(Duration(seconds: flight.seconds))
          .difference(now)
          .inSeconds;
      views.add(
        RemotePendingView(
          execId: entry.key,
          level: flight.record.level,
          item: flight.record.item,
          remainingSeconds: remain < 0 ? 0 : remain,
        ),
      );
    }
    views.sort((a, b) => a.remainingSeconds.compareTo(b.remainingSeconds));
    return List<RemotePendingView>.unmodifiable(views);
  }

  /// 发一段回执（**对外发回执只有这一个口**）。
  ///
  /// 执行链那两段与「被拒」那一档都经这里 —— 直接在别处调 `sendReceipt` 依赖的话，
  /// "送不出去该怎么办"这件事会在两处各判一次，而两处的答案很容易不一样。
  Future<bool> replyReceipt(String peer, RemoteReceipt receipt) =>
      sendReceipt(peer, receipt);

  /// 一条指令从放行到终态的全过程。回 `exec_id`（撤销入口拿它）。
  Future<String> run(RemoteCommandAccepted accepted) async {
    final command = accepted.command;
    final startedAt = now();
    final seconds = await windowSeconds();
    final execId = newId(
      '${accepted.sender}|${command.level}|${command.item}|'
      '${command.argument}|${startedAt.millisecondsSinceEpoch}',
    );
    final record = FnthinkRemoteExecutionRecord(
      execId: execId,
      direction: kFnthinkRemoteDirectionIn,
      peerAddress: accepted.sender,
      level: command.level,
      item: command.item,
      argument: command.argument,
      state: RemoteExecutionStates.pending,
      source: accepted.source,
      createdAt: startedAt.millisecondsSinceEpoch,
    );
    _inFlight[execId] = _InFlight(
      record: record,
      seconds: seconds,
      startedAt: startedAt,
    );
    await saveRecord(record);
    // ① 第一段回执：**收到就发**，不等窗口。
    await _emitReceipt(execId, RemoteExecutionStates.pending);
    if (seconds <= 0) {
      // ⚠⚠ **窗口 0 不发状态栏那一枚**，而且这是**写死**的，不是顺序的巧合：
      //   契约 `delay.minSeconds = 0` 的意思是"立刻执行"，而它立刻就执行完了
      //   —— 发出去的通知活不到用户能看见，而它随即又被 `_finish` 收掉，
      //   留在通知栏里的实际效果是**闪一下**。
      //   闪一下比不发更坏：它会让用户以为"刚才那一下是要执行什么"。
      //   （`inAppBanner` 那一格同样不画 —— 窗口 0 时它连一帧都待不住。）
      await _execute(execId);
      return execId; // `_finish` 里已经通知过（pending → 终态）
    }
    notifyListeners();
    // 状态栏那一枚（撤销入口其二）。⚗ **不 await**：它是原生往返，
    // 而这一格正在收货循环里 —— 挡住它等于让一条通知的延迟拖慢整轮收货。
    // 发不出去也不该影响执行（那只是「撤销入口少了一个」，协议不要求有通知）。
    unawaited(
      statusBar?.show(execId: execId, item: record.item, seconds: seconds) ??
          Future<bool>.value(false),
    );
    // ⚠ 走**注入进来的** [schedule]，不是硬编码 `Timer(...)`：
    //   第一版这里写的是 `Timer(...)`，于是 schedule 字段从未被接上 ——
    //   字段在、默认实现在、测试也能注入，唯独这一行没调它。
    //   表现是「注入了一个不点火的延时」：测试里永远等不到回调，
    //   而生产里走的是真 Timer（所以真机上看不出问题）⇒ 只有用例会红。
    _timers[execId] = schedule(
      Duration(seconds: seconds),
      () => _execute(execId),
    );
    return execId;
  }

  /// 撤销（状态栏通知与界面顶端横幅**都只经这里**，不许各写一份）。
  ///
  /// 回 false = 这一条已经不在未决里（已执行完、或根本不是这条指令）。
  /// ⚗ **不允许"撤一条已经动手的"**：契约 `kRemoteExecutionMoves` 给了
  /// `executing → cancelled` 这条边，而执行本身可能已经做完一半 ——
  /// 所以这里**只在窗口里（还没动手）才真撤**；已动手的那一条回 false，
  /// 让界面把那一格收起来而不是显示一个按了没反应的按钮。
  Future<bool> cancel(String execId) async {
    final flight = _inFlight[execId];
    if (flight == null) return false;
    if (flight.started) {
      return false;
    }
    _timers.remove(execId)?.cancel();
    await _finish(
      execId,
      RemoteExecutionStates.cancelled,
      reason: 'cancelled-by-user',
    );
    return true;
  }

  /// 进程重启之后：把所有未决的行记成 `failed` + `interrupted`（**只落盘，不执行**）。
  ///
  /// ⚠ 只处理**没有在工作集里**的那些：本进程新收的正在跑，不该被这一刀砍掉。
  /// 之所以只落盘不执行：进程已经死过一次了，重启后**自动补做**等于
  /// 「用户以为撤掉了、其实重启后又做了一遍」—— 那一行写着 `interrupted`，
  /// 界面上会说"没做成"，这比偷偷补做诚实。
  Future<int> sweepInterrupted(List<FnthinkRemoteExecutionRecord> rows) async {
    var swept = 0;
    for (final row in rows) {
      if (!row.unsettled) continue;
      if (_inFlight.containsKey(row.execId)) continue;
      await saveRecord(
        FnthinkRemoteExecutionRecord(
          execId: row.execId,
          direction: row.direction,
          peerAddress: row.peerAddress,
          level: row.level,
          item: row.item,
          argument: row.argument,
          state: RemoteExecutionStates.failed,
          source: row.source,
          createdAt: row.createdAt,
          reason: 'interrupted',
        ),
      );
      swept++;
    }
    if (swept > 0) notifyListeners();
    return swept;
  }

  /// 到点了：走一遍 `pending → executing → 终态`。
  Future<void> _execute(String execId) async {
    final flight = _inFlight[execId];
    if (flight == null || flight.started) return;
    _timers.remove(execId);
    // ⚠⚠ **到点动手前先问原生那一句**：用户在状态栏按过「撤销」而 Dart 这边不在
    //   （后台轮次随时被回收，那正是状态栏那个入口存在的理由）。
    //   不问这一句的表现是「我明明按了撤销，它还是执行了」，而本机没有任何痕迹可查。
    //   问完即清（原生那一侧 consume），所以下一轮重投同一条指令时它会被当成没被撤过 ——
    //   那是对的：重投是一次新的指令。
    if (await (statusBar?.takeCancelled(execId) ?? Future<bool>.value(false))) {
      await _finish(
        execId,
        RemoteExecutionStates.cancelled,
        reason: 'cancelled-from-status-bar',
      );
      return;
    }
    // ⚠ 迁移要用**内核那一格**判，不是自己拼字符串：非法迁移要么拒要么不留痕，
    //   而这一层若绕过它，出现一次意外状态就会直接把一次执行记成成功。
    final moving = advanceRemoteExecution(
      contract,
      flight.record.state,
      RemoteExecutionStates.executing,
    );
    if (moving is RemoteExecutionRefused) {
      await _finish(
        execId,
        RemoteExecutionStates.failed,
        reason: moving.reason,
      );
      return;
    }
    flight.started = true;
    // ⚠ 迁移过了也要通知：横幅从这一刻起**不该再给撤销按钮**了
    //   （撤不回来），而它若只在终态才重画，中间那段时间用户按下去只会得到一句
    //   "撤不回来" —— 与"横幅已经撤不掉"是同一件事，但前者多一次失败的按压。
    notifyListeners();
    // ⚠⚠ 迁完**必须把这一行改成 executing**：`_finish` 还要用内核那一格判
    //   `executing → 终态`，而它读到的是这里存的那一份。
    //   漏这一改的症状很难认：`pending → done` 不在允许表里 ⇒ 被判 `illegal-move`
    //   ⇒ 执行明明做成了，历史那一行却记成 `failed`，而第二段回执压根没发出去
    //   （对面一直等下去）。这一条是内核那个判据当场抓出来的，不是想出来的。
    flight.record = _withState(flight.record, RemoteExecutionStates.executing);
    final result = await _dispatch(flight.record);
    await _finish(
      execId,
      result.ok ? RemoteExecutionStates.done : RemoteExecutionStates.failed,
      reason: result.reason,
      result: result.reason ?? '',
    );
  }

  /// 按档派发（L1 走并集那张表：先动作表、再设置表，与判定层同一顺序）。
  Future<({bool ok, String? reason})> _dispatch(
    FnthinkRemoteExecutionRecord record,
  ) async {
    try {
      if (record.level == 'L3') {
        final parsed = parseL3Item(
          contract,
          record.item,
          // ⚠ `confirmedThisTime: true`：**延时窗口走完就是那一次确认**
          //   （契约 `l3.confirmForm = cancelableDelay`：内核仍是"每次确认"，
          //   形式从"点一下"变成"没去取消"）。判定层不判它，因为它那时还没有窗口。
          confirmedThisTime: true,
        );
        if (parsed is FnthinkL3Rejected) {
          return (ok: false, reason: parsed.reason);
        }
        final r = await dispatchL3Setting(
          contract,
          l3,
          (parsed as FnthinkL3Ok).setting,
        );
        return (ok: r.ok, reason: r.reason);
      }
      final parsed = parseL2Item(contract, record.item);
      if (parsed is FnthinkL2Rejected) {
        // 不在这一档的动作表里：L1 仍可能在 L3 那张设置表上（并集表，见判定层注释）。
        final asL3 = contract.l3Settings[record.item];
        if (asL3 == null) return (ok: false, reason: parsed.reason);
        final r = await dispatchL3Setting(contract, l3, asL3);
        return (ok: r.ok, reason: r.reason);
      }
      final action = (parsed as FnthinkL2Ok).action;
      // ⚠ 参数取**从 item 里解析出来的那一份**（`action.argument`），
      //   不是历史那一行的 `argument` 列 —— 判形状那一次也是从它取的，
      //   两处不同源的话"收的时候说没问题、动手时才发现动不了"。
      final r = await dispatchL2Action(contract, l2, action);
      return (ok: r.ok, reason: r.reason);
    } catch (e) {
      // 一条坏指令不许把整轮收货按停（记成失败，接着走下一条）。
      return (ok: false, reason: 'threw:${record.item}');
    }
  }

  /// 落终态 + 发第二段回执 + 从工作集里拿掉。
  Future<void> _finish(
    String execId,
    String state, {
    String? reason,
    String result = '',
  }) async {
    final flight = _inFlight.remove(execId);
    if (flight == null) return;
    _timers.remove(execId)?.cancel();
    final done = advanceRemoteExecution(contract, flight.record.state, state);
    if (done is RemoteExecutionRefused) {
      // 到终态这一步还能被拒，只可能是"工作集里那条已经不是预期的状态"；
      // 记成失败并写明理由，不静默丢掉（丢掉的症状是界面上永远停在 executing）。
      await saveRecord(
        _withState(
          flight.record,
          RemoteExecutionStates.failed,
          reason: done.reason,
        ),
      );
      return;
    }
    await saveRecord(
      _withState(flight.record, state, reason: reason, result: result),
    );
    await _emitReceipt(execId, state, flight: flight);
    // 收掉那一枚：不管这一次是做了、没成、还是撤了，
    // 留着一条「10 秒后执行」就等于告诉用户「还有机会」—— 而其实没有了。
    unawaited(statusBar?.clear(execId) ?? Future<void>.value());
    notifyListeners();
  }

  /// 发一段回执（**两段都走这里** —— 只有"该不该发"那一格按来源分）。
  Future<void> _emitReceipt(
    String execId,
    String state, {
    _InFlight? flight,
  }) async {
    final f = flight ?? _inFlight[execId];
    if (f == null) return;
    if (!remoteExecutionSendsReceipt(contract, f.record.source)) return;
    final receipt = remoteExecutionReceiptFor(
      contract: contract,
      level: f.record.level,
      item: f.record.item,
      argument: f.record.argument,
      state: state,
    );
    if (receipt == null) return;
    final sent = await sendReceipt(f.record.peerAddress, receipt);
    if (sent) return;
    // ⚠ 送不出去只进 reason，**不改执行状态**（见 sendReceipt 那一格）。
    //   写回那一行会把"执行做成了"变成"执行没做成"，那是撒谎。
  }

  FnthinkRemoteExecutionRecord _withState(
    FnthinkRemoteExecutionRecord r,
    String state, {
    String? reason,
    String result = '',
  }) => FnthinkRemoteExecutionRecord(
    execId: r.execId,
    direction: r.direction,
    peerAddress: r.peerAddress,
    level: r.level,
    item: r.item,
    argument: r.argument,
    state: state,
    source: r.source,
    createdAt: r.createdAt,
    result: result,
    reason: reason ?? '',
  );

  /// 把所有还在等窗口的撤掉（装配拆卸时用；不给一条 orphan Timer 留活口）。
  @override
  void dispose() {
    super.dispose();
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _inFlight.clear();
  }
}

/// 一条还在窗口里的东西 —— **给界面的那一份**（撤销入口那两处横幅读它）。
///
/// ⚠ 它是 [RemotePendingView] 而不是直接给记录：横幅要显示「还剩几秒」，
/// 而那个数每时每刻都在变；把它存进记录里就等于给界面一个一动不动的倒计时。
class RemotePendingView {
  const RemotePendingView({
    required this.execId,
    required this.level,
    required this.item,
    required this.remainingSeconds,
  });

  final String execId;
  final String level;
  final String item;

  /// 还差几秒到点（0 = 已到点，那一刻执行就在跑或已跑完）。
  final int remainingSeconds;

  @override
  String toString() =>
      'RemotePendingView($execId $level $item 剩 ${remainingSeconds}s)';
}

/// 一条正在执行的东西（工作集的一格）。
class _InFlight {
  _InFlight({
    required this.record,
    required this.seconds,
    required this.startedAt,
  });

  /// 这一条现在的样子（**迁一次改一次** —— 见 `_execute` 里那格：漏改的后果是
  /// 下一次迁移拿一个过时的状态去判，而内核会判它非法）。
  FnthinkRemoteExecutionRecord record;

  /// 窗口秒数（落在这里是为了 [RemoteCommandRunner.windowSeconds] 那一格
  /// 只读一次 —— 一条指令的窗口不该在读设置与到点之间被改成另一档）。
  final int seconds;

  /// 什么时候开始算窗口（横幅的倒计时按它算，不按 `createdAt` ——
  /// 那两个差着一次落盘与一次回执的工夫，而倒计时差一秒用户就看出来了）。
  final DateTime startedAt;

  /// 已经动手了（`pending → executing` 走完）⇒ 撤销入口不再受理。
  bool started = false;
}
