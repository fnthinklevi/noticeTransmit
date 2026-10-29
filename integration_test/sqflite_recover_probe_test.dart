import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
// 探针要绕开 Dart 层的 singleInstance 缓存，直接走 doOpen —— 只有那一步会
// 调原生 openDatabase 并读到 recoveredInTransaction。
// ignore: implementation_imports
import 'package:sqflite_common/src/database.dart' as sqflite_impl;
// ignore: implementation_imports
import 'package:sqflite_common/src/factory_mixin.dart' as sqflite_impl;
import 'package:sqflite_sqlcipher/sqflite.dart';

/// vendored sqflite_common 补丁的设备侧证据（2026-10-29 真机数据库打不开）。
///
/// 场景就是真机上的那一个：一个连接在事务中（原生 `inTransaction=true`），
/// 另一个 Dart 侧打开同一路径 ⇒ 原生返回 `recoveredInTransaction=true`。
///
/// ⚠ 不能在同 isolate 里调第二次 `openDatabase`：`SqfliteDatabaseOpenHelper`
/// 会把已打开的实例直接返回，根本不进原生 recover 分支（假绿）。这里直接
/// `helper.newDatabase(path).doOpen(...)`，绕开那层缓存，逼原生走 recover。
/// 补丁前：`(options as SqfliteOpenDatabaseOptions)` 抛 CastError，ROLLBACK
/// 永远发不出去；补丁后：按旧行为 ROLLBACK，打开继续。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('闸门 9/9 sqflite 残留事务恢复探针：再次打开时回滚，不抛类型转换错误', (tester) async {
    final dir = await getDatabasesPath();
    final path = p.join(
      dir,
      'recover_probe_${DateTime.now().microsecondsSinceEpoch}.db',
    );
    const password = 'fnthink-recover-probe-key';

    final first = await openDatabase(
      path,
      password: password,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('CREATE TABLE probe (id INTEGER PRIMARY KEY, v TEXT)');
      },
    );

    final factory = databaseFactory as sqflite_impl.SqfliteDatabaseFactoryMixin;
    final helper = factory.databaseOpenHelpers[path];
    expect(helper, isNotNull, reason: '第一次 open 必须留下 Dart 层 helper');

    final inserted = Completer<void>();
    final holdTransaction = Completer<void>();
    final transaction = first.transaction((txn) async {
      await txn.insert('probe', {'v': 'uncommitted'});
      inserted.complete();
      // 停在这里：让原生保持 inTransaction=true，第二次 doOpen 才会走 recover。
      await holdTransaction.future;
    });
    await inserted.future;

    sqflite_impl.SqfliteDatabase? opened;
    try {
      // 补丁前这里直接抛 CastError（测试名就是这条判据）。
      opened = await helper!
          .newDatabase(path)
          .doOpen(SqlCipherOpenDatabaseOptions(password: password));
      expect(
        await opened.query('probe'),
        isEmpty,
        reason: '打开时应当回滚悬挂事务，未提交行不许留下',
      );
      await opened.insert('probe', {'v': 'after-recover'});
      expect(await opened.query('probe'), hasLength(1));
    } finally {
      if (opened != null) {
        await opened.doClose();
      }
      factory.removeDatabaseOpenHelper(path);
      holdTransaction.complete();
      try {
        // 底层事务已被 ROLLBACK，回调返回后的 COMMIT 必然失败；那是本用例的
        // 预期收尾，不是产品错误。
        await transaction;
      } catch (_) {
        // expected
      }
      try {
        await first.close();
      } catch (_) {
        // 与 opened 共享原生单实例；opened.doClose() 已关闭底层连接。
      }
      await deleteDatabase(path);
    }
  });
}
