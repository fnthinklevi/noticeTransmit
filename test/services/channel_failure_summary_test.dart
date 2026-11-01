import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/channel_failure_summary.dart';

/// T220 片2b：`deliveryFailureKindOf` 与 `summarizeChannelFailures` 的判据。
///
/// 这两枚决定通道状态页那一行「最近一次失败」说的是哪一类、连续几次。写偏了的后果
/// 都是**界面替用户编一个事实**：
///  - 429 归成"服务器错误" ⇒ 用户去改地址，而真答案只是"慢一点"；
///  - 平台业务拒绝（HTTP 200 + errcode 非 0）归成"服务器错误" ⇒ 用户去查网络；
///  - 连续次数把中间一次成功也算进去 ⇒ 恢复过的通道仍显示"连续 9 次失败"。
void main() {
  group('deliveryFailureKindOf', () {
    test('429 是限流，不是 4xx 那一档', () {
      expect(
        deliveryFailureKindOf(httpCode: 429, message: '限流 HTTP 429: too many'),
        DeliveryFailureKind.rateLimited,
      );
    });

    test('4xx / 5xx 是"服务器返回错误"', () {
      for (final code in [400, 401, 404, 500, 502, 503]) {
        expect(
          deliveryFailureKindOf(httpCode: code, message: 'HTTP $code'),
          DeliveryFailureKind.http,
          reason: 'code=$code',
        );
      }
    });

    test('HTTP 通了但平台业务拒绝（errcode 非 0）归"业务拒绝"', () {
      // 平台常常回 200 + errcode：按码归就会说成"服务器出错"，而重试根本没用（T202）。
      for (final message in [
        '业务错误: {"errcode":40001}',
        'Business error: invalid token',
      ]) {
        expect(
          deliveryFailureKindOf(httpCode: 200, message: message),
          DeliveryFailureKind.business,
          reason: message,
        );
      }
    });

    test('没有 HTTP 码、请求没到对面 ⇒ 网络', () {
      for (final message in [
        'Network error: timeout',
        'SMTP connect timeout',
        'Unknown failure after 3 attempts',
      ]) {
        expect(
          deliveryFailureKindOf(httpCode: 0, message: message),
          DeliveryFailureKind.network,
          reason: message,
        );
      }
    });

    test('本机自己停下的那一档（引擎不在 / 推送暂停）单列', () {
      for (final message in [
        'NetworkClient inactive',
        'Push paused (skipped)',
        '推送已暂停',
      ]) {
        expect(
          deliveryFailureKindOf(httpCode: 0, message: message),
          DeliveryFailureKind.interrupted,
          reason: message,
        );
      }
    });

    test('有 2xx 码、又没有业务拒绝的痕迹 ⇒ 不猜', () {
      expect(
        deliveryFailureKindOf(httpCode: 200, message: 'OK'),
        DeliveryFailureKind.unknown,
      );
    });
  });

  group('summarizeChannelFailures', () {
    Map<String, dynamic> row({
      required String tag,
      required String status,
      int timestamp = 0,
      int httpCode = 0,
      String message = '',
    }) => {
      'tag': tag,
      'status': status,
      'http_code': httpCode,
      'message': message,
      'timestamp': timestamp,
    };

    test('最近一次失败取最新那条，连续次数只数挨着的失败', () {
      final rows = [
        row(tag: 'chan:a', status: 'failed', timestamp: 500, httpCode: 502),
        row(tag: 'chan:a', status: 'failed', timestamp: 400, httpCode: 502),
        row(tag: 'chan:a', status: 'failed', timestamp: 300, httpCode: 0),
        row(tag: 'chan:a', status: 'success', timestamp: 200),
      ];
      final out = summarizeChannelFailures(rows);
      final a = out['chan:a']!;
      expect(a.lastFailedAt, 500);
      expect(a.httpCode, 502);
      expect(a.kind, DeliveryFailureKind.http);
      expect(a.consecutiveFailures, 3);
    });

    test('失败之后又成功了：那一次失败仍然读得出来（取证不是判决）', () {
      final rows = [
        row(tag: 'chan:a', status: 'success', timestamp: 600),
        row(tag: 'chan:a', status: 'failed', timestamp: 500, httpCode: 429),
      ];
      final out = summarizeChannelFailures(rows);
      expect(out['chan:a']!.lastFailedAt, 500);
      expect(out['chan:a']!.kind, DeliveryFailureKind.rateLimited);
      expect(out['chan:a']!.consecutiveFailures, 1);
    });

    test('中间夹了一条 queued ⇒ 连续链断开，不把两段算成一段', () {
      final rows = [
        row(tag: 'chan:a', status: 'failed', timestamp: 400),
        row(tag: 'chan:a', status: 'queued', timestamp: 300),
        row(tag: 'chan:a', status: 'failed', timestamp: 200),
      ];
      final out = summarizeChannelFailures(rows);
      expect(out['chan:a']!.consecutiveFailures, 1);
    });

    test('窗口内没有失败的通道不出现（"从未失败"不许画占位）', () {
      final out = summarizeChannelFailures([
        row(tag: 'chan:a', status: 'success', timestamp: 500),
        row(tag: 'chan:b', status: 'queued', timestamp: 400),
      ]);
      expect(out, isEmpty);
    });

    test('每个 tag 各自算，不串到邻通道', () {
      final out = summarizeChannelFailures([
        row(tag: 'chan:a', status: 'failed', timestamp: 500),
        row(tag: 'chan:b', status: 'failed', timestamp: 400),
        row(tag: 'chan:a', status: 'success', timestamp: 300),
      ]);
      expect(out['chan:a']!.lastFailedAt, 500);
      expect(out['chan:b']!.lastFailedAt, 400);
    });
  });
}
