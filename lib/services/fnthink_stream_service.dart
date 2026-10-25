import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:http/http.dart' as http;

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
  }) : _open = open ?? _httpOpen,
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

  final FnthinkContract contract;
  final Uri baseUri;
  final Future<FnthinkStreamTicket?> Function() requestTicket;
  final void Function() onWake;
  final void Function(bool healthy) onHealthyChanged;
  final FnthinkSseOpen _open;
  final List<Duration> _backoff;

  bool _running = false;
  bool _healthy = false;
  int _attempt = 0;
  StreamSubscription<String>? _sub;
  void Function()? _closeConnection;
  Timer? _retryTimer;
  final StringBuffer _buffer = StringBuffer();

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
    final ticket = await requestTicket();
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

  void _cleanupConnection() {
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
