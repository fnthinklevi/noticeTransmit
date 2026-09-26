import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/services/app_channel_service.dart';
import 'package:notice_transmit/services/channel_health_store.dart';
import 'package:notice_transmit/services/email_service.dart';
import 'package:notice_transmit/services/notification_service.dart';
import 'package:notice_transmit/services/webhook_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_setup.dart';

/// T18：`pushSynthesizedRecord` 是"本机自己造一条信息送进推送链"的唯一入口
/// （设备状态页的「推送设备信息」走它）。
///
/// 钉三条：
/// 1. **顺序** —— 原生收到 `pushRecordNow` 的那一刻，这条记录必须已经在库里。顺序反了
///    就没有落点：原生回传的送达结果按 id 更新，历史里留下一条永远"发送中"的记录，
///    而用户看到的是一次失败的推送；
/// 2. 只推一条（补推那条与落库那条是**同一个 id**）；
/// 3. 送达快照的键与 `activeChannels()` 同源（送达键 `chan:<slug>`，不是显示名）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabase();

  final helper = DatabaseHelper();
  late Database db;
  final calls = <MethodCall>[];
  var rowPresentAtPush = false;
  String? pushedId;

  Future<Object?> onChannelCall(MethodCall call) async {
    calls.add(call);
    if (call.method == 'pushRecordNow') {
      final record = (call.arguments as Map)['record'] as Map;
      pushedId = record['id'].toString();
      rowPresentAtPush = (await helper.getNotificationById(pushedId!)) != null;
      return true;
    }
    return null;
  }

  setUp(() async {
    calls.clear();
    rowPresentAtPush = false;
    pushedId = null;
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

  test('先落历史记录，再交给原生补推，且是同一条', () async {
    final service = NotificationService();
    final record = await service.pushSynthesizedRecord(
      title: '设备状态',
      content: '型号: MEIZU 21\n存储: 已用 78.1 GB / 共 117.2 GB',
      deviceName: '我的手机',
    );

    expect(
      rowPresentAtPush,
      isTrue,
      reason: '原生收到补推时记录还不在库里 ⇒ 回传的送达结果没有落点（历史永远"发送中"）',
    );
    expect(pushedId, record.id, reason: '推的那条与落库的那条必须同一个 id');
    expect(await helper.getNotificationById(record.id), isNotNull);
    expect(service.records.first.id, record.id);
    expect(
      calls.where((c) => c.method == 'pushRecordNow').length,
      1,
      reason: '一次按钮 = 一次补推；两次会把同一条内容推给收件方两遍',
    );
  });

  test('送达快照走启用通道，键是送达键而不是显示名', () async {
    await GetIt.instance<WebhookService>().saveChannels([
      {
        'id': 'wh1',
        'name': '钩子',
        'url': 'https://example.com/hook',
        'secret': '',
        'channelType': 'generic',
        'enabled': true,
      },
    ]);

    final record = await NotificationService().pushSynthesizedRecord(
      title: '设备状态',
      content: '型号: X',
      deviceName: 'd',
    );

    expect(
      record.channels,
      isNotEmpty,
      reason: '一条启用通道都没算进去 ⇒ 这条记录的送达状态永远是空表，界面画不出结果',
    );
    for (final key in record.channels) {
      expect(key, startsWith('chan:'), reason: '快照必须用稳定送达键（显示名随语言变，回传写不到这一项上）');
    }
    expect(record.deliveryStatus.keys.toSet(), record.channels.toSet());
    expect(
      record.deliveryStatus.values.every(
        (v) => (v as Map)['status'] == 'pending',
      ),
      isTrue,
    );
  });

  test('正文与标题原样带过去，不在此处改写', () async {
    final record = await NotificationService().pushSynthesizedRecord(
      title: '设备状态',
      content: '电池温度: 这台设备读不到',
      deviceName: '测试机',
    );
    final args =
        calls.firstWhere((c) => c.method == 'pushRecordNow').arguments as Map;
    final sent = args['record'] as Map;
    expect(sent['title'], '设备状态');
    expect(sent['content'], '电池温度: 这台设备读不到');
    expect(sent['deviceName'], '测试机');
    expect(record.priority, 1, reason: '本机自造的记录没有"系统优先级"可读，取中；改成 0/2 会改变历史排序');
  });
}
