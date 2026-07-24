import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/database/database_helper.dart';

/// DatabaseHelper 单元测试。
/// 验证单例模式、API 签名及核心数据结构。

void main() {
  group('DatabaseHelper – singleton', () {
    test('instance returns same object', () {
      final db1 = DatabaseHelper();
      final db2 = DatabaseHelper();
      expect(identical(db1, db2), true);
    });
  });

  group('DatabaseHelper – public API smoke', () {
    late DatabaseHelper helper;

    setUp(() {
      helper = DatabaseHelper();
    });

    test('CRUD method signatures exist', () {
      expect(helper.insertNotification, isA<Function>());
      expect(helper.getNotifications, isA<Function>());
      expect(helper.getNotificationCount, isA<Function>());
      expect(helper.deleteNotification, isA<Function>());
      expect(helper.deleteOldNotifications, isA<Function>());
      expect(helper.clearAllNotifications, isA<Function>());
      expect(helper.getNotificationStats, isA<Function>());
      expect(helper.getDailyStats, isA<Function>());
      expect(helper.insertPendingNotification, isA<Function>());
      expect(helper.getPendingNotifications, isA<Function>());
      expect(helper.deletePendingNotification, isA<Function>());
      expect(helper.updatePendingNotification, isA<Function>());
      expect(helper.clearAllPendingNotifications, isA<Function>());
      expect(helper.migrateFromSharedPreferences, isA<Function>());
    });
  });
}
