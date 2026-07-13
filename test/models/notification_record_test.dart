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
  });
}
