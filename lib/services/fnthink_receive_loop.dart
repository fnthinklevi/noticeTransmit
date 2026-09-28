import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fnthink_push/fnthink_push.dart';

import '../models/fnthink_inbox_message.dart';
import 'fnthink_receiver_service.dart';

/// 收货循环（#126 第三片）：把**取货 → 落库 → 回一条 ack → 排下一轮**这个顺序钉死。
///
/// 节奏的出处不在这里 —— 间隔与提频都在契约（`presence.*`）与内核（[FnthinkReceiveKernel]）里，
/// 这里只负责"顺序与后果"。四件事各有一个具体的"写反了会怎样"：
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
///
/// ⚠ ack 用的是 `delivered`（本机已收到并落库），不是 `displayed`：现在还没有把收件显示成
/// 通知的链路（W3d/T48）。内核**一轮只认一条 ack**（`duplicateSuppressed`），所以
/// "落库就报 delivered、显示后再报 displayed"这条路本来就不通 —— 等显示链路落地时，
/// 这里的取值要改成"显示成功报 displayed，否则报 delivered"，两处不能并存。
class FnthinkReceiveLoop {
  /// [poll] / [ack] 传 [FnthinkReceiverService.pollOnce] 与它的 `ack` 即可（签名逐一对得上）。
  /// 之所以写成两个函数而不是收一个服务对象：循环的四条判据不该被 HTTP 层的形状牵着走，
  /// 绑在一起之后，换一次 transport 就得把节奏与后果全部重测一遍。
  /// [persist] 回 true = 新增，false = 这条已经在表里，抛异常 = 没落到盘上。
  FnthinkReceiveLoop({
    required this.poll,
    required this.ack,
    required this.persist,
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
    final deliverable = <String>[];
    var inserted = 0, duplicate = 0, persistedFailed = 0;
    for (final message in outcome.messages) {
      final fresh = await _persistRow(message, at);
      if (fresh == _Persisted.fresh) {
        inserted++;
        deliverable.add(message.messageId);
      } else if (fresh == _Persisted.known) {
        // 已经在表里 = 服务端还在重发 = 我上一次 ack 没送到。必须再报一次。
        duplicate++;
        deliverable.add(message.messageId);
      } else {
        persistedFailed++;
      }
    }

    var acked = 0, ackFailed = 0, ackSkipped = 0;
    var nextDelay = outcome.nextDelay;
    for (var i = 0; i < deliverable.length; i++) {
      final result = await ack(deliverable[i], 'delivered');
      if (result.status == FnthinkPollStatus.ok) {
        acked++;
        continue;
      }
      if (result.status == FnthinkPollStatus.rateLimited) {
        // 闸门就是闸门：剩下的这轮不发，按服务端给的等待时间重来。
        nextDelay = result.nextDelay;
        ackSkipped = deliverable.length - i - 1;
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
      acked: acked,
      ackFailed: ackFailed,
      ackSkipped: ackSkipped,
      pending: outcome.pending,
      nextDelay: nextDelay,
      signedWhileUncalibrated: outcome.signedWhileUncalibrated,
    );
  }

  Future<_Persisted> _persistRow(FnthinkDelivered message, int at) async {
    try {
      final fresh = await persist(
        FnthinkInboxMessage(
          messageId: message.messageId,
          sender: message.sender,
          type: message.type,
          item: message.item,
          title: message.title,
          body: message.body,
          receivedAt: at,
        ),
      );
      return fresh ? _Persisted.fresh : _Persisted.known;
    } catch (e) {
      debugPrint('[fnthink] 收件落库失败（这条不 ack）: ${message.messageId} $e');
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
      'ack $acked/${ackFailed}_skip$ackSkipped · 待取 $pending · '
      '下轮 ${nextDelay.inSeconds}s${reason == null ? '' : ' · $reason'}';
}
