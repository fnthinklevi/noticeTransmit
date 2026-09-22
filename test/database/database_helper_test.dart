import 'dart:io';

import '../support/source_guards.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_setup.dart';

/// DatabaseHelper 迁移与版本戳测试（sqflite_common_ffi，不出平台通道）。
///
/// 为什么这些用例必须存在：`_initDatabase` 打开失败时的兜底是**把库改名成
/// `.corrupt-<ts>` 再重建空库**，于是任何一次 onUpgrade 抛错都等于「用户历史 +
/// 库内通道配置静默清空」，而且下次启动看不出来。
///
/// 历史缺陷：迁移旧明文库时用 `version: 3` 打开新建的加密库，而 `onCreate` 传的
/// 是当前的全量 schema —— 库被贴上 3 号，随后以 dbVersion 打开即触发
/// `onUpgrade(3→10)`，对已存在的列重复 ALTER 抛 `duplicate column name:
/// message_format`（已实测复现）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initTestDatabase);

  final helper = DatabaseHelper();
  late Directory tmp;
  late String path;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nt-db-migration');
    path = join(tmp.path, 'encrypted.db');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<Database> openAt(
    int version, {
    Future<void> Function(Database db, int version)? onCreate,
    Future<void> Function(Database db, int oldV, int newV)? onUpgrade,
  }) => databaseFactory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: version,
      onCreate: onCreate,
      onUpgrade: onUpgrade,
    ),
  );

  Future<Set<String>> columnsOf(Database db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.map((r) => r['name'].toString()).toSet();
  }

  Future<Set<String>> tablesOf(Database db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    );
    return rows.map((r) => r['name'].toString()).toSet();
  }

  group('版本戳一致性', () {
    test('dbVersion 与建表 SQL 的最新增量（v10 app_channels）一致', () async {
      final db = await openAt(
        DatabaseHelper.dbVersion,
        onCreate: (d, v) => helper.createSchemaForTest(d),
      );
      expect(await tablesOf(db), contains('app_channels'));
      await db.close();
    });

    test('迁移期按 dbVersion 建库后，再以 dbVersion 打开不触发 onUpgrade', () async {
      // 这正是修复本身：错号（version: 3）会让第二次打开跑一遍全量迁移
      final created = await openAt(
        DatabaseHelper.dbVersion,
        onCreate: (d, v) => helper.createSchemaForTest(d),
      );
      await created.close();

      var upgradeRan = false;
      final reopened = await openAt(
        DatabaseHelper.dbVersion,
        onUpgrade: (d, o, n) async => upgradeRan = true,
      );
      expect(
        upgradeRan,
        isFalse,
        reason: '库被贴了低于 dbVersion 的版本号 —— 迁移期建库必须用 dbVersion',
      );
      await reopened.close();
    });

    test('加密库的每个 openDatabase 调用都使用 dbVersion（不得出现字面量版本）', () {
      final source = stripComments(
        File('lib/database/database_helper.dart').readAsStringSync(),
      );
      // 带 password: 的打开点即「加密库」，逐个断言其 version 取 dbVersion
      final opens = RegExp(
        r'openDatabase\(([^;]*?)\);',
        dotAll: true,
      ).allMatches(source);
      final encrypted = opens
          .where((m) => m.group(1)!.contains('password: password'))
          .toList();
      expect(encrypted, isNotEmpty, reason: '未匹配到加密库打开点，本用例已失效');
      final bad = encrypted
          .where((m) => !m.group(1)!.contains('version: dbVersion'))
          .length;
      expect(bad, 0, reason: '$bad 处加密库打开用了硬编码版本号，会让库被贴错版本戳');
    });
  });

  group('存量错号库的兜底（幂等 ALTER）', () {
    test('被贴上旧版本号的全量 schema 库，升到 dbVersion 不再抛 duplicate column', () async {
      // 复现缺陷前提：schema 是最新的，版本号却是 3
      final stamped = await openAt(
        3,
        onCreate: (d, v) => helper.createSchemaForTest(d),
      );
      expect(await stamped.rawQuery('PRAGMA user_version'), <Map<String, int>>[
        {'user_version': 3},
      ]);
      await stamped.close();

      final upgraded = await openAt(
        DatabaseHelper.dbVersion,
        onUpgrade: (d, o, n) => helper.upgradeSchemaForTest(d, o, n),
      );
      expect(
        await columnsOf(upgraded, 'webhook_channels'),
        containsAll(['message_format', 'message_template', 'extra_config']),
      );
      expect(
        await columnsOf(upgraded, 'notifications'),
        containsAll(['sub_text', 'delivery_info', 'priority']),
      );
      await upgraded.close();
    });

    test('同一升级链连跑两次必须无副作用（幂等）', () async {
      final db = await openAt(
        3,
        onCreate: (d, v) => helper.createSchemaForTest(d),
      );
      await helper.upgradeSchemaForTest(db, 3, DatabaseHelper.dbVersion);
      await helper.upgradeSchemaForTest(db, 3, DatabaseHelper.dbVersion);
      expect(
        await tablesOf(db),
        containsAll(['app_channels', 'email_channels']),
      );
      await db.close();
    });

    test('v1 老库走完整链到 dbVersion，列与表齐全', () async {
      final v1 = await openAt(
        1,
        onCreate: (d, v) async {
          await d.execute('''
          CREATE TABLE notifications (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            content TEXT NOT NULL,
            package_name TEXT NOT NULL,
            app_name TEXT NOT NULL,
            post_time INTEGER NOT NULL,
            time TEXT NOT NULL,
            type TEXT NOT NULL,
            device_name TEXT,
            timestamp INTEGER NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
        },
      );
      // 老数据必须在新列下存活（NOT NULL DEFAULT 兜底）
      await v1.insert('notifications', {
        'id': 'n-1',
        'title': 't',
        'content': 'c',
        'package_name': 'com.x',
        'app_name': 'X',
        'post_time': 1,
        'time': '00:00',
        'type': 'notification',
        'timestamp': 1,
        'created_at': 1,
      });
      await v1.close();

      final db = await openAt(
        DatabaseHelper.dbVersion,
        onUpgrade: (d, o, n) => helper.upgradeSchemaForTest(d, o, n),
      );
      expect(
        await columnsOf(db, 'notifications'),
        containsAll(['sub_text', 'delivery_info', 'priority']),
      );
      expect(
        await tablesOf(db),
        containsAll([
          'pending_notifications',
          'email_channels',
          'webhook_channels',
          'webhook_delivery_log',
          'app_channels',
        ]),
      );
      final kept = await db.query('notifications');
      expect(kept, hasLength(1));
      expect(kept.single['priority'], 1, reason: '旧行应取 v8 的默认中优先级');
      await db.close();
    });
  });
}
