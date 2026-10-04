import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/models/fnthink_remote_execution_record.dart';
import 'package:notice_transmit/services/fnthink_remote_execution.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/source_guards.dart';
import '../test_setup.dart';

/// 远程执行 片3b：远程执行历史表 `fnthink_remote_executions`
/// （建表两处入口、方向两档、状态迁移覆盖写、还没到终态那一读口、删除返回值）。
///
/// 两条必须跑真 SQL 的假绿：
///  ① `saveRemoteExecutionRecord` 覆盖的是**整行** —— 用"查不到就 insert"的写法时，
///     状态从 `executing` 迁到 `done` 会变成**两行并存**（一执行中一已完成），
///     而撤销那一格读的就是"还没到终态的那几条"，于是它会说"这条还在执行中"。
///  ② `removeRemoteExecutionRecord` 的返回值：删不存在的一行回 false 与回 true 在界面上
///     是两件事 —— 回 true 的话用户以为这一条已经删掉了。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabase();

  final helper = DatabaseHelper();
  late final String dbPath;

  setUpAll(() async {
    dbPath = join(await getDatabasesPath(), 'fnthink_remote_exec_test.db');
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

  Future<Set<String>> columnsOf(Database db) async {
    final rows = await db.rawQuery(
      'PRAGMA table_info(${FnthinkRemoteExecutionRecord.table})',
    );
    return rows.map((r) => r['name'].toString()).toSet();
  }

  FnthinkRemoteExecutionRecord record(
    String id, {
    String direction = kFnthinkRemoteDirectionIn,
    String state = RemoteExecutionStates.pending,
    int at = 1700000000000,
    String source = 'fnthink',
  }) => FnthinkRemoteExecutionRecord(
    execId: id,
    direction: direction,
    peerAddress: '8K3FJ6QPTM9WZ4VHNS',
    level: 'L2',
    item: 'listener:start',
    argument: '',
    state: state,
    source: source,
    createdAt: at,
  );

  String dbSource() => stripComments(
    File(
      '${projectRoot()}/lib/database/database_helper.dart',
    ).readAsStringSync(),
  );

  group('fnthink_remote_executions 建表', () {
    test('建表 SQL 一处定义、两处入口都调它（_onCreate 与 v18 升级）', () {
      final src = dbSource();
      expect(
        RegExp(
          r'CREATE TABLE IF NOT EXISTS \$\{FnthinkRemoteExecutionRecord\.table\} \(',
        ).allMatches(src).length,
        1,
        reason: '建表 SQL 被复制成多处：两处列迟早写漂',
      );
      expect(
        RegExp(
          r'await _createFnthinkRemoteExecutions\(db\);',
        ).allMatches(src).length,
        2,
        reason: '少一处 = 新装正常、升级设备一进远程执行历史就 no such table',
      );
      expect(RegExp(r'if \(oldVersion < 18\)').allMatches(src), hasLength(1));
    });

    test('新建库的列就是模型声明那些列；created_at 落成 INTEGER', () async {
      final db = await freshDb();
      expect(await columnsOf(db), FnthinkRemoteExecutionRecord.columns.toSet());
      final types = <String, String>{
        for (final r in await db.rawQuery(
          'PRAGMA table_info(${FnthinkRemoteExecutionRecord.table})',
        ))
          r['name'].toString(): r['type'].toString(),
      };
      expect(types['created_at'], 'INTEGER');
      expect(types['exec_id'], 'TEXT');
      await helper.saveRemoteExecutionRecord(record('x0000001'));
      final stored = (await helper.loadRemoteExecutionRecords()).single;
      expect(stored.execId, 'x0000001');
      expect(stored.createdAt, 1700000000000);
      expect(stored.direction, kFnthinkRemoteDirectionIn);
    });

    test('表里没有凭据列与正文列（契约 execution.forbiddenFields 那条红线）', () async {
      final db = await freshDb();
      final cols = await columnsOf(db);
      for (final banned in const [
        'key',
        'secret',
        'totp',
        'totp_secret',
        'credential',
        'body',
        'title',
        'text',
        'token',
      ]) {
        expect(
          cols.contains(banned),
          isFalse,
          reason: '远程执行历史落进了「$banned」列：进这张表就等于给每个能读本机库的人发一把钥匙',
        );
      }
    });

    test('v17 老库升上来：最终列与模型声明逐字一致', () async {
      SharedPreferences.setMockInitialValues({});
      if (await databaseFactory.databaseExists(dbPath)) {
        await databaseFactory.deleteDatabase(dbPath);
      }
      final old = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(version: DatabaseHelper.dbVersion),
      );
      addTearDown(() async => old.close());
      await helper.createSchemaForTest(old);
      await old.execute('DROP TABLE ${FnthinkRemoteExecutionRecord.table}');
      expect(await columnsOf(old), isEmpty, reason: '锚点：表没建成，本用例是空转');
      await helper.upgradeSchemaForTest(old, 17, 18);
      expect(
        await columnsOf(old),
        FnthinkRemoteExecutionRecord.columns.toSet(),
      );
    });

    test('升级不造任何占位行（本机第一次有这功能，历史里不可能有它的行）', () async {
      SharedPreferences.setMockInitialValues({});
      if (await databaseFactory.databaseExists(dbPath)) {
        await databaseFactory.deleteDatabase(dbPath);
      }
      final old = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(version: DatabaseHelper.dbVersion),
      );
      addTearDown(() async => old.close());
      await helper.createSchemaForTest(old);
      await old.execute('DROP TABLE ${FnthinkRemoteExecutionRecord.table}');
      await helper.upgradeSchemaForTest(old, 17, 18);
      final rows = await old.rawQuery(
        'SELECT * FROM ${FnthinkRemoteExecutionRecord.table}',
      );
      expect(rows, isEmpty, reason: '凭空造一行 = 界面上显示出没发生过的执行');
    });
  });

  group('两档方向：区分收指令与发指令', () {
    test('按方向各读自己那一档，传 null 才是一起看', () async {
      await freshDb();
      await helper.saveRemoteExecutionRecord(
        record('x0000001', direction: kFnthinkRemoteDirectionIn),
      );
      await helper.saveRemoteExecutionRecord(
        record('x0000002', direction: kFnthinkRemoteDirectionOut),
      );
      final incoming = await helper.loadRemoteExecutionRecords(
        direction: kFnthinkRemoteDirectionIn,
      );
      final outgoing = await helper.loadRemoteExecutionRecords(
        direction: kFnthinkRemoteDirectionOut,
      );
      expect(incoming.map((r) => r.execId), ['x0000001']);
      expect(outgoing.map((r) => r.execId), ['x0000002']);
      expect(await helper.loadRemoteExecutionRecords(), hasLength(2));
    });

    test('本机白名单触发的那一行：对端为空而来源记着（没有远端发送方）', () async {
      await freshDb();
      await helper.saveRemoteExecutionRecord(
        const FnthinkRemoteExecutionRecord(
          execId: 'x0000003',
          direction: kFnthinkRemoteDirectionIn,
          peerAddress: '',
          level: 'L1',
          item: 'listener:start',
          argument: '',
          state: RemoteExecutionStates.done,
          source: 'localNotificationWhitelist',
          createdAt: 1700000000000,
        ),
      );
      final row = (await helper.loadRemoteExecutionRecords()).single;
      expect(row.peerAddress, isEmpty);
      expect(
        row.source,
        'localNotificationWhitelist',
        reason: '那一路上 source 是"谁干的"唯一的线索，丢了就没人知道这条是哪来的',
      );
    });

    test('读回来时两档的判定互不串（in 那一行不是 out）', () async {
      final r = record('x0000004', direction: kFnthinkRemoteDirectionOut);
      expect(r.outgoing, isTrue);
      expect(r.incoming, isFalse);
    });
  });

  group('状态迁移：覆盖写而不是再插一行', () {
    test('同一 exec_id 走完五态，最后只剩一行', () async {
      await freshDb();
      var row = record('x0000005', state: RemoteExecutionStates.pending);
      await helper.saveRemoteExecutionRecord(row);
      for (final next in [
        RemoteExecutionStates.executing,
        RemoteExecutionStates.done,
      ]) {
        row = FnthinkRemoteExecutionRecord(
          execId: row.execId,
          direction: row.direction,
          peerAddress: row.peerAddress,
          level: row.level,
          item: row.item,
          argument: row.argument,
          state: next,
          source: row.source,
          createdAt: row.createdAt,
        );
        await helper.saveRemoteExecutionRecord(row);
      }
      final rows = await helper.loadRemoteExecutionRecords();
      expect(rows, hasLength(1), reason: '两行并存 = 撤销那一格会说"还在执行中"');
      expect(rows.single.state, RemoteExecutionStates.done);
    });

    test('覆盖写时结果与理由也跟着换（不是只换状态那一列）', () async {
      await freshDb();
      await helper.saveRemoteExecutionRecord(
        record('x0000006', state: RemoteExecutionStates.executing),
      );
      await helper.saveRemoteExecutionRecord(
        const FnthinkRemoteExecutionRecord(
          execId: 'x0000006',
          direction: kFnthinkRemoteDirectionIn,
          peerAddress: '8K3FJ6QPTM9WZ4VHNS',
          level: 'L2',
          item: 'listener:start',
          argument: '',
          state: RemoteExecutionStates.cancelled,
          source: 'fnthink',
          createdAt: 1700000000000,
          reason: 'cancelled-by-user',
        ),
      );
      final row = (await helper.loadRemoteExecutionRecords()).single;
      expect(row.state, RemoteExecutionStates.cancelled);
      expect(row.reason, 'cancelled-by-user');
    });

    test('读一条：没有就是 null，不是一句"已取消"', () async {
      await freshDb();
      expect(await helper.remoteExecutionRecord('xNOTHERE'), isNull);
      await helper.saveRemoteExecutionRecord(record('x0000007'));
      expect(
        (await helper.remoteExecutionRecord('x0000007'))?.execId,
        'x0000007',
      );
    });
  });

  group('还没到终态那一读口（撤销那一格读它）', () {
    test('只回 pending 与 executing，done/failed/cancelled 一律不在内', () async {
      await freshDb();
      await helper.saveRemoteExecutionRecord(
        record('x0000008', state: RemoteExecutionStates.pending),
      );
      await helper.saveRemoteExecutionRecord(
        record('x0000009', state: RemoteExecutionStates.executing),
      );
      await helper.saveRemoteExecutionRecord(
        record('x000000a', state: RemoteExecutionStates.done),
      );
      await helper.saveRemoteExecutionRecord(
        record('x000000b', state: RemoteExecutionStates.failed),
      );
      await helper.saveRemoteExecutionRecord(
        record('x000000c', state: RemoteExecutionStates.cancelled),
      );
      final open = await helper.loadUnsettledRemoteExecutions();
      expect(open.map((r) => r.execId).toSet(), {'x0000008', 'x0000009'});
      expect(open.every((r) => r.unsettled), isTrue);
    });

    test('迁移到终态之后那条就不再出现在这一格里', () async {
      await freshDb();
      await helper.saveRemoteExecutionRecord(
        record('x000000d', state: RemoteExecutionStates.pending),
      );
      expect(await helper.loadUnsettledRemoteExecutions(), hasLength(1));
      await helper.saveRemoteExecutionRecord(
        record('x000000d', state: RemoteExecutionStates.cancelled),
      );
      expect(
        await helper.loadUnsettledRemoteExecutions(),
        isEmpty,
        reason: '撤销完了还显示"在执行中" = 用户点了撤销却看着它继续跑',
      );
    });

    test('方向两档一起进来（白名单触发的那一条也要能撤销）', () async {
      await freshDb();
      await helper.saveRemoteExecutionRecord(
        record('x000000e', direction: kFnthinkRemoteDirectionIn),
      );
      await helper.saveRemoteExecutionRecord(
        record('x000000f', direction: kFnthinkRemoteDirectionOut),
      );
      expect(await helper.loadUnsettledRemoteExecutions(), hasLength(2));
    });
  });

  group('删除', () {
    test('删掉一条回 true；删不存在的那条回 false', () async {
      await freshDb();
      await helper.saveRemoteExecutionRecord(record('x0000010'));
      expect(await helper.removeRemoteExecutionRecord('x0000010'), isTrue);
      expect(await helper.loadRemoteExecutionRecords(), isEmpty);
      expect(
        await helper.removeRemoteExecutionRecord('x0000010'),
        isFalse,
        reason: '回 true 的话界面上会说"删掉了"，而那一行本来就不在',
      );
      expect(await helper.removeRemoteExecutionRecord('xNOPE'), isFalse);
    });
  });

  group('排序口径只有一处', () {
    test('同毫秒的两条按 exec_id 升序补齐（不会来回跳）', () async {
      await freshDb();
      await helper.saveRemoteExecutionRecord(record('x0000002', at: 1000));
      await helper.saveRemoteExecutionRecord(record('x0000001', at: 1000));
      await helper.saveRemoteExecutionRecord(record('x0000003', at: 2000));
      final ids = (await helper.loadRemoteExecutionRecords())
          .map((r) => r.execId)
          .toList();
      expect(ids, ['x0000003', 'x0000001', 'x0000002']);
    });

    test('翻页取 limit 时也是同一套顺序', () async {
      await freshDb();
      for (var i = 1; i <= 5; i++) {
        await helper.saveRemoteExecutionRecord(
          record('x000000$i', at: i * 1000),
        );
      }
      final top = await helper.loadRemoteExecutionRecords(limit: 2);
      expect(top.map((r) => r.execId), ['x0000005', 'x0000004']);
    });
  });
}
