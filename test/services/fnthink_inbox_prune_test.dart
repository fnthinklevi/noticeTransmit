import 'package:flutter_test/flutter_test.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/models/fnthink_inbox_message.dart';
import 'package:notice_transmit/services/fnthink_inbox_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../test_setup.dart';

/// T47：收件保留。两层各钉各的 ——
/// ① `pruneFnthinkInbox` 那条 SQL（此前它是死代码，本条是它的第一个调用方）：
///    先删早于天数的、再把剩下的裁到条数（删最旧），两段删掉多少分开报；
/// ② `pruneRetention` 的接线：档位从 settings 读（缺省 30）、契约没装载 ⇒ 跳过不崩。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabase();

  final helper = DatabaseHelper();
  late Database db;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final path = p.join(
      await getDatabasesPath(),
      'fnthink_inbox_prune_test.db',
    );
    if (await databaseFactory.databaseExists(path)) {
      await databaseFactory.deleteDatabase(path);
    }
    db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: DatabaseHelper.dbVersion),
    );
    await helper.createSchemaForTest(db);
    helper.debugDatabase = db;
    addTearDown(() async {
      helper.debugDatabase = null;
      await db.close();
    });
  });

  Future<void> seed(String id, int receivedAt) => db.insert(
    FnthinkInboxMessage.table,
    FnthinkInboxMessage(
      messageId: id,
      sender: 'peer-a',
      type: 'notice',
      item: '',
      title: 't',
      body: 'b',
      receivedAt: receivedAt,
    ).toDbRow(),
  );

  const now = 1780000000000;

  test('pruneFnthinkInbox：先按天数删，再按条数删最旧，两段分开报', () async {
    await seed('old-1', now - 40 * 86400000);
    await seed('mid-1', now - 5 * 86400000);
    await seed('new-1', now);
    final r = await helper.pruneFnthinkInbox(
      olderThanDays: 30,
      maxRows: 2,
      now: now,
    );
    expect(r.byAge, 1, reason: '40 天前那条按天数裁掉');
    final left = await helper.loadFnthinkInbox();
    expect(left.map((m) => m.messageId), containsAll(['mid-1', 'new-1']));
    expect(left, hasLength(2), reason: '条数上限内，不再多删');
  });

  test('pruneFnthinkInbox：超条数裁最旧（保新的）', () async {
    await seed('a', now - 3000);
    await seed('b', now - 2000);
    await seed('c', now - 1000);
    final r = await helper.pruneFnthinkInbox(
      olderThanDays: 30,
      maxRows: 2,
      now: now,
    );
    expect(r.byAge, 0);
    expect(r.byCap, 1);
    final left = await helper.loadFnthinkInbox();
    expect(left.map((m) => m.messageId), [
      'c',
      'b',
    ], reason: '删的是最旧那条（收件列表新到的在前）');
  });

  test('非正数当场抛（按 0 执行 = 清空收件表）', () async {
    expect(
      () => helper.pruneFnthinkInbox(olderThanDays: 0, maxRows: 10),
      throwsArgumentError,
    );
    expect(
      () => helper.pruneFnthinkInbox(olderThanDays: 30, maxRows: 0),
      throwsArgumentError,
    );
  });

  test('pruneRetention：契约没装载 ⇒ 跳过（不崩，一条不裁）', () async {
    await seed('keep-1', now);
    final svc = FnthinkInboxService(db: helper);
    final r = await svc.pruneRetention();
    expect(r, (byAge: 0, byCap: 0));
    expect(await helper.loadFnthinkInbox(), hasLength(1));
  });

  test('pruneRetention：按 settings 那一档裁（缺省 30 天 + 资源闸 20000）', () async {
    final contract = FnthinkContract.readFile();
    // 生产那条路用的是真时钟（pruneRetention 不收 now）⇒ 种子相对现在造。
    final realNow = DateTime.now().millisecondsSinceEpoch;
    await seed('old-1', realNow - 40 * 86400000);
    await seed('new-1', realNow);
    final svc = FnthinkInboxService(db: helper, contract: contract);
    final r = await svc.pruneRetention();
    expect(r.byAge, 1, reason: '缺省档 30 天：40 天前那条裁掉');
    final left = await helper.loadFnthinkInbox();
    expect(left.map((m) => m.messageId), ['new-1']);
  });
}
