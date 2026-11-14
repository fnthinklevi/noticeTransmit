import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/models/fnthink_inbox_message.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_setup.dart';

/// fnthink_messages 的删除方法测试（DatabaseHelper.deleteFnthinkInbox / deleteFnthinkInboxMany）。
///
/// 钉两件事：
/// ① 单条删除命中的返回 true，未命中的（被 prune 或从未存在）返回 false，**不抛异常**；
/// ② 批量删除一次 `IN (…)` 命中多行，部分命中也回真删除行数，不会因为其中一条不存在就整批挂掉。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabase();

  final helper = DatabaseHelper();
  late final String dbPath;

  setUpAll(() async {
    dbPath = join(await getDatabasesPath(), 'fnthink_inbox_delete_test.db');
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
      'SELECT COUNT(*) AS c FROM ${FnthinkInboxMessage.table}',
    );
    return (rows.single['c'] as num).toInt();
  }

  Future<void> insertRow(
    Database db,
    String id, {
    String sender = 'endpoint:ep_1',
    String direction = kFnthinkDirectionIn,
    int receivedAt = 1780000000000,
  }) async {
    await db.insert(
      FnthinkInboxMessage.table,
      FnthinkInboxMessage(
        messageId: id,
        sender: sender,
        type: 'notice',
        item: '',
        title: '测试 $id',
        body: '正文 $id',
        receivedAt: receivedAt,
        direction: direction,
        ackResult: direction == kFnthinkDirectionOut ? '' : 'displayed',
      ).toDbRow(),
    );
  }

  group('单条删除 deleteFnthinkInbox', () {
    test('命中已存在的行 ⇒ 返回 true，表行数 -1', () async {
      final db = await freshDb();
      await insertRow(db, 'm_1');
      await insertRow(db, 'm_2');
      expect(await rowCount(db), 2);

      final ok = await helper.deleteFnthinkInbox('m_1');
      expect(ok, isTrue);
      expect(await rowCount(db), 1);

      // 剩下的那条还在
      final remaining = await db.query(
        FnthinkInboxMessage.table,
        where: 'message_id = ?',
        whereArgs: ['m_2'],
      );
      expect(remaining, hasLength(1));
    });

    test('从未存在的 id ⇒ 返回 false，表行数不变，不抛异常', () async {
      final db = await freshDb();
      await insertRow(db, 'm_real');
      expect(await rowCount(db), 1);

      final ok = await helper.deleteFnthinkInbox('m_does_not_exist');
      expect(ok, isFalse);
      expect(await rowCount(db), 1);
    });

    test('删完再删同一条 ⇒ 第二次返回 false（幂等但返回值准确）', () async {
      final db = await freshDb();
      await insertRow(db, 'm_once');
      expect(await helper.deleteFnthinkInbox('m_once'), isTrue);
      expect(await helper.deleteFnthinkInbox('m_once'), isFalse);
      expect(await rowCount(db), 0);
    });
  });

  group('批量删除 deleteFnthinkInboxMany', () {
    test('全命中 ⇒ 返回实际删除行数，表行数全部消失', () async {
      final db = await freshDb();
      await insertRow(db, 'a');
      await insertRow(db, 'b');
      await insertRow(db, 'c');
      expect(await rowCount(db), 3);

      final deleted = await helper.deleteFnthinkInboxMany(['a', 'b', 'c']);
      expect(deleted, 3);
      expect(await rowCount(db), 0);
    });

    test('部分命中 ⇒ 返回实际删除行数（不因为其中一条不存在就挂掉）', () async {
      final db = await freshDb();
      await insertRow(db, 'real_1');
      await insertRow(db, 'real_2');
      expect(await rowCount(db), 2);

      final deleted = await helper.deleteFnthinkInboxMany([
        'real_1',
        'ghost',
        'real_2',
      ]);
      expect(deleted, 2);
      expect(await rowCount(db), 0);
    });

    test('空列表 ⇒ 返回 0，不跑 SQL', () async {
      final db = await freshDb();
      await insertRow(db, 'm_1');

      final deleted = await helper.deleteFnthinkInboxMany(const []);
      expect(deleted, 0);
      expect(await rowCount(db), 1);
    });

    test('只删发出档的行（方向不同但同一张表）', () async {
      final db = await freshDb();
      await insertRow(db, 'in_1', direction: kFnthinkDirectionIn);
      await insertRow(db, 'out_1', direction: kFnthinkDirectionOut);
      expect(await rowCount(db), 2);

      final deleted = await helper.deleteFnthinkInboxMany(['out_1']);
      expect(deleted, 1);

      // 收件的那条还在
      final inboxRows = await db.query(
        FnthinkInboxMessage.table,
        where: 'message_id = ?',
        whereArgs: ['in_1'],
      );
      expect(inboxRows, hasLength(1));
    });
  });
}
