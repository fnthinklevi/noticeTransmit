import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// P1-1：迁移前自动快照的命名、复用与跳过规则。
///
/// 为什么这些用例值得存在：迁移失败时的全部退路都压在这份快照上。快照没拍、
/// 拍错版本、或者每次「重试」都堆一份整库副本，界面上的「恢复迁移前备份」就成了
/// 一个指向空气的按钮。这里不打开真库，只验文件层与版本标记的判据。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final helper = DatabaseHelper();
  late Directory dir;
  late String dbPath;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('nt-migration-snapshot');
    dbPath = p.join(dir.path, 'notice_transmit_encrypted.db');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> writeBundle() async {
    await File(dbPath).writeAsBytes(const [1, 2, 3]);
    await File('$dbPath-wal').writeAsBytes(const [4, 5]);
    await File('$dbPath-shm').writeAsBytes(const [6]);
  }

  Future<List<String>> snapshotNames() async {
    final out = <String>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.endsWith('-wal') || name.endsWith('-shm')) continue;
      if (name.contains('.pre_v')) out.add(name);
    }
    return out;
  }

  test('版本标记缺失时拍快照，主文件与 WAL 旁车一起复制', () async {
    await writeBundle();

    final snapshot = await helper.snapshotBeforeMigrationForTest(dbPath);

    expect(snapshot, isNotNull, reason: '存量用户第一次升级时标记必然缺失，必须保守地拍一份');
    expect(snapshot, contains('.pre_vunknown_'));
    expect(await File(snapshot!).readAsBytes(), const [1, 2, 3]);
    expect(await File('$snapshot-wal').readAsBytes(), const [4, 5]);
    expect(await File('$snapshot-shm').readAsBytes(), const [6]);
  });

  test('标记等于当前 dbVersion 时不拍快照', () async {
    await writeBundle();
    SharedPreferences.setMockInitialValues({
      'db_last_opened_version': DatabaseHelper.dbVersion,
    });

    expect(await helper.snapshotBeforeMigrationForTest(dbPath), isNull);
    expect(await snapshotNames(), isEmpty);
  });

  test('同一旧版本重试复用同一份快照，不堆多份整库副本', () async {
    await writeBundle();
    SharedPreferences.setMockInitialValues({
      'db_last_opened_version': DatabaseHelper.dbVersion - 1,
    });

    final first = await helper.snapshotBeforeMigrationForTest(dbPath);
    final second = await helper.snapshotBeforeMigrationForTest(dbPath);

    expect(first, isNotNull);
    expect(second, first, reason: '每次重试都新拍一份会让恢复入口指向不确定的原件');
    expect(await snapshotNames(), hasLength(1));
  });

  test('库文件不存在时不拍快照（首次启动没有历史可回滚）', () async {
    expect(await helper.snapshotBeforeMigrationForTest(dbPath), isNull);
    expect(await snapshotNames(), isEmpty);
  });
}
