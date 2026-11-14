import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// T253：**有界**锁等待的机制证据（真 SQLite，不走平台通道）。
///
/// 真机链条（2026-11-14）：插件 `singleInstance` 缺省 true ⇒ 跨 isolate 复用同一条
/// 连接；后台引擎死在事务中途，那条连接与它的事务不被 detach 关掉 ⇒ 前台再写就排在
/// 它后面等框架连接池，而那个等待**没有超时**（splash 永远停在「加载通知记录」）。
///
/// 改法两层：① 调用点 `singleInstance: false`（各持一条连接，不再排别人的事务）；
/// ② 开库后 `PRAGMA busy_timeout`（锁冲突退化成**有界**的 SQLITE_BUSY）。
/// 本用例钉的是第 ② 层：另一条连接持有写事务时，本连接必须在期限附近**报错**，
/// 而不是无限等 —— 那正是"界面能显式报错并给出恢复入口"的前提。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  test('另一条连接持写事务时，本连接在 busy_timeout 附近报错而不是无限等', () async {
    final dir = Directory.systemTemp.createTempSync('nt-busy-timeout');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final path = join(dir.path, 'busy.db');
    final options = OpenDatabaseOptions(singleInstance: false);

    final a = await databaseFactoryFfi.openDatabase(path, options: options);
    final b = await databaseFactoryFfi.openDatabase(path, options: options);
    addTearDown(() async {
      if (a.isOpen) await a.close();
      if (b.isOpen) await b.close();
    });

    await a.execute('CREATE TABLE t (id INTEGER PRIMARY KEY)');
    // b 的锁等待上界：与 DatabaseHelper.busyTimeoutMs 同一个机制，这里缩到 300ms
    // 让用例跑得快；断言的是"有界"这件事，不是那个具体数字。
    await b.execute('PRAGMA busy_timeout = 300');

    // a 开一个写事务并**攥住 1.5 秒**（比 b 的 300ms 长得多）。
    final holder = a.transaction((txn) async {
      await txn.insert('t', {'id': 1});
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    });
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final sw = Stopwatch()..start();
    Object? err;
    try {
      await b.insert('t', {'id': 2});
    } catch (e) {
      err = e;
    }
    sw.stop();
    await holder;

    expect(
      err,
      isNotNull,
      reason:
          '另一条连接持有写事务时，本连接的写必须报错（busy_timeout 到期）——'
          '不报错说明它一直等到了对方放手，界面就会永远卡在"加载通知记录"',
    );
    expect(
      sw.elapsedMilliseconds,
      lessThan(1400),
      reason: '必须在持有者放手（1.5s）之前就回来：等到了 1.5s 说明这条写是无界的',
    );
    expect(
      sw.elapsedMilliseconds,
      greaterThanOrEqualTo(200),
      reason: '至少要等满 busy_timeout（300ms 的量级），否则测到的是别的原因',
    );
  });
}
