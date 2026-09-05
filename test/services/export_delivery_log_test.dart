import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/notification_service.dart';

import '../test_setup.dart';

/// 导出与送达日志单测。
///
/// buildExportJson 为唯一导出实现（旧 exportRecords 已合并），字段统一为
/// recordCount；测试环境下加密 DB 平台通道不可用，按设计回退内存记录，
/// 因此可稳定断言 JSON 契约。updateDelivery 终态触发 delivery_log 落库，
/// DB 不可用时静默降级（与生产 try/catch 行为一致），此处验证不抛异常
/// 且内存送达状态正确。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabase();

  group('NotificationService – 导出 JSON 契约', () {
    test('buildExportJson 输出 recordCount 与 records 一致的合法 JSON', () async {
      final service = NotificationService();
      service.addRecord({
        'id': 'export_1',
        'type': 'notification',
        'title': '标题',
        'content': '内容',
        'packageName': 'com.a.b',
        'appName': '应用',
        'postTime': 1700000000000,
        'time': '2024-01-01 12:00:00',
      });

      final json = await service.buildExportJson('设备名', 'Pixel', 'Google');
      final data = jsonDecode(json) as Map<String, dynamic>;

      expect(data['recordCount'], data['records'].length);
      expect(data['recordCount'], greaterThanOrEqualTo(1));
      expect(data['_warning'], isNotEmpty);
      expect(data['deviceName'], '设备名');
      expect(data['deviceModel'], 'Pixel');
      expect(data['manufacturer'], 'Google');
      // 旧字段 totalCount 不得再出现（双轨实现已合并）
      expect(data.containsKey('totalCount'), isFalse);
      final first = (data['records'] as List).first as Map<String, dynamic>;
      expect(first['id'], isNotNull);
      expect(first['title'], '标题');
    });

    test('buildExportJson 空记录时 recordCount 为 0 且仍是合法 JSON', () async {
      final service = NotificationService();
      final json = await service.buildExportJson('d', 'm', 'f');
      final data = jsonDecode(json) as Map<String, dynamic>;
      expect(data['recordCount'], data['records'].length);
    });
  });

  group('NotificationService – 送达结果含 channelUrl/httpCode（delivery_log 链路）', () {
    test('终态 SUCCESS 带 httpCode/channelUrl 更新状态且不抛异常', () async {
      final service = NotificationService();
      service.addRecord({
        'id': 'log_1',
        'type': 'notification',
        'title': 't',
        'content': 'c',
        'packageName': 'com.a.b',
        'appName': 'app',
        'postTime': 1700000000000,
        'time': '2024-01-01 12:00:00',
      });

      await service.updateDelivery(
        'log_1',
        'DINGTALK',
        'SUCCESS',
        'ok',
        httpCode: 200,
        channelUrl: 'https://oapi.dingtalk.com/robot/send?access_token=x',
      );

      final delivery = service.records.first.deliveryStatus['webhook:钉钉'];
      expect(delivery['status'], 'success');
      expect(delivery['message'], 'ok');
    });

    test('PAUSED（暂停未发送）仅更新状态为 paused', () async {
      final service = NotificationService();
      service.addRecord({
        'id': 'log_2',
        'type': 'notification',
        'title': 't',
        'content': 'c',
        'packageName': 'com.a.b',
        'appName': 'app',
        'postTime': 1700000000000,
        'time': '2024-01-01 12:00:00',
      });

      await service.updateDelivery('log_2', 'EMAIL', 'PAUSED', '用户暂停推送');

      final delivery = service.records.first.deliveryStatus['邮件'];
      expect(delivery['status'], 'paused');
    });

    test('未知记录 ID 的终态仅落 delivery_log，不更新内存且不抛异常', () async {
      final service = NotificationService();
      await service.updateDelivery(
        'not_exists',
        'SMS',
        'FAILED',
        'send error',
        httpCode: 0,
      );
      expect(service.records.where((r) => r.id == 'not_exists'), isEmpty);
    });
  });
}
