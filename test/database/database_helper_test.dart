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

    test('自建应用通道 API 签名存在（app_channels 表）', () {
      // 应用通道体系的 DB 契约（详见 test/database/app_channel_schema_test.dart
      // 的 schema 守卫：列名三方一致 + 双处建表 SQL 不漂移）
      expect(helper.getAppChannels, isA<Function>());
      expect(helper.saveAppChannels, isA<Function>());
    });
  });
}
