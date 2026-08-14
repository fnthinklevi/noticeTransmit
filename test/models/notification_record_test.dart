import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/models/notification_record.dart';

void main() {
  group('NotificationRecord', () {
    const testId = 'test-id-123';
    const testTitle = 'Test Notification';
    const testContent = 'This is a test notification content';
    const testPackageName = 'com.example.app';
    const testAppName = 'Example App';
    const testType = 'normal';
    const testPostTime = 1234567890;
    const testTime = '2024-01-01 12:00:00';
    const testDeviceName = 'My Device';

    test('fromMap creates valid instance', () {
      final map = {
        'id': testId,
        'title': testTitle,
        'content': testContent,
        'subText': '',
        'packageName': testPackageName,
        'appName': testAppName,
        'type': testType,
        'postTime': testPostTime,
        'time': testTime,
        'deviceName': testDeviceName,
      };

      final record = NotificationRecord.fromMap(map);

      expect(record.id, testId);
      expect(record.title, testTitle);
      expect(record.content, testContent);
      expect(record.packageName, testPackageName);
      expect(record.appName, testAppName);
      expect(record.type, testType);
      expect(record.postTime, testPostTime);
      expect(record.time, testTime);
      expect(record.deviceName, testDeviceName);
    });

    test('fromMap handles missing values with defaults', () {
      final map = <String, dynamic>{};

      final record = NotificationRecord.fromMap(map);

      expect(record.id, '');
      expect(record.title, '');
      expect(record.content, '');
      expect(record.subText, '');
      expect(record.packageName, '');
      expect(record.appName, '');
      expect(record.type, 'normal');
      expect(record.postTime, 0);
      expect(record.time, '');
      expect(record.deviceName, '');
    });

    test('toMap serializes correctly', () {
      final record = NotificationRecord(
        id: testId,
        title: testTitle,
        content: testContent,
        subText: '',
        packageName: testPackageName,
        appName: testAppName,
        type: testType,
        postTime: testPostTime,
        time: testTime,
        deviceName: testDeviceName,
      );

      final map = record.toMap();

      expect(map['id'], testId);
      expect(map['title'], testTitle);
      expect(map['content'], testContent);
      expect(map['packageName'], testPackageName);
      expect(map['appName'], testAppName);
      expect(map['type'], testType);
      expect(map['postTime'], testPostTime);
      expect(map['time'], testTime);
      expect(map['deviceName'], testDeviceName);
    });

    test('copyWith creates modified copy', () {
      final original = NotificationRecord(
        id: testId,
        title: testTitle,
        content: testContent,
        subText: '',
        packageName: testPackageName,
        appName: testAppName,
        type: testType,
        postTime: testPostTime,
        time: testTime,
        deviceName: testDeviceName,
      );

      final updated = original.copyWith(
        title: 'Updated Title',
        content: 'Updated Content',
      );

      expect(updated.id, testId);
      expect(updated.title, 'Updated Title');
      expect(updated.content, 'Updated Content');
      expect(updated.packageName, testPackageName);
    });

    test('equality based on id', () {
      final record1 = NotificationRecord(
        id: testId,
        title: testTitle,
        content: testContent,
        subText: '',
        packageName: testPackageName,
        appName: testAppName,
        type: testType,
        postTime: testPostTime,
        time: testTime,
        deviceName: testDeviceName,
      );

      final record2 = NotificationRecord(
        id: testId,
        title: 'Different Title',
        content: 'Different Content',
        subText: '',
        packageName: 'different.package',
        appName: 'Different App',
        type: 'different',
        postTime: 999999999,
        time: '2024-01-02 00:00:00',
        deviceName: 'Other Device',
      );

      final record3 = NotificationRecord(
        id: 'different-id',
        title: testTitle,
        content: testContent,
        subText: '',
        packageName: testPackageName,
        appName: testAppName,
        type: testType,
        postTime: testPostTime,
        time: testTime,
        deviceName: testDeviceName,
      );

      expect(record1, equals(record2));
      expect(record1, isNot(equals(record3)));
      expect(record1.hashCode, equals(record2.hashCode));
    });

    test('round-trip serialization', () {
      final original = NotificationRecord(
        id: testId,
        title: testTitle,
        content: testContent,
        subText: 'Sub Text',
        packageName: testPackageName,
        appName: testAppName,
        type: testType,
        postTime: testPostTime,
        time: testTime,
        deviceName: testDeviceName,
      );

      final map = original.toMap();
      final deserialized = NotificationRecord.fromMap(map);

      expect(deserialized.id, original.id);
      expect(deserialized.title, original.title);
      expect(deserialized.content, original.content);
      expect(deserialized.subText, original.subText);
      expect(deserialized.packageName, original.packageName);
      expect(deserialized.appName, original.appName);
      expect(deserialized.type, original.type);
      expect(deserialized.postTime, original.postTime);
      expect(deserialized.time, original.time);
      expect(deserialized.deviceName, original.deviceName);
    });

    group('priority 优先级', () {
      test('fromMap 缺省为 1（中优先级）', () {
        final map = {
          'id': testId,
          'title': testTitle,
          'content': testContent,
          'packageName': testPackageName,
          'appName': testAppName,
          'type': testType,
          'postTime': testPostTime,
          'time': testTime,
        };

        final record = NotificationRecord.fromMap(map);

        expect(record.priority, 1);
      });

      test('fromMap 读取优先级值', () {
        final map = {
          'id': testId,
          'title': testTitle,
          'content': testContent,
          'packageName': testPackageName,
          'appName': testAppName,
          'type': testType,
          'postTime': testPostTime,
          'time': testTime,
          'priority': 2,
        };

        final record = NotificationRecord.fromMap(map);

        expect(record.priority, 2);
      });

      test('toMap 序列化 priority 字段', () {
        final record = NotificationRecord(
          id: testId,
          title: testTitle,
          content: testContent,
          subText: '',
          packageName: testPackageName,
          appName: testAppName,
          type: testType,
          postTime: testPostTime,
          time: testTime,
          deviceName: testDeviceName,
          priority: 0,
        );

        final map = record.toMap();

        expect(map['priority'], 0);
      });

      test('priority round-trip 序列化', () {
        final original = NotificationRecord(
          id: testId,
          title: testTitle,
          content: testContent,
          subText: '',
          packageName: testPackageName,
          appName: testAppName,
          type: testType,
          postTime: testPostTime,
          time: testTime,
          deviceName: testDeviceName,
          priority: 2,
        );

        final map = original.toMap();
        final restored = NotificationRecord.fromMap(map);

        expect(restored.priority, 2);
      });

      test('copyWith 可修改优先级', () {
        final original = NotificationRecord(
          id: testId,
          title: testTitle,
          content: testContent,
          subText: '',
          packageName: testPackageName,
          appName: testAppName,
          type: testType,
          postTime: testPostTime,
          time: testTime,
          deviceName: testDeviceName,
          priority: 1,
        );

        final updated = original.copyWith(priority: 0);

        expect(updated.priority, 0);
        expect(original.priority, 1);
      });
    });

    group('deliveryStatus 送达状态', () {
      test('fromMap 解析内存 Map 来源', () {
        final map = {
          'id': testId,
          'title': testTitle,
          'content': testContent,
          'packageName': testPackageName,
          'appName': testAppName,
          'type': testType,
          'postTime': testPostTime,
          'time': testTime,
          'deliveryStatus': {
            'webhook:企业微信': {'status': 'success', 'message': 'ok'},
          },
        };

        final record = NotificationRecord.fromMap(map);

        expect(record.deliveryStatus['webhook:企业微信']['status'], 'success');
      });

      test('fromMap 兼容 DB delivery_info JSON 字符串', () {
        final map = {
          'id': testId,
          'title': testTitle,
          'content': testContent,
          'packageName': testPackageName,
          'appName': testAppName,
          'type': testType,
          'postTime': testPostTime,
          'time': testTime,
          'delivery_info':
              '{"webhook:钉钉":{"status":"failed","message":"HTTP 502"}}',
        };

        final record = NotificationRecord.fromMap(map);

        expect(record.deliveryStatus['webhook:钉钉']['status'], 'failed');
        expect(record.deliveryStatus['webhook:钉钉']['message'], 'HTTP 502');
      });

      test('deliveryStatus round-trip 序列化', () {
        final original = NotificationRecord(
          id: testId,
          title: testTitle,
          content: testContent,
          subText: '',
          packageName: testPackageName,
          appName: testAppName,
          type: testType,
          postTime: testPostTime,
          time: testTime,
          deviceName: testDeviceName,
          channels: const ['webhook:企业微信'],
          deliveryStatus: {
            'webhook:企业微信': {'status': 'success', 'message': 'ok'},
          },
        );

        final map = original.toMap();
        final restored = NotificationRecord.fromMap(map);

        expect(restored.deliveryStatus['webhook:企业微信']['status'], 'success');
        expect(restored.deliveryStatus['webhook:企业微信']['message'], 'ok');
        expect(restored.channels, ['webhook:企业微信']);
      });

      test('缺失/非法 deliveryStatus 回退为空 Map', () {
        final empty = NotificationRecord.fromMap({
          'id': testId,
          'title': testTitle,
          'content': testContent,
          'packageName': testPackageName,
          'appName': testAppName,
          'type': testType,
          'postTime': testPostTime,
          'time': testTime,
        });
        expect(empty.deliveryStatus, isEmpty);

        final badJson = NotificationRecord.fromMap({
          'id': testId,
          'title': testTitle,
          'content': testContent,
          'packageName': testPackageName,
          'appName': testAppName,
          'type': testType,
          'postTime': testPostTime,
          'time': testTime,
          'delivery_info': 'not-valid-json',
        });
        expect(badJson.deliveryStatus, isEmpty);
      });
    });
  });
}
