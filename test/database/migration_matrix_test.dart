import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_setup.dart';

/// T184 片1：迁移矩阵守卫 —— **每个**历史 schema 版本起点都要收敛到「全新建库」的同一形状。
///
/// 背景见 database_helper_test.dart 头注：任何 onUpgrade 抛错 = `_initDatabase` 把库改名
/// `.corrupt-*` 再重建空库 = 用户历史与库内通道配置静默清空。既有用例盯的是**单条分支**
/// （3→N 重复调用、inbox / pair_requests / engine_rules 的局部老库 fixture），本文件把面拉开：
///
///   ① 全新建库（`createSchemaForTest`）取一份「标准形状」快照（全部表 × 逐列 + 全部索引）；
///   ② 对 v = 0 .. dbVersion-1 的每个起点重演迁移，断言：不抛 + 终形与标准快照逐项相等。
///      v=0 是**空库起点**（真实老设备里 v1 之前的样子，走 `oldVersion < 1 → _onCreate` 分支）；
///      v≥1 是**全量形状贴旧版本号**起点 —— 这正是历史上出过 duplicate column 事故的形态
///      （迁移期用 version:3 建全量 schema 库），也覆盖「存量库被错号标记」后每次启动重演的路径。
///
/// 这一刀拦的缺陷类别：未守卫的 `ALTER TABLE ADD COLUMN`、漏 `IF NOT EXISTS` 的
/// `CREATE TABLE/INDEX`、迁移语句没做表存在性判定 —— 全部是「打开即丢数据」级别。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initTestDatabase);

  final helper = DatabaseHelper();
  const maxV = DatabaseHelper.dbVersion;
  late Directory tmp;
  late String templatePath;
  late Map<String, Object?> reference;

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('nt-mig-matrix');
    templatePath = p.join(tmp.path, 'template.db');
    final db = await databaseFactory.openDatabase(templatePath);
    await helper.createSchemaForTest(db);
    reference = await _snapshot(db);
    await db.close();
  });

  tearDownAll(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('标准形状：全新建库至少包含核心三表，且 user_version 不参与对账', () {
    final tables = (reference['tables'] as Map<String, List<dynamic>>).keys
        .toSet();
    expect(
      tables,
      containsAll(<String>[
        'notifications',
        'webhook_channels',
        'email_channels',
      ]),
    );
  });

  // v=0：空库起点（先建后迁的完整链路）
  test('迁移矩阵 v=0（空库起点）→ $maxV 收敛到全新建库形状', () async {
    final path = p.join(tmp.path, 'v0.db');
    final db = await databaseFactory.openDatabase(path);
    await helper.upgradeSchemaForTest(db, 0, maxV);
    final snap = await _snapshot(db);
    expect(snap, reference, reason: '空库起点 onUpgrade(0→$maxV) 未收敛到全新建库形状');
    await db.close();
  });

  // v=1..26：全量形状贴旧版本号（历史事故形态），每档一个独立用例——
  // 红的时候点名是哪个版本起点，不用人工二分。
  for (var v = 1; v < maxV; v++) {
    test('迁移矩阵 v=$v（全量形状贴旧版本号）→ $maxV 收敛到全新建库形状', () async {
      final path = p.join(tmp.path, 'v$v.db');
      File(templatePath).copySync(path);
      final db = await databaseFactory.openDatabase(path);
      // 贴旧版本号 = 模拟「迁移期用旧 version 建的全量 schema 库」与「被错号标记的存量库」
      await db.rawQuery('PRAGMA user_version = $v');
      await helper.upgradeSchemaForTest(db, v, maxV);
      final snap = await _snapshot(db);
      expect(
        snap,
        reference,
        reason:
            '起点 v=$v 的 onUpgrade 未收敛到全新建库形状'
            '（常见根因：未守卫的 ALTER / 漏 IF NOT EXISTS / 迁移语句没做表存在性判定）',
      );
      await db.close();
    });
  }
}

/// 库形状快照：全部用户表 × 逐列（name/type/notnull/dflt/pk）+ 全部用户索引。
/// 键顺序无关，直接整体 equals 比较；不取 user_version（那是 sqflite openDatabase 的职责）。
Future<Map<String, Object?>> _snapshot(Database db) async {
  final master = await db.rawQuery(
    "SELECT name FROM sqlite_master"
    " WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
  );
  final tables = <String, List<Map<String, Object?>>>{};
  for (final row in master) {
    final name = row['name'] as String;
    final cols = await db.rawQuery('PRAGMA table_info($name)');
    tables[name] = cols
        .map(
          (r) => <String, Object?>{
            'name': r['name'],
            'type': r['type'],
            'notnull': r['notnull'],
            'dflt': r['dflt_value'],
            'pk': r['pk'],
          },
        )
        .toList();
  }
  final indexes = await db.rawQuery(
    "SELECT name, tbl_name, sql FROM sqlite_master"
    " WHERE type = 'index' AND name NOT LIKE 'sqlite_%' ORDER BY name",
  );
  return <String, Object?>{'tables': tables, 'indexes': indexes};
}
