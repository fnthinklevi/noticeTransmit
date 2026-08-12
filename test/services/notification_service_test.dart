import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/notification_service.dart';

/// NotificationService 送达回传逻辑单元测试。
///
/// 模拟 Kotlin 端短信/电话链路通过 onDeliveryResult 回传的送达结果，
/// 验证首页推送记录逐条送达状态（pending → success/failed）正确生效：
/// - 短信链路：SmsReceiver.onResult → DeliveryNotifier.notify → onDeliveryResult
/// - 电话链路：PhoneCallReceiver.onResult → DeliveryNotifier.notify → onDeliveryResult
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationService – 短信/电话送达回传', () {
    late NotificationService service;

    setUp(() {
      service = NotificationService();
    });

    Map<String, dynamic> smsRecord({String id = 'sms_1700000000000_12345'}) {
      return {
        'id': id,
        'type': 'sms',
        'title': '验证码',
        'content': '您的验证码是 123456',
        'packageName': 'com.android.mms',
        'appName': '短信',
        'postTime': 1700000000000,
        'time': '2024-01-01 12:00:00',
      };
    }

    Map<String, dynamic> callRecord({
      String id = 'call_call_incoming_1700000000000_999',
    }) {
      return {
        'id': id,
        'type': 'call_incoming',
        'title': '来电',
        'content': '未知来电',
        'packageName': 'com.android.dialer',
        'appName': '电话',
        'postTime': 1700000000000,
        'time': '2024-01-01 12:00:00',
      };
    }

    test('短信送达成功：SUCCESS 回传 → 企业微信通道状态更新为 success', () async {
      service.addRecord(smsRecord());

      await service.updateDelivery(
        'sms_1700000000000_12345',
        'WECHAT_WORK',
        'SUCCESS',
        'ok',
      );

      final delivery = service.records.first.deliveryStatus['webhook:企业微信'];
      expect(delivery, isNotNull);
      expect(delivery['status'], 'success');
      expect(delivery['message'], 'ok');
    });

    test('短信送达失败：HTTP_FAIL 回传 → 钉钉通道状态更新为 failed', () async {
      service.addRecord(smsRecord());

      await service.updateDelivery(
        'sms_1700000000000_12345',
        'DINGTALK',
        'HTTP_FAIL',
        'HTTP 502',
      );

      final delivery = service.records.first.deliveryStatus['webhook:钉钉'];
      expect(delivery, isNotNull);
      expect(delivery['status'], 'failed');
      expect(delivery['message'], 'HTTP 502');
    });

    test('电话送达失败：RATE_LIMITED 回传 → 飞书通道状态更新为 failed', () async {
      service.addRecord(callRecord());

      await service.updateDelivery(
        'call_call_incoming_1700000000000_999',
        'FEISHU',
        'RATE_LIMITED',
        '请求过于频繁，已被限流',
      );

      final delivery = service.records.first.deliveryStatus['webhook:飞书'];
      expect(delivery, isNotNull);
      expect(delivery['status'], 'failed');
      expect(delivery['message'], '请求过于频繁，已被限流');
    });

    test('标签映射正确：WECHAT_WORK 回传更新的是企业微信而非通用 Webhook', () async {
      service.addRecord(smsRecord());

      await service.updateDelivery(
        'sms_1700000000000_12345',
        'WECHAT_WORK',
        'SUCCESS',
        '',
      );

      final status = service.records.first.deliveryStatus;
      expect(status.keys, contains('webhook:企业微信'));
      expect(status.keys, isNot(contains('webhook:Webhook')));
    });

    test('未知 id 回传：不抛异常且记录送达状态无变化', () async {
      service.addRecord(smsRecord());

      await service.updateDelivery(
        'sms_unknown_id',
        'WECHAT_WORK',
        'SUCCESS',
        'ok',
      );

      expect(service.records.first.deliveryStatus, isEmpty);
    });

    test('空 id 回传：直接忽略', () async {
      service.addRecord(smsRecord());

      await service.updateDelivery('', 'WECHAT_WORK', 'SUCCESS', 'ok');

      expect(service.records.first.deliveryStatus, isEmpty);
    });

    test('多条记录按 id 精确定位更新', () async {
      service.addRecord(smsRecord());
      service.addRecord(callRecord());

      await service.updateDelivery(
        'call_call_incoming_1700000000000_999',
        'DINGTALK',
        'SUCCESS',
        'ok',
      );

      final callStatus = service.records.first.deliveryStatus['webhook:钉钉'];
      expect(callStatus['status'], 'success');
      // 短信记录不受影响
      final smsStatus = service.records[1].deliveryStatus['webhook:钉钉'];
      expect(smsStatus, isNull);
    });
  });
}
