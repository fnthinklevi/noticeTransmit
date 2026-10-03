import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/di/service_locator.dart';
import 'package:notice_transmit/models/fnthink_peer.dart';
import 'package:notice_transmit/services/fnthink_contract_loader.dart';
import 'package:notice_transmit/services/fnthink_peer_service.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_setup.dart';

/// 配对名单的读写咽喉（T42「配对名单」那一格的数据源 + T31 B 片那一下撤销的落点）。
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

  group('删行也只转发（T31 B 片第二片）', () {
    test('删得掉 ⇒ 回 true，再读一次名单里就没那一行了', () async {
      await helper.upsertFnthinkPeer(peer('EEEEEEEEEEEEEEEEEEEE'));
      expect(await service.remove('EEEEEEEEEEEEEEEEEEEE'), isTrue);
      expect(await service.list(), isEmpty);
    });

    test('删一条本来没有的 ⇒ 回 false，不抛（撤销是幂等的那一半）', () async {
      expect(
        await service.remove('FFFFFFFFFFFFFFFFFFFF'),
        isFalse,
        reason:
            '这一层分不清"没撤成"与"那边本来就没有"，那是协调者与页面的事；'
            '这里若抛，页面就只能把一次幂等的撤销显示成失败',
      );
    });

    test('只删点到的那一行，别的原样留着', () async {
      await helper.upsertFnthinkPeer(peer('GGGGGGGGGGGGGGGGGG'));
      await helper.upsertFnthinkPeer(peer('HHHHHHHHHHHHHHHHHH'));
      await service.remove('GGGGGGGGGGGGGGGGGG');
      expect(
        (await service.list()).map((p) => p.peerAddress).toList(),
        ['HHHHHHHHHHHHHHHHHH'],
        reason: '一次撤销影响 N 台，就是"一键全部失效"那一档（T31），不是这一发',
      );
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

    test('DI 里那一份带着契约装载器（少注入时 `grantFor` 只会抛）', () {
      setupLocator();
      expect(
        GetIt.instance<FnthinkPeerService>().contracts,
        isNotNull,
        reason: '注入是 `setupLocator` 里写的；这里是第一句会因漏写而红的断言',
      );
    });
  });

  // T49：这一层新加的那一段（grantFor）。它把"本机记得我同意过什么"读成裁决层要的形状。
  group('grantFor：本机那份清单才是裁决依据（T49）', () {
    /// 用仓库里那份真契约走资产通道 —— 判据里所有词表都从它来，假的会测到空气。
    FnthinkPeerService withContract() => FnthinkPeerService(
      contracts: FnthinkContractLoader(
        readAsset: (key) async =>
            File(fnthinkContractFile()).readAsStringSync(),
      ),
    );

    test('名单里那一行的档位与清单原样进授权（裁决要的正是这两样）', () async {
      await helper.upsertFnthinkPeer(
        const FnthinkPeer(
          peerAddress: '8K3FJ6QPTM9WZ4VHNS',
          publicKey: 'AAAA',
          level: 'L3',
          grantedAt: 1780000000000,
          items: ['setting:do_not_disturb'],
          revision: 2,
        ),
      );
      final grant = await withContract().grantFor('8K3FJ6QPTM9WZ4VHNS');
      expect(grant.maxLevel, 'L3');
      expect(grant.items, ['setting:do_not_disturb']);
      expect(grant.revision, 2);
    });

    test('名单里没有这一行 ⇒ 缺省档，不是"给最高那档"', () async {
      // 这一条是 T49 的地基：查不到清单时按最窄档判（契约 grantDefaults），
      // 写错了方向就是一台没配对过的设备被当成什么都能做。
      final grant = await withContract().grantFor('8TQVWZ3XKR5B6YD4HM');
      expect(grant.maxLevel, 'L1');
      expect(grant.items, isEmpty);
    });

    test('库里的档位不在契约词表里 ⇒ 按缺省档，不是"放行"也不是崩', () async {
      await helper.upsertFnthinkPeer(
        const FnthinkPeer(
          peerAddress: '8K3FJ6QPTM9WZ4VHNS',
          publicKey: 'AAAA',
          level: 'L9',
          grantedAt: 1780000000000,
        ),
      );
      final grant = await withContract().grantFor('8K3FJ6QPTM9WZ4VHNS');
      expect(grant.maxLevel, 'L1');
    });

    test('没注入契约装载器就抛，不静默放行', () async {
      await expectLater(
        FnthinkPeerService().grantFor('8K3FJ6QPTM9WZ4VHNS'),
        throwsStateError,
      );
    });

    test('拿到的授权喂进裁决层：L3 但清单一空 ⇒ 判"这一条没给"', () async {
      // 端到端那一段：档位是天花板，清单才是判据（契约 itemRequiredFromLevel = L2）。
      // 这一条就是 T49 要防的那个形状 —— 写着 L3 却什么都还没逐条给过。
      await helper.upsertFnthinkPeer(
        const FnthinkPeer(
          peerAddress: '8K3FJ6QPTM9WZ4VHNS',
          publicKey: 'AAAA',
          level: 'L3',
          grantedAt: 1780000000000,
        ),
      );
      final contract = FnthinkContract.readFile();
      final grant = await withContract().grantFor('8K3FJ6QPTM9WZ4VHNS');
      final decided = decideCapability(
        contract,
        stage: CapabilityStage.apply,
        grant: grant,
        type: 'setting',
        item: 'setting:do_not_disturb',
        confirmedThisTime: true,
      );
      expect(decided.allowed, isFalse, reason: '清单一空就该拒');
      expect(decided.reason, startsWith('item:'));
    });
  });
}
