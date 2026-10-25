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
class FnthinkStreamService {
  FnthinkStreamService({
    required this.contract,
    required this.baseUri,
    required this.requestTicket,
    required this.onWake,
    required this.onHealthyChanged,
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
  final void Function(bool healthy) onHealthyChanged;
  final FnthinkSseOpen _open;
  final int Function() _nowMs;
  final List<Duration> _backoff;

  bool _running = false;
  bool _healthy = false;
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

  bool get isHealthy => _healthy;

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
    _setHealthy(false);
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
        _setHealthy(false);
        _scheduleRetry();
        return;
      }
      _closeConnection = connection.close;
      _setHealthy(true);
      _attempt = 0;
      _buffer.clear();
      // T196：连接建立/每一块字节都留一枚时刻，原生自检据此回答"门铃最后一次有动静是什么时候"。
      // T197 片1：同一枚时刻也是看门狗的起点 —— 只有字节能证明这条流还活着。
      _lastByteAtMs = _nowMs();
      _generation++;
      _startWatchdog(_generation);
      unawaited(markFnthinkStreamByte(atMs: _nowMs()));
      _sub = connection.body
          .transform(utf8.decoder)
          .listen(
            _consume,
            onDone: _onGone,
            onError: (Object e) {
              debugPrint('[fnthink] SSE 流断了：$e');
              _onGone();
            },
            cancelOnError: true,
          );
    } catch (e) {
      debugPrint('[fnthink] SSE 连接没建成（退回长轮询）：$e');
      _setHealthy(false);
      _scheduleRetry();
    }
  }

  /// 一块一块地解 SSE：事件之间用空行分隔，`:` 开头的是心跳注释（忽略）。
  void _consume(String chunk) {
    _lastByteAtMs = _nowMs();
    unawaited(markFnthinkStreamByte(atMs: _nowMs()));
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

  void _onGone() {
    if (!_running) return;
    _setHealthy(false);
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
    if (!_running || !_healthy) return;
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
    _setHealthy(false);
    _cleanupConnection();
    _scheduleRetry();
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

  void _setHealthy(bool value) {
    if (_healthy == value) return;
    _healthy = value;
    try {
      onHealthyChanged(value);
    } catch (e) {
      debugPrint('[fnthink] SSE 健康状态回调失败：$e');
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
