import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/models/fnthink_inbox_message.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/source_guards.dart';
import '../test_setup.dart';

/// T47：幻念推送的收件表 `fnthink_messages` —— 建表、幂等入库、未读、ack 记账与保留清理。
///
/// 为什么这些用例必须跑真 SQL（注入 fake 测不出来）：这一族里最会咬人的四个错法都在 SQL 层 ——
/// ① 入库写成 replace（at-least-once 下重发会把「已读」洗回未读、把报过的结果抹空）；
/// ② `read` 落成 TEXT/REAL（读取侧 `as int` 当场抛，而抛的是首页那张未读卡）；
/// ③ 排序没有 tie-breaker（同一毫秒的两条在翻页时重复或消失）；
/// ④ 裁上限"删了就删了"（#94 那次静默丢最旧的教训，必须回条数）。
///
/// 另外钉住两条老不变量：`_onCreate` 与 `oldVersion < 14` 最终列必须逐字一致；
/// 收件内容**默认不进备份**（第三方推来的正文是别人的内容，导出的却是这台机的文件）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabase();

  final helper = DatabaseHelper();
  late final String dbPath;

  setUpAll(() async {
    dbPath = join(await getDatabasesPath(), 'fnthink_inbox_test.db');
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

  /// 全量 schema（v14）建好的干净库，并把 helper 指到它上面。
  Future<Database> freshDb() async {
    // 建表会连带跑引擎规则那次一次性导入（读 prefs），所以每个建库的用例都要先接住它。
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
      'PRAGMA table_info(${FnthinkInboxMessage.table})',
    );
    return rows.map((r) => r['name'].toString()).toSet();
  }

  Future<List<Map<String, Object?>>> allRows(Database db) => db.rawQuery(
    'SELECT * FROM ${FnthinkInboxMessage.table} ORDER BY message_id ASC',
  );

  Future<int> rowCount(Database db) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${FnthinkInboxMessage.table}',
    );
    return (rows.single['c'] as num).toInt();
  }

  FnthinkInboxMessage row(
    String id, {
    String sender = '8K3FJ6QPTM9WZ4VHNS',
    int at = 1700000000000,
    String title = '机箱',
    String body = '温度 63 度',
  }) => FnthinkInboxMessage(
    messageId: id,
    sender: sender,
    type: 'notice',
    item: '',
    title: title,
    body: body,
    receivedAt: at,
  );

  /// ⚠ 源码扫描只在测试体里读文件：锚点找不到时若在 `main()` 顶层抛，
  ///   CI 表现是"这个文件没有用例"而不是红（base.md（75）撞过两次）。
  String dbSource() => stripComments(
    File(
      '${projectRoot()}/lib/database/database_helper.dart',
    ).readAsStringSync(),
  );

  group('fnthink_messages 建表', () {
    test('建表 SQL 只有一处，但两处入口都调它（_onCreate 与 v14 升级）', () {
      final src = dbSource();
      expect(
        RegExp(
          r'CREATE TABLE IF NOT EXISTS \$\{FnthinkInboxMessage\.table\} \(',
        ).allMatches(src).length,
        1,
        reason: '建表 SQL 被复制成了多处：两处列迟早写漂',
      );
      expect(
        RegExp(r'await _createFnthinkInbox\(db\);').allMatches(src).length,
        2,
        reason: '少一处 = 新装正常、升级设备一收件就 no such table',
      );
      expect(
        RegExp(r'if \(oldVersion < 14\)').allMatches(src),
        hasLength(1),
        reason: 'v14 那条升级分支不在了',
      );
    });

    test('新建库的列就是模型声明那十列，一个不多一个不少', () async {
      final db = await freshDb();
      expect(
        await columnsOf(db),
        FnthinkInboxMessage.columns.toSet(),
        reason: '表结构与模型各写一份就是"两端各算一份事实"的又一例',
      );
    });

    test('v13 老库升上来：最终列与模型声明逐字一致', () async {
      // "v13 形状" = 全量 schema 减掉本表，再走 13→14 那条分支。
      // 新建库那一侧由上一条用例钉住与模型一致，这里比的是**升级路径**拿到的列。
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
      await old.execute('DROP TABLE ${FnthinkInboxMessage.table}');
      expect(await columnsOf(old), isEmpty, reason: '锚点：表没建成，本用例就是空转');
      await helper.upgradeSchemaForTest(old, 13, 14);
      expect(await columnsOf(old), FnthinkInboxMessage.columns.toSet());
    });

    test('read 与两个时间列落成 INTEGER（不是 TEXT/REAL）', () async {
      // 读取侧写的是 `row['read'] as int`：这一列要是 TEXT，表现是首页未读卡一刷就抛。
      final db = await freshDb();
      await helper.insertFnthinkInbox(row('m_1'));
      final types = <String, String>{
        for (final r in await db.rawQuery(
          'PRAGMA table_info(${FnthinkInboxMessage.table})',
        ))
          r['name'].toString(): r['type'].toString(),
      };
      expect(types['read'], 'INTEGER');
      expect(types['received_at'], 'INTEGER');
      expect(types['acked_at'], 'INTEGER');
      final stored = (await allRows(db)).single;
      expect(stored['read'], 0, reason: 'bool 要落成 0/1');
      expect(stored['sender'], '8K3FJ6QPTM9WZ4VHNS');
    });
  });

  group('入库幂等（at-least-once 的那一半）', () {
    test('同一条来第二次 ⇒ false，且原行一个字节都不动', () async {
      final db = await freshDb();
      expect(await helper.insertFnthinkInbox(row('m_dup')), isTrue);
      await helper.markFnthinkInboxRead('m_dup');
      await helper.recordFnthinkInboxAck(
        messageId: 'm_dup',
        result: 'displayed',
        at: 1700000009000,
      );
      final before = (await allRows(db)).single;

      // 重发：同 id、内容看着"更新"了 —— 幂等的含义就是**不**拿它覆盖已读与 ack。
      expect(
        await helper.insertFnthinkInbox(
          row('m_dup', title: '改写过的标题', at: 1700000999000),
        ),
        isFalse,
      );
      expect(await allRows(db), [before]);
      expect(await rowCount(db), 1);
    });

    test('不同 id 各算一条，读回来字段逐个对得上', () async {
      await freshDb();
      expect(await helper.insertFnthinkInbox(row('m_a')), isTrue);
      expect(
        await helper.insertFnthinkInbox(
          row('m_b', sender: 'endpoint:ep_1', title: 'NAS', body: '磁盘 91%'),
        ),
        isTrue,
      );
      final loaded = await helper.loadFnthinkInbox();
      expect(loaded.map((m) => m.messageId).toSet(), {'m_a', 'm_b'});
      final fromEndpoint = loaded.firstWhere((m) => m.messageId == 'm_b');
      expect(fromEndpoint.sender, 'endpoint:ep_1');
      expect(fromEndpoint.title, 'NAS');
      expect(fromEndpoint.body, '磁盘 91%');
      expect(fromEndpoint.read, isFalse);
      expect(fromEndpoint.ackResult, '');
      expect(fromEndpoint.ackedAt, 0);
    });

    test('旧服务端不带 sender 的那条照样入库（空串 = 未知来源，不是丢掉）', () async {
      await freshDb();
      expect(
        await helper.insertFnthinkInbox(row('m_old', sender: '')),
        isTrue,
        reason: '正文已经到手，因为缺一个归属就丢消息是「不静默丢」的反面',
      );
      expect((await helper.loadFnthinkInbox()).single.sender, '');
    });
  });

  group('未读与 ack', () {
    test('未读数只数未读；标已读命中与不命中都回得来', () async {
      await freshDb();
      await helper.insertFnthinkInbox(row('m_1'));
      await helper.insertFnthinkInbox(row('m_2', at: 1700000001000));
      expect(await helper.countFnthinkInboxUnread(), 2);

      expect(await helper.markFnthinkInboxRead('m_1'), isTrue);
      expect(await helper.countFnthinkInboxUnread(), 1);
      // 没命中必须说出来：调用方是"点开一条 ⇒ 未读减一"，不说就会减成负的。
      expect(await helper.markFnthinkInboxRead('m_not_here'), isFalse);
      expect(await helper.countFnthinkInboxUnread(), 1);
    });

    test('unreadOnly 那一档筛出来的就是未读的', () async {
      await freshDb();
      await helper.insertFnthinkInbox(row('m_1'));
      await helper.insertFnthinkInbox(row('m_2', at: 1700000001000));
      await helper.markFnthinkInboxRead('m_2');
      final unread = await helper.loadFnthinkInbox(unreadOnly: true);
      expect(unread.map((m) => m.messageId), ['m_1']);
    });

    test('ack 记账落在既有那一行上；id 不存在时不新建行', () async {
      final db = await freshDb();
      await helper.insertFnthinkInbox(row('m_1'));
      expect(
        await helper.recordFnthinkInboxAck(
          messageId: 'm_1',
          result: 'failed_action',
          at: 1700000050000,
        ),
        isTrue,
      );
      final one = (await helper.loadFnthinkInbox()).single;
      expect(one.ackResult, 'failed_action');
      expect(one.ackedAt, 1700000050000);

      expect(
        await helper.recordFnthinkInboxAck(
          messageId: 'm_ghost',
          result: 'delivered',
          at: 1700000060000,
        ),
        isFalse,
      );
      expect(await rowCount(db), 1, reason: '给不存在的 id 记 ack 等于凭空造一条收件');
    });
  });

  group('排序与翻页', () {
    test('新的在前；同一毫秒的两条按 id 稳定排，翻页不重不漏', () async {
      await freshDb();
      await helper.insertFnthinkInbox(row('m_1', at: 1700000000000));
      await helper.insertFnthinkInbox(row('m_2', at: 1700000002000));
      // 同一毫秒到的两条：没有 tie-breaker 时 SQLite 的次序不保证
      await helper.insertFnthinkInbox(row('m_3', at: 1700000001000));
      await helper.insertFnthinkInbox(row('m_4', at: 1700000001000));

      final all = await helper.loadFnthinkInbox();
      expect(all.map((m) => m.messageId).toList(), [
        'm_2',
        'm_3',
        'm_4',
        'm_1',
      ]);

      final p1 = await helper.loadFnthinkInbox(limit: 2, offset: 0);
      final p2 = await helper.loadFnthinkInbox(limit: 2, offset: 2);
      expect(
        [...p1.map((m) => m.messageId), ...p2.map((m) => m.messageId)],
        ['m_2', 'm_3', 'm_4', 'm_1'],
      );
    });
  });

  group('保留与清理（不静默丢）', () {
    test('按天数删、按上限裁最旧，两个计数分开回', () async {
      final db = await freshDb();
      const now = 1800000000000;
      const day = 86400000;
      await helper.insertFnthinkInbox(row('m_old', at: now - 40 * day));
      await helper.insertFnthinkInbox(row('m_edge', at: now - 30 * day));
      await helper.insertFnthinkInbox(row('m_new3', at: now - 3 * day));
      await helper.insertFnthinkInbox(row('m_new2', at: now - 2 * day));
      await helper.insertFnthinkInbox(row('m_new1', at: now - 1 * day));

      final pruned = await helper.pruneFnthinkInbox(
        olderThanDays: 30,
        maxRows: 2,
        now: now,
      );
      // 边界：`received_at < cutoff` —— 正好 30 天那条**不**按"过期"删（它按上限裁掉）。
      expect(pruned.byAge, 1);
      expect(pruned.byCap, 2);
      expect((await allRows(db)).map((r) => r['message_id']), [
        'm_new1',
        'm_new2',
      ], reason: '留下的必须是最新的那两条');
    });

    test('没超限时两个计数都回 0（"一条没删"与"没数"必须可区分）', () async {
      final db = await freshDb();
      const now = 1800000000000;
      // 这一条必须**既没过期也没超限**：拿默认的 2023 年时间戳插进来，它按天数那一档就该被删，
      // 用例测的就不再是"没活干时回 0"。
      await helper.insertFnthinkInbox(row('m_1', at: now - 86400000));
      final pruned = await helper.pruneFnthinkInbox(
        olderThanDays: 30,
        maxRows: 100,
        now: now,
      );
      expect(pruned.byAge, 0);
      expect(pruned.byCap, 0);
      expect(await rowCount(db), 1);
    });

    test('0 或负数一律抛，且一行都不删', () async {
      final db = await freshDb();
      await helper.insertFnthinkInbox(row('m_1'));
      // 按字面执行"maxRows=0"等于清空收件表，而 0 长得太像"没配"。
      await expectLater(
        helper.pruneFnthinkInbox(olderThanDays: 30, maxRows: 0),
        throwsArgumentError,
      );
      await expectLater(
        helper.pruneFnthinkInbox(olderThanDays: 0, maxRows: 100),
        throwsArgumentError,
      );
      expect(await rowCount(db), 1);
    });
  });

  group('边界与不猜', () {
    test('fromDbRow 见到非整数的 read 就抛（不猜成未读/已读）', () {
      expect(
        () => FnthinkInboxMessage.fromDbRow({'read': '1'}),
        throwsStateError,
      );
      expect(FnthinkInboxMessage.fromDbRow({'read': 1}).read, isTrue);
      expect(FnthinkInboxMessage.fromDbRow({'read': 0}).read, isFalse);
    });

    test('收件表默认不进备份：backup_service 既不认识这张表，也没有收件类的键', () {
      // 第三方推来的正文是**别人**写的内容，导出的却是这台机的文件。
      // 路线图定的是"收件计入统计 + 可按方向筛选"，没有"随备份离开这台机"。
      // 这条守卫钉的是：哪天要导出，必须先在这里登记、并写清是谁同意过的。
      final src = stripComments(
        File(
          '${projectRoot()}/lib/services/backup_service.dart',
        ).readAsStringSync(),
      );
      expect(src, isNot(contains('fnthink_messages')));
      expect(src, isNot(contains('FnthinkInbox')));
      final exported = RegExp(
        r"^\s*'([A-Za-z]+)':",
        multiLine: true,
      ).allMatches(src).map((m) => m.group(1)!).toList();
      expect(exported, containsAll(['webhookChannels', 'notificationRules']));
      for (final key in exported) {
        expect(
          key.toLowerCase(),
          isNot(
            anyOf(contains('inbox'), contains('message'), contains('fnthink')),
          ),
          reason: '备份键清单里出现了收件类的键：$key',
        );
      }
    });
  });
}
