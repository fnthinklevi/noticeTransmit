import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/models/fnthink_peer.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/source_guards.dart';
import '../test_setup.dart';

/// T42 前置：本机配对名单 `fnthink_peers`（建表、写入的三种结果、取消配对）。
///
/// 必须跑真 SQL 的那两条假绿：
///  ① "同码不同钥也 update" 在 fake 存储里测不出来 —— 它会照样回 refreshed，
///     而真表上那是**把白名单里那个人换成另一个人**（本机替用户点了"同意换钥"）；
///  ② `removeFnthinkPeer` 的返回值：删不存在的行回 0 与回 true 在界面上是两件事
///     —— 回 true 的话用户以为对面推不进来了，而对面还能推。
/// 另外钉住两条老不变量：两处建表最终列一致；本机这份**默认不进备份**
/// （换机恢复过来的名单，配的是一把不在新机 KeyStore 里的私钥，那是一张点不动的名单）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabase();

  final helper = DatabaseHelper();
  late final String dbPath;

  setUpAll(() async {
    dbPath = join(await getDatabasesPath(), 'fnthink_peers_test.db');
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
    final rows = await db.rawQuery('PRAGMA table_info(${FnthinkPeer.table})');
    return rows.map((r) => r['name'].toString()).toSet();
  }

  Future<List<Map<String, Object?>>> allRows(Database db) => db.rawQuery(
    'SELECT * FROM ${FnthinkPeer.table} ORDER BY peer_address ASC',
  );

  FnthinkPeer peer(
    String address, {
    String key = 'pk-AAAA',
    String level = 'L2',
    int at = 1700000000000,
  }) => FnthinkPeer(
    peerAddress: address,
    publicKey: key,
    level: level,
    grantedAt: at,
    requestId: 'rq-$address',
  );

  String dbSource() => stripComments(
    File(
      '${projectRoot()}/lib/database/database_helper.dart',
    ).readAsStringSync(),
  );

  group('fnthink_peers 建表', () {
    test('建表 SQL 一处定义、两处入口都调它（_onCreate 与 v15 升级）', () {
      final src = dbSource();
      expect(
        RegExp(
          r'CREATE TABLE IF NOT EXISTS \$\{FnthinkPeer\.table\} \(',
        ).allMatches(src).length,
        1,
        reason: '建表 SQL 被复制成多处：两处列迟早写漂',
      );
      expect(
        RegExp(r'await _createFnthinkPeers\(db\);').allMatches(src).length,
        2,
        reason: '少一处 = 新装正常、升级设备一进白名单页就 no such table',
      );
      expect(RegExp(r'if \(oldVersion < 15\)').allMatches(src), hasLength(1));
    });

    test('新建库的列就是模型声明那五列；granted_at 落成 INTEGER', () async {
      final db = await freshDb();
      expect(await columnsOf(db), FnthinkPeer.columns.toSet());
      await helper.upsertFnthinkPeer(peer('8K3FJ6QPTM9WZ4VHNS'));
      final types = <String, String>{
        for (final r in await db.rawQuery(
          'PRAGMA table_info(${FnthinkPeer.table})',
        ))
          r['name'].toString(): r['type'].toString(),
      };
      expect(types['granted_at'], 'INTEGER');
      final stored = (await allRows(db)).single;
      expect(stored['granted_at'], 1700000000000);
      expect(stored['request_id'], 'rq-8K3FJ6QPTM9WZ4VHNS');
    });

    test('v14 老库升上来：最终列与模型声明逐字一致', () async {
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
      await old.execute('DROP TABLE ${FnthinkPeer.table}');
      expect(await columnsOf(old), isEmpty, reason: '锚点：表没建成，本用例是空转');
      await helper.upgradeSchemaForTest(old, 14, 15);
      expect(await columnsOf(old), FnthinkPeer.columns.toSet());
    });
  });

  group('写入的三种结果', () {
    test('第一次是 created，再来一次同钥是 refreshed 且不新增行', () async {
      final db = await freshDb();
      expect(
        await helper.upsertFnthinkPeer(peer('8K3FJ6QPTM9WZ4VHNS')),
        FnthinkPeerWrite.created,
      );
      expect(
        await helper.upsertFnthinkPeer(
          peer('8K3FJ6QPTM9WZ4VHNS', level: 'L3', at: 1700000600000),
        ),
        FnthinkPeerWrite.refreshed,
      );
      final rows = await allRows(db);
      expect(rows, hasLength(1));
      expect(rows.single['level'], 'L3', reason: '重新授权要真的刷档位');
      expect(rows.single['granted_at'], 1700000600000);
    });

    test('① 同码不同公钥 ⇒ keySwapped，且那一行**一个字节都不改**', () async {
      final db = await freshDb();
      await helper.upsertFnthinkPeer(
        peer('8K3FJ6QPTM9WZ4VHNS', key: 'pk-original', level: 'L2'),
      );
      final before = (await allRows(db)).single;

      expect(
        await helper.upsertFnthinkPeer(
          peer('8K3FJ6QPTM9WZ4VHNS', key: 'pk-attacker', level: 'L3'),
        ),
        FnthinkPeerWrite.keySwapped,
      );
      expect(await allRows(db), [before], reason: '覆盖等于本机替用户点了"同意换钥"');
      expect(before['public_key'], 'pk-original');
      expect(before['level'], 'L2');
    });

    test('两个对端各占一行，最近同意的排在前面（同时间按地址码稳定）', () async {
      await freshDb();
      await helper.upsertFnthinkPeer(peer('8K3FJ6QPTM9WZ4VHNS', at: 100));
      await helper.upsertFnthinkPeer(peer('7YD4RKQPBM8XZ3VHNT', at: 300));
      await helper.upsertFnthinkPeer(peer('8TQVWZ3XKR5B6YD4HM', at: 200));
      await helper.upsertFnthinkPeer(peer('8K3FJ6QPTM9WZ4VHNX', at: 200));
      final loaded = await helper.loadFnthinkPeers();
      expect(
        loaded.map((p) => p.peerAddress).toList(),
        [
          '7YD4RKQPBM8XZ3VHNT', // at=300
          '8K3FJ6QPTM9WZ4VHNX', // at=200，同时间按地址码升序
          '8TQVWZ3XKR5B6YD4HM', // at=200
          '8K3FJ6QPTM9WZ4VHNS', // at=100
        ],
        reason: '最近同意的在前；同时间必须有稳定 tie-break，否则翻页会重/漏',
      );
    });
  });

  group('取消配对', () {
    test('② 删不存在的那行必须回 false（不然界面会显示"已取消"而名单没变）', () async {
      final db = await freshDb();
      await helper.upsertFnthinkPeer(peer('8K3FJ6QPTM9WZ4VHNS'));
      expect(await helper.hasFnthinkPeer('8K3FJ6QPTM9WZ4VHNS'), isTrue);
      expect(await helper.hasFnthinkPeer('8TQVWZ3XKR5B6YD4HM'), isFalse);

      expect(
        await helper.removeFnthinkPeer('8TQVWZ3XKR5B6YD4HM'),
        isFalse,
        reason: '用户以为对面推不进来了，而对面还能推 —— 这是最难自证的那种"成功"',
      );
      expect(await helper.removeFnthinkPeer('8K3FJ6QPTM9WZ4VHNS'), isTrue);
      expect(await allRows(db), isEmpty);
    });
  });

  group('边界与不猜', () {
    test('fromDbRow 缺字段回空串/0，不猜一个地址码出来', () {
      final bare = FnthinkPeer.fromDbRow({});
      expect(bare.peerAddress, '');
      expect(bare.publicKey, '');
      expect(bare.level, '');
      expect(bare.grantedAt, 0);
      expect(bare.requestId, '');
    });

    test('toString 不带整串公钥（日志会离开这台机）', () {
      final p = peer('8K3FJ6QPTM9WZ4VHNS', key: 'AAAAAAAABBBBBBBBCCCCCCCC');
      expect(p.toString(), contains('AAAAAAAA…'));
      expect(p.toString(), isNot(contains('CCCCCCCC')));
    });

    test('配对名单默认不进备份：backup_service 既不认识这张表也没有它的键', () {
      // 换机恢复过来的一份名单，配的是一把**不在新机 KeyStore 里**的私钥 ——
      // 那是一张点不动、却显示"已授权"的名单。要导出得先解决"身份不随行"这件事。
      final src = stripComments(
        File(
          '${projectRoot()}/lib/services/backup_service.dart',
        ).readAsStringSync(),
      );
      expect(src, isNot(contains('fnthink_peers')));
      expect(src, isNot(contains('FnthinkPeer')));
      // 只查"有没有出现这张表的名字"是不够的：备份键是 camelCase（`fnthinkPeers` 就不含
      // `fnthink_peers` 也不含 `FnthinkPeer`）。所以把**键清单**本身列出来逐个判 ——
      // 这一段与收件表那份守卫是重复的，而这份重复是必要的：两个文件必须各自能被单独打红。
      final exported = RegExp(
        r"^\s*'([A-Za-z_]+)':",
        multiLine: true,
      ).allMatches(src).map((m) => m.group(1)!).toList();
      expect(
        exported,
        contains('webhookChannels'),
        reason: '锚点：正则没抓到键就该红，而不是"清单为空所以全过"',
      );
      for (final key in exported) {
        final k = key.toLowerCase();
        expect(
          k,
          isNot(
            anyOf(
              contains('peer'),
              contains('inbox'),
              contains('fnthink'),
              contains('message'),
            ),
          ),
          reason: '备份键清单里出现了幻念推送那两面的键：$key',
        );
      }
    });
  });
}
