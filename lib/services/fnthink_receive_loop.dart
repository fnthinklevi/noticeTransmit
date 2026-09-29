import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fnthink_push/fnthink_push.dart';

import '../models/fnthink_inbox_message.dart';
import 'fnthink_receiver_service.dart';

/// 收货循环（#126 第三片）：把**取货 → 落库 → 回一条 ack → 排下一轮**这个顺序钉死。
///
/// 节奏的出处不在这里 —— 间隔与提频都在契约（`presence.*`）与内核（[FnthinkReceiveKernel]）里，
/// 这里只负责"顺序与后果"。五件事各有一个具体的"写反了会怎样"：
///
/// ① **落库失败的那条绝不 ack。** ack 会让服务端**立刻删正文**（`retention.deleteBodyOn` 含
///    delivered），先报成功再把消息弄丢，就是产品不变量「不静默丢」最坏的一种实现方式。
/// ② **重发的那条也要再 ack。** 本地已经有这行 ⇒ `insert` 回 false，但服务端还在重发它，
///    说明上一次 ack 根本没到达。跳过它等于让一条已经在本机里的消息永远挂在队列上，
///    而它会一直占着那个设备的 pending 额度。
/// ③ **ack 撞到 429 就停本轮。** 剩余的不发、也不记成失败，按服务端给的 `Retry-After` 排下一轮
///    —— 把 429 当成"这条没送达"去重试，等于用一台设备的积压去敲服务端的闸门。
/// ④ **一轮只跑一轮。** 一次往返慢过一个间隔时，不拦住就会有两个循环同时在读同一条队列；
///    表现是重复 ack、以及"未读数一会儿 3 一会儿 1"。
/// ⑤ **显示成功才报 `displayed`，否则报 `delivered`。** 一条没进通知栏的消息被报成"已显示"，
///    服务端就按契约删了正文，而用户两头都没见过它 —— 与 ① 是同一件事的两面（① 管"没落库别说收到了"，
///    ⑤ 管"没显示别说看过了"）。内核一轮只认一条 ack，所以这里是**二选一**，不是先 delivered 再 displayed。
///
/// ⚠ [display] 不接（null）时一律报 `delivered` —— 那是"这台设备还没有显示链路"的显式表达，
/// 不是"显示了但没算数"。接上之后走的也是 ⑤ 那条二选一，不会先 delivered 再 displayed：
/// 内核一轮只认一条 ack（`duplicateSuppressed`）。
class FnthinkReceiveLoop {
  /// [poll] / [ack] 传 [FnthinkReceiverService.pollOnce] 与它的 `ack` 即可（签名逐一对得上）。
  /// 之所以写成两个函数而不是收一个服务对象：循环的那几条判据不该被 HTTP 层的形状牵着走，
  /// 绑在一起之后，换一次 transport 就得把节奏与后果全部重测一遍。
  /// [persist] 回 true = 新增，false = 这条已经在表里，抛异常 = 没落到盘上。
  FnthinkReceiveLoop({
    required this.poll,
    required this.ack,
    required this.persist,
    this.display,
    this.recordAck,
    int Function()? nowMs,
    Timer Function(Duration delay, void Function() callback)? schedule,
    this.onRound,
  }) : nowMs = nowMs ?? _systemNowMs,
       schedule = schedule ?? _defaultSchedule;

  /// 一次取货（生产实现是 [FnthinkReceiverService.pollOnce] 的 tear-off）。
  final Future<FnthinkReceiveOutcome> Function() poll;

  /// 回一条送达结论（同上，`ack` 的边界在内核判：词表、本轮、不重复）。
  final Future<FnthinkAckResult> Function(String messageId, String result) ack;

  /// 落一条收件：true = 新增，false = 表里已经有，抛异常 = 没落到盘上。
  final Future<bool> Function(FnthinkInboxMessage message) persist;

  /// 显示一条收件（通知栏）。null = 这台设备还没有显示链路 ⇒ 一律按 `delivered` 报。
  /// ⚠ 顺序在 persist **之后**：用户点通知时要能落到一条已经在表里的事实，
  ///   先显示后落库会在"显示完就崩"的那次里留下一条点不开的通知。
  final Future<bool> Function(FnthinkInboxMessage message)? display;

  /// 服务端**收下**这条 ack 之后，把本机报过的结论记进收件表（`ack_result`/`acked_at`）。
  /// null = 这台设备不记账 ⇒ 那一列一直空着，而空的含义是"没报过"，不是"报失败"。
  ///
  /// ⚠ 只在 `status == ok` 之后调：429 与验签失败都**没报成**，记下来就是本机对自己撒谎
  /// （表现是收件详情写着"我报过 displayed"而服务端那边根本没收到，于是这条永远在重发）。
  final Future<bool> Function({
    required String messageId,
    required String result,
    required int at,
  })?
  recordAck;

  final int Function() nowMs;
  final Timer Function(Duration delay, void Function() callback) schedule;

  /// 每轮结束后的一句账（页面/日志读它；**不含任何标题与正文**）。
  final void Function(FnthinkLoopReport report)? onRound;

  Timer? _timer;
  bool _wantRunning = false;
  bool _inRound = false;

  bool get isRunning => _wantRunning;

  /// 开始循环：立刻跑一轮，之后每轮按内核给的间隔排下一轮。重复调用不会叠出第二个循环。
  void start() {
    if (_wantRunning) return;
    _wantRunning = true;
    _tick();
  }

  /// 停止：不再排下一轮，**已在途的那一轮跑完为止**（强行中断等于把 ack 停在半路）。
  void stop() {
    _wantRunning = false;
    _timer?.cancel();
    _timer = null;
  }

  void _tick() {
    if (!_wantRunning) return;
    unawaited(
      runOnce()
          .then((report) {
            if (!_wantRunning) return;
            _timer = schedule(report.nextDelay, _tick);
            onRound?.call(report);
          })
          .catchError((Object e) {
            // 循环里任何没被分类的异常都不许把链条掐断：断了的表现是"再也不来了"，
            // 而设备侧没有任何地方会显示"收货在三天前就停了"。按一个保守的间隔爬起来。
            debugPrint('[fnthink] 收货循环异常（按下一轮继续）: $e');
            if (!_wantRunning) return;
            _timer = schedule(_fallbackDelay, _tick);
          }),
    );
  }

  static Duration get _fallbackDelay => const Duration(seconds: 60);

  /// 一轮。公开出来是给调用方（页面手动"立即收取"、测试）一个不带定时器的入口。
  Future<FnthinkLoopReport> runOnce() async {
    if (_inRound) {
      // 上一轮还没结束 ⇒ 这一轮**整轮跳过**，不做任何 IO，也不动 ack 计数。
      // 排回去也得等一会儿：拿 Duration.zero 排就等于把"跳过"变成一台空转的马达。
      return FnthinkLoopReport(
        status: FnthinkPollStatus.failed,
        reason: 'round-in-progress',
        nextDelay: _fallbackDelay,
        skipped: true,
      );
    }
    _inRound = true;
    try {
      return await _runRound();
    } finally {
      _inRound = false;
    }
  }

  Future<FnthinkLoopReport> _runRound() async {
    final outcome = await poll();
    if (outcome.status != FnthinkPollStatus.ok) {
      // 一次失败的取货不产生任何"这条没了"的判断（五种失败的下一步在内核里分过类）。
      return FnthinkLoopReport(
        status: outcome.status,
        reason: outcome.reason,
        nextDelay: outcome.nextDelay,
      );
    }

    final at = nowMs();
    // 一条消息 → 这一轮该报的结论。LinkedHashMap 的迭代顺序就是取货顺序（翻页与计数都对得上）。
    final toAck = <String, String>{};
    var inserted = 0, duplicate = 0, persistedFailed = 0, shown = 0;
    for (final message in outcome.messages) {
      // 落库与显示用的是同一份行：两处各映射一次，就会在两处各抄一次字段清单（而 sender
      // 那个缺口正是这么漏掉的）。
      final row = _toRow(message, at);
      final fresh = await _persistRow(row);
      if (fresh == _Persisted.fresh) {
        inserted++;
      } else if (fresh == _Persisted.known) {
        // 已经在表里 = 服务端还在重发 = 我上一次 ack 没送到。必须再报一次。
        duplicate++;
      } else {
        persistedFailed++;
        continue; // ① 没落到盘上的这条**不显示也不 ack**：ack 会让服务端删正文
      }
      // ⑤ 显示成功才报 displayed。报错了那条结论就是替服务端宣布"用户看过了"，
      //    而它下一秒就会把正文删掉 —— 用户两头都没见到。
      final displayed = await _displayRow(row);
      if (displayed) shown++;
      toAck[row.messageId] = displayed ? 'displayed' : 'delivered';
    }

    var acked = 0, ackFailed = 0, ackSkipped = 0;
    var nextDelay = outcome.nextDelay;
    final ids = toAck.keys.toList();
    for (var i = 0; i < ids.length; i++) {
      final result = await ack(ids[i], toAck[ids[i]]!);
      if (result.status == FnthinkPollStatus.ok) {
        acked++;
        await _recordAck(ids[i], toAck[ids[i]]!);
        continue;
      }
      if (result.status == FnthinkPollStatus.rateLimited) {
        // 闸门就是闸门：剩下的这轮不发，按服务端给的等待时间重来。
        nextDelay = result.nextDelay;
        ackSkipped = ids.length - i - 1;
        break;
      }
      ackFailed++;
    }

    return FnthinkLoopReport(
      status: FnthinkPollStatus.ok,
      taken: outcome.messages.length,
      inserted: inserted,
      duplicate: duplicate,
      persistedFailed: persistedFailed,
      displayed: shown,
      acked: acked,
      ackFailed: ackFailed,
      ackSkipped: ackSkipped,
      pending: outcome.pending,
      nextDelay: nextDelay,
      signedWhileUncalibrated: outcome.signedWhileUncalibrated,
    );
  }

  /// 显示这条收件。没接链路 = 没显示；抛异常 = 没显示（两种都退回 delivered）。
  Future<bool> _displayRow(FnthinkInboxMessage message) async {
    final show = display;
    if (show == null) return false;
    try {
      return await show(message);
    } catch (e) {
      debugPrint(
        '[fnthink] 收件显示异常（按未显示处理，ack 退回 delivered）: ${message.messageId} $e',
      );
      return false;
    }
  }

  /// 把这一条报过的结论记进收件表。没接链路就不记；抛异常只记日志 —— 账已经报出去了，
  /// 本机这份记忆丢了不值得让整轮停（下一轮那条还会重发，届时再记一次）。
  Future<void> _recordAck(String messageId, String result) async {
    final write = recordAck;
    if (write == null) return;
    try {
      final hit = await write(
        messageId: messageId,
        result: result,
        at: nowMs(),
      );
      if (!hit) {
        debugPrint('[fnthink] ack 记账没命中那一行（可能已被保留策略裁掉）: $messageId');
      }
    } catch (e) {
      debugPrint('[fnthink] ack 记账失败（不影响本轮）: $messageId $e');
    }
  }

  /// poll 带回来的那条 → 收件表那一行。**这份映射只有一处**。
  static FnthinkInboxMessage _toRow(FnthinkDelivered message, int at) =>
      FnthinkInboxMessage(
        messageId: message.messageId,
        sender: message.sender,
        type: message.type,
        item: message.item,
        title: message.title,
        body: message.body,
        receivedAt: at,
      );

  Future<_Persisted> _persistRow(FnthinkInboxMessage row) async {
    try {
      final fresh = await persist(row);
      return fresh ? _Persisted.fresh : _Persisted.known;
    } catch (e) {
      debugPrint('[fnthink] 收件落库失败（这条不 ack）: ${row.messageId} $e');
      return _Persisted.failed;
    }
  }

  static Timer _defaultSchedule(Duration delay, void Function() callback) =>
      Timer(delay, callback);

  static int _systemNowMs() => DateTime.now().toUtc().millisecondsSinceEpoch;
}

enum _Persisted { fresh, known, failed }

/// 一轮的账。每个数都对应一条独立的判据，所以不合并成"成功/失败"两档。
class FnthinkLoopReport {
  const FnthinkLoopReport({
    required this.status,
    this.taken = 0,
    this.inserted = 0,
    this.duplicate = 0,
    this.persistedFailed = 0,
    this.displayed = 0,
    this.acked = 0,
    this.ackFailed = 0,
    this.ackSkipped = 0,
    this.pending = 0,
    this.nextDelay = Duration.zero,
    this.reason,
    this.signedWhileUncalibrated = false,
    this.skipped = false,
  });

  final FnthinkPollStatus status;

  /// 这一轮从服务端拿到几条
  final int taken;

  /// 其中几条是**新**落进收件表的
  final int inserted;

  /// 表里已经有、但服务端还在重发（于是又 ack 了一次）的条数
  final int duplicate;

  /// 没落到盘上的条数 —— 这些条**没有 ack**（①），服务端会再送一次
  final int persistedFailed;

  /// 真的显示进通知栏的条数（决定那几条 ack 报的是 displayed 还是 delivered）
  final int displayed;

  final int acked;
  final int ackFailed;

  /// 因为 429 本轮没发出去的条数（③：不是失败，所以不记进 ackFailed）
  final int ackSkipped;

  /// 服务端报的"还排着几条"（内核用它判提频）
  final int pending;

  final Duration nextDelay;
  final String? reason;

  /// 这一轮签出去时本机时钟还没校正过（T29：那种 ts 不可信，值得单独看得见）
  final bool signedWhileUncalibrated;

  /// 整轮被跳过（④：上一轮还在途）
  final bool skipped;

  String get summary =>
      '取 $taken · 新 $inserted · 重发 $duplicate · 落库失败 $persistedFailed · '
      '显示 $displayed · '
      'ack $acked/${ackFailed}_skip$ackSkipped · 待取 $pending · '
      '下轮 ${nextDelay.inSeconds}s${reason == null ? '' : ' · $reason'}';
}
