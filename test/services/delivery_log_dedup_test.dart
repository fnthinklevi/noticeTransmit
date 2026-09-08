import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/database/database_helper.dart';

/// webhook_delivery_log 送达日志去重单测（P8）。
///
/// 同一送达结果存在双消费路径（实时广播 + drainPendingDeliveries 补偿拉取），
/// 旧实现会把相同终态写入两条日志，表现为详情弹窗「送达记录」重复显示、
/// 黑名单拦截重复出现多条命中消息。修复分两层：
/// 1. insertDeliveryLog 写入幂等（按 notification_id+tag+status+http_code+message
///    去重，SQL IS 空值感知比较）——加密 DB 在纯 Dart 测试环境无平台通道，
///    无法集成测试，SQL 语义靠真机回归验证；
/// 2. getDeliveryLogsByNotification 展示层折叠（dedupeDeliveryLogs 纯函数，
///    此处覆盖测试），同时兼容清理存量重复数据。
void main() {
  group('dedupeDeliveryLogs 展示层折叠（P8）', () {
    test('重复终态行折叠为一条，保留最新（列表首条）', () {
      final rows = [
        {
          'tag': 'webhook:钉钉',
          'status': 'success',
          'http_code': 200,
          'message': 'ok',
          'timestamp': 2000,
        },
        {
          'tag': 'webhook:钉钉',
          'status': 'success',
          'http_code': 200,
          'message': 'ok',
          'timestamp': 1000,
        },
      ];
      final result = DatabaseHelper.dedupeDeliveryLogs(rows);
      expect(result.length, 1);
      expect(result.first['timestamp'], 2000);
    });

    test('不同终态各自保留（失败后重试成功不折叠）', () {
      final rows = [
        {
          'tag': 'webhook:飞书',
          'status': 'success',
          'http_code': 200,
          'message': 'ok',
          'timestamp': 2000,
        },
        {
          'tag': 'webhook:飞书',
          'status': 'failed',
          'http_code': 502,
          'message': 'Bad Gateway',
          'timestamp': 1000,
        },
      ];
      final result = DatabaseHelper.dedupeDeliveryLogs(rows);
      expect(result.length, 2);
      expect(
        result.map((r) => r['status']),
        containsAll(['failed', 'success']),
      );
    });

    test('黑名单拦截重复命中折叠为一条（FILTER 伪通道）', () {
      final rows = List.generate(
        3,
        (i) => {
          'tag': '过滤拦截',
          'status': 'failed',
          'http_code': 0,
          'message': '黑名单（命中: 关键词）',
          'timestamp': 3000 - i,
        },
      );
      final result = DatabaseHelper.dedupeDeliveryLogs(rows);
      expect(result.length, 1);
      expect(result.first['message'], '黑名单（命中: 关键词）');
    });

    test('http_code/message 为 NULL 的重复终态同样折叠', () {
      final rows = [
        {
          'tag': 'webhook:通用',
          'status': 'failed',
          'http_code': null,
          'message': null,
          'timestamp': 2000,
        },
        {
          'tag': 'webhook:通用',
          'status': 'failed',
          'http_code': null,
          'message': null,
          'timestamp': 1000,
        },
      ];
      final result = DatabaseHelper.dedupeDeliveryLogs(rows);
      expect(result.length, 1);
      expect(result.first['timestamp'], 2000);
    });

    test('不同通道的相同状态互不折叠', () {
      final rows = [
        {
          'tag': 'webhook:钉钉',
          'status': 'success',
          'http_code': 200,
          'message': 'ok',
          'timestamp': 2000,
        },
        {
          'tag': 'webhook:飞书',
          'status': 'success',
          'http_code': 200,
          'message': 'ok',
          'timestamp': 1000,
        },
      ];
      final result = DatabaseHelper.dedupeDeliveryLogs(rows);
      expect(result.length, 2);
    });

    test('空列表返回空列表', () {
      expect(DatabaseHelper.dedupeDeliveryLogs([]), isEmpty);
    });
  });
}
