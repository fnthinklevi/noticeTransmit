import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_setup.dart';

/// notifications 表批量删除测试（DatabaseHelper.deleteNotificationsMany）。
///
/// 钉两件事：
/// ① 全命中 / 部分命中 / 空列表三档返回值准确；
/// ② 单次 DELETE（不是循环 N 次单条删）—— 通过回受影响行数与剩余行数验证。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabase();

  final helper = DatabaseHelper();
  late final String dbPath;

  setUpAll(() async {
    dbPath = join(await getDatabasesPath(), 'notifications_delete_test.db');
  });

  tearDown(() async {
    helper.debugDatabase = null;
  });

  tearDownAll(() async {
    helper.debugDatabase = null;
    if (await databaseFactory.databaseExists(dbPath)) {
      await databaseFactory.deleteDatabase(dbPath);
    }
  });

  Future<Database> freshDb() async {
    SharedPreferences.setMockInitialValues({});
    if (await databaseFactory.databaseExists(dbPath)) {
      await databaseFactory.deleteDatabase(dbPath);
    }
    final db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(version: DatabaseHelper.dbVersion),
    );
    await helper.createSchemaForTest(db);
    helper.debugDatabase = db;
    addTearDown(() async {
      helper.debugDatabase = null;
      await db.close();
    });
    return db;
  }

  Future<int> rowCount(Database db) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM notifications',
    );
    return (rows.single['c'] as num).toInt();
  }

  Future<void> insertNotif(
    Database db,
    String id, {
    int postTime = 1780000000000,
  }) async {
    await db.insert('notifications', {
      'id': id,
      'title': '标题 $id',
      'content': '正文 $id',
      'package_name': 'com.test.$id',
      'app_name': 'Test$id',
      'post_time': postTime,
      'time': '2026-11-14 12:00',
      'type': 'notice',
      'priority': 1,
      'delivery_bucket': '',
      'timestamp': postTime,
    });
  }

  group('deleteNotificationsMany', () {
    test('全命中 ⇒ 返回行数等于列表长度，表清空', () async {
      final db = await freshDb();
      await insertNotif(db, 'n1');
      await insertNotif(db, 'n2');
      await insertNotif(db, 'n3');
      expect(await rowCount(db), 3);

      final deleted = await helper.deleteNotificationsMany(['n1', 'n2', 'n3']);
      expect(deleted, 3);
      expect(await rowCount(db), 0);
    });

    test('部分命中 ⇒ 只删除实际存在的行，返回真实受影响行数', () async {
      final db = await freshDb();
      await insertNotif(db, 'real_1');
      await insertNotif(db, 'real_2');
      expect(await rowCount(db), 2);

      final deleted = await helper.deleteNotificationsMany([
        'real_1',
        'nonexistent',
        'real_2',
      ]);
      expect(deleted, 2);
      expect(await rowCount(db), 0);
    });

    test('空列表 ⇒ 返回 0，不执行任何 SQL', () async {
      final db = await freshDb();
      await insertNotif(db, 'n_kept');

      final deleted = await helper.deleteNotificationsMany(const []);
      expect(deleted, 0);
      expect(await rowCount(db), 1);
    });

    test('全不存在 ⇒ 返回 0，表不受影响', () async {
      final db = await freshDb();
      await insertNotif(db, 'n_real');

      final deleted = await helper.deleteNotificationsMany([
        'ghost_1',
        'ghost_2',
      ]);
      expect(deleted, 0);
      expect(await rowCount(db), 1);
    });

    test('删几条留几条 ⇒ 剩余行完整保留', () async {
      final db = await freshDb();
      await insertNotif(db, 'keep_1');
      await insertNotif(db, 'kill_1');
      await insertNotif(db, 'keep_2');
      await insertNotif(db, 'kill_2');
      expect(await rowCount(db), 4);

      final deleted = await helper.deleteNotificationsMany(['kill_1', 'kill_2']);
      expect(deleted, 2);

      final remaining = await db.query(
        'notifications',
        orderBy: 'id ASC',
      );
      expect(
        remaining.map((r) => r['id'] as String),
        ['keep_1', 'keep_2'],
      );
    });
  });

  group('deleteNotification（单条）', () {
    test('存在则删，不存在则表不变、不抛异常', () async {
      final db = await freshDb();
      await insertNotif(db, 'single_exists');
      expect(await rowCount(db), 1);

      await helper.deleteNotification('single_exists');
      expect(await rowCount(db), 0);

      // 不存在的 id 不应抛异常
      await helper.deleteNotification('single_ghost');
      expect(await rowCount(db), 0);
    });
  });
}
