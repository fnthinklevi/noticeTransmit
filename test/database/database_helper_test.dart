import 'dart:convert';
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

    test('升级链上的函数不得再开 transaction（SQLite 不允许嵌套 BEGIN）', () {
      final source = stripComments(
        File('lib/database/database_helper.dart').readAsStringSync(),
      );
      // onUpgrade 已经跑在 sqflite 打开库的事务里；在其中再 transaction()
      // 就是第二个 BEGIN。逐条 db.update 由外层事务批量承担，不需要内层事务。
      for (final sig in [
        'Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {',
        'Future<void> _migrateDeliveryKeysToCanonical(Database db) async {',
      ]) {
        expect(
          blockAfter(source, sig),
          isNot(contains('.transaction(')),
          reason: '$sig 内部不得出现 transaction()',
        );
      }
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

  // v11 不改表结构，只改**值**：送达状态 JSON 的键与送达日志的 tag 从「显示名」
  // （webhook:企业微信 / 邮件 / Blocked，随语言变）改写为稳定键 chan:<slug>。
  // 迁移跑在 onUpgrade 里，而 onUpgrade 抛错的后果是「备份原库 + 重建空库」=
  // 用户历史被清，所以坏数据必须跳过而不是抛出。
  group('v11 送达键去本地化迁移', () {
    Future<Database> openV10WithLegacyData() async {
      final db = await openAt(
        10,
        onCreate: (d, v) => helper.createSchemaForTest(d),
      );
      Future<void> notif(String id, String? info) =>
          db.insert('notifications', {
            'id': id,
            'title': 't',
            'content': 'c',
            'package_name': 'com.x',
            'app_name': 'X',
            'post_time': 1,
            'time': '00:00',
            'type': 'notification',
            'timestamp': 1,
            'created_at': 1,
            'delivery_info': info,
          });
      await notif(
        'n-legacy',
        '{"webhook:企业微信":{"status":"success","message":"ok"},'
            '"邮件":{"status":"pending","message":""},'
            '"过滤拦截":{"status":"intercepted","message":"黑名单"}}',
      );
      await notif('n-already', '{"chan:feishu":{"status":"success"}}');
      await notif('n-broken', '{"webhook:钉钉"'); // 坏 JSON：跳过，不抛
      await notif('n-null', null);

      Future<void> log(String? tag) => db.insert('webhook_delivery_log', {
        'channel_url': 'https://example.com/hook',
        'notification_id': 'n-legacy',
        'tag': tag,
        'status': 'success',
        'http_code': 200,
        'message': 'ok',
        'retryable': 0,
        'timestamp': 1,
      });
      // 同一通道在旧库里可能因切换语言留下中英两个拼写
      await log('webhook:钉钉');
      await log('webhook:DingTalk');
      await log('过滤拦截');
      await log('chan:slack');
      await log(null);
      return db;
    }

    Future<Map<String, String>> deliveryInfoOf(Database db) async {
      final rows = await db.query('notifications', orderBy: 'id');
      return {
        for (final r in rows)
          r['id'].toString(): r['delivery_info']?.toString() ?? '',
      };
    }

    Future<List<String?>> tagsOf(Database db) async {
      final rows = await db.rawQuery(
        'SELECT tag FROM webhook_delivery_log ORDER BY id',
      );
      return rows.map((r) => r['tag']?.toString()).toList();
    }

    test('本地化键/tag 改写为 chan: 键；坏 JSON 与 NULL 原样保留', () async {
      final db = await openV10WithLegacyData();
      await helper.upgradeSchemaForTest(db, 10, 11);

      final info =
          jsonDecode((await deliveryInfoOf(db))['n-legacy']!)
              as Map<String, dynamic>;
      expect(info.keys.toSet(), {
        'chan:wechat_work',
        'chan:email',
        'chan:blocked',
      });
      expect(info['chan:wechat_work'], {'status': 'success', 'message': 'ok'});

      final tags = await tagsOf(db);
      expect(tags[0], 'chan:dingtalk');
      expect(tags[1], 'chan:dingtalk', reason: '中英双拼写归并为同一键');
      expect(tags[2], 'chan:blocked');
      expect(tags[3], 'chan:slack', reason: '已归一的值不得再改写');
      expect(tags[4], isNull);

      final untouched = await deliveryInfoOf(db);
      expect(untouched['n-broken'], '{"webhook:钉钉"', reason: '坏 JSON 应跳过');
      expect(untouched['n-null'], isEmpty);
      await db.close();
    });

    test('幂等：重复执行结果不变（升级链可能跑第二遍）', () async {
      final db = await openV10WithLegacyData();
      await helper.upgradeSchemaForTest(db, 10, 11);
      final first = await deliveryInfoOf(db);
      final firstTags = await tagsOf(db);
      // 先确认第一次确实改写了——否则"两次相同"在迁移被关掉时也恒为真
      expect(first['n-legacy'], contains('chan:wechat_work'));

      await helper.upgradeSchemaForTest(db, 10, 11);
      expect(await deliveryInfoOf(db), first);
      expect(await tagsOf(db), firstTags);
      await db.close();
    });

    test('库里没有送达信息时不写入、不抛错', () async {
      final db = await openAt(
        10,
        onCreate: (d, v) => helper.createSchemaForTest(d),
      );
      await helper.upgradeSchemaForTest(db, 10, 11);
      expect(await db.query('notifications'), isEmpty);
      await db.close();
    });
  });

  // 三张通道表的保存都是「整表 delete + 逐行 insert」，行主键 id 缺失时必须兜底生成。
  // 写成空串会让多行共用同一个 ''，后一条 replace 掉前一条 —— 保存一次静默丢通道。
  group('通道保存的 id 兜底（三表同规则）', () {
    final src = stripComments(
      File('lib/database/database_helper.dart').readAsStringSync(),
    );

    // 锚点必须带上实现签名（含 `async {`）：文件里同名**抽象声明**在前，
    // 只匹配方法名的话 blockAfter 会从接口声明处起算，取到的是整个类的开头几行。
    for (final sig in [
      'Future<void> saveEmailChannels(List<Map<String, dynamic>> channels) async {',
      'Future<void> saveWebhookChannels(List<Map<String, dynamic>> channels) async {',
      'Future<void> saveAppChannels(List<Map<String, dynamic>> channels) async {',
    ]) {
      test('$sig 缺 id 时生成，不落空主键', () {
        final body = blockAfter(src, sig);
        expect(body, contains('rawId'), reason: '$sig 没有 id 兜底分支：新增行会拿到空主键');
        expect(
          body,
          isNot(contains("'id': c['id'] ?? ''")),
          reason: "写死 c['id'] ?? '' ⇒ 两条无 id 的行同主键，保存即丢一条",
        );
      });
    }
  });
}
