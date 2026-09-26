import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/services/notification_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_setup.dart';

/// #94-A：离线缓存溢出要"看得见"。
///
/// 原生 `drainOfflineCache` 一次交付 `{records: [...], dropped: N}` —— 记录与"期间因缓存满
/// 被丢弃的条数"必须**同一次**给（分开读之间原生可能又丢了新的，计数就漏）。
/// 这里钉四件事：
/// 1. 记录合得进来，且丢弃条数一起带出来（否则"不静默丢失"这条不变量又落空）；
/// 2. `dropped=0` 不留提示（不是每次开应用都告诉用户"一切正常"）；
/// 3. 形状不对时**不崩也不猜**：宁可一条都不合并，也不能把半个结构当成记录读进来；
/// 4. 提示被用户收下后不再重复（原生侧交付时已清零）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabase();

  final helper = DatabaseHelper();
  late Database db;
  Object? drainPayload;

  Future<Object?> onChannelCall(MethodCall call) async {
    if (call.method == 'drainOfflineCache') return drainPayload;
    return null;
  }

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await helper.createSchemaForTest(db);
    helper.debugDatabase = db;
    drainPayload = null;
    GetIt.instance.reset();
    stubNativeChannels(onCall: onChannelCall);
  });

  tearDown(() async {
    clearNativeChannelStubs();
    helper.debugDatabase = null;
    await db.close();
    await GetIt.instance.reset();
  });

  Map<String, dynamic> offlineRecord(String id) => <String, dynamic>{
    'id': id,
    'title': '离线通知$id',
    'content': '软件被杀期间到达',
    'subText': '',
    'packageName': 'com.example.offline',
    'appName': '离线应用',
    'postTime': 1767223200000,
    'time': '2026-01-01 10:00:00',
    'type': 'notification',
    'priority': 1,
  };

  test('记录与丢弃条数一起交付：两边都落到该落的地方', () async {
    drainPayload = <String, Object?>{
      'records': [offlineRecord('off_1'), offlineRecord('off_2')],
      'dropped': 3,
    };
    final service = NotificationService();
    await service.loadRecords();

    expect(
      service.records.map((r) => r.id),
      containsAll(<String>['off_1', 'off_2']),
      reason: '离线期间的通知没合进历史 = 「软件被杀后历史丢失」这个老问题回来了',
    );
    expect(
      service.pendingOfflineDrops,
      3,
      reason: '丢了却不报 ⇒ 静默丢失只是从日志搬到了没人看的地方',
    );
    // 记录同时要真的落库：只在内存里，历史页下次冷启动就又看不见了
    expect(await helper.getAllNotifications(), hasLength(2));
  });

  test('dropped=0 不留提示（不是每次开应用都报一次"一切正常"）', () async {
    drainPayload = <String, Object?>{
      'records': [offlineRecord('off_3')],
      'dropped': 0,
    };
    final service = NotificationService();
    await service.loadRecords();

    expect(service.records.map((r) => r.id), contains('off_3'));
    expect(service.pendingOfflineDrops, 0);
  });

  test('形状不对时不崩也不猜：一条都不合并', () async {
    // 原生改了形状而 Dart 没跟上时，最容易出的不是崩溃，而是"把半个结构猜成记录"——
    // 猜出来的记录没有 id/通道，会污染统计且再也对不上送达回传。
    drainPayload = [offlineRecord('off_4')];
    final service = NotificationService();
    await service.loadRecords();

    expect(service.records, isEmpty);
    expect(service.pendingOfflineDrops, 0);
  });

  test('用户收下提示后不再重复', () async {
    drainPayload = <String, Object?>{
      'records': [offlineRecord('off_5')],
      'dropped': 7,
    };
    final service = NotificationService();
    await service.loadRecords();
    expect(service.pendingOfflineDrops, 7);

    service.ackOfflineDrops();
    expect(service.pendingOfflineDrops, 0);
  });
}
