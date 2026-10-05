import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/models/fnthink_channel.dart';
import 'package:notice_transmit/models/fnthink_peer.dart';
import 'package:notice_transmit/services/fnthink_channel_service.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_setup.dart';

/// 幻念通道的写咽喉（T94 片3）。
///
/// 这里钉的每一条都是「错了不报错、只是慢慢说假话」或「只在真点过一次时才现形」的那几种：
///  ① **设备目标必须已勾选** —— 不挡下来的表现是「这台没同意，却一直在收本机的通知」；
///  ② **读不到不放行**（`enabled` 那一列读不出来当停用）—— 反过来就是「到处都在发」；
///  ③ **webhook 必须 https**：静默改成 http 的表现是「看着存下来了、一条都发不出去」；
///  ④ **取消勾选不删通道**：偷偷删用户配置比留一条会报错的通道更坏。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabase();

  final helper = DatabaseHelper();
  late FnthinkChannelService service;

  late final String dbPath;

  setUpAll(() async {
    dbPath = join(await getDatabasesPath(), 'fnthink_channels_test.db');
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
    service = FnthinkChannelService(db: helper);
    addTearDown(() async {
      helper.debugDatabase = null;
      await db.close();
    });
  });

  /// 一台已配对、**未**勾选的设备 —— 下面两条判据都以它为素材。
  Future<void> seedPeer() => service.db.upsertFnthinkPeer(
    const FnthinkPeer(
      peerAddress: '8KMNPQRSTVWX999777',
      publicKey: 'AAAA',
      level: 'L1',
      grantedAt: 1780000111000,
    ),
  );

  test('空库读出的是空列表（不是「还没读过」）', () async {
    expect(await service.list(), isEmpty);
  });

  test('建一条设备通道：写进去再读回来是同一条', () async {
    await seedPeer();
    await service.setForward('8KMNPQRSTVWX999777', true);
    final made = await service.create(
      id: 'fc_1',
      name: '给孩子',
      target: '8KMNPQRSTVWX999777',
      targetKind: FnthinkChannelTarget.device,
    );
    final rows = await service.list();
    expect(rows, hasLength(1));
    expect(rows.single.id, made.id);
    expect(rows.single.name, '给孩子');
    expect(rows.single.targetKind, FnthinkChannelTarget.device);
    expect(rows.single.enabled, isTrue);
  });

  test('设备目标没勾选 ⇒ 拒（这一条挡的是「没同意却在收」）', () async {
    await seedPeer();
    expect(
      () => service.create(
        id: 'fc_2',
        name: '没勾的',
        target: '8KMNPQRSTVWX999777',
        targetKind: FnthinkChannelTarget.device,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('名单里根本没有这一台 ⇒ 拒（不是「先建着」）', () async {
    expect(
      () => service.create(
        id: 'fc_3',
        name: '陌生设备',
        target: '999999999999999999',
        targetKind: FnthinkChannelTarget.device,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('webhook 目标不以 https 开头 ⇒ 拒并说明理由', () async {
    expect(
      () => service.create(
        id: 'fc_4',
        name: '内网',
        target: 'http://nas.lan/hook',
        targetKind: FnthinkChannelTarget.webhook,
      ),
      throwsA(
        isA<ArgumentError>().having((e) => '$e', 'message', contains('https')),
      ),
    );
  });

  test('名字为空 ⇒ 拒', () async {
    expect(
      () => service.create(
        id: 'fc_5',
        name: '   ',
        target: 'https://example.com/hook',
        targetKind: FnthinkChannelTarget.webhook,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('取消勾选**不**连带删通道（留着的通道会在发送时报目标未勾选）', () async {
    await seedPeer();
    await service.setForward('8KMNPQRSTVWX999777', true);
    await service.create(
      id: 'fc_6',
      name: '留着',
      target: '8KMNPQRSTVWX999777',
      targetKind: FnthinkChannelTarget.device,
    );
    await service.setForward('8KMNPQRSTVWX999777', false);
    expect(await service.list(), hasLength(1));
  });

  test('已勾选的那一份才是目标候选；取消之后它从候选里消失', () async {
    await seedPeer();
    expect(await service.listForwardTargets(), isEmpty);
    await service.setForward('8KMNPQRSTVWX999777', true);
    final targets = await service.listForwardTargets();
    expect(targets.single.peerAddress, '8KMNPQRSTVWX999777');
    expect(targets.single.forwards, isTrue);
    await service.setForward('8KMNPQRSTVWX999777', false);
    expect(await service.listForwardTargets(), isEmpty);
  });

  test('删两次不报错（幂等：界面上那一下也是白按的）', () async {
    await service.create(
      id: 'fc_7',
      name: '幂等',
      target: 'https://example.com/hook',
      targetKind: FnthinkChannelTarget.webhook,
    );
    await service.delete('fc_7');
    await service.delete('fc_7');
    expect(await service.list(), isEmpty);
  });

  test('启用读不出来时当**停用**（fail-closed 的方向只有一个）', () {
    final channel = FnthinkChannel.fromDbRow(const {
      'id': 'fc_8',
      'name': '坏行',
      'enabled': null,
      'target_kind': null,
    });
    expect(channel.enabled, isFalse);
    expect(channel.targetKind, FnthinkChannelTarget.device);
  });

  test('两处建表的列一致（onCreate 与 v19 迁移必须是同一张表）', () async {
    final db = await service.db.database;
    final columns = <String>{
      for (final row in await db.rawQuery(
        'PRAGMA table_info(fnthink_channels)',
      ))
        '${row['name']}',
    };
    expect(columns, FnthinkChannel.columns.toSet());
  });
}
