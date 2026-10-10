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
/// 3. 没有可再发的通道 ⇒ 一次原生调用都不发（空集 ≠ 不限定）；
/// 4. `onlyDeliveryKeys` 缺省仍是整表重建（`pushSynthesizedRecord` 那条"刚落库就要发全部"要用）；
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

    test('没有可再发的通道 ⇒ 一次原生调用都不发（空集 ≠ 不限定）', () async {
      await twoChannels();
      final service = NotificationService();
      service.addRecord(rec());
      final id = service.records.first.id;
      await service.updateDelivery(id, 'DINGTALK', 'SUCCESS', 'ok');
      await service.updateDelivery(id, 'GENERIC', 'SUCCESS', 'ok');

      await service.repushRecord(service.records.first);

      expect(
        calls.where((c) => c.method == 'pushRecordNow'),
        isEmpty,
        reason:
            '把空范围读成"不限定"，点一次"重推"就会把全部通道重发一遍 —— '
            '这正是片4 要修的那一句',
      );
      expect(
        service.records.first.deliveryStatus.values
            .map((v) => v['status'])
            .toList(),
        ['success', 'success'],
        reason: '不发 = 这一条一个字都不该动；抹成 pending 会让"没重推"看起来像"正在推"',
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
}
