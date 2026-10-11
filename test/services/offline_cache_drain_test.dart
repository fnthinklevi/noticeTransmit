import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/models/notification_record.dart';
import 'package:notice_transmit/services/notification_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_setup.dart';

/// #94-A：离线缓存溢出要"看得见"。
///
/// 原生 `drainOfflineCache` 一次交付 `{records: [...], dropped: N}` —— 记录与"期间因缓存满
/// 被丢弃的条数"必须**同一次**给（分开读之间原生可能又丢了新的，计数就漏）。
/// 这里钉五件事：
/// 1. 记录合得进来，且丢弃条数一起带出来（否则"不静默丢失"这条不变量又落空）；
/// 2. `dropped=0` 不留提示（不是每次开应用都告诉用户"一切正常"）；
/// 3. 形状不对时**不崩也不猜**：宁可一条都不合并，也不能把半个结构当成记录读进来；
/// 4. 提示被用户收下后不再重复（原生侧交付时已清零）；
/// 5. T133 量级②：原生一次只交**一批**，`truncated` 为真必须继续排到没了为止 ——
///    而那支循环自己要有上限（上限只停手，不删任何东西：余下的仍躺在原生队列文件里）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabase();

  final helper = DatabaseHelper();
  late Database db;
  Object? drainPayload;

  /// 分批交付的脚本：非空时**每次** `drainOfflineCache` 调用按顺序给一批，给完退回 [drainPayload]。
  /// （原生换了载体之后一次只交一批，"还剩没有"由载荷里的 `truncated` 说 —— 见 T133 量级②。）
  final List<Object?> drainQueue = <Object?>[];
  int drainCalls = 0;

  /// 置真后，脚本给完就**一直**回「还有、这批空」——只用来试那枚循环上限，不是原生真会这样。
  bool drainSpinsForever = false;

  Future<Object?> onChannelCall(MethodCall call) async {
    if (call.method == 'drainOfflineCache') {
      drainCalls++;
      if (drainQueue.isNotEmpty) return drainQueue.removeAt(0);
      if (drainSpinsForever) {
        return <String, Object?>{
          'records': const <Object?>[],
          'truncated': true,
        };
      }
      return drainPayload;
    }
    return null;
  }

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await helper.createSchemaForTest(db);
    helper.debugDatabase = db;
    drainPayload = null;
    drainSpinsForever = false;
    drainCalls = 0;
    drainQueue.clear();
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

  // ── 分批交付（T133 量级②）────────────────────────────────────────────
  test('原生报 truncated ⇒ 一次启动排空到没了，不是只拿第一批', () async {
    drainQueue.addAll(<Object?>[
      <String, Object?>{
        'records': [offlineRecord('p1_a'), offlineRecord('p1_b')],
        'truncated': true,
      },
      <String, Object?>{
        'records': [offlineRecord('p2_a')],
        'truncated': false,
      },
    ]);
    final service = NotificationService();
    await service.loadRecords();

    expect(
      service.records.map((r) => r.id),
      containsAll(<String>['p1_a', 'p1_b', 'p2_a']),
      reason:
          '原生那道 500 条的存储闸拆了之后，一次交付只是其中一批 —— 不续拉就等于'
          '「离线期间的历史只进来头一批，剩下的下次打开再说」，那是新的静默丢失',
    );
    expect(drainCalls, 2, reason: '第二批才是"排到没了"的那一发');
    expect(await helper.getAllNotifications(), hasLength(3));
  });

  test('同一条记录跨批重复 ⇒ 只入库一次', () async {
    drainQueue.addAll(<Object?>[
      <String, Object?>{
        'records': [offlineRecord('dup_1')],
        'truncated': true,
      },
      <String, Object?>{
        'records': [offlineRecord('dup_1')],
        'truncated': false,
      },
    ]);
    final service = NotificationService();
    await service.loadRecords();

    expect(
      service.records.where((r) => r.id == 'dup_1'),
      hasLength(1),
      reason: '批与批之间各算一次 existingIds，第二批没重读 ⇒ 同一条并排两次',
    );
  });

  test('T133 量级①：DB 已有而内存没有的那条 ⇒ 跳过，不许用新的 pending 快照覆盖送达状态', () async {
    // 镜像退役后的真场景：设备死了三天，离线批次里躺着的 id 在 DB 里早就有
    // （带着 success 的送达状态），而内存副本里根本没有它。去重必须查 DB ——
    // 查内存查不到就会照插，insertNotification 的 REPLACE 把送达状态抹成 pending，
    // 那条历史从此永远"发送中"。
    await DatabaseHelper().insertNotification({
      ...offlineRecord('db_known_1'),
      'deliveryStatus': <String, dynamic>{
        'chan:dingtalk': {'status': 'success', 'message': ''},
      },
    });
    drainPayload = <String, Object?>{
      'records': [offlineRecord('db_known_1')],
      'dropped': 0,
    };

    final service = NotificationService();
    await service.loadRecords();

    expect(
      service.records.where((r) => r.id == 'db_known_1'),
      hasLength(0),
      reason: 'DB 已有的记录不该被并进会话副本（那是重复）',
    );
    final kept = NotificationRecord.fromMap(
      (await DatabaseHelper().getNotificationById('db_known_1'))!,
    );
    expect(
      kept.deliveryStatus['chan:dingtalk']?['status'],
      'success',
      reason: '去重查内存不查 DB 的下场：success 被一份新造的 pending 快照 REPLACE 掉',
    );
  });

  test('原生一直报 truncated ⇒ 循环有上限，且余下的不许被当成已交付', () async {
    drainQueue.add(<String, Object?>{
      'records': [offlineRecord('spin_1')],
      'truncated': true,
    });
    drainSpinsForever = true;
    final service = NotificationService();
    await service.loadRecords();

    // 队列脚本给完就退回 null（形状不对 ⇒ 一条都不合并），所以这里到的是**上限**那一支。
    expect(drainCalls, 200, reason: '没有上限 ⇒ 原生一句 truncated 就能把启动变成死循环');
    expect(service.records.map((r) => r.id), contains('spin_1'));
    expect(
      service.pendingOfflineDrops,
      0,
      reason: '到上限只是"这次不排了"，余下的仍躺在原生队列文件里 —— 不丢，也不许报"丢了"',
    );
  });
}
