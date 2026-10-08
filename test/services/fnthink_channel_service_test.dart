import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/models/fnthink_channel.dart';
import 'package:notice_transmit/models/fnthink_peer.dart';
import 'package:notice_transmit/services/active_channels.dart';
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

  test('目标被取消勾选之后**仍改得动主备**（只改角色那条写口不重验目标，T113）', () async {
    // 这一条是 T113 的正面证据。首页那个主备弹层以前**不列**幻念那一族，理由写得很清楚：
    // 角色改只有 `save()` 一条路，而它连带重验目标 ⇒ "点了主/备没改成"有三种成因，
    // 而弹层只有一句「这条通道已经不在了」可说。`setRole` 只写 role/updated_at，
    // 目标那一栏根本没被碰 ⇒ 取消勾选不该挡住这一次，弹层那一行也就说得起那一句了。
    await seedPeer();
    await service.setForward('8KMNPQRSTVWX999777', true);
    await service.create(
      id: 'fc_role',
      name: '改主备',
      target: '8KMNPQRSTVWX999777',
      targetKind: FnthinkChannelTarget.device,
    );
    await service.setForward('8KMNPQRSTVWX999777', false);

    expect(
      await service.setRole('fc_role', 'backup'),
      isTrue,
      reason: '改不动 = 这一族在主备面上不可见（维护者报的就是它）',
    );
    expect(
      (await service.list()).single.role,
      'backup',
      reason: '返回 true 而库里没变 = 用户在弹层里点了一下空气',
    );

    // 归一仍住在写这一侧（与 create/save 同一个口径）：原生认不出的值会按"主通道"处理，
    // 两边各猜一遍的表现是"界面灰着的一条照样推出去"。
    expect(await service.setRole('fc_role', '乱写的值'), isTrue);
    expect((await service.list()).single.role, 'primary');

    // 找不到那条回 false（不抛）：弹层据此说那一句「已经不在了」，那一句这时候才是真话。
    expect(await service.setRole('fc_missing', 'backup'), isFalse);
  });

  test('主备弹层那条写路径**认得**幻念这一族（不掉进 default，T113）', () async {
    // 弹层列出这一族，靠的是 `channelFamilies` 那一份清单；这里钉的是另一半：
    // `updateChannelRole` 的 switch 真有这一族的一支。掉进 `default: return false` 的话，
    // 界面会回一句「通道已不存在，本次设置未保存。」—— 而那条通道明明正躺在列表里，
    // 用户看到的是一句与事实相反的说明（守卫在 channel_single_points_test 只保证集合相等，
    // 保证不了这一支真的写对，所以行为得在这里自己长一遍）。
    GetIt.instance.registerSingleton<FnthinkChannelService>(service);
    addTearDown(GetIt.instance.reset);
    await seedPeer();
    await service.setForward('8KMNPQRSTVWX999777', true);
    await service.create(
      id: 'fc_wire',
      name: '走弹层',
      target: '8KMNPQRSTVWX999777',
      targetKind: FnthinkChannelTarget.device,
    );

    expect(
      await updateChannelRole('fnthink', 'fc_wire', 'backup'),
      isTrue,
      reason: '返回 false ⇒ 弹层那一行点下去是空气，还会说一句假话',
    );
    expect(
      (await service.list()).single.role,
      'backup',
      reason: '认了却没落库 = 下次开 App 又回到主',
    );
    expect(await updateChannelRole('fnthink', 'fc_gone', 'backup'), isFalse);
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
