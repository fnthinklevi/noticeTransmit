import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/di/service_locator.dart';
import 'package:notice_transmit/models/fnthink_peer.dart';
import 'package:notice_transmit/services/fnthink_peer_service.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_setup.dart';

/// 配对名单的读咽喉（T42「配对名单」那一格的数据源）。
///
/// 这一层存在的唯一理由与收件咽喉同一条：**同一件事只许有一处算法**。排序口径（`granted_at DESC,
/// peer_address ASC`）如果被页面再抄一份，两处各自都"对"，但同一次同意之后谁在前会不一样；
/// 而页面绕过这层直连表时，全场测试仍然绿 —— 所以这里除了转发行为，还钉一条"它真的注册在 DI 里"。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabase();

  final helper = DatabaseHelper();
  final service = FnthinkPeerService();
  late String dbPath;

  setUpAll(() async {
    dbPath = join(await getDatabasesPath(), 'fnthink_peer_svc.db');
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

  FnthinkPeer peer(
    String address, {
    String level = 'L1',
    int at = 1780000000000,
    String publicKey = 'AAAA',
  }) => FnthinkPeer(
    peerAddress: address,
    publicKey: publicKey,
    level: level,
    grantedAt: at,
    requestId: 'pr_9',
  );

  group('只转发，不自造读法', () {
    test('空的名单 ⇒ 空列表（不是 null、不抛）', () async {
      expect(
        await service.list(),
        isEmpty,
        reason: '"还没有配对过"是一句可行动的真话，但前提是读得出来 —— 读失败要另说一句',
      );
    });

    test('新的在前；同一次同意里的 tie-breaker 来自表那一层', () async {
      await helper.upsertFnthinkPeer(peer('AAAAAAAAAAAAAAAAAAAA'));
      await helper.upsertFnthinkPeer(peer('BBBBBBBBBBBBBBBBBBBB'));
      await helper.upsertFnthinkPeer(
        peer('CCCCCCCCCCCCCCCCCCCC', at: 1780000999000),
      );
      final rows = await service.list();
      expect(
        rows.map((p) => p.peerAddress).toList(),
        [
          'CCCCCCCCCCCCCCCCCCCC',
          'AAAAAAAAAAAAAAAAAAAA',
          'BBBBBBBBBBBBBBBBBBBB',
        ],
        reason: '同毫秒时按地址码定序。少了它，页面自己排一次就会与这里的顺序不一样',
      );
    });

    test('协调者写进去那一种行，读回来逐字段还在（level 是服务端回的那一档）', () async {
      // 与 `confirmPairing` 落库时同一个形状：档位取服务端回的 grantedLevel，
      // 地址码是对端、公钥是请求里那把、requestId 带着当出处。
      await helper.upsertFnthinkPeer(
        peer(
          'DD4321DCBA98765432',
          level: 'L2',
          at: 1780000111000,
          publicKey: 'BBCC',
        ),
      );
      final one = (await service.list()).single;
      expect(one.peerAddress, 'DD4321DCBA98765432');
      expect(one.level, 'L2');
      expect(one.publicKey, 'BBCC');
      expect(one.grantedAt, 1780000111000);
      expect(one.requestId, 'pr_9');
    });
  });

  group('装配点', () {
    test('DI 里真的注册了它（漏接时全场仍绿，只有页面会退回去直连表）', () {
      setupLocator();
      expect(
        GetIt.instance<FnthinkPeerService>(),
        isA<FnthinkPeerService>(),
        reason:
            '服务层没注册 ⇒ 页面各自 new 一份或直接摸 DatabaseHelper，'
            '"一处读法"就又变成多处',
      );
    });
  });
}
