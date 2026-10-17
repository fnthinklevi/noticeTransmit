import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/models/notification_record.dart';
import 'package:notice_transmit/services/app_channel_service.dart';
import 'package:notice_transmit/services/channel_health_store.dart';
import 'package:notice_transmit/services/email_service.dart';
import 'package:notice_transmit/services/notification_service.dart';
import 'package:notice_transmit/services/webhook_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_setup.dart';

/// T133 片4：手动补推的**范围**（重推只发"这一条里可再发的那几族"）。
///
/// 改之前 `pushRecordNow` 只有一种做法：把**全部启用通道**整表重建成 pending，原生也照全部
/// 通道发。于是一条"钉钉失败、企业微信成功"的通知点一下，企业微信会**再收到一遍同一条内容**
/// —— 收件端多出的是重复消息，不是补发。片1 定好了判据（谁能再发），本片把那一句接到出口上。
///
/// 钉五条，各挡一种会静默回来的失效：
/// 1. 递给原生的范围 = 判据认的那几族（且传的是 **slug**，不是 `chan:` 键本身）；
/// 2. **不在范围里的通道状态原样保留** —— 整表重建会把已送达的那格抹成「发送中」并停在那里
///    （这一轮没人给它回执），比留着"失败"更误导人；
/// 3. 片9（走 (b)：每行都有出口）之后，"没有可再发的通道"不再是"不发"的理由 —— 它换成了
///    另两档：全成功／在途／被拦下的那些按「再发一次」发**这条快照里的全部键**（仍带键，
///    不是缺键），整条没记录的那些才走缺省。空集合＝谁都不发这一条**依然成立**，
///    它现在守的是"算出了键但一个都不在启用清单里"那一格（第 5 条用例）。
/// 4. `onlyDeliveryKeys` 缺省仍是整表重建（`pushSynthesizedRecord` 与"整条没记录"那一档要用）；
/// 5. 判据认它、但它现在已不在启用清单里（通道被删了）⇒ 不重发，也不被抹成「发送中」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabase();

  final helper = DatabaseHelper();
  late Database db;
  final calls = <MethodCall>[];

  Future<Object?> onChannelCall(MethodCall call) async {
    calls.add(call);
    return true;
  }

  setUp(() async {
    calls.clear();
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({});
    stubNativeChannels(onCall: onChannelCall);
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await helper.createSchemaForTest(db);
    helper.debugDatabase = db;
    GetIt.instance
      ..registerSingleton<WebhookService>(WebhookService())
      ..registerSingleton<AppChannelService>(AppChannelService())
      ..registerSingleton<EmailService>(EmailService())
      ..registerSingleton<ChannelHealthStore>(ChannelHealthStore());
  });

  tearDown(() async {
    helper.debugDatabase = null;
    await db.close();
    clearNativeChannelStubs();
    await GetIt.instance.reset();
  });

  /// 两条启用 webhook 通道：钉钉 + 通用（送达键 `chan:dingtalk` / `chan:generic`）。
  Future<void> twoChannels() => GetIt.instance<WebhookService>().saveChannels([
    {
      'id': 'wh_ding',
      'name': '钉钉群',
      'url': 'https://oapi.dingtalk.com/robot/send?access_token=t',
      'secret': '',
      'channelType': 'dingtalk',
      'enabled': true,
    },
    {
      'id': 'wh_gen',
      'name': '自建端点',
      'url': 'https://example.com/hook',
      'secret': '',
      'channelType': 'generic',
      'enabled': true,
    },
  ]);

  Map<String, dynamic> rec({String id = 'n_1700000000000_1'}) => {
    'id': id,
    'type': 'sms',
    'title': '验证码',
    'content': '您的验证码是 123456',
    'packageName': 'com.android.mms',
    'appName': '短信',
    'postTime': 1700000000000,
    'time': '2024-01-01 12:00:00',
  };

  /// 一条"钉钉失败、通用成功"的记录（片4 要修的就是这一格）。
  Future<(NotificationService, NotificationRecord)> failedAndServed({
    bool withBackupMark = false,
  }) async {
    await twoChannels();
    final service = NotificationService();
    service.addRecord(rec());
    final id = service.records.first.id;
    await service.updateDelivery(
      id,
      'DINGTALK',
      'FAIL',
      'HTTP 500',
      viaBackup: withBackupMark,
    );
    await service.updateDelivery(
      id,
      'GENERIC',
      'SUCCESS',
      'ok',
      viaBackup: withBackupMark,
    );
    return (service, service.records.first);
  }

  Map<String, dynamic> pushedSlugsArg() {
    final call = calls.firstWhere((c) => c.method == 'pushRecordNow');
    return (call.arguments as Map).cast<String, dynamic>();
  }

  group('重推的范围（T133 片4）', () {
    test('只把可再发的那几族递给原生，传的是 slug 不是送达键', () async {
      final (service, record) = await failedAndServed();

      await service.repushRecord(record);

      final args = pushedSlugsArg();
      expect(
        args['onlySlugs'],
        ['dingtalk'],
        reason:
            '递送达键（chan:dingtalk）等于让原生去拆 Dart 的存储前缀；'
            '多递 generic 就是把已经送达的那条再发一遍',
      );
    });

    test('不在范围里的通道状态原样保留（不被抹成发送中）', () async {
      final (service, record) = await failedAndServed();
      final id = record.id;

      await service.repushRecord(record);

      final status = service.records.first.deliveryStatus;
      expect(status['chan:dingtalk']['status'], 'pending');
      expect(
        status['chan:dingtalk']['message'],
        isEmpty,
        reason: '待发时不该留着上一轮的失败原因',
      );
      expect(
        status['chan:generic']['status'],
        'success',
        reason: '整表重建会把这一格抹成 pending，而这一轮原生并不发给它 ⇒ 永远挂着「发送中」',
      );
      // 落库的那一份与内存同口径（历史页重新加载读的是库）
      final row = await helper.getNotificationById(id);
      final saved = NotificationRecord.fromMap(row!).deliveryStatus;
      expect(saved['chan:generic']['status'], 'success');
      expect(saved['chan:dingtalk']['status'], 'pending');
    });

    test('全成功那条：片9 起它走「再发一次」，范围＝这条快照里的全部通道', () async {
      await twoChannels();
      final service = NotificationService();
      service.addRecord(rec());
      final id = service.records.first.id;
      await service.updateDelivery(id, 'DINGTALK', 'SUCCESS', 'ok');
      await service.updateDelivery(id, 'GENERIC', 'SUCCESS', 'ok');

      await service.repushRecord(service.records.first);

      final args = pushedSlugsArg();
      expect(
        (args['onlySlugs'] as List).cast<String>().toSet(),
        {'dingtalk', 'generic'},
        reason:
            '这一档说的是"整条再发一遍"，所以范围是**这条快照里的那几族**，'
            '必须带键而不是缺键 —— 缺键那一路读的是"当前启用通道"，'
            '用户后来新加的通道会被这一发顺带捎上，那不是他按的东西。',
      );
      expect(
        service.records.first.deliveryStatus.values
            .map((v) => v['status'])
            .toList(),
        ['pending', 'pending'],
        reason: '按下去就是新的一轮：留着 success 会让界面说"没动过"，而原生正要发',
      );
    });

    test('整条没有送达记录 ⇒ 缺省（不限定）那一发，欠的是当前启用通道各一发', () async {
      await twoChannels();
      final service = NotificationService();
      // 「仅记录不推送」／规则 `Record` 那一档的形状：这条从来没有送达格。
      final record = NotificationRecord.fromMap({
        ...rec(),
        'id': 'n_never_1',
        'channels': <String>[],
        'deliveryStatus': <String, dynamic>{},
      });

      await service.repushRecord(record);

      final args = pushedSlugsArg();
      expect(
        args.containsKey('onlySlugs'),
        isFalse,
        reason:
            '空快照算不出键。把"算不出"读成空集合＝"谁都不发"，那一枚按下去什么都不会发生 —— '
            '而这一条确实欠着全部通道各一发，缺键才是那句真话。',
      );
      expect(
        (args['record'] as Map)['id'],
        'n_never_1',
        reason: '递给原生的必须是这一条本身（它不在内存列表里，走的是 F2 那条按记录直发的路）',
      );
    });

    test('被规则拦下的那条：单条这一枚按 again 档把它一起发（用户当场推翻那条过滤）', () async {
      await twoChannels();
      final service = NotificationService();
      // ⚠ 不能拿 `updateDelivery(..., 'INTERCEPTED')` 造这一格 —— 那一发的归一化里没有
      // INTERCEPTED 这一档（只认 SUCCESS／PAUSED，其余落 failed），造出来的是"失败"不是"被拦"。
      // 真机上的 intercepted 由原生伪通道回传（`applyDelivery` 里 `kBlockedChannelKey` 那一支）。
      final record = NotificationRecord.fromMap({
        ...rec(),
        'id': 'n_blocked_1',
        'channels': ['chan:dingtalk', 'chan:generic'],
        'deliveryStatus': <String, dynamic>{
          'chan:dingtalk': {'status': 'success', 'message': 'ok'},
          'chan:generic': {'status': 'intercepted', 'message': '黑名单'},
        },
      });

      await service.repushRecord(record);

      expect(
        (pushedSlugsArg()['onlySlugs'] as List).cast<String>().toSet(),
        {'dingtalk', 'generic'},
        reason:
            '批量池不收 intercepted（那是"给一批补缺"，判据见 repush_eligibility）；'
            '而对着**这一条**按一下是显式动作，范围就是这条快照的那几族。',
      );
    });

    test('缺省（不限定）仍是整表重建：刚落库那一条欠全部启用通道各一发', () async {
      await twoChannels();
      final service = NotificationService();
      service.addRecord(rec());
      final id = service.records.first.id;
      await service.updateDelivery(id, 'DINGTALK', 'SUCCESS', 'ok');

      await service.pushRecordNow(service.records.first);

      final args = pushedSlugsArg();
      expect(
        args.containsKey('onlySlugs'),
        isFalse,
        reason: '带空列表 = 谁都不发；这一路要的是"全部"，只能用**缺键**表达',
      );
      expect(
        service.records.first.deliveryStatus['chan:generic']['status'],
        'pending',
      );
      expect(
        service.records.first.deliveryStatus['chan:dingtalk']['status'],
        'pending',
      );
    });

    test('判据认它、但它已被删掉 ⇒ 不重发也不抹成发送中', () async {
      final (service, record) = await failedAndServed();
      // 钉钉通道被删：现在只剩通用那一条启用着
      await GetIt.instance<WebhookService>().saveChannels([
        {
          'id': 'wh_gen',
          'name': '自建端点',
          'url': 'https://example.com/hook',
          'secret': '',
          'channelType': 'generic',
          'enabled': true,
        },
      ]);

      await service.repushRecord(record);

      expect(
        calls.where((c) => c.method == 'pushRecordNow'),
        isEmpty,
        reason: '把没有配置在案的通道放进范围 ⇒ 它被抹成 pending 后没人回执，永远挂「发送中」',
      );
      expect(
        service.records.first.deliveryStatus['chan:dingtalk']['status'],
        'failed',
        reason: '留着"失败"才是真话（这一族已经不发了）',
      );
    });

    test('备用标记只在这几格被清；不在范围里的那格仍知道自己上一轮走了备用', () async {
      final (service, record) = await failedAndServed(withBackupMark: true);

      await service.repushRecord(record);

      final status = service.records.first.deliveryStatus;
      expect(
        status['chan:dingtalk']['viaBackup'],
        isNull,
        reason: '这一族是**新的一轮**，上一轮走没走备用不该由它继续声称',
      );
      expect(
        status['chan:generic']['viaBackup'],
        isTrue,
        reason: '粘滞标记只对整表重建失效（见 applyDelivery 头注释），窄口径不该顺手抹平',
      );
    });
  });

  // ── T154 片3：逐格那一发（子页里「重推此通道」/「全部重推」）─────────────────
  //
  // ⚠ 这一组与上面那组**不是同一个问题**，别把两者的判据混起来：
  //   上面问「这一条该补哪几族」（`RepushIntent`，用户没指任何一格）；
  //   这里问「用户指着的那一格，现在还发不发得出去」（服务只答"在不在"，
  //   **状态那一半刻意不设限** —— 子页是"当场做一次决定"那一层，
  //   而行内那一枚本来就含 success 与 intercepted）。
  group('逐格重推的范围（T154 片3）', () {
    /// 只剩通用那一条启用着（钉钉被删）。
    Future<void> onlyGenericEnabled() =>
        GetIt.instance<WebhookService>().saveChannels([
          {
            'id': 'wh_gen',
            'name': '自建端点',
            'url': 'https://example.com/hook',
            'secret': '',
            'channelType': 'generic',
            'enabled': true,
          },
        ]);

    test('可用性只答"这一族现在还配着没有"，与那一格的状态无关', () async {
      await twoChannels();
      final service = NotificationService();

      expect(service.canRepushChannelIndividually('chan:dingtalk'), isTrue);
      expect(
        service.canRepushChannelIndividually('chan:deleted'),
        isFalse,
        reason: '删掉的通道没有配置在案 —— 原生只对配着的通道扇出',
      );
    });

    test('已送达的那一格同样可逐格重推（不按状态设限）', () async {
      await twoChannels();
      final service = NotificationService();
      final record = NotificationRecord.fromMap({
        ...rec(),
        'id': 'n_done_1',
        'channels': ['chan:dingtalk', 'chan:generic'],
        'deliveryStatus': <String, dynamic>{
          'chan:dingtalk': {'status': 'success', 'message': 'ok'},
          'chan:generic': {'status': 'success', 'message': 'ok'},
        },
      });

      await service.repushChannels(record, ['chan:generic']);

      expect(
        (pushedSlugsArg()['onlySlugs'] as List).cast<String>(),
        ['generic'],
        reason:
            '子页是"对着这一格做一次决定"那一层。若这里按 success 设限，界面上就会出现'
            '"我能一次重推全部，却不能只重推其中一条" —— 与本片要修的那条是同一个反方向',
      );
    });

    test('逐格那一发只发用户指着的那一格，其余通道的结论原样保留', () async {
      final (service, record) = await failedAndServed();

      await service.repushChannels(record, ['chan:generic']);

      expect((pushedSlugsArg()['onlySlugs'] as List).cast<String>(), [
        'generic',
      ]);
      expect(
        service.records.first.deliveryStatus['chan:dingtalk']['status'],
        'failed',
        reason: '点的是邮件那一格 ⇒ 钉钉那格不许被抹成 pending（整表重建的害处，见上方头注释）',
      );
    });

    test('指着一条已删除的通道 ⇒ 一个字节都不发（fail-closed）', () async {
      final (service, record) = await failedAndServed();
      await onlyGenericEnabled();

      await service.repushChannels(record, ['chan:dingtalk']);

      expect(
        calls.where((c) => c.method == 'pushRecordNow'),
        isEmpty,
        reason:
            '放行一枚按了不动的钮 = 那一格被写成 pending 且永远没有回执 ⇒'
            '"一直发送中"。T150 片1 修的正是这一族，不许从另一个方向再装回来',
      );
      expect(
        service.records.first.deliveryStatus['chan:dingtalk']['status'],
        'failed',
        reason: '留着"失败"才是真话（这一族已经不发了）',
      );
    });

    test('一批里混着已删除的 ⇒ 只发还在的那些（交集，不是全否）', () async {
      final (service, record) = await failedAndServed();
      await onlyGenericEnabled();

      await service.repushChannels(record, ['chan:dingtalk', 'chan:generic']);

      expect(
        (pushedSlugsArg()['onlySlugs'] as List).cast<String>(),
        ['generic'],
        reason: '一格不可用就把整批否掉，等于让一枚按不动的钮把旁边那枚也废了',
      );
    });
  });
}
