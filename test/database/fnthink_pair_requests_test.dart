import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/models/fnthink_pair_request_record.dart';
import 'package:notice_transmit/models/fnthink_remote_execution_record.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_setup.dart';

/// T116：配对请求那一份账（表 `fnthink_pair_requests`）。
///
/// 这里要抓住的三种假绿，各自对应一种"界面上看不出来"的真实缺陷：
///  ① **两处建表列不一致**（`_onCreate` 全量建库 vs `oldVersion < 22` 迁移）：升级上来的设备
///     少一列，读口把那列读成 0，而屏幕上那一格只是"永远显示 —"，不报错。
///  ② **覆盖写变成了两行并存**：同一条请求先 pending 后 approved，若写成两行，
///     「已发起」那张卡会同时画出"还在等对方答复"和"对方已同意" —— 一行说没结论、
///     一行说有结论，而这两个词是同一件事。
///  ③ **口令落盘**：这一张表留存得比服务端那份久，口令一旦进列就等于把一次性口令
///     写进了会随备份走的库里。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabase();

  final helper = DatabaseHelper();
  late final String dbPath;

  setUpAll(() async {
    dbPath = join(await getDatabasesPath(), 'fnthink_pair_requests_test.db');
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
      'PRAGMA table_info(${FnthinkPairRequestRecord.table})',
    );
    return rows.map((r) => r['name'].toString()).toSet();
  }

  /// 只跑迁移那一段（建一张空库，假装它是 v21 升上来的）。
  Future<Database> upgradeOnly() async {
    SharedPreferences.setMockInitialValues({});
    if (await databaseFactory.databaseExists(dbPath)) {
      await databaseFactory.deleteDatabase(dbPath);
    }
    final db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(version: DatabaseHelper.dbVersion - 1),
    );
    await helper.upgradeSchemaForTest(
      db,
      DatabaseHelper.dbVersion - 1,
      DatabaseHelper.dbVersion,
    );
    helper.debugDatabase = db;
    addTearDown(() async {
      helper.debugDatabase = null;
      await db.close();
    });
    return db;
  }

  FnthinkPairRequestRecord out(
    String id, {
    String target = '8K3FJ6QPTM9WZ4VHNS',
    String status = 'pending',
    int changedAt = 0,
    int createdAt = 1700000000000,
  }) => outgoingPairRequest(
    requestId: id,
    target: target,
    level: 'L1',
    status: status,
    createdAt: createdAt,
    changedAt: changedAt,
    expiresAt: createdAt + 300000,
    updatedAt: createdAt + 1,
  );

  group('建表的两处入口必须一模一样', () {
    test('全量建库那一条：列与模型声明的名单逐字相等', () async {
      final db = await freshDb();
      expect(await columnsOf(db), FnthinkPairRequestRecord.columns.toSet());
    });

    test('迁移那一条（v21→v22）建出的是同一套列，不是一眼看上去差不多', () async {
      final db = await upgradeOnly();
      expect(await columnsOf(db), FnthinkPairRequestRecord.columns.toSet());
    });

    test('同一段迁移连跑两次不报错也不留下第二张表（幂等）', () async {
      final db = await upgradeOnly();
      await helper.upgradeSchemaForTest(
        db,
        DatabaseHelper.dbVersion - 1,
        DatabaseHelper.dbVersion,
      );
      expect(await columnsOf(db), FnthinkPairRequestRecord.columns.toSet());
    });

    test('口令与摘要一字节都不进这张表（红线，同契约 pairRequest.neverStored）', () async {
      final db = await freshDb();
      final cols = await columnsOf(db);
      for (final banned in const [
        'pairing_code',
        'codeDigest',
        'code_digest',
        'secret',
        'private_key',
      ]) {
        expect(cols, isNot(contains(banned)), reason: banned);
      }
    });
  });

  group('写与读', () {
    test('同一个 id 写两次是一行、后写的那份赢（pending → approved 不许并存两行）', () async {
      await freshDb();
      await helper.saveFnthinkPairRequest(out('r1'));
      await helper.saveFnthinkPairRequest(
        out('r1', status: 'approved', changedAt: 1700000012345),
      );
      final rows = await helper.loadFnthinkPairRequests();
      expect(rows, hasLength(1));
      expect(rows.single.status, 'approved');
      expect(rows.single.changedAt, 1700000012345);
      expect(rows.single.settled, isTrue);
    });

    test('两个主语共用一张表而不撞行：同一条请求在本机只可能是其中一个主语', () async {
      await freshDb();
      await helper.saveFnthinkPairRequest(out('rA'));
      await helper.saveFnthinkPairRequest(
        incomingPairRequest(
          requestId: 'rB',
          requester: '2M9WZ4VHNS8K3FJ6QP',
          level: 'L1',
          createdAt: 1700000000000,
          updatedAt: 1700000000001,
        ),
      );
      final rows = await helper.loadFnthinkPairRequests();
      expect(rows, hasLength(2));
      expect(rows.where((r) => r.outgoing).single.requestId, 'rA');
      expect(rows.where((r) => r.incoming).single.requestId, 'rB');
    });

    test('按方向读只回那一个主语；不传方向是两个一起看', () async {
      await freshDb();
      await helper.saveFnthinkPairRequest(out('rOut'));
      await helper.saveFnthinkPairRequest(
        incomingPairRequest(
          requestId: 'rIn',
          requester: '2M9WZ4VHNS8K3FJ6QP',
          updatedAt: 1,
        ),
      );
      expect(
        (await helper.loadFnthinkPairRequests(
          direction: kFnthinkRemoteDirectionOut,
        )).map((r) => r.requestId),
        ['rOut'],
      );
      expect(
        (await helper.loadFnthinkPairRequests()).map((r) => r.requestId),
        containsAll(['rOut', 'rIn']),
      );
    });

    test('排序只有这一个口径：新的在前，不知道什么时候的排最后', () async {
      await freshDb();
      await helper.saveFnthinkPairRequest(out('old', createdAt: 500));
      await helper.saveFnthinkPairRequest(out('new', createdAt: 900));
      await helper.saveFnthinkPairRequest(out('unknown', createdAt: 0));
      expect((await helper.loadFnthinkPairRequests()).map((r) => r.requestId), [
        'new',
        'old',
        'unknown',
      ]);
    });

    test('终态那一判据是"结论时刻被写过"，不是状态词的字面巧合', () async {
      await freshDb();
      // 服务端把 pending 的 statusChangedAt 留空 ⇒ 这一条不该进历史格。
      await helper.saveFnthinkPairRequest(
        out('still-waiting', status: 'pending'),
      );
      // 词表外的结论词（将来契约加了第五个词）也必须进历史，而不是被读成"还在等"。
      await helper.saveFnthinkPairRequest(
        out('future-word', status: 'revoked', changedAt: 800),
      );
      final rows = await helper.loadFnthinkPairRequests();
      expect(
        rows.firstWhere((r) => r.requestId == 'still-waiting').settled,
        isFalse,
      );
      expect(
        rows.firstWhere((r) => r.requestId == 'future-word').settled,
        isTrue,
      );
    });
  });
}
