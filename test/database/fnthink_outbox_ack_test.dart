import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/models/fnthink_inbox_message.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_setup.dart';

/// P2-7：发件回执看守的第二个判据 —— `fnthink_messages` 里 out 档还有没有在等的。
///
/// 为什么必须跑真 SQL：判据全在 WHERE 那三行（方向、acked_at、保留期下限）。
/// 换成 fake 去测，等于只测"调用了一次方法"，而真正会错的是把 direction 写反、
/// 或把 `acked_at = 0` 写成 `<> 0`（后者让"已回执"的永远算在等）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabase();

  final helper = DatabaseHelper();
  late final String dbPath;
  const now = 1780000000000;
  const sevenDays = 7 * 86400000;

  setUpAll(() async {
    dbPath = join(await getDatabasesPath(), 'fnthink_outbox_ack_test.db');
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

  Future<void> freshDb() async {
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
  }

  FnthinkInboxMessage outRow(
    String id, {
    int ackedAt = 0,
    String ackResult = '',
    int receivedAt = now,
  }) => FnthinkInboxMessage(
    messageId: id,
    sender: 'PEER00000000000001',
    type: 'notice',
    item: '',
    title: '温度',
    body: '63 度',
    receivedAt: receivedAt,
    ackResult: ackResult,
    ackedAt: ackedAt,
    direction: kFnthinkDirectionOut,
  );

  test('out + 未 ack ⇒ 有在等的', () async {
    await freshDb();
    await helper.insertFnthinkInbox(outRow('m_wait'));
    expect(
      await helper.hasFnthinkOutboxAwaitingAck(sentAfterMs: now - sevenDays),
      isTrue,
    );
  });

  test('回执写进来（acked_at 与 ack_result 一起）⇒ 不再算在等', () async {
    await freshDb();
    await helper.insertFnthinkInbox(outRow('m_acked'));
    await helper.recordFnthinkInboxAck(
      messageId: 'm_acked',
      result: 'delivered',
      at: now + 1000,
    );
    expect(
      await helper.hasFnthinkOutboxAwaitingAck(sentAfterMs: now - sevenDays),
      isFalse,
    );
  });

  test('in 档的未 ack 行不算（它等的是本机自己报，不是对面回执）', () async {
    await freshDb();
    await helper.insertFnthinkInbox(
      const FnthinkInboxMessage(
        messageId: 'm_in',
        sender: 'PEER00000000000001',
        type: 'notice',
        item: '',
        title: '温度',
        body: '63 度',
        receivedAt: now,
        direction: kFnthinkDirectionIn,
      ),
    );
    expect(
      await helper.hasFnthinkOutboxAwaitingAck(sentAfterMs: now - sevenDays),
      isFalse,
    );
  });

  test('超过保留期的死行不算（服务端已过期，永远不会有回执）', () async {
    await freshDb();
    await helper.insertFnthinkInbox(
      outRow('m_old', receivedAt: now - sevenDays - 1),
    );
    expect(
      await helper.hasFnthinkOutboxAwaitingAck(sentAfterMs: now - sevenDays),
      isFalse,
    );
  });
}
