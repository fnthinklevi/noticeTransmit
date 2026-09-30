import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/di/service_locator.dart';
import 'package:notice_transmit/models/fnthink_inbox_message.dart';
import 'package:notice_transmit/services/fnthink_inbox_service.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_setup.dart';

/// 收件读写咽喉（T48 数据层）。
///
/// 这里钉两件事，各有一个"没有这层会怎样"：
///  ① 服务**不自己实现读**，只转发到 `DatabaseHelper` —— 排序与"命中与否"的语义必须与表那一层
///     同源；两处各写一份，早晚有一处忘了 `message_id` 那个 tie-breaker（翻页重叠就是这么来的）；
///  ② 它注册在 DI 里。装配点漏接时全场测试仍然绿，只有这条会红（本仓那类"只有漏接才现形"的形状）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabase();

  final helper = DatabaseHelper();
  final service = FnthinkInboxService();
  late String dbPath;

  setUpAll(() async {
    dbPath = join(await getDatabasesPath(), 'fnthink_inbox_svc.db');
  });

  setUp(() async {
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
  });

  tearDown(() async {
    helper.debugDatabase = null;
    await GetIt.instance.reset();
  });

  tearDownAll(() async {
    if (await databaseFactory.databaseExists(dbPath)) {
      await databaseFactory.deleteDatabase(dbPath);
    }
  });

  FnthinkInboxMessage row(
    String id, {
    int at = 1780000000000,
    bool read = false,
    String direction = kFnthinkDirectionIn,
    String sender = 'endpoint:ep_7',
  }) => FnthinkInboxMessage(
    messageId: id,
    sender: sender,
    type: 'notice',
    item: '',
    title: '机箱温度',
    body: '温度 63 度（$id）',
    receivedAt: at,
    read: read,
    direction: direction,
  );

  group('转发而非自造', () {
    test('list 的排序与分页口径来自表那一层（同毫秒要有 tie-breaker）', () async {
      await helper.insertFnthinkInbox(row('m_b', at: 1780000000000));
      await helper.insertFnthinkInbox(row('m_a', at: 1780000000000));
      await helper.insertFnthinkInbox(row('m_new', at: 1780000009999));
      final all = await service.list();
      expect(
        all.map((m) => m.messageId).toList(),
        ['m_new', 'm_a', 'm_b'],
        reason: '新的在前；同毫秒按 message_id 定序 —— 没有它翻页会出现同一条来两遍',
      );
      final page = await service.list(limit: 2, offset: 2);
      expect(page.map((m) => m.messageId).toList(), ['m_b']);
    });

    test('markRead 命中回 true 并真的改了表；再标一次仍然 true（幂等不是"没命中"）', () async {
      await helper.insertFnthinkInbox(row('m_1'));
      expect(await service.markRead('m_1'), isTrue);
      final after = await service.list();
      expect(after.single.read, isTrue);
      expect(await service.markRead('m_1'), isTrue);
    });

    test('标一条不存在的 ⇒ 回 false（调用方要的是消失，不是记已读）', () async {
      expect(
        await service.markRead('gone'),
        isFalse,
        reason: '给不存在的那行记已读 = 未读数被凭空减掉',
      );
    });

    test('unreadCount 数的是未读那几行，且与 list(unreadOnly) 同一个口径', () async {
      await helper.insertFnthinkInbox(row('m_1'));
      await helper.insertFnthinkInbox(row('m_2'));
      await helper.insertFnthinkInbox(row('m_3'));
      await service.markRead('m_2');
      expect(
        await service.unreadCount(),
        2,
        reason: '读掉一条就少一条 —— 首页那一格与收件档必须报同一个数',
      );
      final unreadRows = await service.list(unreadOnly: true);
      expect(unreadRows.length, await service.unreadCount());
    });

    test('空表 ⇒ 未读数 0（不是 null、不抛）', () async {
      expect(await service.unreadCount(), 0);
    });
  });

  group('方向两档（T43：收件 / 我发过的）', () {
    test('listSent 只给发出那半，list 只给收件那半（同一张表两条账）', () async {
      await helper.insertFnthinkInbox(row('m_in'));
      await helper.insertFnthinkInbox(
        row(
          'm_out',
          direction: kFnthinkDirectionOut,
          sender: 'PEER00000000000001',
        ),
      );

      final inbox = await service.list();
      expect(inbox.map((m) => m.messageId), ['m_in']);
      final sent = await service.listSent();
      expect(sent.map((m) => m.messageId), ['m_out']);
      expect(
        sent.single.sender,
        'PEER00000000000001',
        reason: '发出那一行的 sender 是**收件人**（含义随方向变，见模型注释）',
      );
    });

    test('未读数只数收件：把发出的一条也数进来，表现是"回一条消息、首页未读多一条"', () async {
      await helper.insertFnthinkInbox(row('m_in'));
      await helper.insertFnthinkInbox(
        row('m_out', direction: kFnthinkDirectionOut, read: false),
      );

      expect(
        await service.unreadCount(),
        1,
        reason: '发出的一条没有"未读"这回事 —— 未读是别人推给我、我还没看的那个数',
      );
    });

    test('未读过滤也分方向：list(unreadOnly) 不会把发出的未读行捞进来', () async {
      await helper.insertFnthinkInbox(
        row('m_out', direction: kFnthinkDirectionOut),
      );
      expect(await service.list(unreadOnly: true), isEmpty);
    });
  });

  group('装配点', () {
    test('DI 里真的注册了它（漏接时全场仍绿，所以只能靠这条）', () {
      setupLocator();
      expect(
        GetIt.instance<FnthinkInboxService>(),
        isA<FnthinkInboxService>(),
        reason: '服务层没注册 ⇒ 页面会退回去各自 new 一份，"一处算法"就又变成多处',
      );
    });
  });
}
