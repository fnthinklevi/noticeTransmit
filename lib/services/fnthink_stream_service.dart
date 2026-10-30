import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:http/http.dart' as http;

import 'fnthink_diag.dart';
import 'fnthink_receiver_service.dart';

/// SSE 门铃（T185 第二步）。
///
/// 它**只回答"现在有东西了"**：收到 `event: wake` 就调 [onWake]（那边去跑真正的那一轮
/// poll → 落库 → ack）。投递语义、去重、ack 归属一个字节都不从这里过 —— 这一层一旦
/// 自己解析消息，就会长出第二条投递链，而两条链的 ack 迟早对不上。
///
/// 三条连接纪律（与 ntfy/Gotify 那套一致）：
///  ① **健康时通知**：连上/断开各回调一次，调用方据此把空闲 poll 退到契约的
///     `safetyPollSeconds`、并决定要不要常驻持锁；
///  ② **断线退避**：5s → 120s 指数退避，连上就清零；
///  ③ **重连换新票**：票是一次性的、90 秒过期，旧票重连只会拿到 403。
/// T218：门铃的三态。`healthy` = 门铃在岗；`degraded` = 中间层吞流但短轮询可达；
/// `offline` = 短轮询也失败，按既有退避重连。
enum FnthinkStreamLinkState { healthy, degraded, offline }

class FnthinkStreamService {
  FnthinkStreamService({
    required this.contract,
    required this.baseUri,
    required this.requestTicket,
    required this.onWake,
    required this.onLinkStateChanged,
    this.probeOnStale,
    this.degradedProbeInterval,
    FnthinkSseOpen? open,
    List<Duration>? backoff,
    int Function()? nowMs,
  }) : _open = open ?? _httpOpen,
       _nowMs = nowMs ?? _defaultNowMs,
       _backoff =
           backoff ??
           const [
             Duration(seconds: 5),
             Duration(seconds: 10),
             Duration(seconds: 15),
             Duration(seconds: 20),
             Duration(seconds: 30),
             Duration(seconds: 45),
             Duration(seconds: 60),
             Duration(seconds: 120),
           ];

  static int _defaultNowMs() => DateTime.now().millisecondsSinceEpoch;

  final FnthinkContract contract;
  final Uri baseUri;
  final Future<FnthinkStreamTicket?> Function() requestTicket;
  final void Function() onWake;

  /// 三态的唯一出口。调用方据此决定轮询节奏、短轮询模式与是否补一轮。
  final void Function(FnthinkStreamLinkState state) onLinkStateChanged;

  /// 判死后先验的那一发 `hold:false` 短轮询；null = 直接按 offline 处理（旧装配/测试）。
  /// 返回 true = 路径可达（degraded），false = 真离线（offline）。
  final Future<bool> Function()? probeOnStale;

  /// degraded 态重探门铃的间隔；null = 读契约 `stream.safetyPollSeconds`（300 秒）。
  final Duration? degradedProbeInterval;

  final FnthinkSseOpen _open;
  final int Function() _nowMs;
  final List<Duration> _backoff;

  bool _running = false;
  FnthinkStreamLinkState _state = FnthinkStreamLinkState.offline;
  int _attempt = 0;

  /// 连接代际：每次新连接/清理都递增；旧连接留下的 Timer 带着旧代际，
  /// 即使漏跑一拍也只能原地返回。
  int _generation = 0;
  StreamSubscription<String>? _sub;
  void Function()? _closeConnection;
  Timer? _retryTimer;

  /// T197 片1：最后一次收到**任何字节**的时刻（含 `: connected` 与服务端心跳）。
  /// 健康位只说明"连接曾经建成"，它不能回答"这条流现在还活着吗"。
  int? _lastByteAtMs;
  Timer? _watchdogTimer;
  final StringBuffer _buffer = StringBuffer();

  int? get _heartbeatSeconds => contract.streamSpec?.heartbeatSeconds;

  FnthinkStreamLinkState get linkState => _state;

  bool get isHealthy => _state == FnthinkStreamLinkState.healthy;

  bool get isDegraded => _state == FnthinkStreamLinkState.degraded;

  @visibleForTesting
  Duration get degradedProbeIntervalForTest =>
      degradedProbeInterval ??
      Duration(seconds: contract.streamSpec?.safetyPollSeconds ?? 300);

  void start() {
    if (_running) return;
    _running = true;
    _attempt = 0;
    unawaited(_connect());
  }

  void stop() {
    _running = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    _cleanupConnection();
    _setState(FnthinkStreamLinkState.offline);
    _buffer.clear();
  }

  Future<void> _connect() async {
    if (!_running) return;
    final spec = contract.streamSpec;
    if (spec == null) return;
    FnthinkStreamTicket? ticket;
    try {
      ticket = await requestTicket();
    } catch (e) {
      debugPrint('[fnthink] SSE 换票抛了（退回长轮询并重试）：$e');
      _scheduleRetry();
      return;
    }
    if (!_running) return;
    if (ticket == null) {
      _scheduleRetry();
      return;
    }
    try {
      final connection = await _open(baseUri.resolve(spec.path), {
        spec.ticketHeader: ticket.ticket,
      });
      if (!_running) {
        connection.close?.call();
        return;
      }
      if (connection.status != 200) {
        connection.close?.call();
        _scheduleRetry();
        return;
      }
      _closeConnection = connection.close;
      _attempt = 0;
      _buffer.clear();
      // T196：连接建立/每一块字节都留一枚时刻，原生自检据此回答"门铃最后一次有动静是什么时候"。
      // T197 片1：同一枚时刻也是看门狗的起点 —— 只有字节能证明这条流还活着。
      _lastByteAtMs = _nowMs();
      _generation++;
      final generation = _generation;
      _setState(FnthinkStreamLinkState.healthy);
      _retryTimer?.cancel();
      _retryTimer = null;
      _startWatchdog(generation);
      unawaited(markFnthinkStreamByte(atMs: _nowMs()));
      _sub = connection.body
          .transform(utf8.decoder)
          .listen(
            _consume,
            onDone: () => _onGone(generation),
            onError: (Object e) {
              debugPrint('[fnthink] SSE 流断了：$e');
              _onGone(generation);
            },
            cancelOnError: true,
          );
    } catch (e) {
      debugPrint('[fnthink] SSE 连接没建成（退回长轮询）：$e');
      _scheduleRetry();
    }
  }

  /// 一块一块地解 SSE：事件之间用空行分隔，`:` 开头的是心跳注释（忽略）。
  void _consume(String chunk) {
    _lastByteAtMs = _nowMs();
    unawaited(markFnthinkStreamByte(atMs: _nowMs()));
    // T218：degraded 只是"看门狗判它不响"，连接仍在。只要它又吐出一个字节
    // （含心跳/`connected`），就说明流活着 —— 立刻回 healthy，并恢复看门狗。
    if (_state != FnthinkStreamLinkState.healthy && _sub != null) {
      _retryTimer?.cancel();
      _retryTimer = null;
      _attempt = 0;
      _setState(FnthinkStreamLinkState.healthy);
      _startWatchdog(_generation);
    }
    // SSE 行尾允许 \r\n；去掉 \r 之后按 \n\n 分块。
    _buffer.write(chunk.replaceAll('\r', ''));
    var text = _buffer.toString();
    var index = text.indexOf('\n\n');
    while (index >= 0) {
      final block = text.substring(0, index);
      text = text.substring(index + 2);
      if (isWakeEventBlock(block)) {
        try {
          onWake();
        } catch (e) {
          debugPrint('[fnthink] SSE 唤醒回调失败：$e');
        }
      }
      index = text.indexOf('\n\n');
    }
    _buffer
      ..clear()
      ..write(text);
  }

  void _onGone(int generation) {
    // 旧连接（已 cleanup / 已换新连接）的收尾回调一律不认：它可能是我们主动关掉的。
    if (!_running || generation != _generation) return;
    _goOffline();
  }

  /// 真离线：门铃关掉，按既有退避重连；轮询由协调者那一侧继续。
  void _goOffline() {
    _setState(FnthinkStreamLinkState.offline);
    _cleanupConnection();
    _scheduleRetry();
  }

  /// T197 片1：连接建成后每半个心跳查一次"上次收到字节是什么时候"。
  /// 健康位只证明连接曾经建成；服务端心跳停了/反代静默切断时，socket 可能还挂着。
  ///
  /// 代际：Timer 只属于创建它的那条连接。旧 Timer 即便漏跑一拍，
  /// 也只会看到 `generation != _generation` 后直接返回，不能改写新连接的健康位。
  void _startWatchdog(int generation) {
    _watchdogTimer?.cancel();
    final hb = _heartbeatSeconds;
    if (hb == null || hb <= 0) return;
    final interval = Duration(seconds: hb <= 2 ? 1 : hb ~/ 2);
    _watchdogTimer = Timer.periodic(
      interval,
      (_) => checkStaleForTest(generation: generation),
    );
  }

  /// 测试入口：不等真实计时器，直接把"现在"推进到阈值之外再调用。
  @visibleForTesting
  void checkStaleForTest({int? generation}) {
    if (generation != null && generation != _generation) return;
    if (!_running || _state != FnthinkStreamLinkState.healthy) return;
    final last = _lastByteAtMs;
    if (last == null) return;
    final hb = _heartbeatSeconds;
    if (hb == null || hb <= 0) return;
    if (!isStreamStale(
      lastByteAtMs: last,
      nowMs: _nowMs(),
      heartbeatSeconds: hb,
    )) {
      return;
    }
    debugPrint('[fnthink] SSE 超过 ${hb * 2.5}s 没有字节，判死不假装在线');
    _onStale();
  }

  /// T218：判死不再等于断开。先降级（轮询继续），再让协调者跑一发短轮询探针；
  /// 探针说路径可达 ⇒ 保持连接并每 `degradedProbeInterval` 再探一次；
  /// 探针也说不可达 ⇒ 才是真离线，关连接走既有退避。
  void _onStale() {
    if (!_running || _state != FnthinkStreamLinkState.healthy) return;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _setState(FnthinkStreamLinkState.degraded);
    final probe = probeOnStale;
    if (probe == null) {
      _goOffline();
      return;
    }
    unawaited(() async {
      bool reachable;
      try {
        reachable = await probe();
      } catch (e) {
        debugPrint('[fnthink] 静默探针抛了（按不可达处理）：$e');
        reachable = false;
      }
      if (!_running || _state != FnthinkStreamLinkState.degraded) return;
      if (reachable) {
        _scheduleDegradedProbe();
      } else {
        _goOffline();
      }
    }());
  }

  void _cleanupConnection() {
    _generation++;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _lastByteAtMs = null;
    final sub = _sub;
    _sub = null;
    if (sub != null) unawaited(sub.cancel());
    final close = _closeConnection;
    _closeConnection = null;
    try {
      close?.call();
    } catch (_) {}
  }

  void _scheduleRetry() {
    if (!_running) return;
    if (_state == FnthinkStreamLinkState.degraded) {
      _scheduleDegradedProbe();
      return;
    }
    _retryTimer?.cancel();
    final delay = _attempt < _backoff.length
        ? _backoff[_attempt]
        : _backoff.last;
    if (_attempt < _backoff.length - 1) _attempt++;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(_connect());
    });
  }

  /// degraded 态的低频重探：不是每 50 秒抖一次，而是每 `safetyPollSeconds`（默认 300s）
  /// 换一次新票重连；连上后拿到任何字节就回 healthy，拿不到就继续留在 degraded。
  void _scheduleDegradedProbe() {
    if (!_running || _state != FnthinkStreamLinkState.degraded) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(degradedProbeIntervalForTest, probeDegradedForTest);
  }

  @visibleForTesting
  void probeDegradedForTest() {
    if (!_running || _state != FnthinkStreamLinkState.degraded) return;
    _retryTimer?.cancel();
    _retryTimer = null;
    _cleanupConnection();
    unawaited(_connect());
  }

  void _setState(FnthinkStreamLinkState next) {
    if (_state == next) return;
    _state = next;
    try {
      onLinkStateChanged(next);
    } catch (e) {
      debugPrint('[fnthink] SSE 链路状态回调失败：$e');
    }
  }

  /// 生产实现：真的开一条 HTTP 流。返回的 close 由服务在断线/停止时调用。
  static Future<FnthinkSseConnection> _httpOpen(
    Uri uri,
    Map<String, String> headers,
  ) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', uri)..headers.addAll(headers);
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        client.close();
        return FnthinkSseConnection(
          status: response.statusCode,
          body: const Stream.empty(),
        );
      }
      return FnthinkSseConnection(
        status: response.statusCode,
        body: response.stream,
        close: client.close,
      );
    } catch (e) {
      client.close();
      rethrow;
    }
  }
}

/// 一条开着的 SSE 连接：状态码 + 字节流 + 关闭钩子。
class FnthinkSseConnection {
  const FnthinkSseConnection({
    required this.status,
    required this.body,
    this.close,
  });

  final int status;
  final Stream<List<int>> body;

  /// 关闭底层 client（关掉流）。null = 测试注入的连接不需要清理。
  final void Function()? close;
}

/// 开一条 SSE 连接。允许注入是为了让用例演"连不上 / 连上 / 断线"三档，
/// 而不必在单测里起一个真 HTTP 服务。
typedef FnthinkSseOpen = Future<FnthinkSseConnection> Function(
  Uri uri,
  Map<String, String> headers,
);

/// 一个 SSE 事件块是不是唤醒。只认 `event: wake` —— 心跳是 `: ping` 注释，
/// `data:` 不参与判定（服务端今天发空对象，将来发别的也不该影响门铃语义）。
bool isWakeEventBlock(String block) {
  for (final line in block.split('\n')) {
    if (line.trim() == 'event: wake') return true;
  }
  return false;
}

/// T197 片1：SSE 的读超时判据。服务端每 `heartbeatSeconds` 发一次心跳，
/// 超过 **2.5 倍**仍没有任何字节 ⇒ 这条流已经静默死了。
///
/// 不算死：从没收到过字节（`lastByteAtMs <= 0`）或契约没给心跳（<= 0）——
/// 那是"还没开始"或"契约坏了"，不是"静默断了"；前者由连接建立那一步处理。
bool isStreamStale({
  required int lastByteAtMs,
  required int nowMs,
  required int heartbeatSeconds,
}) {
  if (lastByteAtMs <= 0 || heartbeatSeconds <= 0) return false;
  return nowMs - lastByteAtMs > heartbeatSeconds * 2500;
}
