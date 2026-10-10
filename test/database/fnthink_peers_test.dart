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

    test('新建库的列就是模型声明那些列；granted_at 落成 INTEGER', () async {
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
      expect(types['revision'], 'INTEGER');
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

    test('v16 老库升上来：T49 那两列补上，**存量行一个字节都不改**', () async {
      // ⚠ "不改存量行"在这里正是要的那个行为：那些行写着 L2/L3，清单一律空。
      // 补上"按档位放行"会让升级变成一次静默的权限扩张 —— 那一半才是不该发生的。
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
      // 造一张 v16 的表：当前 schema 减去 T49 那两列（`ALTER` 不支持 DROP COLUMN 到这份
      // sqlite 版本上，所以整表重建）。存量行带着 L3 —— 正是"看着像没收紧"的那一行。
      await old.execute('DROP TABLE ${FnthinkPeer.table}');
      await old.execute(
        'CREATE TABLE ${FnthinkPeer.table} ('
        ' peer_address TEXT PRIMARY KEY, public_key TEXT NOT NULL,'
        ' level TEXT NOT NULL, granted_at INTEGER NOT NULL,'
        " request_id TEXT NOT NULL DEFAULT '')",
      );
      await old.insert(FnthinkPeer.table, {
        'peer_address': '8K3FJ6QPTM9WZ4VHNS',
        'public_key': 'AAAABBBBCCCC',
        'level': 'L3',
        'granted_at': 1700000000000,
        'request_id': '',
      });
      await helper.upgradeSchemaForTest(old, 16, 17);
      expect(await columnsOf(old), FnthinkPeer.columns.toSet());
      final row = (await old.query(FnthinkPeer.table)).single;
      expect(row['level'], 'L3', reason: '锚点：存量行不该被这一刀改写');
      expect('${row['items'] ?? ''}', isEmpty, reason: '存量授权一条都没逐条给过');
      expect((row['revision'] as num?)?.toInt(), 0);
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

  group('T128 片1：本机别名（这一行在屏幕上叫什么，仅此而已）', () {
    test('没起过名字读出来是空串；起了名字原样往返', () async {
      await freshDb();
      await helper.upsertFnthinkPeer(peer('8K3FJ6QPTM9WZ4VHNS'));
      final before = await helper.loadFnthinkPeers();
      expect(
        before.single.alias,
        '',
        reason: '空串 = "这台没有别名"，界面上就只剩地址码；不许造一个"（ unnamed ）"',
      );

      expect(
        await helper.setFnthinkPeerAlias('8K3FJ6QPTM9WZ4VHNS', '客厅那台'),
        isTrue,
      );
      expect((await helper.loadFnthinkPeers()).single.alias, '客厅那台');
    });

    test('① 重新授权**不许抹掉**用户起的名字', () async {
      // 这一条是本片唯一"两个写者抢同一格"的地方：授权那条 update 写的是调用方刚拼出来的
      // 对象（它没读回旧行），照全量写就等于"对面又发了一次配对请求 ⇒ 我给这台起的名字没了"。
      await freshDb();
      await helper.upsertFnthinkPeer(peer('8K3FJ6QPTM9WZ4VHNS'));
      await helper.setFnthinkPeerAlias('8K3FJ6QPTM9WZ4VHNS', '公司的手机');

      expect(
        await helper.upsertFnthinkPeer(
          peer('8K3FJ6QPTM9WZ4VHNS', level: 'L3', at: 1700000600000),
        ),
        FnthinkPeerWrite.refreshed,
      );
      final after = (await helper.loadFnthinkPeers()).single;
      expect(after.level, 'L3', reason: '档位该刷 —— 那是授权本体');
      expect(after.grantedAt, 1700000600000);
      expect(after.alias, '公司的手机', reason: '别名该活着 —— 它不是授权的一部分');
    });

    test('给不在名单上的地址码起名必须回 false', () async {
      await freshDb();
      expect(
        await helper.setFnthinkPeerAlias('8K3FJ6QPTM9WZ4VHNS', '不存在的那台'),
        isFalse,
        reason: '回 true 就等于界面说"已改名"，而名单里根本没有那一行',
      );
    });

    test('v22 老库升上来：补 alias 列，存量行一律读成"没有名字"', () async {
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
      await old.execute(
        'CREATE TABLE ${FnthinkPeer.table} ('
        ' peer_address TEXT PRIMARY KEY, public_key TEXT NOT NULL,'
        ' level TEXT NOT NULL, granted_at INTEGER NOT NULL,'
        " request_id TEXT NOT NULL DEFAULT '', items TEXT NOT NULL DEFAULT '',"
        ' revision INTEGER NOT NULL DEFAULT 0, forwards INTEGER NOT NULL DEFAULT 0)',
      );
      await old.insert(FnthinkPeer.table, {
        'peer_address': '8K3FJ6QPTM9WZ4VHNS',
        'public_key': 'AAAABBBBCCCC',
        'level': 'L2',
        'granted_at': 1700000000000,
      });
      expect(await columnsOf(old), isNot(contains('alias')), reason: '锚点：旧形状');

      await helper.upgradeSchemaForTest(old, 22, DatabaseHelper.dbVersion);
      expect(await columnsOf(old), FnthinkPeer.columns.toSet());
      helper.debugDatabase = old;
      final rows = await helper.loadFnthinkPeers();
      expect(
        rows.single.alias,
        '',
        reason: '存量那台过去没有名字可读，替它编一个就是屏幕上多出一台并不存在的设备',
      );
    });

    test('normalizeAlias：首尾空白抹掉、中间连续空白压一格、超长才截并留痕', () {
      expect(FnthinkPeer.normalizeAlias('  客厅 那台\n'), '客厅 那台');
      expect(FnthinkPeer.normalizeAlias(''), '');
      final long = '名' * 40;
      final capped = FnthinkPeer.normalizeAlias(long);
      expect(capped.length, 31, reason: '30 个字符 + 一个省略号，界面上那一行不会挤换行');
      expect(capped.endsWith('…'), isTrue);
    });

    test('whoLabel：地址码永远在前，别名只在括号里', () {
      const base = '8K3FJ6QPTM9WZ4VHNS';
      expect(
        const FnthinkPeer(
          peerAddress: base,
          publicKey: 'pk',
          level: 'L1',
          grantedAt: 1,
        ).whoLabel,
        base,
      );
      expect(
        const FnthinkPeer(
          peerAddress: base,
          publicKey: 'pk',
          level: 'L1',
          grantedAt: 1,
          alias: '客厅那台',
        ).whoLabel,
        '$base (客厅那台)',
        reason: '能被核对的那 18 位不能被一个本机编的名字替掉 ⇒ 顺序不能反',
      );
    });
    test('迁移碰到「这台还没有这张表」时跳过，不许半张半张地造表', () async {
      // 加列的分支替不存在的表 CREATE，会造出一张"列集合按当下形状、却少了后续数据迁移"
      // 的半张表 —— 那种表最难查。建表是它自己那条分支的事，别人不许代劳。
      // （T128 片1 加 alias 时，三条只建自己那一张表的既有升级 fixture 就是这样红的。）
      SharedPreferences.setMockInitialValues({});
      final emptyPath = join(
        await getDatabasesPath(),
        'fnthink_peers_no_table_test.db',
      );
      if (await databaseFactory.databaseExists(emptyPath)) {
        await databaseFactory.deleteDatabase(emptyPath);
      }
      final db = await databaseFactory.openDatabase(
        emptyPath,
        options: OpenDatabaseOptions(version: DatabaseHelper.dbVersion),
      );
      addTearDown(() async => db.close());
      await helper.upgradeSchemaForTest(db, 22, DatabaseHelper.dbVersion);
      expect(
        await columnsOf(db),
        isEmpty,
        reason: '表本来不存在 ⇒ 这一刀什么也不做（不 CREATE、也不抛）',
      );
      await databaseFactory.deleteDatabase(emptyPath);
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
      // 缺这两列（v17 之前的老行读进新代码）一律当"一条都没逐条给过"，
      // 而不是"清单字段缺失 ⇒ 放行"。写反了就是一次静默的权限扩张。
      expect(bare.items, isEmpty);
      expect(bare.revision, 0);
    });

    test('清单一格写坏了往收紧的那一侧靠（不许读成"全给"）', () {
      // 空白、只有换行、id 前后带空格都归一成一个空清单
      for (final raw in ['', '\n', '  \n  \n']) {
        expect(
          FnthinkPeer.fromDbRow({'items': raw}).items,
          isEmpty,
          reason: '「$raw」读出了清单',
        );
      }
      expect(FnthinkPeer.fromDbRow({'items': 'setting:a\n setting:b '}).items, [
        'setting:a',
        'setting:b',
      ]);
    });

    test('清单原样往返（写进去什么，读出来还是那几条，顺序不变）', () async {
      await freshDb();
      await helper.upsertFnthinkPeer(
        const FnthinkPeer(
          peerAddress: '8K3FJ6QPTM9WZ4VHNS',
          publicKey: 'AAAABBBBCCCC',
          level: 'L3',
          grantedAt: 1700000000000,
          items: ['setting:do_not_disturb', 'app:a/b/startListen'],
          revision: 3,
        ),
      );
      final back = (await helper.loadFnthinkPeers()).single;
      expect(back.items, ['setting:do_not_disturb', 'app:a/b/startListen']);
      expect(back.revision, 3);
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
      // T59 之后有一颗**已登记**的类别键就叫 `fnthink`（只带 receive_enabled / host /
      // consent_version 三个「意图」字段，字段白名单由
      // test/architecture/fnthink_backup_privacy_guard_test.dart 钉）。
      // 所以这条守卫不能写成"键名里没有 fnthink 这个词"——那样钉的是措辞，不是边界。
      // 真正的边界：名单本身不进备份；且除了那颗登记过的键，任何**别的** fnthink 键
      // （fnthinkPeers / fnthinkKey / fnthinkInbox…）都要在这里红 —— 想随行先改这里。
      final registered = RegExp(r'^fnthink$');
      for (final key in exported) {
        final k = key.toLowerCase();
        expect(
          k,
          isNot(
            anyOf(contains('peer'), contains('inbox'), contains('message')),
          ),
          reason: '备份键清单里出现了幻念推送那两面的键：$key',
        );
        if (!registered.hasMatch(k)) {
          expect(
            k,
            isNot(contains('fnthink')),
            reason: '除已登记的那颗意图类别键，备份键清单里不该再出现 fnthink：$key',
          );
        }
      }
    });
  });
}
