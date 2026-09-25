import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/services/engine_rule_codec.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';

import '../support/source_guards.dart';
import '../test_setup.dart';

/// T20：通知引擎规则表 `engine_rules` 的建表、一次性导入与真实 CRUD。
///
/// 为什么这些用例必须跑真 SQL 而不是注入 fake 存储：这一族里最会咬人的三个错法都是
/// SQL 层的 —— ① 整族替换写成整表 `delete`（照抄 `saveAppChannels` 就会"存电量丢温度"）；
/// ② 导入用 replace 而不是 ignore（第二次跑迁移会把用户改过的阈值洗回旧值）；
/// ③ `threshold` 落成 REAL（电量页 `rule['value'] as int` 当场抛）。
/// fake 存储里这三条**一条都测不出来**，因为它自己就是断言的一部分。
///
/// 另外钉住的是"两处建表最终列一致"这条老不变量：`_onCreate` 与 `oldVersion < 13`
/// 任何一处漏改，表现都是"新装设备正常、升级设备保存规则直接 no such table/column"。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabase();

  final helper = DatabaseHelper();
  late final String dbPath;

  /// ⚠ 源码扫描一律**惰性**（在测试体里才读文件）：锚点找不到时若在 `main()` 顶层抛，
  ///   CI 表现是"这个文件没有用例"而不是红（base.md（75）撞过两次）。
  ///   锚点也不写返回类型/可见性 —— `Future<void> _createEngineRules` 改成别的写法
  ///   不该让守卫以为建表没了。
  String dbSource() => stripComments(
    File(
      '${projectRoot()}/lib/database/database_helper.dart',
    ).readAsStringSync(),
  );
  int engineRuleCreateSites() => RegExp(
    r'CREATE TABLE IF NOT EXISTS engine_rules \(',
  ).allMatches(dbSource()).length;
  int engineRuleCreateCallers() =>
      RegExp(r'await _createEngineRules\(db\);').allMatches(dbSource()).length;

  setUpAll(() async {
    dbPath = join(await getDatabasesPath(), 'engine_rules_schema_test.db');
  });

  tearDown(() => helper.debugDatabase = null);

  tearDownAll(() async {
    helper.debugDatabase = null;
    if (await databaseFactory.databaseExists(dbPath)) {
      await databaseFactory.deleteDatabase(dbPath);
    }
  });

  /// 干净的库：删档重建，**不**自动建表（建表时机由用例自己控制，导入要的是
  /// "先摆好旧键、再建表"这个顺序）。
  Future<Database> emptyDb() async {
    if (await databaseFactory.databaseExists(dbPath)) {
      await databaseFactory.deleteDatabase(dbPath);
    }
    return databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(version: DatabaseHelper.dbVersion),
    );
  }

  Future<Set<String>> columnsOf(Database db) async {
    final rows = await db.rawQuery('PRAGMA table_info(engine_rules)');
    return rows.map((r) => r['name'].toString()).toSet();
  }

  Future<int> rowCount(Database db, String family) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM engine_rules WHERE family = ?',
      [family],
    );
    return (rows.single['c'] as num).toInt();
  }

  group('engine_rules 建表', () {
    test('建表只有一处定义，但两处入口都调它（_onCreate 与 v13 升级）', () {
      // 单一建表函数 = 两处不可能写出不一致的列；但**调用点**必须是两处，
      // 否则"老库升级"那条路拿不到表（新装正常、升级即崩就是这类错法的表现）。
      expect(engineRuleCreateSites(), 1, reason: '建表 SQL 被复制成了多处');
      expect(
        engineRuleCreateCallers(),
        2,
        reason: '_onCreate 或 oldVersion<13 少了一处',
      );
    });

    test('新建库有 engine_rules，列集合是契约那 9 列', () async {
      SharedPreferences.setMockInitialValues({});
      final db = await emptyDb();
      await helper.createSchemaForTest(db);
      expect(await columnsOf(db), {
        'family',
        'position',
        'id',
        'type',
        'threshold',
        'title',
        'content',
        'enabled',
        'updated_at',
      });
      await db.close();
    });

    test('v12 老库升上来：最终列与新建库逐字一致', () async {
      // 新建库
      SharedPreferences.setMockInitialValues({});
      final fresh = await emptyDb();
      await helper.createSchemaForTest(fresh);
      final freshCols = await columnsOf(fresh);
      await fresh.close();

      // "v12 形状"的库：全量 schema 减掉本表，再走 12→13
      final old = await emptyDb();
      await helper.createSchemaForTest(old);
      await old.execute('DROP TABLE engine_rules');
      expect(await columnsOf(old), isEmpty, reason: '锚点：表没建出来，本用例就是空转');
      await helper.upgradeSchemaForTest(old, 12, 13);
      expect(
        await columnsOf(old),
        freshCols,
        reason: '两条路径列不一致 ⇒ 升级设备保存规则会报 no such column',
      );
      await old.close();
    });
  });

  group('v13 一次性导入（prefs 旧键 → 表）', () {
    Future<Database> upgradedWith({
      String? batteryRules,
      String? temperatureRules,
    }) async {
      SharedPreferences.setMockInitialValues({
        'battery_rules': ?batteryRules,
        'temperature_rules': ?temperatureRules,
      });
      final db = await emptyDb();
      await helper.createSchemaForTest(db);
      await db.execute('DROP TABLE engine_rules');
      await helper.upgradeSchemaForTest(db, 12, 13);
      return db;
    }

    test('两族都搬进来，各族 position 从 0 连续、顺序照旧', () async {
      final db = await upgradedWith(
        batteryRules:
            '[{"id":"low20","type":"level_below","value":20,"enabled":true,"title":"低电量"},'
            '{"id":"charging","type":"charging","value":0,"enabled":false,"title":"充电"}]',
        temperatureRules:
            '[{"id":"t1","type":"device_temp_above","value":45,"enabled":true,"title":"过热"}]',
      );
      expect(await rowCount(db, EngineRuleCodec.familyBattery), 2);
      expect(await rowCount(db, EngineRuleCodec.familyTemperature), 1);

      final rows = await db.rawQuery(
        'SELECT family, position, id, threshold, enabled, title '
        'FROM engine_rules WHERE family = ? ORDER BY position',
        [EngineRuleCodec.familyBattery],
      );
      expect(rows.map((r) => r['position']).toList(), [0, 1]);
      expect(rows.first['id'], 'low20');
      expect(rows.first['threshold'], 20);
      expect(rows.first['enabled'], 1);
      expect(rows.last['enabled'], 0, reason: '关掉的规则导入后必须还是关掉的');
      await db.close();
    });

    test('旧键缺失 / 坏 JSON / 认不出的条目：不抛，只跳过坏的那条', () async {
      // 迁移抛错的代价是"_initDatabase 备份原库 + 重建空库"= 用户历史整库被清，
      // 所以这里必须是"跳过"而不是"抛出"。
      final db = await upgradedWith(
        batteryRules: '{"不是数组"',
        temperatureRules:
            '[{"id":"t1","type":"device_temp_above","value":45,"enabled":true},'
            'null, "字符串条目"]',
      );
      expect(await rowCount(db, EngineRuleCodec.familyBattery), 0);
      expect(await rowCount(db, EngineRuleCodec.familyTemperature), 1);
      await db.close();
    });

    test('缺 type/value/enabled 时按原生读取侧那套缺省补齐', () async {
      // `BatteryMonitor.parseBatteryRules` 用的是 optString/optInt/optBoolean + 这些默认，
      // 补齐成同一套才等于"入 DB 这一步不改变任何人的告警行为"。
      final db = await upgradedWith(
        batteryRules: '[{}]',
        temperatureRules: '[{"value":45.6}]',
      );
      final battery = (await db.query(
        'engine_rules WHERE family = ?',
        whereArgs: [EngineRuleCodec.familyBattery],
      )).single;
      expect(battery['type'], 'level_below');
      expect(battery['threshold'], 20);
      expect(
        battery['enabled'],
        1,
        reason: '缺 enabled 视为启用（原生 optBoolean 同口径）',
      );

      final temp = (await db.query(
        'engine_rules WHERE family = ?',
        whereArgs: [EngineRuleCodec.familyTemperature],
      )).single;
      expect(temp['type'], 'battery_temp_above');
      expect(
        temp['threshold'],
        45,
        reason: 'Double 阈值必须落 INTEGER，否则电量页 as int 当场抛',
      );
      expect(
        temp['enabled'],
        1,
        reason: '缺 enabled 一律算启用（原生 optBoolean 的默认值），两族同口径',
      );
      await db.close();
    });

    test('幂等：同一升级跑两遍不重复行，也不会把库里的改动洗回旧值', () async {
      final db = await upgradedWith(
        batteryRules:
            '[{"id":"low20","type":"level_below","value":20,"enabled":true}]',
      );
      await helper.upgradeSchemaForTest(db, 12, 13);
      expect(await rowCount(db, EngineRuleCodec.familyBattery), 1);

      // 用户改过阈值之后再跑一遍迁移：ignore 才不会被旧键里的值盖回去
      await db.execute('UPDATE engine_rules SET threshold = 99');
      await helper.upgradeSchemaForTest(db, 12, 13);
      expect(
        await rowCount(db, EngineRuleCodec.familyBattery),
        1,
        reason: '重复导入插出了第二行（迁移没幂等）',
      );
      final kept = await db.query('engine_rules');
      expect(
        kept.single['threshold'],
        99,
        reason: '用 replace 重放迁移 = 把用户改过的规则洗回旧值',
      );
      await db.close();
    });

    test('建库路径也会导入（旧明文库→加密库那条路没有 onUpgrade）', () async {
      SharedPreferences.setMockInitialValues({
        'battery_rules':
            '[{"id":"low20","type":"level_below","value":20,"enabled":true}]',
      });
      final db = await emptyDb();
      await helper.createSchemaForTest(db);
      expect(
        await rowCount(db, EngineRuleCodec.familyBattery),
        1,
        reason: '只把导入挂在 onUpgrade 上，会漏掉"库里没有加密库文件"的设备',
      );
      await db.close();
    });
  });

  // 下面走的是 EngineRuleStore 的真实实现（helper.debugDatabase 指到本文件的 ffi 库）。
  group('EngineRuleStore CRUD（真 SQL）', () {
    late Database db;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = await emptyDb();
      await helper.createSchemaForTest(db);
      await db.execute('DELETE FROM engine_rules');
      helper.debugDatabase = db;
    });

    test('整族替换只动本族（存电量不得丢温度）', () async {
      await helper.saveEngineRules(EngineRuleCodec.familyTemperature, [
        _rule('t1', 'device_temp_above', 45),
      ]);
      await helper.saveEngineRules(EngineRuleCodec.familyBattery, [
        _rule('low20', 'level_below', 20),
        _rule('low30', 'level_below', 30),
      ]);

      expect(
        await helper.getEngineRules(EngineRuleCodec.familyTemperature),
        hasLength(1),
        reason: 'saveEngineRules 若写成整表 delete（照抄 saveAppChannels），这里就是 0 条',
      );
      expect(
        await helper.getEngineRules(EngineRuleCodec.familyBattery),
        hasLength(2),
      );
    });

    test('回读顺序 = 列表顺序（引擎按此顺序判定，"顺序即优先级"）', () async {
      await helper.saveEngineRules(EngineRuleCodec.familyBattery, [
        _rule('a', 'level_below', 50),
        _rule('b', 'level_below', 20),
        _rule('c', 'charging', 0),
      ]);
      expect(
        (await helper.getEngineRules(
          EngineRuleCodec.familyBattery,
        )).map((r) => r['id']).toList(),
        ['a', 'b', 'c'],
      );
    });

    test('存的值与读出的值逐字段相同（bool/int 不被洗成 null）', () async {
      final wanted = {
        'id': 'r1',
        'type': 'level_below',
        'value': 33,
        'enabled': true,
        'title': '电量低于33%',
        'content': '自定义正文',
      };
      await helper.saveEngineRules(EngineRuleCodec.familyBattery, [wanted]);
      expect(
        (await helper.getEngineRules(EngineRuleCodec.familyBattery)).single,
        wanted,
      );
    });

    test('存空列表 = 清空该族，另一族原样留着', () async {
      await helper.saveEngineRules(EngineRuleCodec.familyBattery, [
        _rule('low20', 'level_below', 20),
      ]);
      await helper.saveEngineRules(EngineRuleCodec.familyTemperature, [
        _rule('t1', 'device_temp_above', 45),
      ]);
      await helper.saveEngineRules(EngineRuleCodec.familyBattery, []);

      expect(
        await helper.getEngineRules(EngineRuleCodec.familyBattery),
        isEmpty,
      );
      expect(
        await helper.getEngineRules(EngineRuleCodec.familyTemperature),
        hasLength(1),
      );
    });

    test('同族两条同 id 的规则能共存（列表语义，id 不是主键）', () async {
      // 页面用毫秒时间戳生成 id，历史上"同 id 一起删"是既有语义；把 id 设成主键
      // 会让第二条静默覆盖第一条 = 保存一次丢一条规则。
      await helper.saveEngineRules(EngineRuleCodec.familyBattery, [
        _rule('dup', 'level_below', 20),
        _rule('dup', 'level_below', 10),
      ]);
      final back = await helper.getEngineRules(EngineRuleCodec.familyBattery);
      expect(back, hasLength(2));
      expect(back.map((r) => r['value']).toList(), [20, 10]);
    });
  });

  group('EngineRuleCodec', () {
    test('normalize 的输出键与 uiKeys 逐字一致（契约名单本身不许漂）', () {
      final one = EngineRuleCodec.normalize(const {
        'id': 'x',
      }, EngineRuleCodec.familyBattery)!;
      expect(one.keys.toSet(), EngineRuleCodec.uiKeys.toSet());
    });

    test('toLegacyJson 的每条都带全部 uiKeys（原生按这些键取值，缺一个就用默认）', () {
      final decoded =
          jsonDecode(
                EngineRuleCodec.toLegacyJson([
                  EngineRuleCodec.normalize(const {
                    'id': 'x',
                  }, EngineRuleCodec.familyBattery)!,
                ]),
              )
              as List;
      expect(
        (decoded.single as Map).keys.toSet(),
        EngineRuleCodec.uiKeys.toSet(),
        reason: '镜像少键 ⇒ 原生 optXxx 拿默认值，用户的阈值悄悄换了个数',
      );
    });

    test('null / 非 Map / 非数组 一律不要凭空造规则', () {
      expect(EngineRuleCodec.normalize(null, 'battery'), isNull);
      expect(EngineRuleCodec.normalize('规则', 'battery'), isNull);
      expect(EngineRuleCodec.parseLegacyJson('{"id":"x"}', 'battery'), isNull);
      expect(EngineRuleCodec.parseLegacyJson('', 'battery'), isNull);
      expect(EngineRuleCodec.parseLegacyJson(null, 'battery'), isNull);
      // 空数组不是 null：那是"用户删空了"，不许再播默认规则
      expect(
        EngineRuleCodec.parseLegacyJson('[]', 'battery'),
        isEmpty,
        reason: 'null 与 [] 必须分得开',
      );
    });
  });
}

Map<String, dynamic> _rule(String id, String type, int value) => {
  'id': id,
  'type': type,
  'value': value,
  'enabled': true,
  'title': '',
  'content': '',
};
